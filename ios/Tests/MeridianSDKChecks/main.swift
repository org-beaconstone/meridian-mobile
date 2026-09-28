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

    func check(_ name: String, _ ok: Bool) {
      print("\(passed + failed + 1). \(name)...")
      if ok {
        print("  ✓ \(name)")
        passed += 1
      } else {
        print("  ✗ \(name)")
        failed += 1
      }
    }

    check("IBAN MOD-97 accepts GB and spaced DE and FR", 
      isValidIban("GB82WEST12345698765432")
        && isValidIban("GB82 WEST 1234 5698 7654 32")
        && isValidIban("de89 3704 0044 0532 0130 00")
        && isValidIban("FR1420041010050500013M02606"))
    check("IBAN MOD-97 rejects bad checksum and shape",
      !isValidIban("GB82WEST12345698765433")
        && !isValidIban("DE89370400440532013001")
        && !isValidIban("")
        && !isValidIban("GB82"))
    let generated = makeIdempotencyKey()
    check("idempotency key is UUID v4", isUuidV4(generated) && !isUuidV4("not-a-uuid") && !isUuidV4("aaaaaaaa-bbbb-1ccc-8ddd-eeeeeeeeeeee"))
    check("retained key is not regenerated", nextIdempotencyKey(current: generated, retain: true) == generated)

    let lockedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let quote = FxQuote(
      quoteId: "q-1",
      sourceAmountMinor: 1000,
      targetAmountMinor: 1170,
      rate: "1.1700",
      serverExpiresAt: nil
    )
    let lock = lockQuote(quote, lockedAt: lockedAt)
    check("quote countdown starts at 60 seconds", lock.remainingSeconds(at: lockedAt) == 60 && !lock.isExpired(at: lockedAt))
    let expiredAt = lockedAt.addingTimeInterval(60)
    check("quote expires at 60 seconds", lock.remainingSeconds(at: expiredAt) == 0 && lock.isExpired(at: expiredAt))
    let sooner = FxQuote(
      quoteId: "q-2",
      sourceAmountMinor: 1000,
      targetAmountMinor: 1170,
      rate: "1.1700",
      serverExpiresAt: lockedAt.addingTimeInterval(15)
    )
    let shortLock = lockQuote(sooner, lockedAt: lockedAt)
    check("server expiry shorter than 60 seconds wins", shortLock.expiresAt == lockedAt.addingTimeInterval(15))

    let fresh = submissionBlockReason(currency: .eur, method: .bank, iban: "GB82WEST12345698765432", quote: lock, amountMinor: 1000, now: lockedAt)
    check("fresh EUR quote can be confirmed", fresh == nil)
    let blocked = submissionBlockReason(currency: .eur, method: .bank, iban: "GB82WEST12345698765432", quote: lock, amountMinor: 1000, now: expiredAt)
    check("expired quote blocks confirmation", blocked == quoteExpiredMessage)
    let badIban = submissionBlockReason(currency: .gbp, method: .bank, iban: "GB82WEST12345698765433", quote: nil, amountMinor: 1000, now: lockedAt)
    check("invalid IBAN blocks submission", badIban == invalidIbanMessage)
    let domestic = submissionBlockReason(currency: .gbp, method: .card, iban: "", quote: nil, amountMinor: 1000, now: lockedAt)
    check("GBP card does not require an IBAN", domestic == nil)

    let quoteJson = """
    {"quoteId":"q-9","amountMinor":2500,"targetAmountMinor":2925,"rate":"1.1700","expiresInSeconds":60}
    """.data(using: .utf8)!
    let decoded = try? JSONDecoder().decode(FxQuote.self, from: quoteJson)
    check("FX quote JSON decodes", decoded?.quoteId == "q-9" && decoded?.sourceAmountMinor == 2500 && decoded?.targetAmountMinor == 2925)

    struct Attempt {
      let key: String
      let method: PaymentMethod
    }
    final class RetryProbe: @unchecked Sendable {
      var attempts: [Attempt] = []
      var delays: [Int] = []
      var calls = 0
    }
    let probe = RetryProbe()
    let paymentKey = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    let retried = try? await submitPaymentWithRetry(
      idempotencyKey: paymentKey,
      method: .bank,
      sleepMilliseconds: { milliseconds in probe.delays.append(milliseconds) }
    ) { attemptKey, attemptMethod in
      probe.calls += 1
      probe.attempts.append(Attempt(key: attemptKey, method: attemptMethod))
      if probe.calls < 3 {
        throw MeridianError.httpError(statusCode: probe.calls == 1 ? 502 : 504, message: "gateway")
      }
      return PaymentResponse(ok: true, state: nil, transaction: nil, error: nil, code: nil, paymentId: "pay-1")
    }
    let sameKey = probe.attempts.allSatisfy { $0.key == paymentKey && $0.method == .bank }
    check(
      "502 and 504 retry the same key and method",
      retried?.ok == true && probe.attempts.count == 3 && sameKey && probe.delays == [200, 400]
    )

    let rejected = RetryProbe()
    do {
      _ = try await submitPaymentWithRetry(
        idempotencyKey: paymentKey,
        method: .card,
        sleepMilliseconds: { _ in rejected.delays.append(1) }
      ) { _, _ in
        rejected.calls += 1
        throw MeridianError.httpError(statusCode: 400, message: "bad request")
      }
      check("HTTP 400 is not retried", false)
    } catch {
      check("HTTP 400 is not retried", rejected.calls == 1 && rejected.delays.isEmpty)
    }

    let unavailable = RetryProbe()
    do {
      _ = try await submitPaymentWithRetry(
        idempotencyKey: paymentKey,
        method: .card,
        sleepMilliseconds: { _ in unavailable.delays.append(1) }
      ) { _, _ in
        unavailable.calls += 1
        throw MeridianError.httpError(statusCode: 503, message: "unavailable")
      }
      check("HTTP 503 does not switch provider or retry", false)
    } catch {
      check("HTTP 503 does not switch provider or retry", unavailable.calls == 1 && unavailable.delays.isEmpty)
    }

    let exhausted = RetryProbe()
    do {
      _ = try await submitPaymentWithRetry(
        idempotencyKey: paymentKey,
        method: .bank,
        sleepMilliseconds: { milliseconds in exhausted.delays.append(milliseconds) }
      ) { _, attemptMethod in
        exhausted.calls += 1
        if attemptMethod != .bank { throw MeridianError.validationError("provider changed") }
        throw MeridianError.httpError(statusCode: 502, message: "gateway")
      }
      check("gateway retries stop after 3 attempts", false)
    } catch let error as MeridianError {
      if case .httpError(let statusCode, _) = error {
        check("gateway retries stop after 3 attempts", statusCode == 502 && exhausted.calls == 3 && exhausted.delays == [200, 400])
      } else {
        check("gateway retries stop after 3 attempts", false)
      }
    } catch {
      check("gateway retries stop after 3 attempts", false)
    }

    check("backoff schedule is exponential", gatewayBackoffMilliseconds(afterFailure: 1) == 200 && gatewayBackoffMilliseconds(afterFailure: 2) == 400 && gatewayBackoffMilliseconds(afterFailure: 3) == 800)

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
