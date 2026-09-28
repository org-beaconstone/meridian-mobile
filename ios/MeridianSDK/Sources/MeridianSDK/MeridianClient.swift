import Foundation

public actor MeridianClient {
  private let baseURL: URL
  private let sessionId: String
  private let session: URLSession
  private let injectedStore: (any CatalogStore)?
  private let catalogTtl: TimeInterval
  private let now: @Sendable () -> Date
  private var resolvedStore: (any CatalogStore)?
  private var catalogClient: CatalogClient?

  /// True when the last catalog load reused a saved snapshot or the compiled-in baseline.
  public var catalogUsingFallback: Bool {
    catalogClient?.usingFallback ?? false
  }

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  ///   - catalogStore: Encrypted or in-memory catalog cache. Defaults to an encrypted file cache.
  ///   - catalogTtl: How long a saved catalog stays fresh before the next refresh.
  ///   - now: Clock used for catalog expiry. Tests can inject a fixed time.
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession = .shared,
    catalogStore: (any CatalogStore)? = nil,
    catalogTtl: TimeInterval = defaultCatalogTtl,
    now: @escaping @Sendable () -> Date = { Date() }
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

    guard catalogTtl >= 0 else {
      throw MeridianError.validationError("Catalog TTL must be zero or positive")
    }

    self.baseURL = url
    self.sessionId = sessionId
    self.session = urlSession
    self.injectedStore = catalogStore
    self.catalogTtl = catalogTtl
    self.now = now
  }

  private func catalogs() throws -> CatalogClient {
    if let catalogClient { return catalogClient }
    let store: any CatalogStore
    if let resolvedStore {
      store = resolvedStore
    } else if let injectedStore {
      store = injectedStore
    } else {
      store = try EncryptedFileCatalogStore(directory: EncryptedFileCatalogStore.defaultDirectory())
    }
    resolvedStore = store
    let client = CatalogClient(
      cacheKey: baseURL.absoluteString + "\n" + sessionId,
      store: store,
      ttl: catalogTtl,
      now: now
    )
    catalogClient = client
    return client
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

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as MeridianError {
      throw error
    } catch {
      throw MeridianError.networkError(error.localizedDescription)
    }

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
      if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
        throw MeridianError.decodingError(error.localizedDescription)
      }
      let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw MeridianError.httpError(statusCode: httpResponse.statusCode, message: errorMsg)
    }
  }

  // MARK: - Public API Methods

  /// GET /health - Check service health
  public func getHealth() async throws -> HealthResponse {
    return try await request(method: "GET", path: "/health")
  }

  /// GET /catalog - Fetch recipients, providers, and corridors.
  /// A fresh cached copy is reused until the TTL expires. Gateway failures,
  /// offline errors, and unrecognized provider ids return the last accepted catalog.
  public func getCatalog() async throws -> CatalogResponse {
    let client = try catalogs()
    if let cached = client.freshCachedCatalog() {
      return cached
    }
    do {
      let fresh: CatalogResponse = try await request(method: "GET", path: "/catalog")
      return try client.accept(fresh)
    } catch let error as MeridianError {
      if shouldFallbackCatalog(error) {
        return client.fallback()
      }
      throw error
    } catch {
      return client.fallback()
    }
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

    return try await request(
      method: "POST",
      path: "/payments",
      body: payload,
      additionalHeaders: ["Idempotency-Key": idempotencyKey]
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
