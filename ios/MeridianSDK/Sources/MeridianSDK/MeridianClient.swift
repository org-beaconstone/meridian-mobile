import Foundation

public actor MeridianClient {
  private struct Transport<T: Decodable> {
    let statusCode: Int
    let body: T
  }

  private let baseURL: URL
  private let sessionId: String
  private let session: URLSession
  private let scaHandler: (any ScaChallengeHandler)?
  private let now: @Sendable () -> Date

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  ///   - scaHandler: Native biometric prompt used when the gateway returns SCA_STEP_UP_REQUIRED
  ///   - now: Clock for the step-up expiry window
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession = .shared,
    scaHandler: (any ScaChallengeHandler)? = nil,
    now: @escaping @Sendable () -> Date = { Date() }
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
    self.scaHandler = scaHandler
    self.now = now
  }

  // MARK: - Internal Request Method

  private func request<T: Decodable>(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:]
  ) async throws -> Transport<T> {
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
      return Transport(statusCode: httpResponse.statusCode, body: try decoder.decode(T.self, from: data))
    } catch {
      throw MeridianError.decodingError(error.localizedDescription)
    }
  }

  // MARK: - Public API Methods

  /// GET /health - Check service health
  public func getHealth() async throws -> HealthResponse {
    return try await request(method: "GET", path: "/health").body
  }

  /// GET /catalog - Fetch recipients and providers
  public func getCatalog() async throws -> CatalogResponse {
    return try await request(method: "GET", path: "/catalog").body
  }

  /// GET /state - Fetch current bank state
  public func getState() async throws -> BankState {
    return try await request(method: "GET", path: "/state").body
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

    let headers = ["Idempotency-Key": idempotencyKey]
    let first: Transport<PaymentResponse> = try await request(
      method: "POST",
      path: "/payments",
      body: payload,
      additionalHeaders: headers
    )
    switch assessSca(statusCode: first.statusCode, body: first.body) {
    case .notRequired:
      return first.body
    case let .malformed(message):
      throw MeridianError.scaMalformed(message)
    case let .ready(challenge):
      if challenge.isExpired(at: now()) {
        throw MeridianError.scaReinitiate(ScaCopy.expired)
      }
      guard let scaHandler else {
        throw MeridianError.scaStepUpRequired(ScaCopy.europeanPayment)
      }
      let accepted = await scaHandler.confirmEuropeanPayment(prompt: ScaCopy.europeanPayment)
      if !accepted {
        throw MeridianError.scaCancelled(ScaCopy.cancelled)
      }
      if challenge.isExpired(at: now()) {
        throw MeridianError.scaReinitiate(ScaCopy.expired)
      }
      let proof = try ScaVerification.token(for: challenge.token)
      var retryHeaders = headers
      retryHeaders[ScaVerification.headerName] = proof
      let second: Transport<PaymentResponse> = try await request(
        method: "POST",
        path: "/payments",
        body: payload,
        additionalHeaders: retryHeaders
      )
      switch assessSca(statusCode: second.statusCode, body: second.body) {
      case .notRequired:
        return second.body
      case .malformed, .ready:
        throw MeridianError.scaReinitiate(ScaCopy.rejected)
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
    ).body
  }

  /// POST /reset - Reset session state
  public func reset() async throws -> ResetResponse {
    return try await request(method: "POST", path: "/reset").body
  }

  /// GET /events - Fetch audit events
  public func getEvents() async throws -> EventsResponse {
    return try await request(method: "GET", path: "/events").body
  }
}
