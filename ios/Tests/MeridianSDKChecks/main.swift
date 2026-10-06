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

    func expect(_ title: String, _ ok: Bool, _ detail: String = "") {
      if ok {
        print("  ✓ \(title)")
        passed += 1
      } else {
        print("  ✗ \(title) \(detail)")
        failed += 1
      }
    }

    func sampleLedger(now: Int64 = 5_000, retention: Int64 = PaymentIntentRetention.terminalWindowMillis) -> (InMemoryPaymentIntentStore, PaymentIntentLedger, (Int64) -> Void) {
      let clock = ClockBox(now)
      let store = InMemoryPaymentIntentStore()
      let ledger = PaymentIntentLedger(store: store, nowMillis: { clock.now }, retentionMillis: retention)
      return (store, ledger, { clock.now = $0 })
    }

    print("21. business payload hash vector...")
    let canonical = PaymentIntentHash.canonicalBusinessPayload(
      customerAccountId: "acct-demo",
      recipientId: "northline-studio",
      amountMinor: 2599,
      method: "card",
      note: "Studio invoice",
      scenario: "success"
    )
    expect(
      "canonical payload and hash",
      canonical == "{\"v\":1,\"customerAccountId\":\"acct-demo\",\"recipientId\":\"northline-studio\",\"amountMinor\":2599,\"method\":\"card\",\"note\":\"Studio invoice\",\"scenario\":\"success\"}"
        && PaymentIntentHash.sha256Hex(canonical) == "ae1c0e96711da9a13695fd7439b2b60ff0a3bf9c3f336729fe5cb3eb98ae642e",
      canonical
    )

    print("22. escaped note hash...")
    let escaped = PaymentIntentHash.canonicalBusinessPayload(
      customerAccountId: "acct-demo",
      recipientId: "northline-studio",
      amountMinor: 100,
      method: "bank",
      note: "line\nquote\"",
      scenario: "pending"
    )
    expect(
      "escaped note hash",
      escaped == "{\"v\":1,\"customerAccountId\":\"acct-demo\",\"recipientId\":\"northline-studio\",\"amountMinor\":100,\"method\":\"bank\",\"note\":\"line\\nquote\\\"\",\"scenario\":\"pending\"}"
        && PaymentIntentHash.sha256Hex(escaped) == "882dc93278f448b32d5782b4312660ebc3f80f7aed5fed70ae82d1495f5f72fd"
    )

    print("23. return state hash...")
    expect(
      "sha256(abc)",
      PaymentIntentHash.returnStateHash("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )

    print("24. restart resumes the same idempotency key...")
    do {
      let (store, ledger, _) = sampleLedger()
      let prepared = try ledger.begin(
        customerAccountId: "acct-demo", recipientId: "northline-studio", amountMinor: 2599,
        method: .card, note: "Studio invoice", scenario: .success
      )
      _ = try ledger.markSubmitted(customerAccountId: "acct-demo", paymentIntentId: prepared.snapshot.paymentIntentId)
      _ = try ledger.record(
        response: PaymentResponse(ok: false, state: nil, transaction: nil, error: "Payment pending confirmation", code: "PAYMENT_PENDING", paymentId: "pay-1"),
        customerAccountId: "acct-demo",
        paymentIntentId: prepared.snapshot.paymentIntentId
      )
      _ = try ledger.begin(customerAccountId: "other-acct", recipientId: "northline-studio", amountMinor: 100, method: .bank, note: "other", scenario: .success)
      let restarted = PaymentIntentLedger(store: store)
      let active = try restarted.activeIntents(customerAccountId: "acct-demo")
      let hidden = try restarted.activeIntents(customerAccountId: "other-acct")
      expect(
        "resumed intent keeps id and idempotency key",
        active.count == 1
          && active[0].paymentIntentId == prepared.snapshot.paymentIntentId
          && active[0].idempotencyKey == prepared.snapshot.idempotencyKey
          && active[0].returnStateHash == prepared.snapshot.returnStateHash
          && hidden.allSatisfy { $0.paymentIntentId != prepared.snapshot.paymentIntentId }
          && (try restarted.lastCustomerAccountId()) == "other-acct"
      )
    } catch {
      expect("resumed intent keeps id and idempotency key", false, String(describing: error))
    }

    print("25. terminal retention window...")
    do {
      let (store, ledger, setNow) = sampleLedger(now: 1_000, retention: 1_000)
      let prepared = try ledger.begin(customerAccountId: "acct-demo", recipientId: "northline-studio", amountMinor: 500, method: .card, note: "", scenario: .success)
      _ = try ledger.markSubmitted(customerAccountId: "acct-demo", paymentIntentId: prepared.snapshot.paymentIntentId)
      let done = try ledger.record(
        response: PaymentResponse(ok: true, state: nil, transaction: nil, error: nil, code: nil, paymentId: "pay-9"),
        customerAccountId: "acct-demo",
        paymentIntentId: prepared.snapshot.paymentIntentId
      )
      setNow(1_999)
      let restarted = PaymentIntentLedger(store: store, nowMillis: { 1_999 }, retentionMillis: 1_000)
      let kept = try restarted.snapshots(customerAccountId: "acct-demo")
      let idle = try restarted.activeIntents(customerAccountId: "acct-demo")
      let expiredLedger = PaymentIntentLedger(store: store, nowMillis: { 2_000 }, retentionMillis: 1_000)
      let gone = try expiredLedger.snapshots(customerAccountId: "acct-demo")
      expect(
        "terminal snapshot expires at the retention boundary",
        done.status == .completed && done.terminalAtEpochMillis == 1_000 && idle.isEmpty && kept.count == 1 && gone.isEmpty
      )
    } catch {
      expect("terminal snapshot expires at the retention boundary", false, String(describing: error))
    }

    print("26. active intents are not expired by time...")
    do {
      let (_, ledger, setNow) = sampleLedger(now: 0, retention: 1_000)
      let kept = try ledger.begin(customerAccountId: "acct-demo", recipientId: "northline-studio", amountMinor: 500, method: .card, note: "", scenario: .success)
      let other = try ledger.begin(customerAccountId: "other-acct", recipientId: "northline-studio", amountMinor: 500, method: .card, note: "", scenario: .success)
      _ = try ledger.markSubmitted(customerAccountId: "other-acct", paymentIntentId: other.snapshot.paymentIntentId)
      _ = try ledger.record(
        response: PaymentResponse(ok: true, state: nil, transaction: nil, error: nil, code: nil, paymentId: nil),
        customerAccountId: "other-acct",
        paymentIntentId: other.snapshot.paymentIntentId
      )
      setNow(50_000)
      let active = try ledger.activeIntents(customerAccountId: "acct-demo")
      let otherLeft = try ledger.snapshots(customerAccountId: "other-acct")
      expect(
        "only the other account's terminal snapshot is purged",
        active.count == 1 && active[0].paymentIntentId == kept.snapshot.paymentIntentId && otherLeft.isEmpty
      )
    } catch {
      expect("only the other account's terminal snapshot is purged", false, String(describing: error))
    }

    print("27. uncertain retry keeps the idempotency key...")
    do {
      let (_, ledger, _) = sampleLedger()
      let prepared = try ledger.begin(customerAccountId: "acct-demo", recipientId: "northline-studio", amountMinor: 2599, method: .bank, note: "rent", scenario: .success)
      _ = try ledger.markSubmitted(customerAccountId: "acct-demo", paymentIntentId: prepared.snapshot.paymentIntentId)
      let uncertain = try ledger.markUncertain(customerAccountId: "acct-demo", paymentIntentId: prepared.snapshot.paymentIntentId)
      let active = try ledger.activeIntents(customerAccountId: "acct-demo")
      expect(
        "unknown status stays active with the same key",
        uncertain.status == .unknown && uncertain.idempotencyKey == prepared.snapshot.idempotencyKey
          && uncertain.terminalAtEpochMillis == nil && active.count == 1
      )
    } catch {
      expect("unknown status stays active with the same key", false, String(describing: error))
    }

    print("28. same payload reuses the intent...")
    do {
      let (_, ledger, _) = sampleLedger()
      let first = try ledger.begin(customerAccountId: "acct-demo", recipientId: "northline-studio", amountMinor: 2599, method: .card, note: "Studio invoice", scenario: .success)
      let second = try ledger.begin(customerAccountId: "acct-demo", recipientId: "northline-studio", amountMinor: 2599, method: .card, note: "Studio invoice", scenario: .success)
      let active = try ledger.activeIntents(customerAccountId: "acct-demo")
      expect(
        "second begin reuses the snapshot",
        second.returnState == nil && second.snapshot.paymentIntentId == first.snapshot.paymentIntentId
          && second.snapshot.idempotencyKey == first.snapshot.idempotencyKey && active.count == 1
      )
    } catch {
      expect("second begin reuses the snapshot", false, String(describing: error))
    }

    print("29. in-flight intent blocks a different payload...")
    do {
      let (_, ledger, _) = sampleLedger()
      let prepared = try ledger.begin(customerAccountId: "acct-demo", recipientId: "northline-studio", amountMinor: 2599, method: .card, note: "Studio invoice", scenario: .success)
      _ = try ledger.markSubmitted(customerAccountId: "acct-demo", paymentIntentId: prepared.snapshot.paymentIntentId)
      _ = try ledger.record(
        response: PaymentResponse(ok: false, state: nil, transaction: nil, error: nil, code: "PAYMENT_PENDING", paymentId: nil),
        customerAccountId: "acct-demo",
        paymentIntentId: prepared.snapshot.paymentIntentId
      )
      do {
        _ = try ledger.begin(customerAccountId: "acct-demo", recipientId: "northline-studio", amountMinor: 100, method: .card, note: "Studio invoice", scenario: .success)
        expect("different payload is rejected", false)
      } catch PaymentIntentError.activeIntentInProgress(let id) {
        let active = try ledger.activeIntents(customerAccountId: "acct-demo")
        expect("different payload is rejected", id == prepared.snapshot.paymentIntentId && active[0].idempotencyKey == prepared.snapshot.idempotencyKey)
      } catch {
        expect("different payload is rejected", false, String(describing: error))
      }
    } catch {
      expect("different payload is rejected", false, String(describing: error))
    }

    print("30. created intent is replaced...")
    do {
      let (_, ledger, _) = sampleLedger()
      let created = try ledger.begin(customerAccountId: "acct-demo", recipientId: "northline-studio", amountMinor: 2599, method: .card, note: "Studio invoice", scenario: .success)
      let replacement = try ledger.begin(customerAccountId: "acct-demo", recipientId: "northline-studio", amountMinor: 100, method: .bank, note: "other", scenario: .success)
      let active = try ledger.activeIntents(customerAccountId: "acct-demo")
      let cancelled = try ledger.snapshots(customerAccountId: "acct-demo").first { $0.paymentIntentId == created.snapshot.paymentIntentId }
      expect(
        "new payload cancels the unsent intent",
        replacement.snapshot.paymentIntentId != created.snapshot.paymentIntentId
          && replacement.snapshot.idempotencyKey != created.snapshot.idempotencyKey
          && active.count == 1 && cancelled?.status == .cancelled
      )
    } catch {
      expect("new payload cancels the unsent intent", false, String(describing: error))
    }

    print("31. return state verification...")
    do {
      let (_, ledger, _) = sampleLedger()
      let prepared = try ledger.begin(customerAccountId: "acct-demo", recipientId: "northline-studio", amountMinor: 2599, method: .card, note: "Studio invoice", scenario: .success)
      if let token = prepared.returnState {
        expect(
          "hash matches the token and rejects a different one",
          ledger.verifyReturnState(prepared.snapshot, returnState: token)
            && !ledger.verifyReturnState(prepared.snapshot, returnState: "different-return-state")
            && prepared.snapshot.returnStateHash != token
        )
      } else {
        expect("hash matches the token and rejects a different one", false, "missing return state")
      }
    } catch {
      expect("hash matches the token and rejects a different one", false, String(describing: error))
    }

    print("32. snapshot JSON round trip...")
    do {
      let (_, ledger, _) = sampleLedger()
      let prepared = try ledger.begin(customerAccountId: "acct-demo", recipientId: "northline-studio", amountMinor: 2599, method: .card, note: "Studio invoice", scenario: .success)
      let data = try JSONEncoder().encode(prepared.snapshot)
      let restored = try JSONDecoder().decode(PaymentIntentSnapshot.self, from: data)
      expect(
        "acceptance fields survive encoding",
        restored == prepared.snapshot
          && restored.paymentIntentId == prepared.snapshot.paymentIntentId
          && restored.idempotencyKey == prepared.snapshot.idempotencyKey
          && restored.businessPayloadHash == prepared.snapshot.businessPayloadHash
          && restored.status == .created
          && restored.returnStateHash == prepared.snapshot.returnStateHash
      )
    } catch {
      expect("acceptance fields survive encoding", false, String(describing: error))
    }

    print("33. decline allows a new intent...")
    do {
      let (_, ledger, _) = sampleLedger()
      let prepared = try ledger.begin(customerAccountId: "acct-demo", recipientId: "northline-studio", amountMinor: 2599, method: .card, note: "Studio invoice", scenario: .success)
      _ = try ledger.markSubmitted(customerAccountId: "acct-demo", paymentIntentId: prepared.snapshot.paymentIntentId)
      let declined = try ledger.record(
        response: PaymentResponse(ok: false, state: nil, transaction: nil, error: "Insufficient balance", code: "INSUFFICIENT_BALANCE", paymentId: nil),
        customerAccountId: "acct-demo",
        paymentIntentId: prepared.snapshot.paymentIntentId
      )
      let next = try ledger.begin(customerAccountId: "acct-demo", recipientId: "northline-studio", amountMinor: 100, method: .card, note: "Studio invoice", scenario: .success)
      let active = try ledger.activeIntents(customerAccountId: "acct-demo")
      expect(
        "declined intent is terminal and a new key can be created",
        declined.status == .declined && declined.status.isTerminal && active.count == 1
          && active[0].status == .created && next.snapshot.idempotencyKey != prepared.snapshot.idempotencyKey
      )
    } catch {
      expect("declined intent is terminal and a new key can be created", false, String(describing: error))
    }

    print("34. storage key is account scoped...")
    do {
      let key = try PaymentIntentStorageKeys.snapshotKey(customerAccountId: "acct-demo", paymentIntentId: "pi_storage_key")
      expect(
        "key prefix isolates the account",
        key == "acct-demo|pi_storage_key"
          && PaymentIntentStorageKeys.belongsToAccount(key, customerAccountId: "acct-demo")
          && !PaymentIntentStorageKeys.belongsToAccount(key, customerAccountId: "acct")
          && !PaymentIntentStorageKeys.belongsToAccount(key, customerAccountId: "other-acct")
      )
    } catch {
      expect("key prefix isolates the account", false, String(describing: error))
    }

    print("35. invalid customer account is rejected...")
    let (_, invalidLedger, _) = sampleLedger()
    do {
      _ = try invalidLedger.begin(customerAccountId: "bad account", recipientId: "northline-studio", amountMinor: 100, method: .card, note: "", scenario: .success)
      expect("invalid account rejected", false)
    } catch PaymentIntentError.invalidAccount {
      expect("invalid account rejected", true)
    } catch {
      expect("invalid account rejected", false, String(describing: error))
    }

    print("36. keychain round trip is account scoped...")
    do {
      let store = KeychainPaymentIntentStore()
      let first = sampleSnapshot(account: "cust-keychain-a", intentId: "pi_keychain_a", note: "alpha")
      let second = sampleSnapshot(account: "cust-keychain-b", intentId: "pi_keychain_b", note: "beta")
      try store.delete(customerAccountId: "cust-keychain-a", paymentIntentId: "pi_keychain_a")
      try store.delete(customerAccountId: "cust-keychain-b", paymentIntentId: "pi_keychain_b")
      try store.save(first)
      try store.save(second)
      try store.rememberCustomerAccountId("cust-keychain-a")
      let reopened = KeychainPaymentIntentStore()
      let loaded = try reopened.load(customerAccountId: "cust-keychain-a")
      let other = try reopened.load(customerAccountId: "cust-keychain-b")
      try reopened.delete(customerAccountId: "cust-keychain-a", paymentIntentId: "pi_keychain_a")
      let afterDelete = try reopened.load(customerAccountId: "cust-keychain-a")
      let otherAfter = try reopened.load(customerAccountId: "cust-keychain-b")
      try reopened.delete(customerAccountId: "cust-keychain-b", paymentIntentId: "pi_keychain_b")
      expect(
        "keychain keeps each account separate across a new store",
        loaded == [first] && other == [second] && afterDelete.isEmpty && otherAfter == [second]
          && (try reopened.lastCustomerAccountId()) == "cust-keychain-a"
      )
    } catch {
      expect("keychain keeps each account separate across a new store", false, String(describing: error))
    }

    let total = passed + failed
    print("\n=== Results ===")
    print("Passed: \(passed)/\(total)")
    print("Failed: \(failed)/\(total)")

    if failed > 0 {
      exit(1)
    }
  }
}

private final class ClockBox {
  var now: Int64
  init(_ now: Int64) { self.now = now }
}

private func sampleSnapshot(account: String, intentId: String, note: String) -> PaymentIntentSnapshot {
  PaymentIntentSnapshot(
    paymentIntentId: intentId,
    idempotencyKey: "idem-\(intentId)",
    businessPayloadHash: "abc123",
    status: .pending,
    returnStateHash: PaymentIntentHash.returnStateHash("return-\(intentId)"),
    customerAccountId: account,
    recipientId: "northline-studio",
    amountMinor: 2599,
    method: .card,
    note: note,
    scenario: .success,
    createdAtEpochMillis: 10,
    updatedAtEpochMillis: 20
  )
}

