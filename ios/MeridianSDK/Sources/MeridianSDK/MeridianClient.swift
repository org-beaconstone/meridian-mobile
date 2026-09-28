import Foundation

public actor MeridianClient {
  private let baseURL: URL
  private let sessionId: String
  private let session: URLSession
  public nonisolated let telemetry: TelemetryLog
  private var healthTask: Task<Void, Never>?

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  ///   - telemetry: In-memory trace and event log. A new log is used when omitted.
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
  }

  private struct RawHTTP {
    let data: Data
    let statusCode: Int
    let trace: TraceContext?
  }

  private func perform(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:],
    trace: TraceContext? = nil,
    failureStage: String
  ) async throws -> RawHTTP {
    let url = baseURL.appendingPathComponent(path)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(sessionId, forHTTPHeaderField: "X-Rehearsal-Session")
    for (key, value) in additionalHeaders {
      request.setValue(value, forHTTPHeaderField: key)
    }

    let activeTrace = trace ?? (shouldInjectTraceparent(path: path) ? TraceContext.root() : nil)
    if let activeTrace {
      request.setValue(activeTrace.traceparent, forHTTPHeaderField: "traceparent")
    }

    if let body {
      request.httpBody = try JSONEncoder().encode(body)
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      telemetry.recordError(code: "NETWORK_ERROR", stage: failureStage)
      throw MeridianError.networkError(TelemetrySanitizer.redact(error.localizedDescription))
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      telemetry.recordError(code: "NETWORK_ERROR", stage: failureStage)
      throw MeridianError.networkError("Invalid response type")
    }

    return RawHTTP(data: data, statusCode: httpResponse.statusCode, trace: activeTrace)
  }

  private func decode<T: Decodable>(
    _ type: T.Type,
    from data: Data,
    statusCode: Int,
    stage: String
  ) throws -> T {
    let acceptable = (200..<300).contains(statusCode) || statusCode == 202 || statusCode == 400 || statusCode == 409 || statusCode == 422 || statusCode == 503
    guard acceptable else {
      let message = TelemetrySanitizer.redact(String(data: data, encoding: .utf8) ?? "Unknown error")
      telemetry.recordError(code: "HTTP_\(statusCode)", stage: stage)
      throw MeridianError.httpError(statusCode: statusCode, message: message)
    }
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      let message = TelemetrySanitizer.redact(error.localizedDescription)
      telemetry.recordError(code: "DECODING_ERROR", stage: stage)
      throw MeridianError.decodingError(message)
    }
  }

  private func request<T: Decodable>(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:],
    failureStage: String = "network"
  ) async throws -> T {
    let raw = try await perform(
      method: method,
      path: path,
      body: body,
      additionalHeaders: additionalHeaders,
      failureStage: failureStage
    )
    return try decode(T.self, from: raw.data, statusCode: raw.statusCode, stage: failureStage)
  }

  public func getHealth() async throws -> HealthResponse {
    try await request(method: "GET", path: "/health")
  }

  public func getCatalog() async throws -> CatalogResponse {
    let raw = try await perform(method: "GET", path: "/catalog", failureStage: "network")
    guard (200..<300).contains(raw.statusCode) else {
      let message = TelemetrySanitizer.redact(String(data: raw.data, encoding: .utf8) ?? "Unknown error")
      telemetry.recordError(code: "HTTP_\(raw.statusCode)", stage: "network")
      throw MeridianError.httpError(statusCode: raw.statusCode, message: message)
    }
    let started = ContinuousClock.now
    let child = raw.trace?.child() ?? TraceContext.root()
    do {
      let decoded = try JSONDecoder().decode(CatalogResponse.self, from: raw.data)
      telemetry.recordSpan(
        name: "catalog.parse",
        context: child,
        parentSpanId: raw.trace?.spanId,
        durationMillis: MonotonicMark.millis(since: started),
        status: "ok",
        attributes: [
          "http.route": "/api/v1/catalog",
          "recipient.count": String(decoded.recipients.count),
          "provider.count": String(decoded.providers.count),
        ]
      )
      return decoded
    } catch {
      telemetry.recordSpan(
        name: "catalog.parse",
        context: child,
        parentSpanId: raw.trace?.spanId,
        durationMillis: MonotonicMark.millis(since: started),
        status: "error",
        attributes: ["http.route": "/api/v1/catalog"]
      )
      telemetry.recordError(
        code: "DECODING_ERROR",
        stage: "catalog_parse",
        attributes: ["error.message": error.localizedDescription]
      )
      throw MeridianError.decodingError(TelemetrySanitizer.redact(error.localizedDescription))
    }
  }

  public func getState() async throws -> BankState {
    try await request(method: "GET", path: "/state")
  }

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
    let trace = TraceContext.root()
    let started = ContinuousClock.now
    let provider = method == .card ? "adyen" : "worldpay"
    var closed = false
    func close(status: String, statusCode: Int?, outcome: String?, message: String?) {
      if closed { return }
      closed = true
      var attributes = [
        "http.route": "/api/v1/payments",
        "http.method": "POST",
        "payment.method": method.rawValue,
        "payment.provider": provider,
      ]
      if let statusCode {
        attributes["http.status_code"] = String(statusCode)
      }
      if let outcome {
        attributes["outcome"] = outcome
      }
      if let message {
        attributes["error.message"] = message
      }
      telemetry.recordSpan(
        name: "payment.gateway",
        context: trace,
        parentSpanId: nil,
        durationMillis: MonotonicMark.millis(since: started),
        status: status,
        attributes: attributes
      )
    }

    let raw: RawHTTP
    do {
      raw = try await perform(
        method: "POST",
        path: "/payments",
        body: payload,
        additionalHeaders: ["Idempotency-Key": idempotencyKey],
        trace: trace,
        failureStage: "gateway_roundtrip"
      )
    } catch {
      close(status: "error", statusCode: nil, outcome: "network", message: nil)
      throw error
    }

    let decoded: PaymentResponse
    do {
      decoded = try decode(PaymentResponse.self, from: raw.data, statusCode: raw.statusCode, stage: "gateway_roundtrip")
    } catch {
      close(status: "error", statusCode: raw.statusCode, outcome: "error", message: nil)
      throw error
    }

    let outcome = decoded.ok ? "ok" : (decoded.code ?? "error")
    close(
      status: decoded.ok ? "ok" : "error",
      statusCode: raw.statusCode,
      outcome: outcome,
      message: decoded.error
    )
    if !decoded.ok {
      let code = decoded.code ?? "GATEWAY_ERROR"
      var attributes = [
        "http.route": "/api/v1/payments",
        "http.status_code": String(raw.statusCode),
        "payment.method": method.rawValue,
        "payment.provider": provider,
        "outcome": outcome,
      ]
      if let message = decoded.error {
        attributes["error.message"] = message
      }
      if code.uppercased().contains("SCA") {
        telemetry.recordEvent(name: "sca.fallback", code: code, stage: "sca_challenge", attributes: attributes)
      } else {
        telemetry.recordError(code: code, stage: "gateway_roundtrip", attributes: attributes)
      }
    }
    return decoded
  }

  public func updateBudget(
    category: Category,
    limitMinor: Int
  ) async throws -> BudgetResponse {
    let payload = BudgetRequest(category: category, limitMinor: limitMinor)
    return try await request(method: "PATCH", path: "/budgets", body: payload)
  }

  public func reset() async throws -> ResetResponse {
    try await request(method: "POST", path: "/reset")
  }

  public func getEvents() async throws -> EventsResponse {
    try await request(method: "GET", path: "/events")
  }

  /// Local rehearsal biometric resolution. This does not call a device
  /// authenticator or a payment provider. A fallback keeps the same provider.
  public func resolveLocalBiometricPrompt(
    method: PaymentMethod,
    accepted: Bool = true,
    available: Bool = true
  ) -> BiometricResolution {
    let started = ContinuousClock.now
    let trace = TraceContext.root()
    let provider = method == .card ? "adyen" : "worldpay"
    let attributes = [
      "payment.method": method.rawValue,
      "payment.provider": provider,
    ]
    let duration = MonotonicMark.millis(since: started)
    if !available {
      var fallbackAttributes = attributes
      fallbackAttributes["outcome"] = "fallback"
      telemetry.recordSpan(
        name: "biometric.prompt",
        context: trace,
        parentSpanId: nil,
        durationMillis: duration,
        status: "fallback",
        attributes: fallbackAttributes
      )
      telemetry.recordEvent(
        name: "sca.fallback",
        code: "SCA_CHALLENGE_FALLBACK",
        stage: "biometric_prompt",
        attributes: attributes
      )
      return BiometricResolution(accepted: false, fallback: true, durationMillis: duration)
    }
    if !accepted {
      var declinedAttributes = attributes
      declinedAttributes["outcome"] = "declined"
      telemetry.recordSpan(
        name: "biometric.prompt",
        context: trace,
        parentSpanId: nil,
        durationMillis: duration,
        status: "error",
        attributes: declinedAttributes
      )
      telemetry.recordError(code: "BIOMETRIC_DECLINED", stage: "biometric_prompt", attributes: attributes)
      return BiometricResolution(accepted: false, fallback: false, durationMillis: duration)
    }
    var acceptedAttributes = attributes
    acceptedAttributes["outcome"] = "accepted"
    telemetry.recordSpan(
      name: "biometric.prompt",
      context: trace,
      parentSpanId: nil,
      durationMillis: duration,
      status: "ok",
      attributes: acceptedAttributes
    )
    return BiometricResolution(accepted: true, fallback: false, durationMillis: duration)
  }

  /// GET /session/health. Transport failures become an unreachable report
  /// instead of throwing, so a corridor probe cannot abort a payment retry.
  public func checkSessionHealth() async -> SessionHealthReport {
    let started = ContinuousClock.now
    let trace = TraceContext.root()
    do {
      let raw = try await perform(
        method: "GET",
        path: "/session/health",
        trace: trace,
        failureStage: "session_health"
      )
      let report = SessionHealthParser.parse(statusCode: raw.statusCode, data: raw.data)
      let duration = MonotonicMark.millis(since: started)
      telemetry.recordSpan(
        name: "session.health",
        context: trace,
        parentSpanId: nil,
        durationMillis: duration,
        status: report.connectionState == "healthy" ? "ok" : "error",
        attributes: [
          "http.route": "/api/v1/session/health",
          "http.method": "GET",
          "http.status_code": String(raw.statusCode),
          "connection.current": report.connectionState,
        ]
      )
      telemetry.observeSessionHealth(report, durationMillis: duration)
      return report
    } catch {
      let report = SessionHealthReport(connectionState: "unreachable", httpStatus: nil, corridors: [])
      let duration = MonotonicMark.millis(since: started)
      telemetry.recordSpan(
        name: "session.health",
        context: trace,
        parentSpanId: nil,
        durationMillis: duration,
        status: "error",
        attributes: [
          "http.route": "/api/v1/session/health",
          "http.method": "GET",
          "connection.current": "unreachable",
        ]
      )
      telemetry.observeSessionHealth(report, durationMillis: duration)
      return report
    }
  }

  public func startSessionHealthChecks(every seconds: Double = 15) {
    healthTask?.cancel()
    let interval = max(1, seconds)
    healthTask = Task { [self] in
      while !Task.isCancelled {
        _ = await self.checkSessionHealth()
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
      }
    }
  }

  public func stopSessionHealthChecks() {
    healthTask?.cancel()
    healthTask = nil
  }
}
