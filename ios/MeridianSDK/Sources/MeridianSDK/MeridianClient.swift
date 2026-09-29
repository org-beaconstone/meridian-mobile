import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PaymentCall {
  public let statusCode: Int
  public let response: PaymentResponse
  public let body: Data

  public init(statusCode: Int, response: PaymentResponse, body: Data) {
    self.statusCode = statusCode
    self.response = response
    self.body = body
  }

  public var ok: Bool { response.ok }
  public var state: BankState? { response.state }
  public var transaction: Transaction? { response.transaction }
  public var error: String? { response.error }
  public var code: String? { response.code }
  public var paymentId: String? { response.paymentId }
}

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

  // MARK: - Internal Request Method

  private struct RawHttp {
    let statusCode: Int
    let data: Data
  }

  private func request<T: Decodable>(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:]
  ) async throws -> T {
    let raw = try await exchange(
      method: method,
      path: path,
      body: body,
      additionalHeaders: additionalHeaders
    )
    return try decode(T.self, from: raw.data)
  }

  private func exchange(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:]
  ) async throws -> RawHttp {
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

    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw MeridianError.networkError("Invalid response type")
    }

    let statusCode = httpResponse.statusCode
    // Check HTTP status
    guard statusCode >= 200 && statusCode < 300 || statusCode == 202 || statusCode == 400 || statusCode == 409 || statusCode == 422 || statusCode == 503
    else {
      let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw MeridianError.httpError(
        statusCode: statusCode,
        message: errorMsg
      )
    }

    return RawHttp(statusCode: statusCode, data: data)
  }

  private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
      return try JSONDecoder().decode(T.self, from: data)
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
  ///   - idempotencyKey: Unique key for idempotency. Reuse it for SCA resubmit and uncertain retries.
  ///   - scaChallengeToken: Set only after local biometric or passcode verification. Omitted on the first submit.
  public func submitPayment(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = .success,
    idempotencyKey: String,
    scaChallengeToken: String? = nil
  ) async throws -> PaymentCall {
    let payload = PaymentRequest(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: method,
      note: note,
      scenario: scenario,
      scaChallengeToken: scaChallengeToken
    )

    let raw = try await exchange(
      method: "POST",
      path: "/payments",
      body: payload,
      additionalHeaders: ["Idempotency-Key": idempotencyKey]
    )
    if let response = try? decode(PaymentResponse.self, from: raw.data) {
      return PaymentCall(statusCode: raw.statusCode, response: response, body: raw.data)
    }
    let intercept = ScaInterpreter.intercept(statusCode: raw.statusCode, body: raw.data)
    switch intercept {
    case .notStepUp:
      throw MeridianError.decodingError("Payment response could not be decoded")
    case .invalid, .expired, .required:
      return PaymentCall(
        statusCode: raw.statusCode,
        response: PaymentResponse(
          ok: false,
          state: nil,
          transaction: nil,
          error: ScaCopy.failureMessage,
          code: ScaCopy.stepUpCode,
          paymentId: nil
        ),
        body: raw.data
      )
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
