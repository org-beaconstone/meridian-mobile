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

    func check(_ name: String, _ condition: Bool) {
      if condition {
        print("  ✓ \(name)")
        passed += 1
      } else {
        print("  ✗ \(name)")
        failed += 1
      }
    }

    let payloadHash = businessPayloadHash(
      customerAccountId: "acct-1",
      recipientId: "northline-studio",
      amountMinor: 2599,
      method: .card,
      note: "lunch"
    )
    print("21. business payload hash...")
    check(
      "canonical business payload hash",
      payloadHash == "f7005a22f7deb113825ad2d2ec98e98abbd62f06fde119402dd062575bd863a6"
    )
    let escapedHash = businessPayloadHash(
      customerAccountId: "acct-1",
      recipientId: "northline-studio",
      amountMinor: 100,
      method: .bank,
      note: "say \"hi\""
    )
    check(
      "escaped note changes the hash",
      escapedHash == "311d46ff743ceab3f78257a3b6313cf311f234079de3c0c32845de6266d978ef"
        && escapedHash != businessPayloadHash(
          customerAccountId: "acct-1",
          recipientId: "northline-studio",
          amountMinor: 101,
          method: .bank,
          note: "say \"hi\""
        )
    )

    let settledState = PaymentReturnState(
      ok: true,
      paymentId: "pay-1",
      code: nil,
      error: nil,
      stateVersion: 4,
      balancePence: 1_245_451
    )
    print("22. return state hash...")
    check(
      "settled return state hash",
      returnStateHash(settledState) == "b5249909bae8e7dd177a9d782f43300fb7e0ce1da42a696d0f5770227d68bb44"
    )
    let pendingState = PaymentReturnState(
      ok: false,
      paymentId: "pay-9",
      code: "PAYMENT_PENDING",
      error: "Awaiting confirmation",
      stateVersion: nil,
      balancePence: nil
    )
    check(
      "pending return state hash",
      returnStateHash(pendingState) == "a5ea41d10b6f195c073b33f96c57bb76cfee49de91d4a38c5220bd4ecb85197b"
    )

    print("23. status mapping...")
    check("ok response is succeeded", paymentIntentStatus(for: PaymentResponse(ok: true, state: nil, transaction: nil, error: nil, code: nil, paymentId: "pay-1")) == .succeeded)
    check("pending code stays active", paymentIntentStatus(for: PaymentResponse(ok: false, state: nil, transaction: nil, error: "Awaiting confirmation", code: "PAYMENT_PENDING", paymentId: "pay-9")) == .pending)
    check("declined code is terminal", paymentIntentStatus(for: PaymentResponse(ok: false, state: nil, transaction: nil, error: "Declined", code: "PAYMENT_DECLINED", paymentId: nil)) == .declined)
    check("unavailable stays retryable", paymentIntentStatus(for: PaymentResponse(ok: false, state: nil, transaction: nil, error: "Down", code: "PROVIDER_UNAVAILABLE", paymentId: nil)) == .processing)
    check("empty code stays retryable", paymentIntentStatus(for: PaymentResponse(ok: false, state: nil, transaction: nil, error: nil, code: nil, paymentId: nil)) == .processing)
    check("validation failure is terminal", paymentIntentStatus(for: PaymentResponse(ok: false, state: nil, transaction: nil, error: "Bad", code: "VALIDATION_ERROR", paymentId: nil)) == .failed)

    func draft(account: String, intent: String, key: String, amount: Int = 2599) -> PaymentIntentDraft {
      PaymentIntentDraft(
        customerAccountId: account,
        paymentIntentId: intent,
        idempotencyKey: key,
        recipientId: "northline-studio",
        amountMinor: amount,
        method: .card,
        note: "lunch"
      )
    }

    print("24. account isolation and required fields...")
    let memory = InMemoryPaymentIntentSnapshotStore()
    let repository = PaymentIntentSnapshotRepository(store: memory)
    do {
      let began = try repository.begin(draft(account: "acct-a", intent: "intent-aaa1", key: "idem-key-a1"), nowEpochMs: 1_000)
      let snapshot = began.snapshot
      check("new intent is active", began.created && began.payloadMatches && snapshot.status == .processing)
      check(
        "snapshot keeps intent, key, hash and empty return state",
        snapshot.paymentIntentId == "intent-aaa1"
          && snapshot.idempotencyKey == "idem-key-a1"
          && snapshot.businessPayloadHash == businessPayloadHash(
            customerAccountId: "acct-a",
            recipientId: "northline-studio",
            amountMinor: 2599,
            method: .card,
            note: "lunch"
          )
          && snapshot.returnState == nil
          && snapshot.returnStateHash == nil
      )
      let otherAccount = try repository.resumeActive(customerAccountId: "acct-b", nowEpochMs: 1_000)
      let hidden = try repository.load(customerAccountId: "acct-b", paymentIntentId: "intent-aaa1", nowEpochMs: 1_000)
      check("other customer account cannot see the intent", otherAccount.isEmpty && hidden == nil)
    } catch {
      check("account isolation threw \(error)", false)
    }

    print("25. process recovery...")
    do {
      let recovered = try PaymentIntentSnapshotRepository(store: memory)
        .resumeActive(customerAccountId: "acct-a", nowEpochMs: 9_000)
      check(
        "new repository finds the active intent and original key",
        recovered.count == 1 && recovered[0].idempotencyKey == "idem-key-a1" && !recovered[0].status.isTerminal
      )
    } catch {
      check("process recovery threw \(error)", false)
    }

    print("26. uncertain retry keeps the idempotency key...")
    do {
      let uncertain = try repository.markUncertain(customerAccountId: "acct-a", paymentIntentId: "intent-aaa1", nowEpochMs: 20)
      let again = try repository.begin(draft(account: "acct-a", intent: "intent-bbb2", key: "idem-key-b2"), nowEpochMs: 30)
      check(
        "uncertain intent is resumed instead of replaced",
        uncertain.status == .processing
          && uncertain.idempotencyKey == "idem-key-a1"
          && !again.created
          && again.payloadMatches
          && again.snapshot.idempotencyKey == "idem-key-a1"
      )
      let mismatch = try repository.begin(
        draft(account: "acct-a", intent: "intent-ccc3", key: "idem-key-c3", amount: 2600),
        nowEpochMs: 31
      )
      check(
        "different payload does not mint a second active intent",
        !mismatch.payloadMatches && mismatch.snapshot.idempotencyKey == "idem-key-a1" && mismatch.snapshot.amountMinor == 2599
      )
    } catch {
      check("uncertain retry threw \(error)", false)
    }

    print("27. terminal retention window...")
    let window = PaymentIntentRetention.terminalWindowMs
    do {
      let pending = try repository.recordOutcome(
        customerAccountId: "acct-a",
        paymentIntentId: "intent-aaa1",
        response: PaymentResponse(ok: false, state: nil, transaction: nil, error: "Awaiting confirmation", code: "PAYMENT_PENDING", paymentId: "pay-9"),
        nowEpochMs: 40
      )
      let stillActive = try repository.resumeActive(customerAccountId: "acct-a", nowEpochMs: 41)
      check(
        "pending stores the return state hash and stays active",
        pending.status == .pending
          && pending.returnStateHash == "a5ea41d10b6f195c073b33f96c57bb76cfee49de91d4a38c5220bd4ecb85197b"
          && stillActive.count == 1
          && stillActive[0].idempotencyKey == "idem-key-a1"
      )
      let settled = try repository.recordOutcome(
        customerAccountId: "acct-a",
        paymentIntentId: "intent-aaa1",
        response: PaymentResponse(
          ok: true,
          state: BankState(version: 4, balance: 1_245_451, transactions: [], budgets: []),
          transaction: nil,
          error: nil,
          code: nil,
          paymentId: "pay-1"
        ),
        nowEpochMs: 2_000
      )
      let duringWindow = try repository.load(customerAccountId: "acct-a", paymentIntentId: "intent-aaa1", nowEpochMs: 2_000 + window - 1)
      let afterWindow = try repository.load(customerAccountId: "acct-a", paymentIntentId: "intent-aaa1", nowEpochMs: 2_000 + window)
      let resumedAfterSuccess = try repository.resumeActive(customerAccountId: "acct-a", nowEpochMs: 2_000)
      check(
        "success records return state and leaves the active set",
        settled.status == .succeeded
          && settled.returnStateHash == "b5249909bae8e7dd177a9d782f43300fb7e0ce1da42a696d0f5770227d68bb44"
          && settled.returnState?.balancePence == 1_245_451
          && resumedAfterSuccess.isEmpty
      )
      check("terminal snapshot expires at the retention boundary", duringWindow != nil && afterWindow == nil)
    } catch {
      check("retention threw \(error)", false)
    }

    print("28. active intents ignore the retention window...")
    do {
      let fresh = PaymentIntentSnapshotRepository(store: InMemoryPaymentIntentSnapshotStore())
      _ = try fresh.begin(draft(account: "acct-old", intent: "intent-old1", key: "idem-old-11"), nowEpochMs: 1_000)
      let aged = try fresh.resumeActive(customerAccountId: "acct-old", nowEpochMs: 1_000 + window * 5)
      check("old active intent is still resumable", aged.count == 1 && aged[0].idempotencyKey == "idem-old-11")
      _ = try fresh.cancel(customerAccountId: "acct-old", paymentIntentId: "intent-old1", nowEpochMs: 50)
      let afterCancel = try fresh.resumeActive(customerAccountId: "acct-old", nowEpochMs: 51)
      let held = try fresh.load(customerAccountId: "acct-old", paymentIntentId: "intent-old1", nowEpochMs: 50 + window - 1)
      let dropped = try fresh.load(customerAccountId: "acct-old", paymentIntentId: "intent-old1", nowEpochMs: 50 + window)
      let replacement = try fresh.begin(draft(account: "acct-old", intent: "intent-new2", key: "idem-new-22"), nowEpochMs: 52)
      check(
        "cancelled intent is kept until the window ends",
        afterCancel.isEmpty && held?.status == .cancelled && dropped == nil && replacement.created && replacement.snapshot.idempotencyKey == "idem-new-22"
      )
    } catch {
      check("active expiry threw \(error)", false)
    }

    print("29. empty customer account is rejected...")
    do {
      _ = try repository.begin(draft(account: "", intent: "intent-aaa1", key: "idem-key-a1"), nowEpochMs: 1)
      check("empty account should fail", false)
    } catch PaymentIntentSnapshotError.invalidCustomerAccount {
      check("empty customer account rejected", true)
    } catch {
      check("unexpected account error \(error)", false)
    }

    #if canImport(Security)
    print("30. keychain round trip...")
    let keychainAccount = "acct-" + UUID().uuidString.lowercased()
    let keychain = KeychainPaymentIntentSnapshotStore()
    do {
      defer { try? keychain.delete(customerAccountId: keychainAccount, paymentIntentId: "intent-kc01") }
      let stored = PaymentIntentSnapshotRepository(store: keychain)
      let began = try stored.begin(
        draft(account: keychainAccount, intent: "intent-kc01", key: "idem-key-kc"),
        nowEpochMs: 70
      )
      let restarted = PaymentIntentSnapshotRepository(store: KeychainPaymentIntentSnapshotStore())
      let active = try restarted.resumeActive(customerAccountId: keychainAccount, nowEpochMs: 71)
      check(
        "keychain restores the intent for the same customer account",
        began.created && active.count == 1 && active[0].idempotencyKey == "idem-key-kc" && active[0].businessPayloadHash == began.snapshot.businessPayloadHash
      )
      let foreign = try restarted.resumeActive(customerAccountId: "acct-other", nowEpochMs: 72)
      check("keychain service does not return another account", foreign.isEmpty)
    } catch {
      let text = String(describing: error)
      if text.contains("SecItem") {
        print("  SKIP keychain unavailable in this environment (\(text))")
      } else {
        check("keychain round trip threw \(text)", false)
      }
    }
    #endif

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
