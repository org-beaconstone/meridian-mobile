import CryptoKit
import Foundation

/// Rehearsal Strong Customer Authentication and bank-return checks.
/// The signing key stays in process memory and is not a provider credential.
/// Bank URLs are confined to a reserved `.test` host. This does not call Adyen or Worldpay.

public enum ReturnOutcome: String, Equatable {
  case accepted
  case replayed
  case invalid
  case expired
  case ignored

  public var userMessage: String {
    switch self {
    case .accepted:
      return "Bank return accepted. The same payment key will be used."
    case .replayed:
      return "This bank return was already used. The payment was not sent again."
    case .invalid:
      return "This bank return is not valid. The payment was not sent."
    case .expired:
      return "This bank return has expired. The payment was not sent."
    case .ignored:
      return "That link is not a bank return. The payment was not sent."
    }
  }
}

public struct ReturnDecision: Equatable {
  public let outcome: ReturnOutcome
  /// Idempotency key already chosen for this checkout. A return never mints a replacement.
  public let idempotencyKey: String
  public let allowsPaymentSubmit: Bool
  /// Return handling never creates a payment.
  public var createsPayment: Bool { false }

  public init(outcome: ReturnOutcome, idempotencyKey: String, allowsPaymentSubmit: Bool) {
    self.outcome = outcome
    self.idempotencyKey = idempotencyKey
    self.allowsPaymentSubmit = allowsPaymentSubmit
  }
}

public struct IssuedBankHandoff: Equatable {
  public let handoffURL: String
  public let returnURL: String
  public let state: String
  public let idempotencyKey: String
  public let expiresAtEpochSeconds: Int64

  public init(
    handoffURL: String,
    returnURL: String,
    state: String,
    idempotencyKey: String,
    expiresAtEpochSeconds: Int64
  ) {
    self.handoffURL = handoffURL
    self.returnURL = returnURL
    self.state = state
    self.idempotencyKey = idempotencyKey
    self.expiresAtEpochSeconds = expiresAtEpochSeconds
  }
}

public enum UrlCheck: Equatable {
  case allowed(String)
  case refused(String)
}

enum LinkMatch: Equatable {
  case unrelated
  case malformed(String)
  case ready(url: String, state: String)
}

public enum BankHandoffPolicy {
  public static let bankHost = "bank.meridian-rehearsal.test"
  public static let returnHost = "app.meridian-rehearsal.test"
  public static let bankPath = "/handoff"
  public static let returnPath = "/bank/return"

  public static func inspectBankHandoff(_ url: String) -> UrlCheck {
    verdict(matchLink(url, host: bankHost, path: bankPath))
  }

  public static func inspectReturnLink(_ url: String) -> UrlCheck {
    verdict(matchLink(url, host: returnHost, path: returnPath))
  }

  static func matchReturn(_ url: String) -> LinkMatch {
    matchLink(url, host: returnHost, path: returnPath)
  }

  private static func verdict(_ match: LinkMatch) -> UrlCheck {
    switch match {
    case let .ready(url, _):
      return .allowed(url)
    case let .malformed(reason):
      return .refused(reason)
    case .unrelated:
      return .refused("Host is not allowlisted")
    }
  }
}

public enum PinConfirmation {
  public static func rejectReason(pin: String, repeated: String) -> String? {
    let digits = CharacterSet.decimalDigits
    if pin.count < 4 || pin.count > 6 || pin.unicodeScalars.contains(where: { !digits.contains($0) }) {
      return "PIN must be 4 to 6 digits"
    }
    if pin != repeated {
      return "PIN entries do not match"
    }
    return nil
  }
}

public struct PaymentAttempt: Equatable {
  public let idempotencyKey: String
  public let method: PaymentMethod
  public private(set) var scaConfirmed: Bool
  public private(set) var bankAccepted: Bool

  public init(
    idempotencyKey: String,
    method: PaymentMethod,
    scaConfirmed: Bool = false,
    bankAccepted: Bool = false
  ) {
    self.idempotencyKey = idempotencyKey
    self.method = method
    self.scaConfirmed = scaConfirmed
    self.bankAccepted = bankAccepted
  }

  public var readyToSubmit: Bool {
    switch method {
    case .card:
      return scaConfirmed
    case .bank:
      return bankAccepted
    }
  }

  public func confirmingBiometric(succeeded: Bool) -> PaymentAttempt {
    var copy = self
    if succeeded { copy.scaConfirmed = true }
    return copy
  }

  public func confirmingPin(pin: String, repeated: String) -> (PaymentAttempt, String?) {
    if let error = PinConfirmation.rejectReason(pin: pin, repeated: repeated) {
      return (self, error)
    }
    var copy = self
    copy.scaConfirmed = true
    return (copy, nil)
  }

  public func applying(_ decision: ReturnDecision) -> PaymentAttempt {
    guard method == .bank,
          decision.outcome == .accepted,
          decision.allowsPaymentSubmit,
          !decision.createsPayment,
          decision.idempotencyKey == idempotencyKey
    else { return self }
    var copy = self
    copy.bankAccepted = true
    return copy
  }

