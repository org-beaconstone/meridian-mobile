import Foundation

public actor MeridianClient {
  private let baseURL: URL
  private let sessionId: String
  private let session: URLSession
  private let traceContext: TraceContext
  private let telemetryConfig: TelemetryConfig

  // Catalog metadata captured during getCatalog() for telemetry correlation.
  private var catalogVersion: String?
  private var catalogFetchedAt: Date?
  private var catalogMethodCount: Int?

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  ///   - telemetry: Configuration for payment telemetry and audit logging
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession = .shared,
    telemetry: TelemetryConfig = TelemetryConfig()
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
    self.traceContext = TraceContext()
    self.telemetryConfig = telemetry
  }

  /// The trace ID for this client session, for correlation in error reports.
  public var traceId: String { traceContext.traceId }

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

    // Propagate distributed trace context on every outgoing request.
    let spanId = TraceContext.newSpanId()
    request.setValue(traceContext.traceparent(spanId: spanId), forHTTPHeaderField: "traceparent")
    request.setValue(traceContext.traceId, forHTTPHeaderField: "X-Trace-Id")

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

  /// GET /catalog - Fetch recipients and providers.
  /// Catalog metadata (version, method count) is stored for telemetry correlation.
  public func getCatalog() async throws -> CatalogResponse {
    let response: CatalogResponse = try await request(method: "GET", path: "/catalog")
    catalogVersion = response.demoDate
    catalogFetchedAt = Date()
    catalogMethodCount = response.providers.flatMap { $0.methods }.count
    return response
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

    let catalogAge = catalogFetchedAt.map { Date().timeIntervalSince($0) }
    let start = Date()

    let response: PaymentResponse
    do {
      response = try await request(
        method: "POST",
        path: "/payments",
        body: payload,
        additionalHeaders: ["Idempotency-Key": idempotencyKey]
      )
    } catch {
      let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
      emitTelemetry(
        outcome: .error, scaInvoked: method == .card,
        latencyMs: latencyMs, catalogAge: catalogAge)
      emitAudit(
        action: "PAYMENT_ERROR", idempotencyKey: idempotencyKey,
        paymentMethod: method.rawValue, outcome: "error", sample: true)
      throw error
    }

    let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
    let outcome: PaymentOutcome =
      response.ok ? .success
      : (response.code == "PAYMENT_PENDING" ? .pending : .declined)

    emitTelemetry(
      outcome: outcome, scaInvoked: method == .card,
      latencyMs: latencyMs, catalogAge: catalogAge)

    // Successful journeys are always audited; failed journeys respect the sampling rate.
    let shouldAudit =
      outcome == .success
      || Double.random(in: 0..<1) < telemetryConfig.failedJourneySamplingRate
    emitAudit(
      action: "PAYMENT_SUBMITTED", idempotencyKey: idempotencyKey,
      paymentMethod: method.rawValue, outcome: outcome.rawValue, sample: shouldAudit)

    return response
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

  // MARK: - Telemetry Helpers

  private func emitTelemetry(
    outcome: PaymentOutcome,
    scaInvoked: Bool,
    latencyMs: Int,
    catalogAge: Double?
  ) {
    guard let onEvent = telemetryConfig.onEvent else { return }
    onEvent(PaymentJourneyEvent(
      traceId: traceContext.traceId,
      catalogAgeSeconds: catalogAge,
      methodCount: catalogMethodCount,
      scaInvoked: scaInvoked,
      latencyMs: latencyMs,
      outcome: outcome,
      timestamp: isoNow()
    ))
  }

  private func emitAudit(
    action: String,
    idempotencyKey: String,
    paymentMethod: String,
    outcome: String,
    sample: Bool
  ) {
    guard sample, let onAudit = telemetryConfig.onAudit else { return }
    onAudit(AuditLogEntry(
      traceId: traceContext.traceId,
      timestamp: isoNow(),
      action: action,
      hashedIdempotencyKey: sha256Hex(idempotencyKey),
      catalogVersion: catalogVersion,
      paymentMethod: paymentMethod,
      outcome: outcome
    ))
  }
}
