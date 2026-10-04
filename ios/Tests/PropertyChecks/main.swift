import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MeridianSDK

@main
struct MeridianPropertyChecks {
  static func main() async {
    let checks = Checks()
    currencyBoundaries(checks)
    currencyProperties(checks)
    ibanProperties(checks)
    scaProperties(checks)
    providerSwitch(checks)
    await faultInjection(checks)
    print("\n=== Property suite ===")
    print("Passed: \(checks.passed)")
    print("Failed: \(checks.failed)")
    if checks.failed > 0 { exit(1) }
  }
}

final class Checks {
  var passed = 0
  var failed = 0
  func expect(_ condition: Bool, _ message: String) {
    if condition {
      passed += 1
      print("  ✓ \(message)")
    } else {
      failed += 1
      print("  ✗ \(message)")
    }
  }
}

struct Seeded: RandomNumberGenerator {
  private var state: UInt64
  init(_ seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E3779B97F4A7C15
    var mixed = state
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
    return mixed ^ (mixed >> 31)
  }
  mutating func int(_ upper: Int) -> Int { Int(next() % UInt64(upper)) }
  mutating func int(_ lower: Int, _ upper: Int) -> Int { lower + int(upper - lower) }
}

func currencyBoundaries(_ checks: Checks) {
  let (minParsed, minError) = parseAmount("0.01")
  let (minRounded, _) = roundMajorToMinor("0.01")
  checks.expect(minParsed == gbpMinMinor && minError == nil && minRounded == gbpMinMinor, "£0.01 is 1 pence")
  let (maxWhole, _) = parseAmount("10000")
  let (maxExact, _) = parseAmount("10000.00")
  let (maxRounded, _) = roundMajorToMinor("10000.00")
  let (justUnder, _) = roundMajorToMinor("10000.004")
  checks.expect(
    maxWhole == gbpMaxMinor && maxExact == gbpMaxMinor && maxRounded == gbpMaxMinor && justUnder == gbpMaxMinor,
    "£10,000.00 is 1000000 pence"
  )
  checks.expect(roundMajorToMinor("10000.005").0 == nil, "half-up above £10,000.00 is rejected")
  checks.expect(parseAmount("10000.01").0 == nil, "£10,000.01 is rejected")
  checks.expect(roundMajorToMinor("0.004").0 == nil && roundMajorToMinor("0.005").0 == 1, "half-up at one pence")
  checks.expect(roundMajorToMinor("1.999").0 == 200 && roundMajorToMinor("1.994").0 == 199, "carry and truncation")
  checks.expect(parseAmount("10.505").0 == nil && roundMajorToMinor("10.505").0 == 1051, "strict parse rejects a third digit that rounding accepts")
  checks.expect(formatMinorUnits(gbpMinMinor) == "0.01" && formatMinorUnits(gbpMaxMinor) == "10000.00", "canonical formatting")
}

func currencyProperties(_ checks: Checks) {
  var rng = Seeded(20261004)
  var failures: [String] = []
  for index in 0..<200 {
    let minor = rng.int(gbpMinMinor, gbpMaxMinor + 1)
    let text = formatMinorUnits(minor)
    let parsed = parseAmount(text).0
    let rounded = roundMajorToMinor(text).0
    let down = String(rng.int(0, 5)) + String(rng.int(0, 10)) + String(rng.int(0, 10))
    let roundedDown = roundMajorToMinor(text + down).0
    if parsed != minor || rounded != minor || roundedDown != minor {
      failures.append("case \(index) minor \(minor) text \(text) down \(down)")
      break
    }
    if minor < gbpMaxMinor {
      let up = String(rng.int(5, 10)) + String(rng.int(0, 10))
      if roundMajorToMinor(text + up).0 != minor + 1 {
        failures.append("round up case \(index) minor \(minor) suffix \(up)")
        break
      }
    } else if roundMajorToMinor(text + "5").0 != nil {
      failures.append("max bound case \(index)")
      break
    }
  }
  checks.expect(failures.isEmpty, failures.first ?? "200 currency properties")
  let samples = ["0.01", "0.10", "1", "10.", "10.5", "10.50", "0004.20", "10000", "10000.00"]
  let agreed = samples.allSatisfy { parseAmount($0).0 == roundMajorToMinor($0).0 }
  checks.expect(agreed, "parser and rounding agree through two decimals")
  let invalid = ["", " ", "0", "0.00", "-1", "+1", "1e2", "10000.01", "10001", "£1", "1,000"]
  let rejected = invalid.allSatisfy { parseAmount($0).0 == nil && roundMajorToMinor($0).0 == nil }
  checks.expect(rejected, "invalid amounts stay rejected")
}

