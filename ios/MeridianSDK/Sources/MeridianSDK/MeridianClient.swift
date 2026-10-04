import Foundation

public actor MeridianClient {
  private let baseURL: URL
  private let sessionId: String
  private let session: URLSession
  private let flagCache: any FeatureFlagCache
  private var flagEvaluation = FeatureFlagEvaluation.legacy(source: "default")
  private var telemetry: [PaymentTelemetryEvent] = []

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  ///   - flagCache: Local cache for feature-flag evaluation. Defaults to UserDefaults.
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession = .shared,
    flagCache: any FeatureFlagCache = UserDefaultsFeatureFlagCache()
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
    self.flagCache = flagCache
  }

  // MARK: - Internal Request Method

  private struct RawHTTPResponse {
    let status: Int
    let data: Data
  }

  private func exchange(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:]
  ) async throws -> RawHTTPResponse {
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

    return RawHTTPResponse(status: httpResponse.statusCode, data: data)
  }

  private func request<T: Decodable>(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:]
  ) async throws -> T {
    let response = try await exchange(
      method: method,
      path: path,
      body: body,
      additionalHeaders: additionalHeaders
    )

    // Check HTTP status
    guard response.status >= 200 && response.status < 300 || response.status == 202 || response.status == 400 || response.status == 409 || response.status == 422 || response.status == 503
    else {
      let errorMsg = String(data: response.data, encoding: .utf8) ?? "Unknown error"
      throw MeridianError.httpError(
        statusCode: response.status,
        message: errorMsg
      )
    }

    let decoder = JSONDecoder()
    do {
      return try decoder.decode(T.self, from: response.data)
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
  /// Accepts the legacy two-provider document and the dynamic methods document.
  public func getCatalog() async throws -> CatalogResponse {
    let response = try await exchange(method: "GET", path: "/catalog")
    guard response.status >= 200 && response.status < 300 else {
      let errorMsg = String(data: response.data, encoding: .utf8) ?? "Unknown error"
      throw MeridianError.httpError(statusCode: response.status, message: errorMsg)
    }
    guard let catalog = PaymentCatalogDecoder.decode(response.data) else {
      throw MeridianError.decodingError("Catalog response was not a JSON object")
    }
    return catalog
  }

  /// GET /flags - Evaluate enable_mobile_eu_payments before payment UI is shown.
  /// Network and decode failures use the room cache, then the legacy kill-switch default.
  /// This method does not throw.
  public func evaluateEuPaymentsFlag() async -> FeatureFlagEvaluation {
    let cacheKey = FeatureFlags.cacheKey(sessionId: sessionId)
    do {
      let response = try await exchange(method: "GET", path: "/flags")
      if (200..<300).contains(response.status), let parsed = FeatureFlagParser.parse(response.data) {
        let evaluation = FeatureFlagEvaluation(
          key: FeatureFlags.mobileEuPayments,
          enabled: parsed.enabled,
          variant: parsed.variant,
          source: "remote"
        )
        flagCache.write(key: cacheKey, evaluation: evaluation)
        flagEvaluation = evaluation
        return evaluation
      }
      if response.status == 404 {
        let evaluation = FeatureFlagEvaluation.legacy(source: "remote")
        flagCache.write(key: cacheKey, evaluation: evaluation)
        flagEvaluation = evaluation
        return evaluation
      }
    } catch {
      // Fall through to the cached evaluation.
    }
    if let cached = flagCache.read(key: cacheKey) {
      let evaluation = FeatureFlagEvaluation(
        key: cached.key,
        enabled: cached.enabled,
        variant: cached.enabled ? cached.variant : "legacy",
        source: "cache"
      )
      flagEvaluation = evaluation
      return evaluation
    }
    let fallback = FeatureFlagEvaluation.legacy(source: "default")
    flagEvaluation = fallback
    return fallback
  }

  public func currentFlag() -> FeatureFlagEvaluation {
    flagEvaluation
  }

  public func paymentTelemetry() -> [PaymentTelemetryEvent] {
    telemetry
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
  ///   - displayCurrency: GBP or EUR display control. Ledger submission stays integer minor units.
  public func submitPayment(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = .success,
    idempotencyKey: String,
    displayCurrency: String = "GBP"
  ) async throws -> PaymentResponse {
    let payload = PaymentRequest(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: method,
      note: note,
      scenario: scenario
    )
    let event = PaymentTelemetry.event(
      evaluation: flagEvaluation,
      idempotencyKey: idempotencyKey,
      sessionId: sessionId,
      displayCurrency: displayCurrency
    )
    telemetry.append(event)

    return try await request(
      method: "POST",
      path: "/payments",
      body: payload,
      additionalHeaders: [
        "Idempotency-Key": idempotencyKey,
        "X-Meridian-Flag": PaymentTelemetry.headerValue(event),
      ]
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
