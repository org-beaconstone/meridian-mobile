import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor MeridianClient {
  private let baseURL: URL
  private let baseURLString: String
  private let sessionId: String
  private let session: URLSession

  /// Initialize Meridian API client
  /// - Parameters:
  ///   - baseURL: API base URL (e.g., "http://localhost:8080/api/v1")
  ///   - sessionId: Rehearsal session ID (3-64 URL-safe ASCII)
  ///   - urlSession: Optional URLSession for testing
  public init(
    baseURL: String,
    sessionId: String,
    urlSession: URLSession = .shared
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
    self.baseURLString = urlStr
    self.sessionId = sessionId
    self.session = urlSession
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

  /// POST /api/v2/payment-intents
  /// Sends the canonical payload bytes unchanged, with the attempt's idempotency key and payload hash.
  /// The rehearsal session header is the same room selected for v1 calls.
  public func submitPaymentIntent(
    canonicalBody: String,
    idempotencyKey: String,
    payloadHash: String
  ) async throws -> (statusCode: Int, body: PaymentIntentResponse) {
    guard let absolute = resolvePaymentIntentsURL(baseURLString), let url = URL(string: absolute) else {
      throw MeridianError.invalidURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(sessionId, forHTTPHeaderField: "X-Rehearsal-Session")
    request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
    request.setValue(payloadHash, forHTTPHeaderField: "X-Payload-Hash")
    request.httpBody = Data(canonicalBody.utf8)

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw MeridianError.networkError("Invalid response type")
    }
    let statusCode = httpResponse.statusCode
    let allowed = (200..<300).contains(statusCode) || statusCode == 202 || statusCode == 400 || statusCode == 409 || statusCode == 422 || statusCode == 503
    guard allowed else {
      let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw MeridianError.httpError(statusCode: statusCode, message: errorMsg)
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    do {
      let body = try decoder.decode(PaymentIntentResponse.self, from: data)
      return (statusCode, body)
    } catch {
      throw MeridianError.decodingError(error.localizedDescription)
    }
  }
}
