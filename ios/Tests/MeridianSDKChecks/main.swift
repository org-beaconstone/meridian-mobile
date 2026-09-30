import Foundation
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

    let intent = IntentCheckBox()
    await runPaymentIntentChecks(intent)
    passed += intent.passed
    failed += intent.failed

    let total = passed + failed
    print("\n=== Results ===")
    print("Passed: \(passed)/\(total)")
    print("Failed: \(failed)/\(total)")

    if failed > 0 {
      exit(1)
    }
  }
}

final class IntentCheckBox: @unchecked Sendable {
  var passed = 0
  var failed = 0
  func pass(_ name: String) {
    passed += 1
    print("  ✓ \(name)")
  }
  func fail(_ name: String, _ detail: String) {
    failed += 1
    print("  ✗ \(name): \(detail)")
  }
}

private let goldenIntentBody =
  "{\"amountMinor\":2599,\"bank\":\"Adyen\",\"consentAccepted\":true,\"consentSummary\":\"I authorise Meridian to submit this GBP payment to the named recipient. This rehearsal does not move real money or contact Adyen or Worldpay.\",\"currency\":\"GBP\",\"feeMinor\":39,\"localReference\":\"INV-1042\",\"method\":\"card\",\"provider\":\"adyen\",\"quoteExpiresAt\":\"2026-09-18T12:01:00Z\",\"quoteId\":\"quote-fixed\",\"recipientId\":\"northline-studio\",\"recipientName\":\"Northline Studio\"}"

private func goldenAttempt() throws -> PaymentIntentAttempt {
  try preparePaymentIntent(
    recipientId: "northline-studio",
    recipientName: "Northline Studio",
    recipientDetail: "Design tools & materials",
    amountInput: "25.99",
    localReference: "INV-1042",
    method: .card,
    idempotencyKey: "11111111-1111-4111-8111-111111111111",
    quoteId: "quote-fixed",
    quoteExpiresAt: "2026-09-18T12:01:00Z"
  )
}

private func intentResponse(
  ok: Bool,
  status: String,
  intentId: String,
  code: String? = nil,
  error: String? = nil
) -> PaymentIntentResponse {
  PaymentIntentResponse(
    ok: ok,
    status: status,
    intentId: intentId,
    state: nil,
    transaction: nil,
    error: error,
    code: code
  )
}