  @discardableResult
  public func submitIfReady(_ block: (String) -> Void) -> Bool {
    guard readyToSubmit else { return false }
    block(idempotencyKey)
    return true
  }
}

public final class ReturnStateVault {
  public static let defaultTtlSeconds: Int64 = 300

  private let key: Data
  private let ttlSeconds: Int64
  private let now: () -> Int64
  private var consumed: Set<String> = []
  private let lock = NSLock()

  public init(
    key: Data? = nil,
    ttlSeconds: Int64 = ReturnStateVault.defaultTtlSeconds,
    now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) }
  ) {
    let material = key ?? ReturnStateVault.randomKey()
    precondition(material.count >= 16, "Return state key is too short")
    self.key = material
    self.ttlSeconds = min(max(ttlSeconds, 1), ReturnStateVault.defaultTtlSeconds)
    self.now = now
  }

  public func issue(sessionId: String, paymentKey: String) throws -> IssuedBankHandoff {
    guard ReturnStateVault.sessionPattern.matches(sessionId) else {
      throw MeridianError.validationError("Invalid session")
    }
    guard ReturnStateVault.paymentKeyPattern.matches(paymentKey) else {
      throw MeridianError.validationError("Invalid payment key")
    }
    let exp = now() + ttlSeconds
    let nonce = UUID().uuidString.lowercased()
    let payload = ReturnStateVault.canonical(exp: exp, nonce: nonce, paymentKey: paymentKey, session: sessionId)
    let token = ReturnStateVault.sign(key: key, payload: payload)
    let handoff = "https://\(BankHandoffPolicy.bankHost)\(BankHandoffPolicy.bankPath)?state=\(token)"
    let ret = "https://\(BankHandoffPolicy.returnHost)\(BankHandoffPolicy.returnPath)?state=\(token)"
    guard case .allowed = BankHandoffPolicy.inspectBankHandoff(handoff) else {
      throw MeridianError.validationError("Handoff URL left the allowlist")
    }
    guard case .allowed = BankHandoffPolicy.inspectReturnLink(ret) else {
      throw MeridianError.validationError("Return URL is not an app link")
    }
    return IssuedBankHandoff(
      handoffURL: handoff,
      returnURL: ret,
      state: token,
      idempotencyKey: paymentKey,
      expiresAtEpochSeconds: exp
    )
  }

  public func cancel(state: String) {
    guard let parsed = parseToken(state) else { return }
    lock.lock()
    consumed.insert(parsed.nonce)
    lock.unlock()
  }

  public func intercept(url: String, expectedSession: String, expectedPaymentKey: String) -> ReturnDecision {
    func finish(_ outcome: ReturnOutcome, _ allow: Bool) -> ReturnDecision {
      ReturnDecision(outcome: outcome, idempotencyKey: expectedPaymentKey, allowsPaymentSubmit: allow)
    }

    let state: String
    switch BankHandoffPolicy.matchReturn(url) {
    case .unrelated:
      return finish(.ignored, false)
    case .malformed:
      return finish(.invalid, false)
    case let .ready(_, readyState):
      state = readyState
    }

    guard let parsed = parseToken(state) else { return finish(.invalid, false) }
    if now() >= parsed.exp { return finish(.expired, false) }

    lock.lock()
    let seen = consumed.contains(parsed.nonce)
    if !seen { consumed.insert(parsed.nonce) }
    lock.unlock()
    if seen { return finish(.replayed, false) }

    if parsed.session != expectedSession || parsed.paymentKey != expectedPaymentKey {
      return finish(.invalid, false)
    }
    return finish(.accepted, true)
  }

  private func parseToken(_ token: String) -> Claims? {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    guard let payloadData = Base64Url.decode(String(parts[0])) else { return nil }
    guard let payload = String(data: payloadData, encoding: .utf8) else { return nil }
    guard let provided = decodeHexMac(String(parts[1])) else { return nil }
    let expected = HmacSha256.sign(key: key, message: Data(payload.utf8))
    guard constantTimeEquals(provided, expected) else { return nil }
    return ReturnStateVault.parsePayload(payload)
  }

  static func canonical(exp: Int64, nonce: String, paymentKey: String, session: String) -> String {
    "{\"exp\":\(exp),\"nonce\":\"\(nonce)\",\"paymentKey\":\"\(paymentKey)\",\"session\":\"\(session)\",\"v\":1}"
  }

  static func sign(key: Data, payload: String) -> String {
    let mac = HmacSha256.sign(key: key, message: Data(payload.utf8))
    return Base64Url.encode(Data(payload.utf8)) + "." + hex(mac)
  }

  private static func randomKey() -> Data {
    var bytes = [UInt8](repeating: 0, count: 32)
    var generator = SystemRandomNumberGenerator()
    for index in bytes.indices {
      bytes[index] = UInt8.random(in: .min ... .max, using: &generator)
    }
    return Data(bytes)
  }

  private static let sessionPattern = WholePattern("^[A-Za-z0-9_-]{3,64}$")
  private static let paymentKeyPattern = WholePattern("^[A-Za-z0-9_-]{1,100}$")
  private static let payloadExpression: NSRegularExpression = {
    let pattern = "^\\{\"exp\":(\\d{1,12}),\"nonce\":\"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\",\"paymentKey\":\"([A-Za-z0-9_-]{1,100})\",\"session\":\"([A-Za-z0-9_-]{3,64})\",\"v\":1\\}$"
    return try! NSRegularExpression(pattern: pattern)
  }()

  private static func parsePayload(_ payload: String) -> Claims? {
    let range = NSRange(payload.startIndex..<payload.endIndex, in: payload)
    guard let match = payloadExpression.firstMatch(in: payload, range: range),
          match.range.location == 0,
          match.range.length == range.length
    else { return nil }

    func group(_ index: Int) -> String? {
      let groupRange = match.range(at: index)
      guard let swiftRange = Range(groupRange, in: payload) else { return nil }
      return String(payload[swiftRange])
    }

    guard let expText = group(1), let exp = Int64(expText), exp > 0, String(exp) == expText else { return nil }
    guard let nonce = group(2), let paymentKey = group(3), let session = group(4) else { return nil }
    return Claims(exp: exp, nonce: nonce, paymentKey: paymentKey, session: session)
  }
}