func ibanProperties(_ checks: Checks) {
  let known = [
    "GB82WEST12345698765432",
    "DE89370400440532013000",
    "FR1420041010050500013M02606",
    "GR1601101250000000012300695",
    "GB94BARC10201530093459",
    "NL91ABNA0417164300",
  ]
  let knownOk = known.allSatisfy { iban in
    ibanMod97(iban) == 1 && ibanIsValid(iban) && ibanIsValid(grouped(iban.lowercased())) && !ibanIsValid(String(iban.prefix(2)) + "00" + iban.dropFirst(4))
  }
  checks.expect(knownOk, "published MOD-97 examples")
  checks.expect(ibanCompose(country: "gb", bban: "WEST12345698765432") == "GB82WEST12345698765432", "GB example check digits")
  checks.expect(!ibanIsValid("") && !ibanIsValid("GB00") && !ibanIsValid("1234WEST12345698765432"), "structural IBAN rejects")

  var rng = Seeded(20261004)
  var failure: String?
  let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
  let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
  for index in 0..<200 {
    let country = String(letters[rng.int(26)]) + String(letters[rng.int(26)])
    let length = rng.int(11, 31)
    var bban = ""
    for _ in 0..<length { bban.append(alphabet[rng.int(alphabet.count)]) }
    let iban = ibanCompose(country: country, bban: bban)
    let check = Int(iban.dropFirst(2).prefix(2)) ?? 0
    let corrupted = String(iban.prefix(2)) + String(format: "%02d", (check + 1) % 100) + iban.dropFirst(4)
    if !ibanIsValid(iban) || ibanMod97(ibanNormalize(grouped(iban.lowercased()))) != 1 || ibanIsValid(corrupted) {
      failure = "case \(index) \(iban)"
      break
    }
  }
  checks.expect(failure == nil, failure ?? "200 composed IBAN properties")
}

func grouped(_ iban: String) -> String {
  var result = ""
  for (index, character) in iban.enumerated() {
    if index > 0 && index % 4 == 0 { result.append(" ") }
    result.append(character)
  }
  return result
}

func scaProperties(_ checks: Checks) {
  do {
    try assertSimulatedScaFlows()
    checks.expect(true, "biometric pass, passcode fallback, and timeout")
  } catch {
    checks.expect(false, "SCA flows: \(error)")
  }
  var rng = Seeded(20261004)
  var failure: String?
  for index in 0..<200 {
    let method: PaymentMethod = rng.int(2) == 0 ? .card : .bank
    let provider = providerFor(method: method)
    let id = "sca-\(rng.int(1_000_000))"
    let key = "key-\(rng.int(1_000_000))"
    var passed = ScaChallenge(id: id, paymentKey: key, method: method)
    passed.submitBiometric(matched: true)
    var fallback = ScaChallenge(id: id + "-fb", paymentKey: key, method: method)
    fallback.submitBiometric(matched: false)
    fallback.submitPasscode(fallback.rehearsalPasscode())
    var timed = ScaChallenge(id: id + "-to", paymentKey: key, method: method, timeoutSteps: 1)
    timed.advance()
    timed.submitBiometric(matched: true)
    if passed.status != .passed(.biometric) || passed.provider != provider || passed.paymentKey != key
      || fallback.status != .passed(.passcode) || fallback.provider != provider
      || timed.status != .timedOut || timed.provider != provider || timed.paymentKey != key {
      failure = "case \(index) \(id)"
      break
    }
  }
  checks.expect(failure == nil, failure ?? "200 SCA properties keep provider and key")
}

func providerSwitch(_ checks: Checks) {
  do {
    try refuseProviderSwitch(from: .adyen, to: .worldpay)
    checks.expect(false, "card timeout must not move to Worldpay")
  } catch MeridianError.validationError {
    checks.expect(providerFor(method: .card) == .adyen && providerFor(method: .bank) == .worldpay, "provider baseline stays fixed")
  } catch {
    checks.expect(false, "unexpected routing error \(error)")
  }
}

final class FaultBox: @unchecked Sendable {
  let lock = NSLock()
  var dropAfterCommit = 0
  var dropBeforeCommit = 0
  var mode = "success"
  var debits = 0
  var keys: [String] = []
  var methods: [String] = []
  var sessions: [String] = []
  var providers: [String] = []
  var committed: [String: Data] = [:]

  func reset(dropAfterCommit: Int, dropBeforeCommit: Int, mode: String) {
    lock.lock()
    self.dropAfterCommit = dropAfterCommit
    self.dropBeforeCommit = dropBeforeCommit
    self.mode = mode
    debits = 0
    keys = []
    methods = []
    sessions = []
    providers = []
    committed = [:]
    lock.unlock()
  }
}

