import Foundation

public struct CatalogCache {
  public static let defaultTtlMillis: Int64 = 30_000
  private var sessionId: String?
  private var storedAt: Int64 = 0
  private var ttlMillis: Int64 = 0
  private var document: CatalogDocument?

  public init() {}

  public mutating func store(session: String, document: CatalogDocument, at: Int64, ttlMillis: Int64) {
    sessionId = session
    self.document = document
    storedAt = at
    self.ttlMillis = ttlMillis
  }

  public func read(session: String, at: Int64) -> String {
    guard document != nil, sessionId == session else { return "miss" }
    if at >= storedAt + ttlMillis { return "expired" }
    return "hit"
  }
}

struct StoredAttempt {
  var sessionId: String
  var key: String
  var recipientId: String
  var currency: String
  var minor: Int
  var exponent: Int
  var method: String
  var note: String
  var status: String
}

public struct IdempotencyJournal {
  private var attempt: StoredAttempt?
  public static let snapshotDefaultsKey = "meridian.idempotency.snapshot"
  public static let emptySnapshot = "{\"version\":1,\"empty\":true}"

  public init() {}

  public var status: String { attempt?.status ?? "empty" }
  public var key: String? { attempt?.key }
  public var sessionId: String? { attempt?.sessionId }

  public mutating func begin(sessionId: String, key: String, recipientId: String, currency: String, minor: Int, exponent: Int, method: String, note: String) -> ContractError? {
    if !Json.matches("^[A-Za-z0-9_-]{3,64}$", sessionId) || !Json.matches("^[A-Za-z0-9_-]{1,100}$", key) || !Json.matches("^[a-z0-9-]{1,64}$", recipientId) {
      return ContractError(code: "MALFORMED_ATTEMPT", message: "Payment attempt is invalid")
    }
    if method != "card" && method != "bank" { return ContractError(code: "MALFORMED_ATTEMPT", message: "Payment method is invalid") }
    if !Json.matches("^[A-Z]{3}$", currency) || exponent < 0 || exponent > 4 || minor < 0 || note.count > 200 {
      return ContractError(code: "MALFORMED_ATTEMPT", message: "Payment attempt is invalid")
    }
    if let existing = attempt, existing.status != "completed" {
      return ContractError(code: "IDEMPOTENCY_RETAINED", message: "An unfinished payment key is retained")
    }
    attempt = StoredAttempt(sessionId: sessionId, key: key, recipientId: recipientId, currency: currency, minor: minor, exponent: exponent, method: method, note: note, status: "draft")
    return nil
  }

  public mutating func markUncertain() -> ContractError? {
    guard var existing = attempt else { return ContractError(code: "MISSING_ATTEMPT", message: "No payment attempt") }
    if existing.status == "completed" { return ContractError(code: "ALREADY_COMPLETED", message: "Payment already completed") }
    existing.status = "uncertain"
    attempt = existing
    return nil
  }

  public mutating func markCompleted() -> ContractError? {
    guard var existing = attempt else { return ContractError(code: "MISSING_ATTEMPT", message: "No payment attempt") }
    existing.status = "completed"
    attempt = existing
    return nil
  }

  public mutating func discardDraft() -> ContractError? {
    guard let existing = attempt else { return ContractError(code: "MISSING_ATTEMPT", message: "No payment attempt") }
    if existing.status != "draft" { return ContractError(code: "IDEMPOTENCY_RETAINED", message: "Uncertain payment key is retained") }
    attempt = nil
    return nil
  }

  public func retry(note: String, recipientId: String? = nil, minor: Int? = nil, method: String? = nil, currency: String? = nil) -> Result<String, ContractError> {
    guard let existing = attempt else { return .failure(ContractError(code: "MISSING_ATTEMPT", message: "No payment attempt")) }
    let same = (recipientId ?? existing.recipientId) == existing.recipientId &&
      (minor ?? existing.minor) == existing.minor &&
      (method ?? existing.method) == existing.method &&
      (currency ?? existing.currency) == existing.currency &&
      note == existing.note
    if !same { return .failure(ContractError(code: "IDEMPOTENCY_MISMATCH", message: "Idempotency key reused with a different payload")) }
    return .success(existing.key)
  }