private func runPaymentIntentChecks(_ box: IntentCheckBox) async {
  print("21. payload hash and review fields...")
  do {
    let attempt = try goldenAttempt()
    if attempt.canonicalBody == goldenIntentBody
      && attempt.payloadHash == "c04ec489e9f4ddb99b509f0e493f2f5cd278b93935d65af809d29d28b4a14ef0"
      && attempt.review.recipientName == "Northline Studio"
      && attempt.review.amountLabel == "£25.99"
      && attempt.review.feeLabel == "£0.39"
      && attempt.review.methodLabel == "Debit card"
      && attempt.review.bank == "Adyen"
      && attempt.review.expiryLabel == "18 Sep 2026, 12:01 UTC"
      && attempt.review.consentSummary == paymentConsentSummary
      && SHA256.hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      && SHA256.hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    {
      box.pass("canonical payload, hash, and localized review")
    } else {
      box.fail("canonical payload", attempt.canonicalBody)
    }
  } catch {
    box.fail("canonical payload", String(describing: error))
  }

  print("22. unique key and hash per attempt...")
  do {
    let first = try preparePaymentIntent(
      recipientId: "northline-studio", recipientName: "Northline Studio", recipientDetail: "",
      amountInput: "10", localReference: "REF-1", method: .card, quoteId: "quote-one",
      quoteExpiresAt: "2026-09-18T12:01:00Z"
    )
    let second = try preparePaymentIntent(
      recipientId: "northline-studio", recipientName: "Northline Studio", recipientDetail: "",
      amountInput: "10", localReference: "REF-1", method: .card, quoteId: "quote-two",
      quoteExpiresAt: "2026-09-18T12:01:00Z"
    )
    let uuid = #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-4[0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}$"#
    if first.idempotencyKey != second.idempotencyKey
      && first.payloadHash != second.payloadHash
      && first.idempotencyKey.range(of: uuid, options: .regularExpression) != nil
      && second.idempotencyKey.range(of: uuid, options: .regularExpression) != nil
    {
      box.pass("distinct idempotency keys and payload hashes")
    } else {
      box.fail("distinct attempts", "\(first.idempotencyKey) \(second.idempotencyKey)")
    }
  } catch {
    box.fail("distinct attempts", String(describing: error))
  }

  print("23. local reference and amount validation...")
  let rejected = ["", "   ", String(repeating: "a", count: 201), "line\nbreak"]
  var validationOK = true
  for sample in rejected {
    do {
      _ = try preparePaymentIntent(
        recipientId: "northline-studio", recipientName: "Northline Studio", recipientDetail: "",
        amountInput: "10", localReference: sample, method: .bank
      )
      validationOK = false
    } catch is MeridianError {
      continue
    } catch {
      validationOK = false
    }
  }
  do {
    _ = try preparePaymentIntent(
      recipientId: "northline-studio", recipientName: "Northline Studio", recipientDetail: "",
      amountInput: "10.501", localReference: "REF-1", method: .card
    )
    validationOK = false
  } catch is MeridianError {
  } catch { validationOK = false }
  let bank = try? preparePaymentIntent(
    recipientId: "northline-studio", recipientName: "Cafe\u{0301}", recipientDetail: "Cafe",
    amountInput: "8", localReference: "  REF-8  ", method: .bank,
    idempotencyKey: "bank-key", quoteId: "quote-bank", quoteExpiresAt: "2026-09-18T12:02:00Z"
  )
  if validationOK && bank?.review.bank == "Worldpay" && bank?.review.feeMinor == 0
    && bank?.review.localReference == "REF-8" && bank?.review.recipientName == "Caf\u{00e9}"
    && resolvePaymentIntentsURL("http://10.0.2.2:8080/api/v1/") == "http://10.0.2.2:8080/api/v2/payment-intents"
  {
    box.pass("reference, amount, bank rail, and v2 URL")
  } else {
    box.fail("validation", "ok=\(validationOK) bank=\(bank?.review.bank ?? "nil")")
  }

  print("24. classify success, decline, and action required...")
  let success = classifyPaymentIntent(statusCode: 200, ok: true, status: "succeeded", code: nil)
  let declined = classifyPaymentIntent(statusCode: 422, ok: false, status: "declined", code: "DECLINED")
  let action = classifyPaymentIntent(statusCode: 202, ok: false, status: "action-required", code: "ACTION_REQUIRED")
  let retry = classifyPaymentIntent(statusCode: 503, ok: false, status: nil, code: "UNAVAILABLE")
  if success == .succeeded && declined == .declined && action == .actionRequired && retry == .retrySameIntent {
    box.pass("intent dispositions")
  } else {
    box.fail("intent dispositions", "\(success) \(declined) \(action) \(retry)")
  }

  print("25. rapid tap and terminal responses do not recreate the intent...")
  do {
    let attempt = try goldenAttempt()
    let hits = IntentHitCounter()
    let now = Date(timeIntervalSince1970: 0)
    async let first: PaymentIntentSubmission = attempt.submit(now: now, consentAccepted: true) { _, key, hash in
      await hits.record(key: key, hash: hash)
      try await Task.sleep(nanoseconds: 150_000_000)
      return (200, intentResponse(ok: true, status: "succeeded", intentId: "pi_ok"))
    }
    var inFlight = false
    for _ in 0..<50 {
      if await hits.count > 0 {
        inFlight = true
        break
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    if !inFlight { box.fail("duplicate tap", "first submit did not start"); return }
    do {
      _ = try await attempt.submit(now: now, consentAccepted: true) { _, key, hash in
        await hits.record(key: key, hash: hash)
        return (200, intentResponse(ok: true, status: "succeeded", intentId: "pi_new"))
      }
      box.fail("duplicate tap", "second submit was accepted")
    } catch MeridianError.duplicateSubmission {
      let submission = try await first
      let repeated = try await attempt.submit(now: Date(), consentAccepted: true) { _, key, hash in
        await hits.record(key: key, hash: hash)
        return (200, intentResponse(ok: true, status: "succeeded", intentId: "pi_new"))
      }
      let count = await hits.count
      if submission.intentId == "pi_ok" && repeated.intentId == "pi_ok" && count == 1
        && submission.message.contains("not submitted again")
      {
        box.pass("duplicate tap reuses the succeeded intent")
      } else {
        box.fail("duplicate tap", "id=\(repeated.intentId ?? "nil") hits=\(count)")
      }
    }
  } catch {
    box.fail("duplicate tap", String(describing: error))
  }

  print("26. decline and action required stay on the same intent...")
  do {
    let declinedAttempt = try goldenAttempt()
    let actionAttempt = try goldenAttempt()
    let declinedHits = IntentHitCounter()
    let actionHits = IntentHitCounter()
    let now = Date(timeIntervalSince1970: 0)
    let declinedResult = try await declinedAttempt.submit(now: now, consentAccepted: true) { _, _, _ in
      await declinedHits.record(key: "d", hash: "d")
      return (422, intentResponse(ok: false, status: "declined", intentId: "pi_decline", code: "DECLINED", error: "The payment was declined"))
    }
    let declinedAgain = try await declinedAttempt.submit(now: now, consentAccepted: true) { _, _, _ in
      await declinedHits.record(key: "d2", hash: "d2")
      return (422, intentResponse(ok: false, status: "declined", intentId: "pi_other"))
    }
    let actionResult = try await actionAttempt.submit(now: now, consentAccepted: true) { _, _, _ in
      await actionHits.record(key: "a", hash: "a")
      return (202, intentResponse(ok: false, status: "action_required", intentId: "pi_action", code: "ACTION_REQUIRED", error: "Additional customer action is required"))
    }
    let actionAgain = try await actionAttempt.submit(now: now, consentAccepted: true) { _, _, _ in
      await actionHits.record(key: "a2", hash: "a2")
      return (200, intentResponse(ok: true, status: "succeeded", intentId: "pi_other"))
    }
    let declinedCount = await declinedHits.count
    let actionCount = await actionHits.count
    if declinedResult.disposition == .declined && declinedAgain.intentId == "pi_decline"
      && declinedCount == 1 && declinedResult.message.contains("stays closed")
      && actionResult.disposition == .actionRequired && actionAgain.intentId == "pi_action"
      && actionCount == 1 && actionResult.message.contains("not recreated")
    {
      box.pass("decline and action required do not recreate intents")
    } else {
      box.fail("terminal outcomes", "decline=\(declinedAgain.intentId ?? "nil") action=\(actionAgain.intentId ?? "nil")")
    }
  } catch {
    box.fail("terminal outcomes", String(describing: error))
  }

  print("27. uncertain failure retries the same key without switching rail...")
  do {
    let attempt = try preparePaymentIntent(
      recipientId: "northline-studio", recipientName: "Northline Studio", recipientDetail: "",
      amountInput: "12", localReference: "REF-12", method: .bank,
      idempotencyKey: "bank-retry-key", quoteId: "quote-bank-retry",
      quoteExpiresAt: "2026-09-18T12:05:00Z"
    )
    let hits = IntentHitCounter()
    let now = Date(timeIntervalSince1970: 0)
    do {
      _ = try await attempt.submit(now: now, consentAccepted: false) { _, _, _ in
        await hits.record(key: "no", hash: "no")
        return (200, intentResponse(ok: true, status: "succeeded", intentId: "no"))
      }
      box.fail("consent", "submitted without consent")
    } catch MeridianError.validationError {
      let expiredNow = Date(timeIntervalSince1970: 1_893_456_000)
      do {
        _ = try await attempt.submit(now: expiredNow, consentAccepted: true) { _, _, _ in
          await hits.record(key: "expired", hash: "expired")
          return (200, intentResponse(ok: true, status: "succeeded", intentId: "expired"))
        }
        box.fail("expiry", "submitted an expired quote")
      } catch MeridianError.quoteExpired {
        do {
          _ = try await attempt.submit(now: now, consentAccepted: true) { _, key, hash in
            await hits.record(key: key, hash: hash)
            throw MeridianError.httpError(statusCode: 504, message: "gateway timeout")
          }
        } catch is MeridianError {}
        let retried = try await attempt.submit(now: expiredNow, consentAccepted: true) { body, key, hash in
          await hits.record(key: key, hash: hash)
          if !body.contains("\"provider\":\"worldpay\"") || !body.contains("\"method\":\"bank\"") {
            throw MeridianError.validationError("rail changed")
          }
          return (200, intentResponse(ok: true, status: "succeeded", intentId: "pi_bank"))
        }
        let count = await hits.count
        if retried.intentId == "pi_bank" && retried.idempotencyKey == "bank-retry-key" && count == 2 {
          box.pass("uncertain retry keeps the Worldpay bank intent")
        } else {
          box.fail("uncertain retry", "hits=\(count) id=\(retried.intentId ?? "nil")")
        }
      }
    }
  } catch {
    box.fail("uncertain retry", String(describing: error))
  }
}

private actor IntentHitCounter {
  var count = 0
  func record(key: String, hash: String) {
    count += 1
    _ = key
    _ = hash
  }
}
