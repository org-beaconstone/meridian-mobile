import Foundation

/// Customer-facing consent locked into each payment-intent payload.
public let paymentConsentSummary =
  "I authorise Meridian to submit this GBP payment to the named recipient. This rehearsal does not move real money or contact Adyen or Worldpay."

public let paymentQuoteTTLSeconds = 60

public enum IntentDisposition: String, Equatable {
  case succeeded
  case declined
  case actionRequired
  case retrySameIntent
}

public struct PaymentReview: Equatable {
  public let recipientName: String
  public let recipientDetail: String
  public let amountMinor: Int
  public let feeMinor: Int
  public let amountLabel: String
  public let feeLabel: String
  public let methodLabel: String
  public let bank: String
  public let quoteExpiresAt: String
  public let expiryLabel: String
  public let consentSummary: String
  public let localReference: String
  public let currency: String
}

public struct PaymentIntentResponse: Decodable {
  public let ok: Bool
  public let status: String?
  public let intentId: String?
  public let state: BankState?
  public let transaction: Transaction?
  public let error: String?
  public let code: String?
}

public struct PaymentIntentSubmission: Equatable {
  public let disposition: IntentDisposition
  public let statusCode: Int
  public let intentId: String?
  public let ok: Bool
  public let code: String?
  public let error: String?
  public let message: String
  public let idempotencyKey: String
  public let payloadHash: String
  public let state: BankState?
  public var terminal: Bool {
    disposition == .succeeded || disposition == .declined || disposition == .actionRequired
  }
}

public func resolvePaymentIntentsURL(_ baseURL: String) -> String? {
  var trimmed = baseURL
  while trimmed.hasSuffix("/") { trimmed.removeLast() }
  let root: String
  if trimmed.hasSuffix("/api/v1") {
    root = String(trimmed.dropLast("/api/v1".count))
  } else {
    root = trimmed
  }
  let absolute = root + "/api/v2/payment-intents"
  guard absolute.hasPrefix("http://") || absolute.hasPrefix("https://") else { return nil }
  return absolute
}

public func rehearsalFeeMinor(method: PaymentMethod, amountMinor: Int) -> Int {
  switch method {
  case .bank:
    return 0
  case .card:
    let rounded = (amountMinor * 15 + 500) / 1000
    return max(rounded, 1)
  }
}

public func baselineBank(method: PaymentMethod) -> String {
  switch method {
  case .card: return "Adyen"
  case .bank: return "Worldpay"
  }
}

public func baselineProviderId(method: PaymentMethod) -> String {
  switch method {
  case .card: return "adyen"
  case .bank: return "worldpay"
  }
}

public func baselineMethodLabel(method: PaymentMethod) -> String {
  switch method {
  case .card: return "Debit card"
  case .bank: return "Bank payment"
  }
}

public func localizedRecipientName(_ name: String) -> String {
  name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
}

public func formatUTC(_ date: Date) -> String {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
  return String(
    format: "%04d-%02d-%02dT%02d:%02d:%02dZ",
    parts.year ?? 0,
    parts.month ?? 0,
    parts.day ?? 0,
    parts.hour ?? 0,
    parts.minute ?? 0,
    parts.second ?? 0
  )
}

public func localizedQuoteExpiry(_ iso: String) -> String {
  let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  guard iso.count == 20, iso.hasSuffix("Z"), iso.contains("T") else { return iso }
  let datePart = iso.prefix(10)
  let timePart = iso.dropFirst(11).prefix(8)
  let dateBits = datePart.split(separator: "-")
  let timeBits = timePart.split(separator: ":")
  guard dateBits.count == 3, timeBits.count == 3,
    let monthNumber = Int(dateBits[1]), let day = Int(dateBits[2]),
    months.indices.contains(monthNumber - 1)
  else { return iso }
  return "\(day) \(months[monthNumber - 1]) \(dateBits[0]), \(timeBits[0]):\(timeBits[1]) UTC"
}

public func isQuoteExpired(quoteExpiresAt: String, now: Date) -> Bool {
  formatUTC(now) >= quoteExpiresAt
}

public func normalizedLocalReference(_ input: String) -> (String?, String?) {
  let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty { return (nil, "Local reference is required") }
  if trimmed.count > 200 { return (nil, "Local reference is too long") }
  if trimmed.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) {
    return (nil, "Local reference contains invalid characters")
  }
  return (trimmed, nil)
}

public func jsonString(_ value: String) -> String {
  var out = "\""
  for scalar in value.unicodeScalars {
    switch scalar.value {
    case 0x22: out += "\\\""
    case 0x5C: out += "\\\\"
    case 0x08: out += "\\b"
    case 0x0C: out += "\\f"
    case 0x0A: out += "\\n"
    case 0x0D: out += "\\r"
    case 0x09: out += "\\t"
    case 0x00...0x1F:
      out += String(format: "\\u%04x", scalar.value)
    default:
      out.unicodeScalars.append(scalar)
    }
  }
  out += "\""
  return out
}

