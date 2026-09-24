import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor MeridianClient {
  private let baseURL: URL
  private let sessionId: String
  private let session: URLSession
  private let catalogCache: ProviderCatalogCache

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  ///   - catalogTTL: In-memory lifetime of a successfully fetched provider catalog
  ///   - catalogClock: Clock used for the catalog time-to-live
  ///   - catalogLogger: Receives configuration fetch success, failure, and fallback logs
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession = .shared,
    catalogTTL: TimeInterval = ProviderCatalogCache.defaultTTL,
    catalogClock: @escaping @Sendable () -> Date = { Date() },
    catalogLogger: any CatalogMetricLogging = StandardCatalogMetricLog()
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
    self.session = urlSession
    self.catalogCache = ProviderCatalogCache(
      ttl: catalogTTL,
      clock: catalogClock,
      logger: catalogLogger
    )
  }

  // MARK: - Internal Request Method

  private func request<T: Decodable>(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:],
    timeout: TimeInterval? = nil
  ) async throws -> T {
    let url = baseURL.appendingPathComponent(path)

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(sessionId, forHTTPHeaderField: "X-Rehearsal-Session")
    if let timeout {
      request.timeoutInterval = timeout
    }

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

  /// GET /catalog - Fetch recipients and providers
  public func getCatalog(timeout: TimeInterval? = nil) async throws -> CatalogResponse {
    return try await request(method: "GET", path: "/catalog", timeout: timeout)
  }

  /// Config-driven provider list. Serves the in-memory cache inside its time-to-live.
  /// Fetch failure, timeout, or a malformed catalog falls back to the last-known-good list.
  public func loadProviderConfiguration() async -> ProviderConfiguration {
    if let fresh = await catalogCache.freshConfiguration() {
      return fresh
    }
    do {
      let catalog = try await getCatalog(timeout: ProviderCatalogCache.fetchTimeout)
      return await catalogCache.store(catalog: catalog, sessionId: sessionId)
    } catch {
      return await catalogCache.fail(
        detail: CatalogFailureDetail.describe(error),
        sessionId: sessionId
      )
    }
  }

  public func providerCatalogMetrics() async -> CatalogFetchMetrics {
    await catalogCache.currentMetrics()
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
    try await submitPayment(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: method.rawValue,
      note: note,
      scenario: scenario,
      idempotencyKey: idempotencyKey
    )
  }

  /// Submits a payment for a catalog method id (`adyen_card`, `worldpay_bank`) or the
  /// existing wire values (`card`, `bank`). The idempotency key is forwarded unchanged.
  /// The JSON body still uses `card` or `bank`, matching meridian-api.
  public func submitPayment(
    recipientId: String,
    amountMinor: Int,
    method: String,
    note: String = "",
    scenario: Scenario = .success,
    idempotencyKey: String
  ) async throws -> PaymentResponse {
    let payload = try PaymentSubmission.request(
      recipientId: recipientId,
      amountMinor: amountMinor,
      methodId: method,
      note: note,
      scenario: scenario
    )

    return try await request(
      method: "POST",
      path: "/payments",
      body: payload,
      additionalHeaders: PaymentSubmission.headers(idempotencyKey: idempotencyKey)
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
