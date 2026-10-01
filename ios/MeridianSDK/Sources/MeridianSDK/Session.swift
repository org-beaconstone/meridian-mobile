import Foundation

public struct InFlightPayment: Codable, Equatable {
  public let idempotencyKey: String
  public let sessionId: String
  public let recipientId: String
  public let amountMinor: Int
  public let method: String
  public let provider: String
  public let note: String
  public var outcomeUncertain: Bool
}

public struct CachedCatalog: Codable, Equatable {
  public let demoDate: String
  public let currency: String
  public let recipientIds: [String]
  public let providerIds: [String]

  public init(demoDate: String, currency: String, recipientIds: [String], providerIds: [String]) {
    self.demoDate = demoDate
    self.currency = currency
    self.recipientIds = recipientIds
    self.providerIds = providerIds
  }
}

public struct ProcessCheckpoint: Codable, Equatable {
  public var sessionId: String
  public var endpoint: String
  public var recipientId: String
  public var amountInput: String
  public var note: String
  public var method: String
  public var reviewing: Bool
  public var message: String
  public var inFlight: InFlightPayment?
  public var consumedReturnNonces: [String]
  public var catalog: CachedCatalog?
  public var catalogCachedAtMillis: Int64?

  public init(
    sessionId: String,
    endpoint: String,
    recipientId: String,
    amountInput: String,
    note: String,
    method: String,
    reviewing: Bool,
    message: String,
    inFlight: InFlightPayment?,
    consumedReturnNonces: [String],
    catalog: CachedCatalog?,
    catalogCachedAtMillis: Int64?
  ) {
    self.sessionId = sessionId
    self.endpoint = endpoint
    self.recipientId = recipientId
    self.amountInput = amountInput
    self.note = note
    self.method = method
    self.reviewing = reviewing
    self.message = message
    self.inFlight = inFlight
    self.consumedReturnNonces = consumedReturnNonces
    self.catalog = catalog
    self.catalogCachedAtMillis = catalogCachedAtMillis
  }
}

public enum ReturnDecision: Equatable {
  case accepted(paymentId: String)
  case rejected(String)
}

public struct SessionRuntime {
  public private(set) var checkpoint: ProcessCheckpoint
  public static let catalogTtlMillis: Int64 = 30_000

  public init(sessionId: String, endpoint: String) {
    checkpoint = ProcessCheckpoint(
      sessionId: sessionId,
      endpoint: endpoint,
      recipientId: "northline-studio",
      amountInput: "",
      note: "",
      method: "card",
      reviewing: false,
      message: "",
      inFlight: nil,
      consumedReturnNonces: [],
      catalog: nil,
      catalogCachedAtMillis: nil
    )
  }

  public init(checkpoint: ProcessCheckpoint) {
    self.checkpoint = checkpoint
  }

  public static func failureIsUncertain(statusCode: Int?) -> Bool {
    guard let statusCode else { return true }
    return statusCode == 202 || statusCode >= 500
  }

  public mutating func selectSession(room: String, endpoint: String) {
    checkpoint.sessionId = room
    checkpoint.endpoint = endpoint
    if let flight = checkpoint.inFlight {
      checkpoint.inFlight = InFlightPayment(
        idempotencyKey: flight.idempotencyKey,
        sessionId: room,
        recipientId: flight.recipientId,
        amountMinor: flight.amountMinor,
        method: flight.method,
        provider: flight.provider,
        note: flight.note,
        outcomeUncertain: flight.outcomeUncertain
      )
    }
  }

  public mutating func clearInFlight() {
    checkpoint.inFlight = nil
  }

  @discardableResult
  public mutating func begin(
    key: String,
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String,
    sessionId: String
  ) -> InFlightPayment {
    if let current = checkpoint.inFlight, current.outcomeUncertain {
      return current
    }
    let methodName = method == .bank ? "bank" : "card"
    let created = InFlightPayment(
      idempotencyKey: key,
      sessionId: sessionId,
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: methodName,
      provider: providerForMethod(methodName) ?? "adyen",
      note: note,
      outcomeUncertain: false
    )
    checkpoint.inFlight = created
    return created
  }

  public mutating func markUncertain() {
    guard var flight = checkpoint.inFlight else { return }
    flight.outcomeUncertain = true
    checkpoint.inFlight = flight
  }

  public mutating func rememberCatalog(_ catalog: CachedCatalog, nowMillis: Int64) {
    checkpoint.catalog = catalog
    checkpoint.catalogCachedAtMillis = nowMillis
  }

  public func cachedCatalog(nowMillis: Int64, ttlMillis: Int64 = SessionRuntime.catalogTtlMillis) -> CachedCatalog? {
    guard let catalog = checkpoint.catalog, let storedAt = checkpoint.catalogCachedAtMillis else { return nil }
    if ttlMillis <= 0 || nowMillis >= storedAt + ttlMillis { return nil }
    return catalog
  }

