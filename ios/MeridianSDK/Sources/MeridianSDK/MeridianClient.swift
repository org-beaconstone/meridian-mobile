import Foundation

public actor MeridianClient {
  private let baseURL: URL
  private let sessionId: String
  private let session: URLSession
  private let catalogTTL: TimeInterval
  private let catalogStore: CatalogStoring
  private let clock: () -> Date

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  ///   - catalogTTL: How long a saved catalog is fresh before the next refresh
  ///   - catalogStore: Encrypted local cache. Defaults to an app-support file.
  ///   - now: Clock used for catalog expiry. Tests can supply a fixed time.
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession = .shared,
    catalogTTL: TimeInterval = 300,
    catalogStore: CatalogStoring? = nil,
    now: @escaping () -> Date = { Date() }
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
    self.catalogTTL = catalogTTL
    self.clock = now
    self.catalogStore = catalogStore ?? EncryptedFileCatalogStore(
      directory: Self.catalogDirectory(sessionId: sessionId)
    )
  }

  static func catalogDirectory(sessionId: String) -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let safe = sessionId.map { character -> Character in
      let ok = character.isLetter || character.isNumber || character == "-" || character == "_"
      return ok ? character : "_"
    }
    return base
      .appendingPathComponent("Meridian", isDirectory: true)
      .appendingPathComponent("catalog", isDirectory: true)
      .appendingPathComponent(String(safe), isDirectory: true)
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

  /// Authenticated catalog read with encrypted local cache.
  /// Gateway failures, offline errors, and unrecognized provider ids reuse the
  /// last accepted catalog. Payment submission is unchanged.
  public func loadCatalog() async -> CatalogLoad {
    let now = clock()
    let nowMillis = Int64((now.timeIntervalSince1970 * 1000).rounded())
    let cached = catalogStore.load()
    if let cached, nowMillis &- cached.fetchedAtEpochMillis < Int64(catalogTTL * 1000) {
      return CatalogLoad(catalog: cached.catalog, origin: .cache)
    }

    do {
      let fetched = try await getCatalog()
      if let accepted = ProviderBaseline.accept(fetched) {
        catalogStore.save(
          StoredCatalog(fetchedAtEpochMillis: nowMillis, catalog: accepted)
        )
        return CatalogLoad(catalog: accepted, origin: .network)
      }
      return CatalogFallback.load(cached)
    } catch let error as MeridianError {
      switch error {
      case let .httpError(statusCode, _) where CatalogFallback.isGateway(statusCode):
        return CatalogFallback.load(cached)
      case .decodingError, .networkError:
        return CatalogFallback.load(cached)
      default:
        return CatalogFallback.load(cached)
      }
    } catch {
      return CatalogFallback.load(cached)
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
