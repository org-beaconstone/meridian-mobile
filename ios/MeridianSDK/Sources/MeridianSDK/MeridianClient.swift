import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor MeridianClient {
  private let baseURL: URL
  private let sessionId: String
  private let session: URLSession
  public let telemetry: TelemetryLog
  private let sessionTraceId: String
  private let sessionSpanId: String
  private var lastConnection: String?
  private var lastHealthError: String?
  private var corridorStates: [String: String] = [:]

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  ///   - telemetry: In-memory trace and event log. Defaults to a private log.
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession = .shared,
    telemetry: TelemetryLog = TelemetryLog()
  ) throws {
    guard !sessionId.isEmpty else {
      throw MeridianError.missingSession
    }

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
    self.telemetry = telemetry
    self.sessionTraceId = TraceIds.hex(16)
    self.sessionSpanId = TraceIds.hex(8)
  }

  private struct RawResponse {
    let statusCode: Int
    let body: Data
    let traceId: String
    let spanId: String
  }

  private struct SessionHealthBody: Decodable {
    let status: String?
    let connection: String?
    let corridors: [CorridorBody]?
  }

  private struct CorridorBody: Decodable {
    let id: String?
    let provider: String?
    let state: String?
    let status: String?
  }

  private func endpoint(_ path: String) -> URL {
    path.split(separator: "/").map(String.init).reduce(baseURL) { partial, component in
      partial.appendingPathComponent(component)
    }
  }

  private func beginSpan(_ name: String, parentSpanId: String? = nil) -> SpanToken {
    telemetry.startSpan(
      name: name,
      traceId: sessionTraceId,
      parentSpanId: parentSpanId ?? sessionSpanId
    )
  }

  private func isHandled(_ statusCode: Int) -> Bool {
    (statusCode >= 200 && statusCode < 300) || statusCode == 202 || statusCode == 400 || statusCode == 409 || statusCode == 422 || statusCode == 503
  }

  private func exchange(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:],
    spanName: String,
    recordTransportErrors: Bool = true
  ) async throws -> RawResponse {
    let span = beginSpan(spanName)
    let url = endpoint(path)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(sessionId, forHTTPHeaderField: "X-Rehearsal-Session")
    request.setValue(span.traceparent, forHTTPHeaderField: "traceparent")
    for (key, value) in additionalHeaders {
      request.setValue(value, forHTTPHeaderField: key)
    }
    if let body {
      request.httpBody = try JSONEncoder().encode(body)
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      telemetry.endSpan(span, status: "error", attributes: ["http.path": path])
      if recordTransportErrors {
        telemetry.recordError(
          code: "NETWORK_ERROR",
          stage: "network",
          message: error.localizedDescription,
          traceId: span.traceId,
          spanId: span.spanId,
          attributes: ["http.path": path]
        )
      }
      throw MeridianError.networkError(Sanitizer.sanitize(error.localizedDescription))
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      telemetry.endSpan(span, status: "error", attributes: ["http.path": path])
      telemetry.recordError(
        code: "NETWORK_ERROR",
        stage: "network",
        message: "Invalid response type",
        traceId: span.traceId,
        spanId: span.spanId,
        attributes: ["http.path": path]
      )
      throw MeridianError.networkError("Invalid response type")
    }

    let status = (200...299).contains(httpResponse.statusCode) ? "ok" : "error"
    telemetry.endSpan(
      span,
      status: status,
      attributes: [
        "http.status": String(httpResponse.statusCode),
        "http.path": path,
      ]
    )
    return RawResponse(statusCode: httpResponse.statusCode, body: data, traceId: span.traceId, spanId: span.spanId)
  }

  private func decode<T: Decodable>(_ raw: RawResponse, as type: T.Type, stage: String) throws -> T {
    if !isHandled(raw.statusCode) {
      let message = String(data: raw.body, encoding: .utf8) ?? "Unknown error"
      telemetry.recordError(
        code: "HTTP_\(raw.statusCode)",
        stage: stage,
        message: message,
        traceId: raw.traceId,
        spanId: raw.spanId
      )
      throw MeridianError.httpError(statusCode: raw.statusCode, message: Sanitizer.sanitize(message))
    }

    do {
      return try JSONDecoder().decode(type, from: raw.body)
    } catch {
      telemetry.recordError(
        code: "DECODING_ERROR",
        stage: stage,
        message: error.localizedDescription,
        traceId: raw.traceId,
        spanId: raw.spanId
      )
      throw MeridianError.decodingError(Sanitizer.sanitize(error.localizedDescription))
    }
  }

  private func request<T: Decodable>(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:],
    spanName: String = "http.client",
    stage: String = "network"
  ) async throws -> T {
    let raw = try await exchange(
      method: method,
      path: path,
      body: body,
      additionalHeaders: additionalHeaders,
      spanName: spanName
    )
    return try decode(raw, as: T.self, stage: stage)
  }

  /// GET /health - Check service health
  public func getHealth() async throws -> HealthResponse {
    try await request(method: "GET", path: "/health")
  }

  /// GET /catalog - Fetch recipients and providers. Parsing is timed apart from the roundtrip.
  public func getCatalog() async throws -> CatalogResponse {
    let raw = try await exchange(method: "GET", path: "/catalog", spanName: "http.catalog")
    let parse = beginSpan("catalog.parse", parentSpanId: raw.spanId)
    do {
      let parsed = try decode(raw, as: CatalogResponse.self, stage: "catalog_parse")
      telemetry.endSpan(parse, status: "ok", attributes: ["recipientCount": String(parsed.recipients.count)])
      return parsed
    } catch {
      telemetry.endSpan(parse, status: "error")
      throw error
    }
  }

  /// GET /state - Fetch current bank state
  public func getState() async throws -> BankState {
    try await request(method: "GET", path: "/state")
  }

  /// Local biometric prompt. No credential store and no network call.
  /// An unavailable sensor records an SCA fallback and leaves the selected provider unchanged.
  public func resolveBiometricPrompt(sensorAvailable: Bool = true) -> BiometricResolution {
    let span = beginSpan("biometric.prompt")
    let outcome = sensorAvailable ? "authenticated" : "fallback"
    if !sensorAvailable {
      telemetry.recordError(
        code: "SCA_FALLBACK",
        stage: "biometric",
        message: "Local biometric sensor unavailable",
        traceId: span.traceId,
        spanId: span.spanId,
        attributes: ["outcome": outcome]
      )
    }
    telemetry.endSpan(span, status: sensorAvailable ? "ok" : "error", attributes: ["outcome": outcome])
    return BiometricResolution(outcome: outcome, code: sensorAvailable ? nil : "SCA_FALLBACK")
  }

  /// POST /payments - Submit a payment. The gateway span covers the HTTP roundtrip.
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
    let raw = try await exchange(
      method: "POST",
      path: "/payments",
      body: payload,
      additionalHeaders: ["Idempotency-Key": idempotencyKey],
      spanName: "payment.gateway"
    )
    let response = try decode(raw, as: PaymentResponse.self, stage: "gateway")
    let safe = PaymentResponse(
      ok: response.ok,
      state: response.state,
      transaction: response.transaction,
      error: response.error.map(Sanitizer.sanitize),
      code: response.code,
      paymentId: response.paymentId
    )
    if !safe.ok && safe.code != "PAYMENT_PENDING" {
      telemetry.recordError(
        code: safe.code ?? "GATEWAY_ERROR",
        stage: "gateway",
        message: safe.error ?? "",
        traceId: raw.traceId,
        spanId: raw.spanId
      )
    }
    return safe
  }

  /// PATCH /budgets - Update budget for a category
  public func updateBudget(
    category: Category,
    limitMinor: Int
  ) async throws -> BudgetResponse {
    let payload = BudgetRequest(category: category, limitMinor: limitMinor)
    return try await request(method: "PATCH", path: "/budgets", body: payload)
  }

  /// POST /reset - Reset session state
  public func reset() async throws -> ResetResponse {
    try await request(method: "POST", path: "/reset")
  }

  /// GET /events - Fetch audit events
  public func getEvents() async throws -> EventsResponse {
    try await request(method: "GET", path: "/events")
  }

  /// GET /session/health. Records connection changes and emits an event when a corridor degrades.
  public func checkSessionHealth() async -> SessionHealthSnapshot {
    let raw: RawResponse
    do {
      raw = try await exchange(
        method: "GET",
        path: "/session/health",
        spanName: "session.health",
        recordTransportErrors: false
      )
    } catch {
      return updateHealth(
        connection: "disconnected",
        corridors: [],
        errorCode: "NETWORK_ERROR",
        errorMessage: String(describing: error)
      )
    }

    guard (200...299).contains(raw.statusCode) else {
      let message = String(data: raw.body, encoding: .utf8) ?? ""
      return updateHealth(
        connection: "disconnected",
        corridors: [],
        errorCode: "HTTP_\(raw.statusCode)",
        errorMessage: message
      )
    }

    let parsed: SessionHealthBody
    do {
      parsed = try JSONDecoder().decode(SessionHealthBody.self, from: raw.body)
    } catch {
      return updateHealth(
        connection: "disconnected",
        corridors: [],
        errorCode: "DECODING_ERROR",
        errorMessage: error.localizedDescription
      )
    }

    let corridors = (parsed.corridors ?? []).map { corridor in
      CorridorStatus(
        id: CorridorIds.canonical(id: corridor.id, provider: corridor.provider),
        state: CorridorIds.state(corridor.state, status: corridor.status)
      )
    }
    let connection = CorridorIds.connection(explicit: parsed.connection, status: parsed.status, corridors: corridors)
    return updateHealth(connection: connection, corridors: corridors, errorCode: nil, errorMessage: nil)
  }

  /// Polls /session/health until the returned task is cancelled.
  public func startSessionHealthChecks(
    interval: Duration = .seconds(15),
    onUpdate: @escaping @Sendable (SessionHealthSnapshot) -> Void
  ) -> Task<Void, Never> {
    precondition(interval > .zero, "Health check interval must be positive")
    return Task {
      while !Task.isCancelled {
        let snapshot = await self.checkSessionHealth()
        onUpdate(snapshot)
        try? await Task.sleep(for: interval)
      }
    }
  }

  private func updateHealth(
    connection: String,
    corridors: [CorridorStatus],
    errorCode: String?,
    errorMessage: String?
  ) -> SessionHealthSnapshot {
    var pending: [TelemetryEvent] = []
    if lastConnection != connection {
      pending.append(
        TelemetryEvent(
          name: "connection.state",
          code: connection.uppercased(),
          stage: "health",
          message: "Connection \(connection)",
          traceId: sessionTraceId,
          spanId: sessionSpanId,
          attributes: [
            "previous": lastConnection ?? "unknown",
            "connection": connection,
          ]
        )
      )
      lastConnection = connection
    }
    if let errorCode, errorCode != lastHealthError {
      pending.append(
        TelemetryEvent(
          name: "client.error",
          code: errorCode,
          stage: "health",
          message: errorMessage ?? "",
          traceId: sessionTraceId,
          spanId: sessionSpanId,
          attributes: ["connection": connection]
        )
      )
      lastHealthError = errorCode
    }
    if errorCode == nil {
      lastHealthError = nil
    }
    for corridor in corridors {
      let previous = corridorStates[corridor.id]
      let degraded = corridor.state == "degraded" || corridor.state == "down"
      if degraded && previous != corridor.state {
        pending.append(
          TelemetryEvent(
            name: "corridor.degraded",
            code: "CORRIDOR_DEGRADED",
            stage: "health",
            message: "\(corridor.id) \(corridor.state)",
            traceId: sessionTraceId,
            spanId: sessionSpanId,
            attributes: [
              "corridorId": corridor.id,
              "state": corridor.state,
            ]
          )
        )
      }
      corridorStates[corridor.id] = corridor.state
    }
    for event in pending {
      telemetry.record(event)
    }
    return SessionHealthSnapshot(connection: connection, corridors: corridors)
  }
}