  public mutating func evaluateReturn(url: String, nowMillis: Int64) -> ReturnDecision {
    guard let parsed = parseReturnLink(url) else { return .rejected("malformed") }
    if nowMillis >= parsed.exp { return .rejected("expired") }
    if checkpoint.consumedReturnNonces.contains(parsed.nonce) { return .rejected("replayed") }
    checkpoint.consumedReturnNonces.append(parsed.nonce)
    checkpoint.consumedReturnNonces.sort()
    return .accepted(paymentId: parsed.paymentId)
  }

  public func requestHeaders(includeIdempotency: Bool) -> [String: String] {
    var headers = [
      "Content-Type": "application/json",
      "X-Rehearsal-Session": checkpoint.sessionId,
    ]
    if includeIdempotency, let key = checkpoint.inFlight?.idempotencyKey {
      headers["Idempotency-Key"] = key
    }
    return headers
  }

  public mutating func syncForm(
    recipientId: String,
    amountInput: String,
    note: String,
    method: String,
    reviewing: Bool,
    message: String,
    endpoint: String
  ) {
    checkpoint.recipientId = recipientId
    checkpoint.amountInput = amountInput
    checkpoint.note = note
    checkpoint.method = method
    checkpoint.reviewing = reviewing
    checkpoint.message = message
    checkpoint.endpoint = endpoint
    checkpoint.consumedReturnNonces.sort()
  }

  public func encode() -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(checkpoint) else { return "{}" }
    return String(data: data, encoding: .utf8) ?? "{}"
  }

  public static func decode(_ json: String) -> ProcessCheckpoint? {
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(ProcessCheckpoint.self, from: data)
  }
}

private struct ParsedReturn {
  let paymentId: String
  let nonce: String
  let exp: Int64
}

private func parseReturnLink(_ raw: String) -> ParsedReturn? {
  let prefix = "meridian://return?"
  guard raw.hasPrefix(prefix) else { return nil }
  let query = String(raw.dropFirst(prefix.count))
  if query.isEmpty || query.contains("#") || query.contains(" ") { return nil }
  var values: [String: String] = [:]
  for part in query.split(separator: "&", omittingEmptySubsequences: false) {
    let bits = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    if bits.count != 2 { return nil }
    let key = String(bits[0])
    let value = String(bits[1])
    if key.isEmpty || value.isEmpty || values[key] != nil { return nil }
    values[key] = value
  }
  if Set(values.keys) != Set(["paymentId", "nonce", "exp"]) { return nil }
  let paymentId = values["paymentId"] ?? ""
  let nonce = values["nonce"] ?? ""
  let expText = values["exp"] ?? ""
  let token = "^[A-Za-z0-9_-]{1,64}$"
  guard paymentId.range(of: token, options: .regularExpression) != nil,
        nonce.range(of: token, options: .regularExpression) != nil,
        expText.range(of: "^[0-9]{1,15}$", options: .regularExpression) != nil,
        let exp = Int64(expText) else { return nil }
  return ParsedReturn(paymentId: paymentId, nonce: nonce, exp: exp)
}

public struct PaymentScreenModel {
  public var endpoint: String
  public var room: String
  public var recipientId: String
  public var amountInput: String
  public var note: String
  public var method: PaymentMethod
  public var reviewing: Bool
  public var busy: Bool
  public var message: String
  public var generation: Int
  public private(set) var runtime: SessionRuntime
  public var keyFactory: () -> String

  public init(
    endpoint: String,
    room: String,
    recipientId: String = "northline-studio",
    message: String = "Connect to the Spring Boot API to start.",
    keyFactory: @escaping () -> String = { UUID().uuidString }
  ) {
    self.endpoint = endpoint
    self.room = room
    self.recipientId = recipientId
    amountInput = ""
    note = ""
    method = .card
    reviewing = false
    busy = false
    self.message = message
    generation = 0
    runtime = SessionRuntime(sessionId: room, endpoint: endpoint)
    self.keyFactory = keyFactory
  }

  public static func failureIsUncertain(statusCode: Int?) -> Bool {
    SessionRuntime.failureIsUncertain(statusCode: statusCode)
  }

  @discardableResult
  public mutating func connect() -> Bool {
    let valid = room.range(of: "^[A-Za-z0-9_-]{3,64}$", options: .regularExpression) != nil
    guard valid else {
      message = "Invalid room"
      return false
    }
    if runtime.checkpoint.inFlight?.outcomeUncertain == true && room != runtime.checkpoint.sessionId {
      room = runtime.checkpoint.sessionId
      message = "Payment outcome is unknown. Stay in this room and retry the same payment."
      return false
    }
    runtime.selectSession(room: room, endpoint: endpoint)
    reviewing = false
    if runtime.checkpoint.inFlight?.outcomeUncertain != true {
      runtime.clearInFlight()
    }
    generation += 1
    message = "Connecting"
    return true
  }

