import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor MeridianClient {
  private let baseURL: URL
  private let sessionId: String
  private let session: URLSession
  public let idempotency: IdempotencyKeyManager

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  ///   - idempotency: Key manager used for payment attempts. Defaults to an in-memory store.
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession = .shared,
    idempotency: IdempotencyKeyManager? = nil
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
    self.idempotency = try idempotency ?? IdempotencyKeyManager()
  }

  // MARK: - Internal Request Method

  private func request<T: Decodable>(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:]
  ) async throws -> T {
    if method.uppercased() == "POST" && path == "/payments" {
      let idempotencyKey = additionalHeaders[IdempotencyKeyManager.header] ?? ""
      if idempotencyKey.isEmpty {
        throw MeridianError.validationError("Idempotency-Key header is required for payment requests")
      }
    }
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

  /// Start a payment attempt and persist its UUID v4 idempotency key.
  /// Review screens call this before the first network request.
  @discardableResult
  public func preparePayment(
    transactionId: String,
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = .success
  ) throws -> String {
    try idempotency.begin(
      transactionId: transactionId,
      fingerprint: attempt(
        recipientId: recipientId,
        amountMinor: amountMinor,
        method: method,
        note: note,
        scenario: scenario
      ).fingerprint()
    )
  }

  /// POST /payments - Submit a payment.
  /// Pass `transactionId` to generate and retain a UUID v4 key for the attempt.
  /// An explicit `idempotencyKey` is still sent as the header for callers that already hold one.
  public func submitPayment(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = .success,
    idempotencyKey: String? = nil,
    transactionId: String? = nil
  ) async throws -> PaymentResponse {
    try await postPayment(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: method,
      note: note,
      scenario: scenario,
      idempotencyKey: idempotencyKey,
      transactionId: transactionId,
      mode: .initialOrRetry
    )
  }

  /// Network retry of an in-flight payment. Reuses the stored key and never mints a replacement.
  public func retryPayment(
    transactionId: String,
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = .success
  ) async throws -> PaymentResponse {
    try await postPayment(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: method,
      note: note,
      scenario: scenario,
      idempotencyKey: nil,
      transactionId: transactionId,
      mode: .retry
    )
  }

  /// Two-factor challenge submission for an in-flight payment.
  /// Uses the same Idempotency-Key and the same payment body as the original attempt.
  public func submitChallenge(
    transactionId: String,
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = .success
  ) async throws -> PaymentResponse {
    try await postPayment(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: method,
      note: note,
      scenario: scenario,
      idempotencyKey: nil,
      transactionId: transactionId,
      mode: .challenge
    )
  }

  public func cancelTransaction(transactionId: String) throws {
    try idempotency.cancel(transactionId: transactionId)
  }

  private enum KeyMode {
    case initialOrRetry
    case retry
    case challenge
  }

  private func postPayment(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String,
    scenario: Scenario,
    idempotencyKey: String?,
    transactionId: String?,
    mode: KeyMode
  ) async throws -> PaymentResponse {
    let fingerprint = attempt(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: method,
      note: note,
      scenario: scenario
    ).fingerprint()
    let key = try resolveKey(
      transactionId: transactionId,
      idempotencyKey: idempotencyKey,
      fingerprint: fingerprint,
      mode: mode
    )
    let payload = PaymentRequest(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: method,
      note: note,
      scenario: scenario
    )
    let response: PaymentResponse = try await request(
      method: "POST",
      path: "/payments",
      body: payload,
      additionalHeaders: [IdempotencyKeyManager.header: key]
    )
    if let transactionId, isTerminalSuccess(response) {
      try idempotency.settle(transactionId: transactionId)
    }
    return response
  }

  private func resolveKey(
    transactionId: String?,
    idempotencyKey: String?,
    fingerprint: String,
    mode: KeyMode
  ) throws -> String {
    let managed = !(transactionId ?? "").isEmpty
    let explicit = !(idempotencyKey ?? "").isEmpty
    if managed && explicit {
      throw MeridianError.validationError("Pass either a managed transaction id or an explicit idempotency key")
    }
    if !managed {
      guard let idempotencyKey, !idempotencyKey.isEmpty else {
        throw MeridianError.validationError("An idempotency key or transaction id is required")
      }
      return idempotencyKey
    }
    let id = transactionId!
    switch mode {
    case .retry:
      return try idempotency.keyForRetry(transactionId: id, fingerprint: fingerprint)
    case .challenge:
      return try idempotency.keyForChallenge(transactionId: id, fingerprint: fingerprint)
    case .initialOrRetry:
      do {
        return try idempotency.keyForRetry(transactionId: id, fingerprint: fingerprint)
      } catch MeridianError.missingIdempotencyKey(_) {
        return try idempotency.begin(transactionId: id, fingerprint: fingerprint)
      }
    }
  }

  private func isTerminalSuccess(_ response: PaymentResponse) -> Bool {
    if !response.ok { return false }
    if response.code == "PAYMENT_PENDING" { return false }
    if response.transaction?.status == .pending { return false }
    return true
  }

  private func attempt(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String,
    scenario: Scenario
  ) -> PaymentAttempt {
    PaymentAttempt(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: method.rawValue,
      note: note,
      scenario: scenario.rawValue
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