public func canonicalPaymentIntentJSON(
  amountMinor: Int,
  bank: String,
  consentSummary: String,
  feeMinor: Int,
  localReference: String,
  method: String,
  provider: String,
  quoteExpiresAt: String,
  quoteId: String,
  recipientId: String,
  recipientName: String
) -> String {
  let pairs: [(String, String)] = [
    ("amountMinor", String(amountMinor)),
    ("bank", jsonString(bank)),
    ("consentAccepted", "true"),
    ("consentSummary", jsonString(consentSummary)),
    ("currency", jsonString("GBP")),
    ("feeMinor", String(feeMinor)),
    ("localReference", jsonString(localReference)),
    ("method", jsonString(method)),
    ("provider", jsonString(provider)),
    ("quoteExpiresAt", jsonString(quoteExpiresAt)),
    ("quoteId", jsonString(quoteId)),
    ("recipientId", jsonString(recipientId)),
    ("recipientName", jsonString(recipientName)),
  ]
  return "{" + pairs.map { "\(jsonString($0.0)):\($0.1)" }.joined(separator: ",") + "}"
}

public func classifyPaymentIntent(statusCode: Int, ok: Bool, status: String?, code: String?) -> IntentDisposition {
  let normalized = status?
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .lowercased()
    .replacingOccurrences(of: "-", with: "_")
  switch normalized {
  case "succeeded", "success", "completed":
    return .succeeded
  case "declined", "decline":
    return .declined
  case "action_required", "requires_action":
    return .actionRequired
  default:
    break
  }
  switch code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
  case "SUCCEEDED", "SUCCESS":
    return .succeeded
  case "DECLINED":
    return .declined
  case "ACTION_REQUIRED", "REQUIRES_ACTION":
    return .actionRequired
  default:
    break
  }
  if statusCode == 422 { return .declined }
  if statusCode == 202 { return .actionRequired }
  if (200..<300).contains(statusCode) && ok { return .succeeded }
  return .retrySameIntent
}

public func paymentIntentMessage(disposition: IntentDisposition, error: String?) -> String {
  let reason = error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  switch disposition {
  case .succeeded:
    return "Payment intent succeeded. This intent was not submitted again."
  case .declined:
    let lead = reason.isEmpty ? "Payment declined" : reason.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return "\(lead). This intent stays closed."
  case .actionRequired:
    let lead = reason.isEmpty ? "Action required" : reason.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return "\(lead). This intent was not recreated."
  case .retrySameIntent:
    let lead = reason.isEmpty ? "Outcome may be unknown" : reason.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return "\(lead). Retry keeps the same idempotency key and payload hash."
  }
}

private func safeToken(_ value: String) -> Bool {
  value.range(of: "^[A-Za-z0-9_-]{1,100}$", options: .regularExpression) != nil
}

public func preparePaymentIntent(
  recipientId: String,
  recipientName: String,
  recipientDetail: String,
  amountInput: String,
  localReference: String,
  method: PaymentMethod,
  now: Date = Date(),
  ttlSeconds: Int = paymentQuoteTTLSeconds,
  idempotencyKey: String = UUID().uuidString,
  quoteId: String = "quote-\(UUID().uuidString.lowercased())",
  quoteExpiresAt: String? = nil
) throws -> PaymentIntentAttempt {
  let recipient = recipientId.trimmingCharacters(in: .whitespacesAndNewlines)
  let name = localizedRecipientName(recipientName)
  guard !recipient.isEmpty, !name.isEmpty else {
    throw MeridianError.validationError("Recipient is required")
  }
  let (amountMinor, amountError) = parseAmount(amountInput)
  guard let amountMinor else {
    throw MeridianError.validationError(amountError ?? "Amount is required")
  }
  let (reference, referenceError) = normalizedLocalReference(localReference)
  guard let reference else {
    throw MeridianError.validationError(referenceError ?? "Local reference is required")
  }
  guard safeToken(idempotencyKey) else {
    throw MeridianError.validationError("Idempotency key is invalid")
  }
  guard safeToken(quoteId) else {
    throw MeridianError.validationError("Quote id is invalid")
  }
  let expiry = quoteExpiresAt ?? formatUTC(now.addingTimeInterval(TimeInterval(ttlSeconds)))
  guard expiry.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#, options: .regularExpression) != nil else {
    throw MeridianError.validationError("Quote expiry is invalid")
  }
  let fee = rehearsalFeeMinor(method: method, amountMinor: amountMinor)
  let bank = baselineBank(method: method)
  let provider = baselineProviderId(method: method)
  let canonical = canonicalPaymentIntentJSON(
    amountMinor: amountMinor,
    bank: bank,
    consentSummary: paymentConsentSummary,
    feeMinor: fee,
    localReference: reference,
    method: method.rawValue,
    provider: provider,
    quoteExpiresAt: expiry,
    quoteId: quoteId,
    recipientId: recipient,
    recipientName: name
  )
  let review = PaymentReview(
    recipientName: name,
    recipientDetail: recipientDetail.trimmingCharacters(in: .whitespacesAndNewlines),
    amountMinor: amountMinor,
    feeMinor: fee,
    amountLabel: money(amountMinor),
    feeLabel: money(fee),
    methodLabel: baselineMethodLabel(method: method),
    bank: bank,
    quoteExpiresAt: expiry,
    expiryLabel: localizedQuoteExpiry(expiry),
    consentSummary: paymentConsentSummary,
    localReference: reference,
    currency: "GBP"
  )
  return PaymentIntentAttempt(
    idempotencyKey: idempotencyKey,
    payloadHash: SHA256.hex(canonical),
    canonicalBody: canonical,
    quoteExpiresAt: expiry,
    review: review
  )
}