  @discardableResult
  public mutating func review() -> Bool {
    let parsed = parseAmount(amountInput)
    guard let minor = parsed.0 else {
      message = parsed.1 ?? "Invalid amount"
      return false
    }
    guard note.count <= 200 else {
      message = "Reference is too long"
      return false
    }
    reviewing = true
    if runtime.checkpoint.inFlight?.outcomeUncertain == true {
      message = "Payment outcome is unknown. Retry keeps the same payment key."
      return true
    }
    runtime.begin(
      key: keyFactory(),
      recipientId: recipientId,
      amountMinor: minor,
      method: method,
      note: note,
      sessionId: runtime.checkpoint.sessionId
    )
    message = "Review before confirming. No real money moves."
    return true
  }

  public mutating func edit() {
    if runtime.checkpoint.inFlight?.outcomeUncertain == true {
      message = "Payment outcome is unknown. Retry the same payment before editing."
      return
    }
    reviewing = false
    runtime.clearInFlight()
    message = "Edit the payment. A new confirmation will use a new payment key."
  }

  public func submitInstruction() -> InFlightPayment? {
    runtime.checkpoint.inFlight
  }

  public mutating func markUncertain(reason: String) {
    runtime.markUncertain()
    message = reason
  }

  public mutating func markSettled() {
    runtime.clearInFlight()
    reviewing = false
    amountInput = ""
    note = ""
    message = "Demo payment completed. Other clients will refresh."
  }

  public mutating func rememberCatalog(_ catalog: CachedCatalog, nowMillis: Int64) {
    runtime.rememberCatalog(catalog, nowMillis: nowMillis)
  }

  public func cachedCatalog(nowMillis: Int64, ttlMillis: Int64 = SessionRuntime.catalogTtlMillis) -> CachedCatalog? {
    runtime.cachedCatalog(nowMillis: nowMillis, ttlMillis: ttlMillis)
  }

  public mutating func openReturn(url: String, nowMillis: Int64) -> ReturnDecision {
    let decision = runtime.evaluateReturn(url: url, nowMillis: nowMillis)
    switch decision {
    case let .accepted(paymentId):
      message = "Return accepted for \(paymentId)."
    case let .rejected(reason):
      message = "Return rejected: \(reason)."
    }
    return decision
  }

  public func requestHeaders(includeIdempotency: Bool) -> [String: String] {
    runtime.requestHeaders(includeIdempotency: includeIdempotency)
  }

  public func confirmationAccessibility(
    recipientName: String,
    language: String,
    fontScale: Double,
    platform: String
  ) -> AccessibilityDescriptor {
    let minor = runtime.checkpoint.inFlight?.amountMinor ?? parseAmount(amountInput).0 ?? 0
    let methodName = runtime.checkpoint.inFlight?.method ?? (method == .bank ? "bank" : "card")
    return paymentConfirmationAccessibility(
      amountLabel: money(minor),
      recipientName: recipientName,
      method: methodName,
      language: language,
      fontScale: fontScale,
      platform: platform
    )
  }

  public func checkpointJSON() -> String {
    var copy = runtime
    copy.syncForm(
      recipientId: recipientId,
      amountInput: amountInput,
      note: note,
      method: method == .bank ? "bank" : "card",
      reviewing: reviewing,
      message: message,
      endpoint: endpoint
    )
    return copy.encode()
  }

  public static func restore(
    _ json: String,
    keyFactory: @escaping () -> String = { UUID().uuidString }
  ) -> PaymentScreenModel? {
    guard var checkpoint = SessionRuntime.decode(json) else { return nil }
    if var flight = checkpoint.inFlight {
      flight.outcomeUncertain = true
      checkpoint.inFlight = flight
    }
    var model = PaymentScreenModel(
      endpoint: checkpoint.endpoint,
      room: checkpoint.sessionId,
      recipientId: checkpoint.recipientId,
      message: checkpoint.message,
      keyFactory: keyFactory
    )
    model.runtime = SessionRuntime(checkpoint: checkpoint)
    model.amountInput = checkpoint.amountInput
    model.note = checkpoint.note
    model.method = checkpoint.method == "bank" ? .bank : .card
    model.reviewing = checkpoint.reviewing
    if let flight = checkpoint.inFlight {
      model.method = flight.method == "bank" ? .bank : .card
      model.recipientId = flight.recipientId
      model.note = flight.note
      model.reviewing = true
      model.message = "Restored after process interruption. Retry keeps the same payment key."
    }
    model.busy = false
    return model
  }
}
