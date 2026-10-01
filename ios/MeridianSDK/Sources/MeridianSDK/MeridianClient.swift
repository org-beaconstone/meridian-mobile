import Foundation

public actor MeridianClient {
  private let baseURL: URL
  private let sessionId: String
  private let session: URLSession
  private let snapshotStore: (any PaymentIntentStore)?

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  ///   - snapshotStore: Optional store for resumable payment intent snapshots.
  ///     Pass a `KeychainPaymentIntentStore` for production; omit for stateless use.
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession = .shared,
    snapshotStore: (any PaymentIntentStore)? = nil
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
    self.snapshotStore = snapshotStore
  }

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

  /// POST /payments - Submit a payment
  ///
  /// When a `snapshotStore` is configured, this method persists a
  /// `PaymentIntentSnapshot` before and after the network call so the intent
  /// can be resumed if the process is interrupted.
  ///
  /// - Parameters:
  ///   - recipientId: Recipient ID
  ///   - amountMinor: Amount in GBP pence (integer)
  ///   - method: Payment method (card or bank)
  ///   - note: Optional note (max 200 chars)
  ///   - scenario: Simulation scenario
  ///   - idempotencyKey: Unique key for idempotency (retain across retries)
  public func submitPayment(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = .success,
    idempotencyKey: String
  ) async throws -> PaymentResponse {
    let payloadHash = paymentPayloadHash(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: method,
      note: note
    )

    // Persist a created snapshot before sending so a crash during the request
    // is recoverable with the original idempotency key.
    if let store = snapshotStore {
      let existing = try? await store.load(idempotencyKey: idempotencyKey)
      if existing == nil {
        let snapshot = PaymentIntentSnapshot(
          paymentIntentId: idempotencyKey,
          idempotencyKey: idempotencyKey,
          businessPayloadHash: payloadHash,
          status: .created
        )
        try await store.save(snapshot)
      }
    }

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
      additionalHeaders: ["Idempotency-Key": idempotencyKey]
    )

    // Update the snapshot to reflect the server's response status.
    if let store = snapshotStore {
      let newStatus: PaymentIntentStatus
      if response.ok {
        newStatus = .completed
      } else if response.code == "PAYMENT_PENDING" {
        newStatus = .pending
      } else {
        newStatus = .declined
      }

      let returnHash = response.state.map {
        bankStateHash(version: $0.version, balance: $0.balance)
      }

      let serverIntentId = response.paymentId
        ?? response.transaction?.id
        ?? idempotencyKey

      var updated = PaymentIntentSnapshot(
        paymentIntentId: serverIntentId,
        idempotencyKey: idempotencyKey,
        businessPayloadHash: payloadHash,
        status: newStatus,
        returnStateHash: returnHash
      )
      // Preserve original createdAt by loading existing and mutating.
      if var existing = try? await store.load(idempotencyKey: idempotencyKey) {
        existing.paymentIntentId = serverIntentId
        existing.status = newStatus
        existing.returnStateHash = returnHash
        existing.updatedAt = Date()
        updated = existing
      }
      try await store.save(updated)
    }

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

  // MARK: - Resumption

  /// Returns all non-terminal payment intent snapshots for the current account.
  ///
  /// Call this on app launch or after process recovery to detect in-flight
  /// payments that should be retried with their original idempotency keys.
  public func resumeActiveIntents() async throws -> [PaymentIntentSnapshot] {
    guard let store = snapshotStore else { return [] }
    return try await store.loadActive()
  }
}
