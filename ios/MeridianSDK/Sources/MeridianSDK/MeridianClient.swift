import Foundation

public actor MeridianClient {
  private let baseURL: URL
  private let sessionId: String
  private let session: URLSession
  private let telemetryConfig: TelemetryConfig

  /// Cached catalog from the most recent `getCatalog()` call, used for telemetry enrichment.
  private var cachedCatalog: CatalogResponse?

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - telemetryConfig: Configuration for audit logging and distributed tracing
  ///   - urlSession: Optional URLSession for testing
  public init(
    baseURL: String,
    sessionId: String,
    telemetryConfig: TelemetryConfig = TelemetryConfig(),
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
    self.telemetryConfig = telemetryConfig
    self.session = urlSession
  }

  // MARK: - Internal Request Method

  private func request<T: Decodable>(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:],
    traceContext: TraceContext = TraceContext.generate()
  ) async throws -> T {
    let url = baseURL.appendingPathComponent(path)

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(sessionId, forHTTPHeaderField: "X-Rehearsal-Session")
    request.setValue(traceContext.traceparent, forHTTPHeaderField: "X-Trace-ID")

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
  /// Caches the response for telemetry enrichment of subsequent payment calls.
  public func getCatalog() async throws -> CatalogResponse {
    let catalog: CatalogResponse = try await request(method: "GET", path: "/catalog")
    cachedCatalog = catalog
    return catalog
  }

  /// GET /state - Fetch current bank state
  public func getState() async throws -> BankState {
    return try await request(method: "GET", path: "/state")
  }

  /// POST /payments - Submit a payment
  ///
  /// Emits a structured `AuditLogEntry` on every call via the configured `TelemetryConfig`.
  /// The idempotency key is hashed (SHA-256) before logging; no raw key, token, or bank
  /// credential ever appears in telemetry. Failed-journey entries are subject to the
  /// configured `TelemetryConfig.failedJourneySampleRate`.
  ///
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
    let trace = TraceContext.generate()
    let startMs = Int(Date().timeIntervalSince1970 * 1000)
    var outcome = "error"

    do {
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
        additionalHeaders: ["Idempotency-Key": idempotencyKey],
        traceContext: trace
      )

      outcome = response.ok ? "success"
        : response.code == "PAYMENT_PENDING" ? "pending"
        : "declined"

      emitPaymentTelemetry(
        trace: trace,
        outcome: outcome,
        idempotencyKey: idempotencyKey,
        method: method,
        amountMinor: amountMinor,
        latencyMs: Int(Date().timeIntervalSince1970 * 1000) - startMs
      )
      return response
    } catch {
      emitPaymentTelemetry(
        trace: trace,
        outcome: "error",
        idempotencyKey: idempotencyKey,
        method: method,
        amountMinor: amountMinor,
        latencyMs: Int(Date().timeIntervalSince1970 * 1000) - startMs
      )
      throw error
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

  // MARK: - Private Telemetry Helpers

  private func emitPaymentTelemetry(
    trace: TraceContext,
    outcome: String,
    idempotencyKey: String,
    method: PaymentMethod,
    amountMinor: Int,
    latencyMs: Int
  ) {
    // Successful journeys always log; failed journeys are subject to sampling.
    let sampled = outcome == "success" || Double.random(in: 0.0..<1.0) < telemetryConfig.failedJourneySampleRate
    guard sampled else { return }

    let catalog = cachedCatalog
    let catalogAgeDays: Int? = catalog.flatMap { c in
      let fmt = DateFormatter()
      fmt.dateFormat = "yyyy-MM-dd"
      guard let demoDate = fmt.date(from: c.demoDate) else { return nil }
      return Calendar.current.dateComponents([.day], from: demoDate, to: Date()).day
    }
    let methodCount = catalog.map { c in c.providers.reduce(0) { $0 + $1.methods.count } }

    // SCA (PSD2) applies to bank-method payments and to journeys that returned pending.
    let scaInvoked = method == .bank || outcome == "pending"

    let entry = AuditLogEntry(
      traceId: trace.traceId,
      timestamp: ISO8601DateFormatter().string(from: Date()),
      event: "payment.completed",
      outcome: outcome,
      hashedIdempotencyKey: hashIdempotencyKey(idempotencyKey),
      catalogAgeDays: catalogAgeDays,
      methodCount: methodCount,
      scaInvoked: scaInvoked,
      latencyMs: latencyMs,
      amountMinor: amountMinor,
      paymentMethod: method.rawValue
    )

    telemetryConfig.onEntry(entry)
  }
}
