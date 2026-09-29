import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MeridianSDK

@main
struct MeridianSDKChecks {
  static func main() async {
    print("=== Meridian SDK Checks ===\n")

    var passed = 0
    var failed = 0

    // CHECK 1: parseAmount valid integer
    print("1. parseAmount valid integer...")
    let (pence1, err1) = parseAmount("10")
    if pence1 == 1000 && err1 == nil {
      print("  ✓ parseAmount(\"10\") = 1000 pence")
      passed += 1
    } else {
      print("  ✗ Expected 1000 pence, got: \(pence1 ?? 0)")
      failed += 1
    }

    // CHECK 2: parseAmount valid decimal
    print("2. parseAmount valid decimal...")
    let (pence2, err2) = parseAmount("10.50")
    if pence2 == 1050 && err2 == nil {
      print("  ✓ parseAmount(\"10.50\") = 1050 pence")
      passed += 1
    } else {
      print("  ✗ Expected 1050 pence, got: \(pence2 ?? 0)")
      failed += 1
    }

    // CHECK 3: parseAmount single decimal
    print("3. parseAmount single decimal...")
    let (pence3, err3) = parseAmount("10.5")
    if pence3 == 1050 && err3 == nil {
      print("  ✓ parseAmount(\"10.5\") = 1050 pence")
      passed += 1
    } else {
      print("  ✗ Expected 1050 pence, got: \(pence3 ?? 0)")
      failed += 1
    }

    // CHECK 4: parseAmount zero rejected
    print("4. parseAmount zero rejected...")
    let (pence4, err4) = parseAmount("0")
    if pence4 == nil && err4 != nil {
      print("  ✓ parseAmount(\"0\") correctly rejected")
      passed += 1
    } else {
      print("  ✗ Should reject zero")
      failed += 1
    }

    // CHECK 5: parseAmount negative rejected
    print("5. parseAmount negative rejected...")
    let (pence5, err5) = parseAmount("-10.50")
    if pence5 == nil && err5 != nil {
      print("  ✓ parseAmount(\"-10.50\") correctly rejected")
      passed += 1
    } else {
      print("  ✗ Should reject negative amounts")
      failed += 1
    }

    // CHECK 6: parseAmount exponent rejected
    print("6. parseAmount exponent rejected...")
    let (pence6, err6) = parseAmount("1e3")
    if pence6 == nil && err6 != nil {
      print("  ✓ parseAmount(\"1e3\") correctly rejected")
      passed += 1
    } else {
      print("  ✗ Should reject exponent notation")
      failed += 1
    }

    // CHECK 7: parseAmount too many decimals rejected
    print("7. parseAmount too many decimals...")
    let (pence7, err7) = parseAmount("10.501")
    if pence7 == nil && err7 != nil {
      print("  ✓ parseAmount(\"10.501\") correctly rejected")
      passed += 1
    } else {
      print("  ✗ Should reject more than 2 decimals")
      failed += 1
    }

    // CHECK 8: parseAmount too large rejected
    print("8. parseAmount too large...")
    let (pence8, err8) = parseAmount("10001")
    if pence8 == nil && err8 != nil {
      print("  ✓ parseAmount(\"10001\") correctly rejected")
      passed += 1
    } else {
      print("  ✗ Should reject amounts > 10000")
      failed += 1
    }

    // CHECK 9: parseAmount empty rejected
    print("9. parseAmount empty string...")
    let (pence9, err9) = parseAmount("")
    if pence9 == nil && err9 != nil {
      print("  ✓ parseAmount(\"\") correctly rejected")
      passed += 1
    } else {
      print("  ✗ Should reject empty string")
      failed += 1
    }

    // CHECK 10: parseAmount max valid
    print("10. parseAmount max valid...")
    let (pence10, err10) = parseAmount("10000")
    if pence10 == 1_000_000 && err10 == nil {
      print("  ✓ parseAmount(\"10000\") = 1000000 pence")
      passed += 1
    } else {
      print("  ✗ Expected 1000000 pence, got: \(pence10 ?? 0)")
      failed += 1
    }

    // CHECK 11: money formatting pounds
    print("11. money formatting pounds...")
    let formatted11 = money(1050)
    if formatted11 == "£10.50" {
      print("  ✓ money(1050) = £10.50")
      passed += 1
    } else {
      print("  ✗ Expected £10.50, got: \(formatted11)")
      failed += 1
    }

    // CHECK 12: money formatting pence
    print("12. money formatting pence...")
    let formatted12 = money(100)
    if formatted12 == "£1.00" {
      print("  ✓ money(100) = £1.00")
      passed += 1
    } else {
      print("  ✗ Expected £1.00, got: \(formatted12)")
      failed += 1
    }

    // CHECK 13: BankState JSON decoding
    print("13. BankState JSON decoding...")
    let bankStateJson = """
    {
      "version": 1,
      "balance": 1248050,
      "transactions": [],
      "budgets": []
    }
    """
    do {
      let decoder = JSONDecoder()
      let state = try decoder.decode(
        BankState.self,
        from: bankStateJson.data(using: .utf8)!
      )
      if state.version == 1 && state.balance == 1_248_050 {
        print("  ✓ BankState decoded: v=\(state.version), balance=\(state.balance)")
        passed += 1
      } else {
        print("  ✗ Fields mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ Decoding failed: \(error)")
      failed += 1
    }

    // CHECK 14: PaymentResponse success decoding
    print("14. PaymentResponse success decoding...")
    let paymentJson = """
    {
      "ok": true,
      "error": null,
      "code": null,
      "state": {
        "version": 1,
        "balance": 1000000,
        "transactions": [],
        "budgets": []
      },
      "transaction": null
    }
    """
    do {
      let decoder = JSONDecoder()
      let response = try decoder.decode(
        PaymentResponse.self,
        from: paymentJson.data(using: .utf8)!
      )
      if response.ok && response.error == nil {
        print("  ✓ PaymentResponse success: ok=\(response.ok)")
        passed += 1
      } else {
        print("  ✗ Response fields mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ Decoding failed: \(error)")
      failed += 1
    }

    // CHECK 15: HTTP 202 pending response
    print("15. HTTP 202 pending response...")
    let pendingJson = """
    {
      "ok": false,
      "error": "Payment pending confirmation",
      "code": "PAYMENT_PENDING",
      "state": null,
      "transaction": null
    }
    """
    do {
      let decoder = JSONDecoder()
      let response = try decoder.decode(
        PaymentResponse.self,
        from: pendingJson.data(using: .utf8)!
      )
      if !response.ok && response.code == "PAYMENT_PENDING" {
        print("  ✓ HTTP 202 response decoded: code=\(response.code ?? "nil")")
        passed += 1
      } else {
        print("  ✗ Response fields mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ Decoding failed: \(error)")
      failed += 1
    }

    // CHECK 16: Recipient JSON decoding
    print("16. Recipient JSON decoding...")
    let recipientJson = """
    {
      "id": "alice-001",
      "name": "Alice",
      "initials": "A",
      "detail": "GH Bank",
      "category": "Shopping",
      "color": "#007AFF"
    }
    """
    do {
      let decoder = JSONDecoder()
      let recipient = try decoder.decode(
        Recipient.self,
        from: recipientJson.data(using: .utf8)!
      )
      if recipient.id == "alice-001" && recipient.name == "Alice" {
        print("  ✓ Recipient decoded: id=\(recipient.id), name=\(recipient.name)")
        passed += 1
      } else {
        print("  ✗ Recipient fields mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ Decoding failed: \(error)")
      failed += 1
    }

    // CHECK 17: CatalogResponse JSON decoding
    print("17. CatalogResponse JSON decoding...")
    let catalogJson = """
    {
      "demoDate": "2026-09-18",
      "recipients": [
        {"id": "alice-001", "name": "Alice", "initials": "A", "detail": "GH Bank", "category": "Shopping", "color": "#007AFF"}
      ],
      "providers": [
        {"id": "adyen", "name": "Adyen", "description": "Card processor", "methods": ["card"]}
      ]
    }
    """
    do {
      let decoder = JSONDecoder()
      let catalog = try decoder.decode(
        CatalogResponse.self,
        from: catalogJson.data(using: .utf8)!
      )
      if catalog.demoDate == "2026-09-18" && catalog.recipients.count == 1 {
        print("  ✓ CatalogResponse decoded: recipients=\(catalog.recipients.count), providers=\(catalog.providers.count)")
        passed += 1
      } else {
        print("  ✗ Catalog fields mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ Decoding failed: \(error)")
      failed += 1
    }

    // CHECK 18: MeridianClient initialization
    print("18. MeridianClient initialization...")
    do {
      _ = try MeridianClient(
        baseURL: "http://localhost:8080/api/v1",
        sessionId: "test-session"
      )
      print("  ✓ Client initialized successfully")
      passed += 1
    } catch {
      print("  ✗ Initialization failed: \(error)")
      failed += 1
    }

    // CHECK 19: Client rejects empty session
    print("19. Client rejects empty session...")
    do {
      _ = try MeridianClient(
        baseURL: "http://localhost:8080/api/v1",
        sessionId: ""
      )
      print("  ✗ Should have rejected empty session ID")
      failed += 1
    } catch MeridianError.missingSession {
      print("  ✓ Client correctly rejected empty session ID")
      passed += 1
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 20: Client rejects invalid URL
    print("20. Client rejects invalid URL...")
    do {
      _ = try MeridianClient(
        baseURL: "not a url",
        sessionId: "test-session"
      )
      print("  ✗ Should have rejected invalid URL")
      failed += 1
    } catch MeridianError.invalidURL {
      print("  ✓ Client correctly rejected invalid URL")
      passed += 1
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    await runScaChecks(passed: &passed, failed: &failed)

    // Summary
    let total = passed + failed
    print("\n=== Results ===")
    print("Passed: \(passed)/\(total)")
    print("Failed: \(failed)/\(total)")

    if failed > 0 {
      exit(1)
    }
  }

  static func runScaChecks(passed: inout Int, failed: inout Int) async {
    let tally = CheckTally(passed: passed, failed: failed)
    defer {
      passed = tally.passed
      failed = tally.failed
    }
    func check(_ name: String, _ condition: Bool) { tally.check(name, condition) }

    let now = ISO8601DateFormatter().date(from: "2026-09-29T00:00:00Z")!
    let future = """
    {"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"payload":"ch_abc","expiresAt":"2099-01-01T00:00:00Z","token":"tok_1"}}
    """.data(using: .utf8)!
    let intercept = ScaInterpreter.intercept(statusCode: 202, body: future, now: now)
    if case let .required(challenge) = intercept {
      check("SCA 202 extracts payload, expiry and token", challenge.payload == "ch_abc" && challenge.token == "tok_1" && !challenge.isExpired(at: now))
    } else {
      check("SCA 202 extracts payload, expiry and token", false)
    }

    let pending = """
    {"ok":false,"code":"PAYMENT_PENDING","paymentId":"pay-1"}
    """.data(using: .utf8)!
    check(
      "PAYMENT_PENDING is not an SCA step-up",
      ScaInterpreter.intercept(statusCode: 202, body: pending, now: now) == .notStepUp
    )
    let not202 = """
    {"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"payload":"ch","expiresAt":"2099-01-01T00:00:00Z"}}
    """.data(using: .utf8)!
    check("non-202 SCA body is ignored", ScaInterpreter.intercept(statusCode: 400, body: not202, now: now) == .notStepUp)

    let missing = """
    {"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"expiresAt":"2099-01-01T00:00:00Z"}}
    """.data(using: .utf8)!
    check("incomplete challenge is invalid", ScaInterpreter.intercept(statusCode: 202, body: missing, now: now) == .invalid)

    let expiredBody = """
    {"ok":false,"code":"SCA_STEP_UP_REQUIRED","challengePayload":"ch_old","expiresAt":"2000-01-01T00:00:00Z"}
    """.data(using: .utf8)!
    if case .expired = ScaInterpreter.intercept(statusCode: 202, body: expiredBody, now: now) {
      check("expired challenge is reported", true)
    } else {
      check("expired challenge is reported", false)
    }

    let draft = PaymentDraft(
      recipientId: "northline-studio",
      amountMinor: 4000,
      method: .card,
      note: "Studio",
      scenario: .success,
      idempotencyKey: "same-key"
    )
    guard case let .required(live) = ScaInterpreter.intercept(statusCode: 202, body: future, now: now) else {
      check("step-up session can start", false)
      return
    }
    var session = ScaSession(draft: draft, challenge: live, now: now)
    check("biometric failure keeps the payment and opens passcode", {
      session = session.afterBiometric(.failed, now: now)
      return session.phase == .passcode && session.resubmitToken == nil && session.draft.amountMinor == 4000 && session.draft.method == .card && session.draft.idempotencyKey == "same-key"
    }())
    check("wrong passcode shows the failure copy and keeps the draft", {
      session = session.afterPasscode("000000", now: now)
      return session.message == ScaCopy.failureMessage && session.resubmitToken == nil && session.draft.recipientId == "northline-studio"
    }())
    check("rehearsal passcode releases the original token", {
      session = session.afterPasscode(ScaCopy.rehearsalPasscode, now: now)
      return session.resubmitToken == "tok_1"
    }())
    check("passcode is not the rehearsal value when mistyped", !RehearsalPasscode.matches("135791"))

    let plain = PaymentRequest(recipientId: "northline-studio", amountMinor: 4000, method: .card, note: "Studio", scenario: .success)
    let plainJson = String(data: try! JSONEncoder().encode(plain), encoding: .utf8)!
    check("first payment omits scaChallengeToken and the passcode", !plainJson.contains("scaChallengeToken") && !plainJson.contains(ScaCopy.rehearsalPasscode) && plainJson.contains("\"method\":\"card\""))
    let stepped = PaymentRequest(recipientId: "northline-studio", amountMinor: 4000, method: .bank, note: "Studio", scenario: .success, scaChallengeToken: "tok_1")
    let steppedJson = String(data: try! JSONEncoder().encode(stepped), encoding: .utf8)!
    check("resubmit keeps bank method and adds only the token", steppedJson.contains("\"method\":\"bank\"") && steppedJson.contains("\"scaChallengeToken\":\"tok_1\"") && !steppedJson.contains(ScaCopy.rehearsalPasscode))

    await checkTransport(tally: tally)
  }

  static func checkTransport(tally: CheckTally) async {
    let number = tally.passed + tally.failed + 1
    print("\(number). SCA resubmit keeps session, key and card method...")
    let script = ScaScript()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ScaURLProtocol.self]
    configuration.timeoutIntervalForRequest = 5
    ScaURLProtocol.script = script
    defer { ScaURLProtocol.script = nil }
    do {
      let session = URLSession(configuration: configuration)
      let client = try MeridianClient(baseURL: "http://127.0.0.1:9/api/v1", sessionId: "sca-room", urlSession: session)
      let key = "idem-sca-1"
      let first = try await client.submitPayment(recipientId: "northline-studio", amountMinor: 4000, method: .card, note: "Studio", idempotencyKey: key)
      let intercept = ScaInterpreter.intercept(statusCode: first.statusCode, body: first.body)
      guard case let .required(challenge) = intercept else {
        print("  ✗ expected step-up, got \(first.statusCode) \(first.code ?? "")")
        tally.failed += 1
        return
      }
      var flow = ScaSession(draft: PaymentDraft(recipientId: "northline-studio", amountMinor: 4000, method: .card, note: "Studio", scenario: .success, idempotencyKey: key), challenge: challenge)
      flow = flow.afterBiometric(.unavailable)
      flow = flow.afterPasscode("000000")
      let failedCopy = flow.message == ScaCopy.failureMessage && flow.resubmitToken == nil
      flow = flow.afterPasscode(ScaCopy.rehearsalPasscode)
      let token = flow.resubmitToken
      let second = try await client.submitPayment(recipientId: "northline-studio", amountMinor: 4000, method: .card, note: "Studio", idempotencyKey: key, scaChallengeToken: token)
      let bodies = script.bodies.joined(separator: "\n")
      let ok = first.statusCode == 202 && second.ok && failedCopy && token == "ch_http" && script.keys == [key, key] && script.sessions == ["sca-room", "sca-room"] && !script.bodies[0].contains("scaChallengeToken") && script.bodies[1].contains("\"scaChallengeToken\":\"ch_http\"") && script.bodies[0].contains("\"method\":\"card\"") && script.bodies[1].contains("\"method\":\"card\"") && !bodies.contains(ScaCopy.rehearsalPasscode)
      if ok {
        print("  ✓ SCA resubmit keeps session, key and card method")
        tally.passed += 1
      } else {
        print("  ✗ transport script mismatch keys=\(script.keys) sessions=\(script.sessions) bodies=\(script.bodies)")
        tally.failed += 1
      }
    } catch {
      print("  ✗ transport failed: \(error)")
      tally.failed += 1
    }
  }
}

final class CheckTally {
  var passed: Int
  var failed: Int
  init(passed: Int, failed: Int) {
    self.passed = passed
    self.failed = failed
  }
  func check(_ name: String, _ condition: Bool) {
    let number = passed + failed + 1
    print("\(number). \(name)...")
    if condition {
      print("  ✓ \(name)")
      passed += 1
    } else {
      print("  ✗ \(name)")
      failed += 1
    }
  }
}

final class ScaScript: @unchecked Sendable {
  var bodies: [String] = []
  var keys: [String] = []
  var sessions: [String] = []
}

final class ScaURLProtocol: URLProtocol, @unchecked Sendable {
  static var script: ScaScript?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let script = Self.script
    let body = Self.bodyText(request)
    script?.bodies.append(body)
    script?.keys.append(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "")
    script?.sessions.append(request.value(forHTTPHeaderField: "X-Rehearsal-Session") ?? "")
    let hasToken = body.contains("scaChallengeToken")
    let payload = hasToken
      ? #"{"ok":true,"paymentId":"tx-sca"}"#
      : #"{"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"payload":"ch_http","expiresAt":"2099-01-01T00:00:00Z"}}"#
    let data = Data(payload.utf8)
    let response = HTTPURLResponse(url: request.url!, statusCode: hasToken ? 200 : 202, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}

  private static func bodyText(_ request: URLRequest) -> String {
    if let body = request.httpBody, let text = String(data: body, encoding: .utf8) { return text }
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let count = stream.read(buffer, maxLength: 1024)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return String(data: data, encoding: .utf8) ?? ""
  }
}