final class FaultURLProtocol: URLProtocol, @unchecked Sendable {
  static let box = FaultBox()

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let box = FaultURLProtocol.box
    let request = self.request
    let body = Self.readBody(request)
    let key = request.value(forHTTPHeaderField: "Idempotency-Key") ?? ""
    let session = request.value(forHTTPHeaderField: "X-Rehearsal-Session") ?? ""
    let method = Self.method(in: body)
    let provider = method == "card" ? "adyen" : method == "bank" ? "worldpay" : "unknown"
    box.lock.lock()
    box.keys.append(key)
    box.methods.append(method)
    box.sessions.append(session)
    box.providers.append(provider)
    if box.mode == "decline" {
      box.lock.unlock()
      finish(status: 422, data: Data("{\"ok\":false,\"code\":\"PAYMENT_DECLINED\",\"error\":\"Payment declined. No debit was made.\"}".utf8))
      return
    }
    if box.dropBeforeCommit > 0 {
      box.dropBeforeCommit -= 1
      box.lock.unlock()
      client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
      return
    }
    let payload: Data
    if let existing = box.committed[key] {
      payload = existing
    } else {
      box.debits += 1
      let json = "{\"ok\":true,\"transaction\":{\"id\":\"pay-1\",\"reference\":\"MER-PAY\",\"recipientId\":\"northline-studio\",\"name\":\"Northline Studio\",\"category\":\"Shopping\",\"amount\":1,\"date\":\"2026-09-18\",\"provider\":\"\(provider)\",\"method\":\"\(method)\",\"status\":\"completed\",\"note\":\"drop\"},\"state\":{\"version\":1,\"balance\":1,\"transactions\":[],\"budgets\":[]}}"
      payload = Data(json.utf8)
      box.committed[key] = payload
    }
    if box.dropAfterCommit > 0 {
      box.dropAfterCommit -= 1
      box.lock.unlock()
      client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
      return
    }
    box.lock.unlock()
    finish(status: 200, data: payload)
  }

  override func stopLoading() {}

  private func finish(status: Int, data: Data) {
    let response = HTTPURLResponse(url: request.url ?? URL(string: "http://127.0.0.1/api/v1/payments")!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  private static func readBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let count = stream.read(buffer, maxLength: bufferSize)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }

  private static func method(in body: Data) -> String {
    guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return "" }
    return object["method"] as? String ?? ""
  }
}

func faultInjection(_ checks: Checks) async {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [FaultURLProtocol.self]
  let session = URLSession(configuration: config)
  let box = FaultURLProtocol.box

  box.reset(dropAfterCommit: 2, dropBeforeCommit: 0, mode: "success")
  do {
    let client = try MeridianClient(baseURL: "http://127.0.0.1:9/api/v1", sessionId: "fault-session", urlSession: session)
    let response = try await client.submitPayment(recipientId: "northline-studio", amountMinor: 1, method: .card, note: "drop", idempotencyKey: "drop-key-1")
    let ok = response.ok && response.transaction?.provider == .adyen && response.transaction?.method == .card
      && box.debits == 1 && box.keys == ["drop-key-1", "drop-key-1", "drop-key-1"]
      && box.methods == ["card", "card", "card"] && box.providers == ["adyen", "adyen", "adyen"]
      && box.sessions == ["fault-session", "fault-session", "fault-session"]
    checks.expect(ok, "response drop dedupes on Adyen card")
  } catch {
    checks.expect(false, "response drop threw \(error)")
  }

  box.reset(dropAfterCommit: 0, dropBeforeCommit: 2, mode: "success")
  do {
    let client = try MeridianClient(baseURL: "http://127.0.0.1:9/api/v1", sessionId: "fault-session-2", urlSession: session)
    let response = try await client.submitPayment(recipientId: "northline-studio", amountMinor: 2500, method: .bank, note: "lost", idempotencyKey: "drop-key-2")
    let ok = response.ok && response.transaction?.provider == .worldpay && response.transaction?.method == .bank
      && box.debits == 1 && box.keys.count == 3 && box.keys.allSatisfy { $0 == "drop-key-2" }
      && box.methods.allSatisfy { $0 == "bank" } && box.providers.allSatisfy { $0 == "worldpay" }
    checks.expect(ok, "request drop recovers on Worldpay bank")
  } catch {
    checks.expect(false, "request drop threw \(error)")
  }

  box.reset(dropAfterCommit: 0, dropBeforeCommit: 0, mode: "decline")
  do {
    let client = try MeridianClient(baseURL: "http://127.0.0.1:9/api/v1", sessionId: "fault-session-3", urlSession: session)
    let response = try await client.submitPayment(recipientId: "northline-studio", amountMinor: 50, method: .card, note: "declined", idempotencyKey: "decline-key")
    let ok = !response.ok && response.code == "PAYMENT_DECLINED" && box.debits == 0 && box.keys == ["decline-key"] && box.methods == ["card"] && box.providers == ["adyen"]
    checks.expect(ok, "decline is not retried and stays on Adyen")
  } catch {
    checks.expect(false, "decline threw \(error)")
  }
}
