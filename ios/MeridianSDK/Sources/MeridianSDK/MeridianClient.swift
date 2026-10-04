import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor MeridianClient {
  private let baseURL: URL
  private let sessionId: String
  private let session: URLSession
  private let telemetry: TelemetryCenter

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  ///   - upstreamTraceparent: W3C traceparent from the gateway, continued by this client
  ///   - upstreamTracestate: Optional tracestate forwarded with the gateway trace
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession = .shared,
    upstreamTraceparent: String? = nil,
    upstreamTracestate: String? = nil,
    clock: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) }
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
    self.telemetry = TelemetryCenter(
      upstreamTraceparent: upstreamTraceparent,
      upstreamTracestate: upstreamTracestate,
      vendor: "sdk-ios",
      language: "swift",
      sessionId: sessionId,
      now: clock
    )
  }

  // MARK: - Internal Request Method

  private func request<T: Decodable>(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:],
    query: [URLQueryItem] = [],
    parent: OpenSpan? = nil
  ) async throws -> T {
    let route = Self.displayPath(path)
    let span = telemetry.startHttpSpan(method: method, path: route, parent: parent)
    let url: URL
    do {
      url = try makeURL(path: path, query: query)
    } catch {
      telemetry.noteError(span, String(describing: error))
      telemetry.endSpan(span, status: "error")
      throw error
    }

    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = method
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue(sessionId, forHTTPHeaderField: "X-Rehearsal-Session")

    for (key, value) in additionalHeaders {
      urlRequest.setValue(value, forHTTPHeaderField: key)
    }
    urlRequest.setValue(span.traceparent, forHTTPHeaderField: "traceparent")
    if let tracestate = span.tracestate {
      urlRequest.setValue(tracestate, forHTTPHeaderField: "tracestate")
    }

    if let body {
      do {
        urlRequest.httpBody = try JSONEncoder().encode(body)
      } catch {
        let clean = TelemetrySanitizer.sanitize(error.localizedDescription)
        telemetry.noteError(span, clean)
        telemetry.endSpan(span, status: "error")
        throw MeridianError.networkError(clean)
      }
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: urlRequest)
    } catch {
      let clean = TelemetrySanitizer.sanitize(error.localizedDescription)
      telemetry.noteError(span, clean)
      telemetry.endSpan(span, status: "error")
      throw MeridianError.networkError(clean)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      telemetry.noteError(span, "Invalid response type")
      telemetry.endSpan(span, status: "error")
      throw MeridianError.networkError("Invalid response type")
    }

    let statusCode = httpResponse.statusCode
    telemetry.setAttribute(span, "http.response.status_code", String(statusCode))
    let allowed = (200 ..< 300).contains(statusCode) || [202, 400, 409, 422, 503].contains(statusCode)
    if !allowed {
      let errorMsg = TelemetrySanitizer.sanitize(String(data: data, encoding: .utf8) ?? "Unknown error")
      telemetry.noteError(span, errorMsg)
      telemetry.endSpan(span, status: "error")
      throw MeridianError.httpError(statusCode: statusCode, message: errorMsg)
    }

    let decoded: T
    do {
      decoded = try JSONDecoder().decode(T.self, from: data)
    } catch {
      let clean = TelemetrySanitizer.sanitize(error.localizedDescription)
      telemetry.noteError(span, clean)
      telemetry.endSpan(span, status: "error")
      throw MeridianError.decodingError(clean)
    }

    if statusCode >= 400 {
      let errorMsg = TelemetrySanitizer.sanitize(String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)")
      telemetry.noteError(span, errorMsg)
      telemetry.endSpan(span, status: "error")
    } else {
      telemetry.endSpan(span, status: "ok")
    }
    return decoded
  }

  private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
    let url = baseURL.appendingPathComponent(path)
    guard !query.isEmpty else { return url }
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw MeridianError.invalidURL
    }
    components.queryItems = query
    guard let composed = components.url else {
      throw MeridianError.invalidURL
    }
    return composed
  }

  private static func displayPath(_ path: String) -> String {
    let bare = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
    return bare.hasPrefix("/") ? bare : "/\(bare)"
  }

  // MARK: - Public API Methods

  /// GET /health - Check service health
  public func getHealth() async throws -> HealthResponse {
    return try await request(method: "GET", path: "/health")
  }

  /// GET /session/health - Session-scoped health used by client traces
  public func getSessionHealth() async throws -> SessionHealthResponse {
    return try await request(method: "GET", path: "/session/health")
  }

  /// GET /catalog - Fetch recipients and providers
  public func getCatalog() async throws -> CatalogResponse {
    return try await request(method: "GET", path: "/catalog")
  }

  /// GET /fx/quote - GBP pence quote. Quote currency stays GBP.
  public func getFxQuote(amountMinor: Int) async throws -> FxQuoteResponse {
    guard amountMinor >= 1 && amountMinor <= 1_000_000 else {
      throw MeridianError.invalidAmount("Amount must be 1...1000000 pence")
    }
    return try await request(
      method: "GET",
      path: "/fx/quote",
      query: [
        URLQueryItem(name: "base", value: "GBP"),
        URLQueryItem(name: "quote", value: "GBP"),
        URLQueryItem(name: "amountMinor", value: String(amountMinor)),
      ]
    )
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
    let span = telemetry.startSpan(name: "payment.submit")
    telemetry.setAttribute(span, "meridian.idempotency_key", idempotencyKey)
    telemetry.setAttribute(span, "payment.method", method.rawValue)
    let payload = PaymentRequest(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: method,
      note: note,
      scenario: scenario
    )

    do {
      let result: PaymentResponse = try await request(
        method: "POST",
        path: "/payments",
        body: payload,
        additionalHeaders: ["Idempotency-Key": idempotencyKey],
        parent: span
      )
      let success = result.ok || result.code == "PAYMENT_PENDING"
      if !success {
        telemetry.noteError(span, result.error ?? result.code ?? "payment failed")
      }
      telemetry.endSpan(span, status: success ? "ok" : "error")
      return result
    } catch {
      telemetry.noteError(span, String(describing: error))
      telemetry.endSpan(span, status: "error")
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

  // MARK: - Telemetry

  /// Local rehearsal timer for the biometric prompt SLO. This is not a device biometric.
  public func measureBiometricPrompt() -> BiometricPromptResult {
    telemetry.measureBiometricPrompt()
  }

  public func recordBiometricPrompt(durationMs: Int64) -> BiometricPromptResult {
    telemetry.recordBiometricPrompt(durationMs: durationMs)
  }

  public func recordSca(dropped: Bool, detail: String = "") {
    telemetry.recordSca(dropped: dropped, detail: detail)
  }

  public func addBreadcrumb(_ message: String) {
    telemetry.addBreadcrumb(message)
  }

  public func telemetrySnapshot() -> TelemetrySnapshot {
    telemetry.snapshot()
  }
}
