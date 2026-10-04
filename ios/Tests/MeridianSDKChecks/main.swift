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

    let extra = runPaymentInputChecks()
    passed += extra.passed
    failed += extra.failed

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

private struct CheckTally {
  var passed = 0
  var failed = 0
}

private func runPaymentInputChecks() -> CheckTally {
  var tally = CheckTally()

  func check(_ name: String, _ ok: Bool) {
    if ok {
      print("  ✓ \(name)")
      tally.passed += 1
    } else {
      print("  ✗ \(name)")
      tally.failed += 1
    }
  }

  print("21. amount bounds and spoken label...")
  let lower = evaluateAmount("0.01")
  check("£0.01 is 1 pence", lower.isValid && lower.minorUnits == 1 && lower.prefix == "£")
  check("0.01 is spoken as 0 pounds and 1 penny", lower.spoken == "0 pounds and 1 penny")
  let typical = evaluateAmount("£10.50")
  check("£10.50 is 1050 pence", typical.minorUnits == 1050 && typical.spoken == "10 pounds and 50 pence")
  check("1 pound is singular", evaluateAmount("1").spoken == "1 pound and 0 pence")
  check("1 penny is singular", amountSpokenLabel(101) == "1 pound and 1 penny")
  check("grouped thousands parse", evaluateAmount("1,000.50").minorUnits == 100_050)
  check("zero is below the lower bound", evaluateAmount("0.00").helper == "Amount must be at least £0.01")
  check("upper bound is £10,000.00", evaluateAmount("10000.01").helper == "Amount cannot exceed £10,000.00")
  check("comma decimal is rejected", evaluateAmount("10,50").helper == "Use a decimal point for pence, for example 10.50")
  check("maximum amount is valid", evaluateAmount("10000.00").minorUnits == 1_000_000)
  check("empty amount is not valid", !evaluateAmount("").isValid && evaluateAmount("").spoken == "No amount entered")

  print("22. IBAN MOD-97 and format errors...")
  let spaced = validateIban("gb82 west 1234 5698 7654 32")
  check("spaced GB IBAN is valid", spaced.isValid && spaced.normalized == "GB82WEST12345698765432")
  check("hyphenated DE IBAN is valid", validateIban("DE89-3704-0044-0532-0130-00").isValid)
  check("French IBAN is valid", validateIban("FR14 2004 1010 0505 0001 3M02 606").isValid)
  check("Dutch IBAN is valid", validateIban("NL91ABNA0417164300").isValid)
  check("Norwegian IBAN is valid", validateIban("NO9386011117947").isValid)
  check("IBAN groups wrap every four characters", formatIbanGroups("DE89370400440532013000") == "DE89 3704 0044 0532 0130 00")
  check(
    "bad checksum is described",
    validateIban("GB82WEST12345698765433").helper == "IBAN checksum is invalid. Check the account number and try again"
  )
  check(
    "short IBAN explains the missing characters",
    validateIban("DE89 3704").helper == "IBANs for Germany are 22 characters. Enter 14 more characters"
  )
  check(
    "long IBAN explains the country length",
    validateIban("DE893704004405320130000").helper == "IBANs for Germany are 22 characters"
  )
  check("empty IBAN asks for input", validateIban("  ").helper == "Enter the recipient IBAN")
  check(
    "punctuation is rejected",
    validateIban("DE89 3704 0044 0532 0130 0!").helper == "IBAN can contain only letters and numbers"
  )
  check(
    "non-European country is rejected",
    validateIban("US64SVBKUS6S3300958879").helper == "Enter a European IBAN. US is not a supported country code"
  )
  check(
    "check digits must be numbers",
    validateIban("DEAB370400440532013000").helper == "The two characters after the country code must be digits"
  )

  print("23. draft survives transitions and failures...")
  let draft = PaymentEntry(
    amount: "10.50",
    iban: "DE89370400440532013000",
    reference: "Rent",
    recipientId: "northline-studio",
    method: "bank",
    idempotencyKey: "key-1",
    reviewing: false
  )
  check("valid bank draft can be reviewed", paymentReviewError(draft) == nil)
  check("bank draft requires an IBAN", paymentReviewError(PaymentEntry(amount: "10.50", method: "bank")) == "Enter the recipient IBAN")
  check("card draft does not require an IBAN", paymentReviewError(PaymentEntry(amount: "10.50", method: "card")) == nil)
  let reviewing = reducePaymentEntry(draft, .review(newKey: "key-2"))
  check("review keeps the amount and IBAN", reviewing.amount == "10.50" && reviewing.iban == draft.iban && reviewing.reviewing && reviewing.idempotencyKey == "key-2")
  let editing = reducePaymentEntry(reviewing, .edit(newKey: "key-3"))
  check("edit keeps the amount and IBAN", editing.amount == "10.50" && editing.iban == draft.iban && !editing.reviewing)
  check("network failure keeps the draft and key", reducePaymentEntry(reviewing, .networkFailure) == reviewing)
  check("pending keeps the draft and key", reducePaymentEntry(reviewing, .pending) == reviewing)
  let done = reducePaymentEntry(reviewing, .completed(newKey: "key-5"))
  check(
    "completion clears the inputs and keeps the recipient",
    done.amount.isEmpty && done.iban.isEmpty && done.reference.isEmpty && done.recipientId == "northline-studio" && done.idempotencyKey == "key-5"
  )
  return tally
}
