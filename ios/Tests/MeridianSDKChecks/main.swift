import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MeridianSDK

@main
struct MeridianSDKChecks {
  static func main() {
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

    // CHECK 21: first payment body omits the challenge token
    print("21. Payment body omits SCA token until verified...")
    do {
      let encoder = JSONEncoder()
      let firstPayment = PaymentRequest(
        recipientId: "northline-studio",
        amountMinor: 4500,
        method: .card,
        note: "Studio materials",
        scenario: .success
      )
      let secondPayment = PaymentRequest(
        recipientId: "northline-studio",
        amountMinor: 4500,
        method: .card,
        note: "Studio materials",
        scenario: .success,
        scaChallengeToken: "token-eu"
      )
      let firstData = try encoder.encode(firstPayment)
      let secondData = try encoder.encode(secondPayment)
      let firstJSON = try JSONSerialization.jsonObject(with: firstData) as? [String: Any]
      let secondJSON = try JSONSerialization.jsonObject(with: secondData) as? [String: Any]
      let secondText = String(data: secondData, encoding: .utf8) ?? ""
      if firstJSON?["scaChallengeToken"] == nil,
        secondJSON?["scaChallengeToken"] as? String == "token-eu",
        firstJSON?["method"] as? String == "card",
        secondJSON?["method"] as? String == "card",
        !secondText.contains("135790") {
        print("  ✓ Token is omitted, then sent on the original card payment")
        passed += 1
      } else {
        print("  ✗ Payment encoding did not keep the token off the first body")
        failed += 1
      }
    } catch {
      print("  ✗ Payment encoding failed: \(error)")
      failed += 1
    }

    // CHECK 22: HTTP 202 step-up extraction
    print("22. HTTP 202 SCA_STEP_UP_REQUIRED extraction...")
    let stepUp = """
    {"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"payload":"payload-eu","expiresAt":"2099-06-01T12:00:00Z","scaChallengeToken":"token-eu"}}
    """.data(using: .utf8)!
    let pending = """
    {"ok":false,"code":"PAYMENT_PENDING","paymentId":"pay-1","error":"Payment pending confirmation"}
    """.data(using: .utf8)!
    let missing = """
    {"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"payload":"only"}}
    """.data(using: .utf8)!
    let expiredBody = """
    {"code":"SCA_STEP_UP_REQUIRED","challengePayload":"payload-eu","expirationTimestamp":"2000-01-01T00:00:00Z","scaChallengeToken":"token-eu"}
    """.data(using: .utf8)!
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let extracted = ScaInterpreter.intercept(statusCode: 202, body: stepUp, now: now)
    let expiredIntercept = ScaInterpreter.intercept(statusCode: 202, body: expiredBody, now: now)
    let expiredMatches: Bool
    if case .expired = expiredIntercept { expiredMatches = true } else { expiredMatches = false }
    if case .required(let challenge) = extracted,
      challenge.payload == "payload-eu",
      challenge.token == "token-eu",
      ScaInterpreter.intercept(statusCode: 202, body: pending, now: now) == .notStepUp,
      ScaInterpreter.intercept(statusCode: 200, body: stepUp, now: now) == .notStepUp,
      ScaInterpreter.intercept(statusCode: 202, body: missing, now: now) == .invalid,
      expiredMatches {
      print("  ✓ Step-up payload and expiry extracted; pending stays separate")
      passed += 1
    } else {
      print("  ✗ Step-up intercept mismatch")
      failed += 1
    }

    // CHECK 23: biometric failure keeps the draft and passcode stays local
    print("23. Biometric fallback and passcode resubmit...")
    let draft = PaymentDraft(
      recipientId: "northline-studio",
      amountMinor: 4500,
      method: .card,
      note: "Studio materials",
      scenario: .success,
      idempotencyKey: "idem-sca-1"
    )
    let challenge = ScaChallenge(
      payload: "payload-eu",
      expiresAt: Date(timeIntervalSince1970: 4_102_444_800),
      token: "token-eu"
    )
    var session = ScaSession(draft: draft, challenge: challenge, now: Date(timeIntervalSince1970: 0))
    session.completeBiometric(.failed, now: Date(timeIntervalSince1970: 0))
    let afterFailure = session
    session.submitPasscode("111111", now: Date(timeIntervalSince1970: 0))
    let wrong = session
    session.submitPasscode(ScaCopy.rehearsalPasscode, now: Date(timeIntervalSince1970: 0))
    let verified = session.resubmit()
    var expired = ScaSession(draft: draft, challenge: challenge, now: Date(timeIntervalSince1970: 0))
    expired.completeBiometric(.unavailable, now: Date(timeIntervalSince1970: 0))
    expired.submitPasscode(ScaCopy.rehearsalPasscode, now: challenge.expiresAt)
    if afterFailure.phase == .passcode,
      afterFailure.draft == draft,
      wrong.message == ScaCopy.failureMessage,
      wrong.draft.recipientId == "northline-studio",
      wrong.draft.amountMinor == 4500,
      wrong.resubmit() == nil,
      verified?.scaChallengeToken == "token-eu",
      verified?.idempotencyKey == "idem-sca-1",
      verified?.method == .card,
      expired.message == ScaCopy.failureMessage,
      expired.draft.amountMinor == 4500,
      ScaCopy.biometricPrompt == "Confirm with Face ID / Fingerprint to authorize European payment",
      ScaCopy.failureMessage == "Authentication challenge failed. Please verify with your passcode." {
      print("  ✓ Fallback keeps recipient, amount and key; token follows verification")
      passed += 1
    } else {
      print("  ✗ Challenge session did not keep the payment draft")
      failed += 1
    }

    // CHECK 24: client keeps status 202 and replays the original key with the token
    print("24. Client intercepts step-up and resubmits the original key...")
    let outcome = awaitPaymentRoundTrip()
    if outcome.passed {
      print("  ✓ \(outcome.detail)")
      passed += 1
    } else {
      print("  ✗ \(outcome.detail)")
      failed += 1
    }

    // Summary
    print("\n=== Results ===")
    print("Passed: \(passed)/\(passed + failed)")
    print("Failed: \(failed)/\(passed + failed)")

    if failed > 0 {
      exit(1)
    }
  }
}

