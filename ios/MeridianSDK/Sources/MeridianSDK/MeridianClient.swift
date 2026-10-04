import Foundation

public actor MeridianClient {
  private let baseURL: URL
  private let sessionId: String
  private let session: URLSession
  private let retryPolicy: RetryPolicy
  private let sleeper: @Sendable (Int) async -> Void
  private var healthTask: Task<Void, Never>?
  private var healthSnapshot: SessionHealthSnapshot = .unknown

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  ///   - retryPolicy: Gateway retry schedule for HTTP 502 and 504
  ///   - sleeper: Delay used between payment retries
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession = .shared,
    retryPolicy: RetryPolicy = RetryPolicy(),
    sleeper: @escaping @Sendable (Int) async -> Void = { millis in
      try? await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
    }
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
    self.retryPolicy = retryPolicy
    self.sleeper = sleeper
  }

  private func makeURL(path: String) -> URL {
    let suffix = path.hasPrefix("/") ? path : "/" + path
    return URL(string: baseURL.absoluteString + suffix) ?? baseURL
  }

  // MARK: - Internal Request Method

  private func request<T: Decodable>(
    method: String,
    path: String,
    body: Encodable? = nil,
    additionalHeaders: [String: String] = [:]
  ) async throws -> T {
    let url = makeURL(path: path)

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

  /// GET /session/health — corridor and rail status for this rehearsal session.
  /// Full path is `{baseURL}/session/health`, which is `/api/v1/session/health` for the shared API.
  public func getSessionHealth() async throws -> SessionHealth {
    return try await request(method: "GET", path: "/session/health")
  }

  public func latestSessionHealth() -> SessionHealthSnapshot {
    healthSnapshot
  }

  /// Polls `/session/health` until the returned stream is cancelled.
  /// A missing endpoint is reported as unreachable and is not treated as a corridor outage.
  public func pollSessionHealth(every interval: Duration = .seconds(5)) -> AsyncStream<SessionHealthSnapshot> {
    healthTask?.cancel()
    let (stream, continuation) = AsyncStream<SessionHealthSnapshot>.makeStream()
    let task = Task {
      while !Task.isCancelled {
        let snapshot = await self.loadSessionHealth()
        continuation.yield(snapshot)
        try? await Task.sleep(for: interval)
      }
      continuation.finish()
    }
    healthTask = task
    continuation.onTermination = { @Sendable _ in
      task.cancel()
    }
    return stream
  }

  public func stopSessionHealthPolling() {
    healthTask?.cancel()
    healthTask = nil
  }

  public func loadSessionHealth() async -> SessionHealthSnapshot {
    let snapshot: SessionHealthSnapshot
    do {
      let health = try await getSessionHealth()
      snapshot = SessionHealthSnapshot(health: health, reachable: true, detail: nil)
    } catch let error as MeridianError {
      if case let .httpError(status, _) = error, status == 404 {
        snapshot = SessionHealthSnapshot(health: nil, reachable: false, detail: "Session health is not available")
      } else {
        snapshot = SessionHealthSnapshot(health: nil, reachable: false, detail: error.localizedDescription)
      }
    } catch {
      snapshot = SessionHealthSnapshot(health: nil, reachable: false, detail: error.localizedDescription)
    }
    healthSnapshot = snapshot
    return snapshot
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
    var lastStatus = 0
    var lastMessage = ""
    var attempt = 1
    while attempt <= retryPolicy.maxAttempts {
      do {
        return try await request(
          method: "POST",
          path: "/payments",
          body: payload,
          additionalHeaders: headers
        )
      } catch let error as MeridianError {
        guard case let .httpError(status, message) = error, retryPolicy.retriesHTTPStatus(status) else {
          throw error
        }
        lastStatus = status
        lastMessage = message
        if attempt == retryPolicy.maxAttempts { break }
        await sleeper(retryPolicy.delayMillis(beforeAttempt: attempt + 1))
        attempt += 1
      }
    }
    throw MeridianError.retriesExhausted(
      statusCode: lastStatus,
      attempts: retryPolicy.maxAttempts,
      message: lastMessage
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