  public func snapshot() -> String {
    guard let current = attempt else { return IdempotencyJournal.emptySnapshot }
    return "{\"version\":1,\"empty\":false" +
      ",\"sessionId\":\(jsonString(current.sessionId))" +
      ",\"key\":\(jsonString(current.key))" +
      ",\"status\":\(jsonString(current.status))" +
      ",\"recipientId\":\(jsonString(current.recipientId))" +
      ",\"currency\":\(jsonString(current.currency))" +
      ",\"minor\":\(current.minor)" +
      ",\"exponent\":\(current.exponent)" +
      ",\"method\":\(jsonString(current.method))" +
      ",\"note\":\(jsonString(current.note))}"
  }

  public mutating func kill() {
    self = IdempotencyJournal.restore(snapshot())
  }

  public static func restore(_ snapshot: String) -> IdempotencyJournal {
    var journal = IdempotencyJournal()
    guard let data = snapshot.data(using: .utf8),
          let node = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return journal }
    if Json.bool(node["empty"]) == true || Json.int(node["version"]) != 1 || Json.isNull(node["key"]) { return journal }
    guard let sessionId = Json.string(node["sessionId"]),
          let key = Json.string(node["key"]),
          let recipientId = Json.string(node["recipientId"]),
          let currency = Json.string(node["currency"]),
          let minor = Json.int(node["minor"]),
          let exponent = Json.int(node["exponent"]),
          let method = Json.string(node["method"]),
          let note = Json.string(node["note"]),
          let status = Json.string(node["status"]) else { return journal }
    journal.attempt = StoredAttempt(sessionId: sessionId, key: key, recipientId: recipientId, currency: currency, minor: minor, exponent: exponent, method: method, note: note, status: status)
    return journal
  }
}

private func jsonString(_ value: String) -> String {
  let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
  return "\"\(escaped)\""
}

struct ArmedReturn {
  var sessionId: String
  var paymentId: String
  var nonce: String
  var exp: Int64
  var key: String
  var consumed = false
}

public struct ReturnStateGuard {
  private var selected = ""
  private var armed: [ArmedReturn] = []

  public init() {}

  public var selectedSession: String { selected }

  public mutating func select(session: String) {
    selected = session
  }

  public mutating func arm(sessionId: String, paymentId: String, nonce: String, exp: Int64, key: String) -> ContractError? {
    if sessionId != selected { return ContractError(code: "SESSION_MISMATCH", message: "Return state does not match the selected room") }
    if paymentId.isEmpty || nonce.isEmpty || key.isEmpty { return ContractError(code: "MALFORMED_LINK", message: "Return link is incomplete") }
    if armed.contains(where: { $0.nonce == nonce }) { return ContractError(code: "REPLAY", message: "Return nonce was already used") }
    armed.append(ArmedReturn(sessionId: sessionId, paymentId: paymentId, nonce: nonce, exp: exp, key: key))
    return nil
  }

  public mutating func open(paymentId: String, nonce: String, now: Int64) -> Result<String, ContractError> {
    guard let index = armed.firstIndex(where: { $0.nonce == nonce && $0.paymentId == paymentId }) else {
      return .failure(ContractError(code: "MALFORMED_LINK", message: "Return link is not recognised"))
    }
    if armed[index].sessionId != selected {
      return .failure(ContractError(code: "SESSION_MISMATCH", message: "Return link does not match the selected room"))
    }
    if armed[index].consumed { return .failure(ContractError(code: "REPLAY", message: "This return link was already used")) }
    if now >= armed[index].exp { return .failure(ContractError(code: "EXPIRED", message: "This return link has expired")) }
    armed[index].consumed = true
    return .success(armed[index].key)
  }

  public mutating func openUrl(_ url: String, now: Int64) -> Result<String, ContractError> {
    guard let params = parseReturnUrl(url) else {
      return .failure(ContractError(code: "MALFORMED_LINK", message: "Return link is invalid"))
    }
    if params["session"] != selected {
      return .failure(ContractError(code: "SESSION_MISMATCH", message: "Return link does not match the selected room"))
    }
    return open(paymentId: params["paymentId"] ?? "", nonce: params["nonce"] ?? "", now: now)
  }

  public func userMessage(_ result: Result<String, ContractError>) -> String {
    switch result {
    case .success:
      return "Returned from payment. Retry uses the original payment key."
    case let .failure(error):
      switch error.code {
      case "REPLAY": return "This return link was already used."
      case "EXPIRED": return "This return link has expired."
      case "SESSION_MISMATCH": return "Return link does not match the selected room."
      default: return "Return link was rejected."
      }
    }
  }
}