private struct Claims {
  let exp: Int64
  let nonce: String
  let paymentKey: String
  let session: String
}

private struct WholePattern {
  let regex: NSRegularExpression
  init(_ pattern: String) {
    regex = try! NSRegularExpression(pattern: pattern)
  }

  func matches(_ value: String) -> Bool {
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = regex.firstMatch(in: value, range: range) else { return false }
    return match.range.location == 0 && match.range.length == range.length
  }
}

private let stateQuery = try! NSRegularExpression(pattern: "^state=([A-Za-z0-9_-]+)\\.([0-9a-f]{64})$")

private func matchLink(_ url: String, host: String, path: String) -> LinkMatch {
  if url.isEmpty || url.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "\\" }) {
    return .unrelated
  }
  if !url.hasPrefix("https://") {
    if url.hasPrefix("http://") && url.contains(host) {
      return .malformed("Only HTTPS URLs can be opened")
    }
    return .unrelated
  }
  guard let components = URLComponents(string: url), components.scheme == "https" else {
    return .malformed("URL is not usable")
  }
  if components.user != nil || components.password != nil || url.contains("@") {
    return .malformed("URL userinfo is not allowed")
  }
  let parsedHost = components.host?.lowercased() ?? ""
  if parsedHost != host || components.path != path {
    return .unrelated
  }
  if let port = components.port, port != 443 {
    return .malformed("Unexpected port")
  }
  if components.fragment != nil {
    return .malformed("Fragments are not allowed")
  }
  guard let queryStart = url.firstIndex(of: "?") else {
    return .malformed("Missing state")
  }
  let query = String(url[url.index(after: queryStart)...])
  if query.contains("#") || query.contains("?") {
    return .malformed("Return state is missing or not opaque")
  }
  let range = NSRange(query.startIndex..<query.endIndex, in: query)
  guard let match = stateQuery.firstMatch(in: query, range: range),
        match.range.location == 0,
        match.range.length == range.length,
        let stateRange = Range(match.range(at: 0), in: query)
  else {
    return .malformed("Return state is missing or not opaque")
  }
  let raw = String(query[stateRange])
  let state = String(raw.dropFirst("state=".count))
  return .ready(url: url, state: state)
}

enum HmacSha256 {
  static func sign(key: Data, message: Data) -> Data {
    let code = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key))
    return Data(code)
  }
}

enum Base64Url {
  static func encode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  static func decode(_ text: String) -> Data? {
    if text.isEmpty || text.count % 4 == 1 { return nil }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    if text.unicodeScalars.contains(where: { !allowed.contains($0) }) { return nil }
    var padded = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    let remainder = padded.count % 4
    if remainder > 0 { padded += String(repeating: "=", count: 4 - remainder) }
    return Data(base64Encoded: padded)
  }
}

func hex(_ data: Data) -> String {
  data.map { String(format: "%02x", $0) }.joined()
}

func decodeHexMac(_ text: String) -> Data? {
  guard text.count == 64 else { return nil }
  var data = Data(capacity: 32)
  var index = text.startIndex
  while index < text.endIndex {
    let next = text.index(index, offsetBy: 2)
    guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
    data.append(byte)
    index = next
  }
  return data
}

func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
  guard a.count == b.count else { return false }
  var diff: UInt8 = 0
  for index in 0..<a.count {
    diff |= a[index] ^ b[index]
  }
  return diff == 0
}
