import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor MeridianClient {
  private let baseURL: URL
  private let sessionId: String
  private let session: URLSession

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession = .shared
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
  }

  /// Extra attempts after an uncertain transport failure. The same session and idempotency key are reused.
  public var maxTransportRetries = 2

  // MARK: - Internal Request Method

  private func request<T: Decodable>(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:]
  ) async throws -> T {
    let url = baseURL.appendingPathComponent(path)

    var request = URLRequest(url: url)
    request.httpMethod = method
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

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as MeridianError {
      throw error
    } catch {
      throw MeridianError.networkError(error.localizedDescription)
    }

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
  public func getCatalog() async throws -> CatalogResponse {
    return try await request(method: "GET", path: "/catalog")
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
    let provider = providerFor(method: method)
    var attempt = 0
    while true {
      try refuseProviderSwitch(from: provider, to: providerFor(method: method))
      do {
        return try await request(
          method: "POST",
          path: "/payments",
          body: payload,
          additionalHeaders: ["Idempotency-Key": idempotencyKey]
        )
      } catch let error as MeridianError {
        if case .networkError = error, attempt < maxTransportRetries {
          attempt += 1
          continue
        }
        throw error
      }
    }
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