private struct RoundTrip {
  let passed: Bool
  let detail: String
}

private func awaitPaymentRoundTrip() -> RoundTrip {
  final class Box: @unchecked Sendable {
    var result = RoundTrip(passed: false, detail: "Timed out")
  }
  ScriptedURLProtocol.gate.lock()
  ScriptedURLProtocol.steps = [
    ScriptedURLProtocol.Step(
      status: 202,
      body: Data("""
      {"code":"SCA_STEP_UP_REQUIRED","challenge":{"payload":"payload-eu","expiresAt":"2099-06-01T12:00:00Z","scaChallengeToken":"token-eu"}}
      """.utf8)
    ),
    ScriptedURLProtocol.Step(
      status: 200,
      body: Data("{\"ok\":true,\"paymentId\":\"pay-sca\"}".utf8)
    ),
  ]
  ScriptedURLProtocol.seen = []
  ScriptedURLProtocol.gate.unlock()
  let box = Box()
  let done = DispatchSemaphore(value: 0)
  Task {
    box.result = await paymentRoundTrip()
    done.signal()
  }
  _ = done.wait(timeout: .now() + 10)
  return box.result
}

private final class ScriptedURLProtocol: URLProtocol, @unchecked Sendable {
    struct Step { let status: Int; let body: Data }
    static let gate = NSLock()
    static var steps: [Step] = []
    static var seen: [(session: String?, key: String?, body: String)] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      let step: Step? = {
        Self.gate.lock()
        defer { Self.gate.unlock() }
        Self.seen.append((
          request.value(forHTTPHeaderField: "X-Rehearsal-Session"),
          request.value(forHTTPHeaderField: "Idempotency-Key"),
          Self.payload(request)
        ))
        guard !Self.steps.isEmpty else { return nil }
        return Self.steps.removeFirst()
      }()
      guard let step, let url = request.url,
        let response = HTTPURLResponse(url: url, statusCode: step.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])
      else {
        client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        return
      }
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: step.body)
      client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func payload(_ request: URLRequest) -> String {
      if let body = request.httpBody, !body.isEmpty {
        return String(data: body, encoding: .utf8) ?? ""
      }
      guard let stream = request.httpBodyStream else { return "" }
      stream.open()
      defer { stream.close() }
      var data = Data()
      let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
      defer { buffer.deallocate() }
      while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: 4096)
        if count <= 0 { break }
        data.append(buffer, count: count)
      }
      return String(data: data, encoding: .utf8) ?? ""
    }
  }

