import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PaymentSubmission {
  public let statusCode: Int
  public let body: PaymentResponse

  public init(statusCode: Int, body: PaymentResponse) {
    self.statusCode = statusCode
    self.body = body
  }
}

public actor MeridianClient {
  private let baseURL: URL
  public let sessionId: String
  private let session: URLSession
  private let timeout: TimeInterval

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  ///   - timeout: Per-request timeout. Uncertain timeouts keep the caller's idempotency key.
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession = .shared,
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
    self.session = urlSession
    self.timeout = timeout
  }

  // MARK: - Internal Request Method

  private func request<T: Decodable>(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:]
  ) async throws -> (value: T, statusCode: Int) {
    let url = baseURL.appendingPathComponent(path)

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = timeout
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
    } catch let error as URLError where error.code == .timedOut {
      throw MeridianError.networkError("Gateway timeout. Retry the same payment.")
    } catch {
      throw MeridianError.networkError(String(describing: error))
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
      return (try decoder.decode(T.self, from: data), httpResponse.statusCode)
    } catch {
      throw MeridianError.decodingError(error.localizedDescription)
    }
  }

  // MARK: - Public API Methods

  /// GET /health - Check service health
  public func getHealth() async throws -> HealthResponse {
    let response: (value: HealthResponse, statusCode: Int) = try await request(method: "GET", path: "/health")
    return response.value
  }

  /// GET /catalog - Fetch recipients and providers
  public func getCatalog() async throws -> CatalogResponse {
    let response: (value: CatalogResponse, statusCode: Int) = try await request(method: "GET", path: "/catalog")
    guard response.statusCode == 200 else {
      throw MeridianError.httpError(statusCode: response.statusCode, message: "Catalog request failed")
    }
    return response.value
  }

  /// GET /state - Fetch current bank state
  public func getState() async throws -> BankState {
    let response: (value: BankState, statusCode: Int) = try await request(method: "GET", path: "/state")
    return response.value
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
    try await submitPaymentDetailed(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: method,
      note: note,
      scenario: scenario,
      idempotencyKey: idempotencyKey
    ).body
  }

  /// POST /payments including the HTTP status so callers can tell 200 settlement from 202 pending.
  /// The idempotency key is sent unchanged. Method stays the caller's card or bank choice.
  public func submitPaymentDetailed(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = .success,
    idempotencyKey: String
  ) async throws -> PaymentSubmission {
    let payload = PaymentRequest(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: method,
      note: note,
      scenario: scenario
    )
    let response: (value: PaymentResponse, statusCode: Int) = try await request(
      method: "POST",
      path: "/payments",
      body: payload,
      additionalHeaders: ["Idempotency-Key": idempotencyKey]
    )
    return PaymentSubmission(statusCode: response.statusCode, body: response.value)
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
    let response: (value: BudgetResponse, statusCode: Int) = try await request(
      method: "PATCH",
      path: "/budgets",
      body: payload
    )
    return response.value
  }

  /// POST /reset - Reset session state
  public func reset() async throws -> ResetResponse {
    let response: (value: ResetResponse, statusCode: Int) = try await request(method: "POST", path: "/reset")
    return response.value
  }

  /// GET /events - Fetch audit events
  public func getEvents() async throws -> EventsResponse {
    let response: (value: EventsResponse, statusCode: Int) = try await request(method: "GET", path: "/events")
    return response.value
  }
}
