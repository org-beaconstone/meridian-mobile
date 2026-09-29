import Foundation
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

    let future = "2099-01-01T00:00:00Z"
    let past = "2000-01-01T00:00:00Z"
    let now = ISO8601DateFormatter().date(from: "2026-09-29T00:00:00Z")!

    // CHECK 21: HTTP 202 SCA extracts payload and expiry
    print("21. SCA 202 challenge extraction...")
    let scaJson = """
    {"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"payload":"ch_abc","expiresAt":"\(future)","token":"tok_1"}}
    """.data(using: .utf8)!
    if case .required(let challenge) = ScaInterpreter.intercept(statusCode: 202, body: scaJson, now: now),
      challenge.payload == "ch_abc",
      challenge.resubmitToken == "tok_1",
      challenge.expiresAt == ISO8601DateFormatter().date(from: future) {
      print("  ✓ payload and token extracted")
      passed += 1
    } else {
      print("  ✗ SCA challenge was not extracted")
      failed += 1
    }

    // CHECK 22: pending 202 is not SCA
    print("22. PAYMENT_PENDING is not SCA...")
    let pendingBody = """
    {"ok":false,"code":"PAYMENT_PENDING","error":"Payment pending confirmation","paymentId":"pay-1"}
    """.data(using: .utf8)!
    if case .notStepUp = ScaInterpreter.intercept(statusCode: 202, body: pendingBody, now: now) {
      print("  ✓ pending response left unchanged")
      passed += 1
    } else {
      print("  ✗ pending was treated as SCA")
      failed += 1
    }

    // CHECK 23: non-202 is not a step-up
    print("23. non-202 SCA code is ignored...")
    if case .notStepUp = ScaInterpreter.intercept(statusCode: 400, body: scaJson, now: now) {
      print("  ✓ status other than 202 is not a step-up")
      passed += 1
    } else {
      print("  ✗ non-202 was treated as SCA")
      failed += 1
    }

    // CHECK 24: missing payload is invalid
    print("24. SCA without payload...")
    let missingPayload = """
    {"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"expiresAt":"\(future)"}}
    """.data(using: .utf8)!
    if case .invalid = ScaInterpreter.intercept(statusCode: 202, body: missingPayload, now: now) {
      print("  ✓ incomplete challenge rejected")
      passed += 1
    } else {
      print("  ✗ incomplete challenge was accepted")
      failed += 1
    }

    // CHECK 25: expired challenge
    print("25. expired SCA challenge...")
    let expiredBody = """
    {"ok":false,"code":"SCA_STEP_UP_REQUIRED","challengePayload":"ch_old","expiresAt":"\(past)"}
    """.data(using: .utf8)!
    if case .expired = ScaInterpreter.intercept(statusCode: 202, body: expiredBody, now: now) {
      print("  ✓ expired challenge detected")
      passed += 1
    } else {
      print("  ✗ expired challenge was not detected")
      failed += 1
    }

    let draft = PaymentDraft(
      recipientId: "northline-studio",
      amountMinor: 4500,
      method: .card,
      note: "Studio",
      scenario: .success,
      idempotencyKey: "idem-sca-1"
    )
    let liveChallenge = ScaChallenge(
      payload: "ch_live",
      expiresAt: ISO8601DateFormatter().date(from: future)!,
      token: nil
    )

    // CHECK 26: biometric failure keeps the draft and opens passcode
    print("26. biometric fallback keeps payment draft...")
    var fallback = ScaSession(draft: draft, challenge: liveChallenge, now: now)
    fallback.completeBiometric(.unavailable, now: now)
    if fallback.showsPasscode,
      fallback.draft.idempotencyKey == "idem-sca-1",
      fallback.draft.amountMinor == 4500,
      fallback.draft.recipientId == "northline-studio",
      fallback.draft.method == .card {
      print("  ✓ passcode fallback retained recipient, amount, method and key")
      passed += 1
    } else {
      print("  ✗ biometric fallback changed the draft")
      failed += 1
    }

    // CHECK 27: wrong passcode shows the required message and keeps the draft
    print("27. failed passcode message...")
    fallback.submitPasscode("000000", now: now)
    if case .failed(let message) = fallback.phase,
      message == "Authentication challenge failed. Please verify with your passcode.",
      fallback.draft.amountMinor == 4500,
      fallback.draft.recipientId == "northline-studio" {
      print("  ✓ failure copy retained recipient and amount")
      passed += 1
    } else {
      print("  ✗ passcode failure did not keep the draft")
      failed += 1
    }

    // CHECK 28: successful passcode resubmits the original key and token
    print("28. passcode success resubmits original key...")
    var verified = ScaSession(draft: draft, challenge: liveChallenge, now: now)
    verified.completeBiometric(.failed, now: now)
    verified.submitPasscode(ScaCopy.rehearsalPasscode, now: now)
    if case .readyToResubmit(let token) = verified.phase,
      token == "ch_live",
      verified.draft.idempotencyKey == draft.idempotencyKey,
      verified.draft.method == .card {
      print("  ✓ scaChallengeToken uses the challenge payload and the original key")
      passed += 1
    } else {
      print("  ✗ verified passcode did not produce a resubmit token")
      failed += 1
    }

    // CHECK 29: biometric success skips passcode
    print("29. biometric success...")
    var biometric = ScaSession(
      draft: PaymentDraft(
        recipientId: draft.recipientId,
        amountMinor: draft.amountMinor,
        method: .bank,
        note: draft.note,
        scenario: draft.scenario,
        idempotencyKey: draft.idempotencyKey
      ),
      challenge: liveChallenge,
      now: now
    )
    biometric.completeBiometric(.success, now: now)
    if case .readyToResubmit(let token) = biometric.phase,
      token == "ch_live",
      !biometric.showsPasscode,
      biometric.draft.method == .bank {
      print("  ✓ biometric success is ready to resubmit on the original bank method")
      passed += 1
    } else {
      print("  ✗ biometric success did not resubmit")
      failed += 1
    }

    // CHECK 30: payment JSON omits a nil SCA token
    print("30. payment body omits empty SCA token...")
    let plain = PaymentRequest(recipientId: "northline-studio", amountMinor: 4500, method: .card, note: "", scenario: .success)
    let plainJson = String(data: (try? JSONEncoder().encode(plain)) ?? Data(), encoding: .utf8) ?? ""
    if !plainJson.contains("scaChallengeToken") && plainJson.contains("\"method\":\"card\"") {
      print("  ✓ first submit stays on card without scaChallengeToken")
      passed += 1
    } else {
      print("  ✗ unexpected payment JSON: \(plainJson)")
      failed += 1
    }

    // CHECK 31: payment JSON includes the token for the same method
    print("31. payment body includes SCA token...")
    let stepped = PaymentRequest(
      recipientId: "northline-studio",
      amountMinor: 4500,
      method: .card,
      note: "",
      scenario: .success,
      scaChallengeToken: "ch_live"
    )
    let steppedJson = String(data: (try? JSONEncoder().encode(stepped)) ?? Data(), encoding: .utf8) ?? ""
    if steppedJson.contains("\"scaChallengeToken\":\"ch_live\"") && steppedJson.contains("\"method\":\"card\"") {
      print("  ✓ resubmit keeps card and includes scaChallengeToken")
      passed += 1
    } else {
      print("  ✗ resubmit JSON missing token: \(steppedJson)")
      failed += 1
    }

    // Summary
    let total = passed + failed
    print("\n=== Results ===")
    print("Passed: \(passed)/\(total)")
    print("Failed: \(failed)/\(total)")

    if failed > 0 {
      exit(1)
    }
  }
}