public func parseReturnUrl(_ url: String) -> [String: String]? {
  let prefix = "meridian://payments/return?"
  guard url.hasPrefix(prefix) else { return nil }
  let query = String(url.dropFirst(prefix.count))
  if query.isEmpty { return nil }
  var params: [String: String] = [:]
  for part in query.split(separator: "&", omittingEmptySubsequences: false) {
    let bits = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    if bits.count != 2 || bits[0].isEmpty { return nil }
    guard let decoded = percentDecode(bits[1]) else { return nil }
    params[bits[0]] = decoded
  }
  guard let paymentId = params["paymentId"], !paymentId.isEmpty,
        let nonce = params["nonce"], !nonce.isEmpty,
        let session = params["session"], !session.isEmpty,
        let exp = params["exp"], Int64(exp) != nil else { return nil }
  _ = session
  return params
}

private func percentDecode(_ value: String) -> String? {
  var bytes: [UInt8] = []
  var index = value.startIndex
  while index < value.endIndex {
    let char = value[index]
    if char == "%", value.distance(from: index, to: value.endIndex) >= 3 {
      let start = value.index(after: index)
      let end = value.index(start, offsetBy: 2)
      guard let parsed = UInt8(value[start..<end], radix: 16) else { return nil }
      bytes.append(parsed)
      index = end
    } else if char == "+" {
      bytes.append(32)
      index = value.index(after: index)
    } else {
      guard let ascii = char.asciiValue else { return nil }
      bytes.append(ascii)
      index = value.index(after: index)
    }
  }
  return String(bytes: bytes, encoding: .utf8)
}

public struct A11yNode: Equatable {
  public let id: String
  public let voiceOverLabel: String
  public let talkBackDescription: String
  public let traits: [String]
  public let textDirection: String
  public let scalesWithFont: Bool
  public let mirrorsInRtl: Bool
  public let minTouchTargetPt: Int
  public let minTouchTargetDp: Int

  public init(id: String, voiceOverLabel: String, talkBackDescription: String, traits: [String], textDirection: String, scalesWithFont: Bool, mirrorsInRtl: Bool, minTouchTargetPt: Int = 44, minTouchTargetDp: Int = 48) {
    self.id = id
    self.voiceOverLabel = voiceOverLabel
    self.talkBackDescription = talkBackDescription
    self.traits = traits
    self.textDirection = textDirection
    self.scalesWithFont = scalesWithFont
    self.mirrorsInRtl = mirrorsInRtl
    self.minTouchTargetPt = minTouchTargetPt
    self.minTouchTargetDp = minTouchTargetDp
  }
}

public enum AccessibilityCatalog {
  public static let nodes: [A11yNode] = [
    A11yNode(id: "balance", voiceOverLabel: "Everyday account balance", talkBackDescription: "Everyday account balance", traits: ["updatesFrequently"], textDirection: "ltr", scalesWithFont: true, mirrorsInRtl: false),
    A11yNode(id: "amount-input", voiceOverLabel: "Amount in pounds", talkBackDescription: "Amount in pounds", traits: ["textField"], textDirection: "ltr", scalesWithFont: true, mirrorsInRtl: false),
    A11yNode(id: "review-payment", voiceOverLabel: "Review payment", talkBackDescription: "Review payment", traits: ["button"], textDirection: "locale", scalesWithFont: true, mirrorsInRtl: false),
    A11yNode(id: "confirm-payment", voiceOverLabel: "Confirm payment", talkBackDescription: "Confirm payment", traits: ["button"], textDirection: "locale", scalesWithFont: true, mirrorsInRtl: false),
    A11yNode(id: "method-card", voiceOverLabel: "Debit card · Adyen", talkBackDescription: "Debit card · Adyen", traits: ["button"], textDirection: "locale", scalesWithFont: true, mirrorsInRtl: false),
    A11yNode(id: "method-bank", voiceOverLabel: "Bank payment · Worldpay", talkBackDescription: "Bank payment · Worldpay", traits: ["button"], textDirection: "locale", scalesWithFont: true, mirrorsInRtl: false),
    A11yNode(id: "connect", voiceOverLabel: "Connect", talkBackDescription: "Connect", traits: ["button"], textDirection: "locale", scalesWithFont: true, mirrorsInRtl: false),
    A11yNode(id: "back-navigation", voiceOverLabel: "Back", talkBackDescription: "Back", traits: ["button"], textDirection: "locale", scalesWithFont: true, mirrorsInRtl: true),
  ]

  public static func node(_ id: String) -> A11yNode? {
    nodes.first { $0.id == id }
  }
}
