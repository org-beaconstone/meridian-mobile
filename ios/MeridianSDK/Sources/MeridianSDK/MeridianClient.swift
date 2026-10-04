import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class RejectRedirects: NSObject, URLSessionTaskDelegate {
  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

public actor MeridianClient {
  private let baseURL: URL
  private let sessionId: String
  private let session: URLSession
  private let timeout: TimeInterval

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  ///   - timeout: Per-request timeout. Catalog failures inside this limit fall back to cache.
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession? = nil,
    timeout: TimeInterval = 15
  ) throws {
    guard !sessionId.isEmpty else {
      throw MeridianError.missingSession
    }

    // Normalize baseURL: remove trailing slash
    var urlStr = baseURL
    while urlStr.hasSuffix("/") {
      urlStr.removeLast()
    }

    guard !urlStr.isEmpty && urlStr.starts(with: "http://") || urlStr.starts(with: "https://") else {
      throw MeridianError.invalidURL
    }

    guard let url = URL(string: urlStr) else {
      throw MeridianError.invalidURL
    }

    self.baseURL = url
    self.sessionId = sessionId
    self.timeout = timeout
    if let urlSession {
      self.session = urlSession
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = timeout
      configuration.timeoutIntervalForResource = timeout + 5
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      configuration.urlCache = nil
      configuration.httpCookieStorage = nil
      configuration.httpShouldSetCookies = false
      self.session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    }
  }

  // MARK: - Internal Request Method

  private func request<T: Decodable>(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:],
    require2xx: Bool = false
  ) async throws -> T {
    let url = baseURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path)

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = timeout
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(sessionId, forHTTPHeaderField: "X-Rehearsal-Session")

    // Add additional headers (e.g., Idempotency-Key)
    for (key, value) in additionalHeaders {
      request.setValue(value, forHTTPHeaderField: key)
    }

    // Encode body if present
    if let body {
      let encoder = JSONEncoder()
      request.httpBody = try encoder.encode(body)
    }

    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw MeridianError.networkError("Invalid response type")
    }

    if require2xx && !(200...299).contains(httpResponse.statusCode) {
      let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw MeridianError.httpError(statusCode: httpResponse.statusCode, message: errorMsg)
    }

    // Check HTTP status
    guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 || httpResponse.statusCode == 202 || httpResponse.statusCode == 400 || httpResponse.statusCode == 409 || httpResponse.statusCode == 422 || httpResponse.statusCode == 503
    else {
      let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw MeridianError.httpError(
        statusCode: httpResponse.statusCode,
        message: errorMsg
      )
    }

    let decoder = JSONDecoder()
    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      throw MeridianError.decodingError(error.localizedDescription)
    }
  }

  // MARK: - Public API Methods

  /// GET /health - Check service health
  public func getHealth() async throws -> HealthResponse {
    return try await request(method: "GET", path: "/health")
  }

  /// GET /catalog - Fetch recipients and the Adyen/Worldpay baseline.
  public func getCatalog() async throws -> CatalogResponse {
    let raw: CatalogResponse = try await request(method: "GET", path: "/catalog", require2xx: true)
    return projectBaselineCatalog(raw)
  }

  /// GET /catalog, then the encrypted local cache when the device is offline or the API times out or returns 5xx.
  /// One request only: a timeout never contacts another host.
  public func loadCatalog(cache: CatalogCache) async -> CatalogLoad {
    do {
      let catalog = try await getCatalog()
      cache.save(sessionId: sessionId, catalog: catalog)
      return CatalogLoad(catalog: catalog, origin: .network)
    } catch {
      if catalogFailureUsesCache(error), let saved = cache.load(sessionId: sessionId) {
        return CatalogLoad(catalog: saved, origin: .cache)
      }
      return CatalogLoad(catalog: nil, origin: nil)
    }
  }

  /// GET /state - Fetch current bank state
  public func getState() async throws -> BankState {
    return try await request(method: "GET", path: "/state")
  }

  /// POST /payments - Submit a payment
  /// - Parameters:
  ///   - recipientId: Recipient ID
  ///   - amountMinor: Amount in GBP pence (integer)
  ///   - method: Payment method (card or bank)
  ///   - note: Optional note (max 200 chars)
  ///   - scenario: Simulation scenario
  ///   - idempotencyKey: Unique key for idempotency
  public func submitPayment(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = .success,
    idempotencyKey: String
  ) async throws -> PaymentResponse {
    let payload = PaymentRequest(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: method,
      note: note,
      scenario: scenario
    )

    return try await request(
      method: "POST",
      path: "/payments",
      body: payload,
      additionalHeaders: ["Idempotency-Key": idempotencyKey]
    )
  }

  /// PATCH /budgets - Update budget for a category
  /// - Parameters:
  ///   - category: Budget category
  ///   - limitMinor: Limit in GBP pence
  public func updateBudget(
    category: Category,
    limitMinor: Int
  ) async throws -> BudgetResponse {
    let payload = BudgetRequest(category: category, limitMinor: limitMinor)
    return try await request(
      method: "PATCH",
      path: "/budgets",
      body: payload
    )
  }

  /// POST /reset - Reset session state
  public func reset() async throws -> ResetResponse {
    return try await request(method: "POST", path: "/reset")
  }

  /// GET /events - Fetch audit events
  public func getEvents() async throws -> EventsResponse {
    return try await request(method: "GET", path: "/events")
  }
}
