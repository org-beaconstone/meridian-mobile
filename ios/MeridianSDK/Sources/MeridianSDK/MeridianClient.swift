import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor MeridianClient {
  private let baseURL: URL
  private let sessionId: String
  private let transport: any MeridianHTTPTransport
  private let features: MeridianFeatures
  private let providerCacheTTL: TimeInterval
  private let providerFetchTimeout: TimeInterval
  private let now: @Sendable () -> Date
  private let metricsHandler: (@Sendable (ProviderConfigMetricEvent) -> Void)?
  private var providerCache: (options: [PaymentMethodOption], fetchedAt: Date)?
  private var metricEvents: [ProviderConfigMetricEvent] = []
  private var paymentLogs: [PaymentTransactionLog] = []

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1" or an HTTPS host)
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  ///   - features: Feature flags. Config-driven providers default off.
  ///   - providerCacheTTL: In-memory lifetime for a successful provider list.
  ///   - providerFetchTimeout: Catalog fetch timeout before last-known-good fallback.
  ///   - metricsHandler: Receives provider-config metric events as they are emitted.
  ///   - now: Clock used for the provider cache TTL.
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession = .shared,
    features: MeridianFeatures = MeridianFeatures(),
    providerCacheTTL: TimeInterval = 30,
    providerFetchTimeout: TimeInterval = 3,
    metricsHandler: (@Sendable (ProviderConfigMetricEvent) -> Void)? = nil,
    now: @escaping @Sendable () -> Date = { Date() }
  ) throws {
    try self.init(
      validatedBaseURL: Self.validatedBaseURL(baseURL, sessionId: sessionId),
      sessionId: sessionId,
      transport: URLSessionTransport(session: urlSession),
      features: features,
      providerCacheTTL: providerCacheTTL,
      providerFetchTimeout: providerFetchTimeout,
      metricsHandler: metricsHandler,
      now: now
    )
  }

  init(
    baseURL: String,
    sessionId: String,
    transport: any MeridianHTTPTransport,
    features: MeridianFeatures = MeridianFeatures(),
    providerCacheTTL: TimeInterval = 30,
    providerFetchTimeout: TimeInterval = 3,
    metricsHandler: (@Sendable (ProviderConfigMetricEvent) -> Void)? = nil,
    now: @escaping @Sendable () -> Date = { Date() }
  ) throws {
    try self.init(
      validatedBaseURL: Self.validatedBaseURL(baseURL, sessionId: sessionId),
      sessionId: sessionId,
      transport: transport,
      features: features,
      providerCacheTTL: providerCacheTTL,
      providerFetchTimeout: providerFetchTimeout,
      metricsHandler: metricsHandler,
      now: now
    )
  }

  private init(
    validatedBaseURL: URL,
    sessionId: String,
    transport: any MeridianHTTPTransport,
    features: MeridianFeatures,
    providerCacheTTL: TimeInterval,
    providerFetchTimeout: TimeInterval,
    metricsHandler: (@Sendable (ProviderConfigMetricEvent) -> Void)?,
    now: @escaping @Sendable () -> Date
  ) {
    self.baseURL = validatedBaseURL
    self.sessionId = sessionId
    self.transport = transport
    self.features = features
    self.providerCacheTTL = providerCacheTTL
    self.providerFetchTimeout = providerFetchTimeout
    self.metricsHandler = metricsHandler
    self.now = now
  }

  private static func validatedBaseURL(_ baseURL: String, sessionId: String) throws -> URL {
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
    return url
  }

  // MARK: - Internal Request Method

  private func perform(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:],
    timeout: TimeInterval? = nil
  ) async throws -> (Data, HTTPURLResponse) {
    let url = baseURL.appendingPathComponent(path)

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(sessionId, forHTTPHeaderField: "X-Rehearsal-Session")
    if let timeout {
      request.timeoutInterval = timeout
      request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    }

    // Add additional headers (e.g., Idempotency-Key)
    for (key, value) in additionalHeaders {
      request.setValue(value, forHTTPHeaderField: key)
    }

    // Encode body if present
    if let body {
      let encoder = JSONEncoder()
      request.httpBody = try encoder.encode(body)
    }

    let (data, response) = try await transport.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw MeridianError.networkError("Invalid response type")
    }

    return (data, httpResponse)
  }

  private func request<T: Decodable>(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:]
  ) async throws -> T {
    let (data, httpResponse) = try await perform(
      method: method,
      path: path,
      body: body,
      additionalHeaders: additionalHeaders
    )

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

  /// Provider methods for the picker.
  ///
  /// With `configDrivenProviders` off, this is the hardcoded Adyen card and Worldpay bank list
  /// and does not touch the network. With the flag on, the list is read from `GET /catalog`
  /// over the configured base URL (HTTPS for a shared host), cached for a short TTL, and
  /// replaced by the last-known-good list — or the same two-provider baseline — if the fetch
  /// fails, times out, or is malformed. This path does not throw.
  public func paymentMethodOptions() async -> [PaymentMethodOption] {
    if !features.configDrivenProviders {
      return ProviderConfiguration.baseline
    }
    if let providerCache, now().timeIntervalSince(providerCache.fetchedAt) < providerCacheTTL {
      return providerCache.options
    }

    switch await fetchProviderCatalog() {
    case let .ready(options, correlationId):
      providerCache = (options, now())
      emit(.fetchSuccess, correlationId: correlationId, reason: nil)
      return options
    case let .failed(reason, correlationId):
      emit(.fetchFailure, correlationId: correlationId, reason: reason)
      if let providerCache {
        emit(.fallbackToCache, correlationId: correlationId, reason: reason)
        return providerCache.options
      }
      emit(.fallbackToBaseline, correlationId: correlationId, reason: reason)
      return ProviderConfiguration.baseline
    }
  }

  public func providerConfigMetrics() -> ProviderConfigMetrics {
    ProviderConfigMetrics(
      fetchSuccess: metricEvents.filter { $0.kind == .fetchSuccess }.count,
      fetchFailure: metricEvents.filter { $0.kind == .fetchFailure }.count,
      fallbackToCache: metricEvents.filter { $0.kind == .fallbackToCache }.count,
      fallbackToBaseline: metricEvents.filter { $0.kind == .fallbackToBaseline }.count,
      events: metricEvents
    )
  }

  public func paymentTransactionLogs() -> [PaymentTransactionLog] {
    paymentLogs
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
  ///   - idempotencyKey: Unique key for idempotency. Retained as supplied; never rewritten.
  public func submitPayment(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = .success,
    idempotencyKey: String
  ) async throws -> PaymentResponse {
    guard let option = ProviderConfiguration.baseline.first(where: { $0.method == method }) else {
      throw MeridianError.validationError("Unknown payment method")
    }
    return try await performSubmit(
      recipientId: recipientId,
      amountMinor: amountMinor,
      option: option,
      note: note,
      scenario: scenario,
      idempotencyKey: idempotencyKey
    )
  }

  /// POST /payments using a provider-method id from `paymentMethodOptions()`.
  ///
  /// The idempotency key is forwarded unchanged. The JSON `method` field stays `card` or `bank`;
  /// the option id is not substituted into the body or the key. A timeout does not select a different provider.
  public func submitPayment(
    recipientId: String,
    amountMinor: Int,
    methodId: String,
    note: String = "",
    scenario: Scenario = .success,
    idempotencyKey: String
  ) async throws -> PaymentResponse {
    let options = await paymentMethodOptions()
    guard let option = options.first(where: { $0.id == methodId }) else {
      throw MeridianError.validationError("Unknown payment method")
    }
    return try await performSubmit(
      recipientId: recipientId,
      amountMinor: amountMinor,
      option: option,
      note: note,
      scenario: scenario,
      idempotencyKey: idempotencyKey
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

  // MARK: - Provider catalog

  private enum CatalogFetchResult {
    case ready([PaymentMethodOption], correlationId: String?)
    case failed(reason: String, correlationId: String?)
  }

  private func fetchProviderCatalog() async -> CatalogFetchResult {
    do {
      let (data, http) = try await perform(
        method: "GET",
        path: "/catalog",
        timeout: providerFetchTimeout
      )
      let correlationId = Self.correlationIdentifier(from: http, body: data)
      guard (200..<300).contains(http.statusCode) else {
        return .failed(reason: Self.httpFailureReason(http.statusCode, body: data), correlationId: correlationId)
      }
      let catalog: CatalogResponse
      do {
        catalog = try JSONDecoder().decode(CatalogResponse.self, from: data)
      } catch {
        return .failed(reason: "malformed-catalog", correlationId: correlationId)
      }
      guard let options = ProviderConfiguration.options(from: catalog) else {
        return .failed(reason: "incomplete-catalog", correlationId: correlationId)
      }
      return .ready(options, correlationId: correlationId)
    } catch {
      return .failed(reason: Self.isTimeout(error) ? "timeout" : "network", correlationId: nil)
    }
  }

  static func correlationIdentifier(from response: HTTPURLResponse, body: Data) -> String? {
    let headerNames = [
      "x-correlation-id",
      "x-request-id",
      "x-meridian-correlation-id",
      "x-meridian-request-id",
    ]
    for (rawKey, rawValue) in response.allHeaderFields {
      let name = String(describing: rawKey).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard headerNames.contains(name) else { continue }
      let text = String(describing: rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
      if !text.isEmpty { return text }
    }
    guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
    for key in ["correlationId", "requestId", "correlation_id", "request_id"] {
      if let value = json[key] as? String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
      }
    }
    return nil
  }

  private static func httpFailureReason(_ status: Int, body: Data) -> String {
    if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
       let code = json["code"] as? String {
      let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        return "http-\(status) code=\(trimmed)"
      }
    }
    return "http-\(status)"
  }

  private static func isTimeout(_ error: Error) -> Bool {
    if let urlError = error as? URLError, urlError.code == .timedOut {
      return true
    }
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
  }

  private func emit(_ kind: ProviderConfigMetricEvent.Kind, correlationId: String?, reason: String?) {
    let event = ProviderConfigMetricEvent(
      kind: kind,
      correlationId: correlationId,
      sessionId: sessionId,
      reason: reason
    )
    metricEvents.append(event)
    metricsHandler?(event)
  }

  private func performSubmit(
    recipientId: String,
    amountMinor: Int,
    option: PaymentMethodOption,
    note: String,
    scenario: Scenario,
    idempotencyKey: String
  ) async throws -> PaymentResponse {
    let payload = PaymentRequest(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: option.method,
      note: note,
      scenario: scenario
    )
    do {
      let response: PaymentResponse = try await request(
        method: "POST",
        path: "/payments",
        body: payload,
        additionalHeaders: ["Idempotency-Key": idempotencyKey]
      )
      paymentLogs.append(transactionLog(option: option, idempotencyKey: idempotencyKey, response: response))
      return response
    } catch {
      paymentLogs.append(transactionLog(option: option, idempotencyKey: idempotencyKey, response: nil))
      throw error
    }
  }

  private func transactionLog(
    option: PaymentMethodOption,
    idempotencyKey: String,
    response: PaymentResponse?
  ) -> PaymentTransactionLog {
    PaymentTransactionLog(
      action: "payment.submitted",
      idempotencyKey: idempotencyKey,
      methodId: option.id,
      providerName: option.providerName,
      method: option.method,
      transactionId: response?.transaction?.id,
      paymentId: response?.paymentId ?? response?.transaction?.id,
      reference: response?.transaction?.reference,
      sessionId: sessionId
    )
  }
}