private func paymentRoundTrip() async -> RoundTrip {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [ScriptedURLProtocol.self]
  let session = URLSession(configuration: configuration)
  do {
    let client = try MeridianClient(
      baseURL: "http://127.0.0.1:9/api/v1",
      sessionId: "sca-room",
      urlSession: session
    )
    let key = "idem-sca-1"
    let first = try await client.submitPayment(
      recipientId: "northline-studio",
      amountMinor: 4500,
      method: .card,
      note: "Studio materials",
      idempotencyKey: key
    )
    guard first.statusCode == 202, first.code == ScaCopy.stepUpCode else {
      return RoundTrip(passed: false, detail: "Expected HTTP 202 step-up, got \(first.statusCode) \(first.code ?? "")")
    }
    guard case .required(let challenge) = ScaInterpreter.intercept(statusCode: first.statusCode, body: first.body, now: Date(timeIntervalSince1970: 0)) else {
      return RoundTrip(passed: false, detail: "Challenge payload was not extracted")
    }
    let draft = PaymentDraft(
      recipientId: "northline-studio",
      amountMinor: 4500,
      method: .card,
      note: "Studio materials",
      scenario: .success,
      idempotencyKey: key
    )
    var sca = ScaSession(draft: draft, challenge: challenge, now: Date(timeIntervalSince1970: 0))
    sca.completeBiometric(.cancelled, now: Date(timeIntervalSince1970: 0))
    sca.submitPasscode(ScaCopy.rehearsalPasscode, now: Date(timeIntervalSince1970: 0))
    guard let retry = sca.resubmit() else {
      return RoundTrip(passed: false, detail: "Verified session did not produce a resubmit")
    }
    let second = try await client.submitPayment(
      recipientId: retry.recipientId,
      amountMinor: retry.amountMinor,
      method: retry.method,
      note: retry.note,
      scenario: retry.scenario,
      idempotencyKey: retry.idempotencyKey,
      scaChallengeToken: retry.scaChallengeToken
    )
    guard second.ok else {
      return RoundTrip(passed: false, detail: "Resubmit was not accepted")
    }
    let seen = ScriptedURLProtocol.seen
    guard seen.count == 2,
      seen.allSatisfy({ $0.session == "sca-room" && $0.key == key }),
      !seen[0].body.contains("scaChallengeToken"),
      !seen[0].body.contains(ScaCopy.rehearsalPasscode),
      seen[1].body.contains("\"scaChallengeToken\":\"token-eu\""),
      seen[1].body.contains("\"method\":\"card\""),
      !seen[1].body.contains(ScaCopy.rehearsalPasscode)
    else {
      return RoundTrip(passed: false, detail: "Headers or body were not retained: \(seen)")
    }
    return RoundTrip(passed: true, detail: "Original room and idempotency key carried the challenge token")
  } catch {
    return RoundTrip(passed: false, detail: "Transport failed: \(error)")
  }
}