public actor PaymentIntentAttempt {
  public nonisolated let idempotencyKey: String
  public nonisolated let payloadHash: String
  public nonisolated let canonicalBody: String
  public nonisolated let quoteExpiresAt: String
  public nonisolated let review: PaymentReview
  private var inFlight = false
  private var submitted = false
  private var settled: PaymentIntentSubmission?

  public init(
    idempotencyKey: String,
    payloadHash: String,
    canonicalBody: String,
    quoteExpiresAt: String,
    review: PaymentReview
  ) {
    self.idempotencyKey = idempotencyKey
    self.payloadHash = payloadHash
    self.canonicalBody = canonicalBody
    self.quoteExpiresAt = quoteExpiresAt
    self.review = review
  }

  public func hasSubmitted() -> Bool { submitted || settled != nil }

  public func submit(
    now: Date = Date(),
    consentAccepted: Bool,
    transport: @Sendable (String, String, String) async throws -> (statusCode: Int, body: PaymentIntentResponse)
  ) async throws -> PaymentIntentSubmission {
    if let settled { return settled }
    if inFlight { throw MeridianError.duplicateSubmission }
    if !submitted {
      if !consentAccepted { throw MeridianError.validationError("Consent is required") }
      if isQuoteExpired(quoteExpiresAt: quoteExpiresAt, now: now) { throw MeridianError.quoteExpired }
    }
    inFlight = true
    submitted = true
    do {
      let result = try await transport(canonicalBody, idempotencyKey, payloadHash)
      let disposition = classifyPaymentIntent(
        statusCode: result.statusCode,
        ok: result.body.ok,
        status: result.body.status,
        code: result.body.code
      )
      let submission = PaymentIntentSubmission(
        disposition: disposition,
        statusCode: result.statusCode,
        intentId: result.body.intentId,
        ok: result.body.ok,
        code: result.body.code,
        error: result.body.error,
        message: paymentIntentMessage(disposition: disposition, error: result.body.error),
        idempotencyKey: idempotencyKey,
        payloadHash: payloadHash,
        state: result.body.state
      )
      inFlight = false
      if submission.terminal { settled = submission }
      return submission
    } catch {
      inFlight = false
      throw error
    }
  }
}

enum SHA256 {
  private static let k: [UInt32] = [
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
  ]

  static func hex(_ text: String) -> String {
    digest(Array(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  static func digest(_ message: [UInt8]) -> [UInt8] {
    var bytes = message
    let bitLength = UInt64(message.count) &* 8
    bytes.append(0x80)
    while bytes.count % 64 != 56 { bytes.append(0) }
    var shift: UInt64 = 56
    while true {
      bytes.append(UInt8((bitLength >> shift) & 0xFF))
      if shift == 0 { break }
      shift -= 8
    }
    var h: [UInt32] = [
      0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
      0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
    ]
    func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
    var offset = 0
    while offset < bytes.count {
      var w = [UInt32](repeating: 0, count: 64)
      for i in 0..<16 {
        let j = offset + i * 4
        w[i] = (UInt32(bytes[j]) << 24) | (UInt32(bytes[j + 1]) << 16) | (UInt32(bytes[j + 2]) << 8) | UInt32(bytes[j + 3])
      }
      for i in 16..<64 {
        let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
        let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
        w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
      }
      var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
      for i in 0..<64 {
        let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
        let ch = (e & f) ^ (~e & g)
        let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
        let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
        let maj = (a & b) ^ (a & c) ^ (b & c)
        let t2 = s0 &+ maj
        hh = g
        g = f
        f = e
        e = d &+ t1
        d = c
        c = b
        b = a
        a = t1 &+ t2
      }
      h[0] = h[0] &+ a
      h[1] = h[1] &+ b
      h[2] = h[2] &+ c
      h[3] = h[3] &+ d
      h[4] = h[4] &+ e
      h[5] = h[5] &+ f
      h[6] = h[6] &+ g
      h[7] = h[7] &+ hh
      offset += 64
    }
    var out: [UInt8] = []
    out.reserveCapacity(32)
    for value in h {
      out.append(UInt8((value >> 24) & 0xFF))
      out.append(UInt8((value >> 16) & 0xFF))
      out.append(UInt8((value >> 8) & 0xFF))
      out.append(UInt8(value & 0xFF))
    }
    return out
  }
}
