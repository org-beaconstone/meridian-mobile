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

    // Summary
    print("\n=== PaymentIntentSnapshot checks ===\n")

    // CHECK 21: PaymentIntentStatus terminal flags
    print("21. PaymentIntentStatus terminal flags...")
    let terminalStatuses: [PaymentIntentStatus] = [.completed, .declined, .expired]
    let activeStatuses: [PaymentIntentStatus] = [.created, .pending]
    let terminalOk = terminalStatuses.allSatisfy { $0.isTerminal }
    let activeOk = activeStatuses.allSatisfy { !$0.isTerminal }
    if terminalOk && activeOk {
      print("  ✓ Terminal and active statuses correctly classified")
      passed += 1
    } else {
      print("  ✗ PaymentIntentStatus.isTerminal mismatch")
      failed += 1
    }

    // CHECK 22: paymentPayloadHash produces deterministic output
    print("22. paymentPayloadHash deterministic...")
    let h1 = paymentPayloadHash(recipientId: "r1", amountMinor: 1000, method: .card, note: "n")
    let h2 = paymentPayloadHash(recipientId: "r1", amountMinor: 1000, method: .card, note: "n")
    let h3 = paymentPayloadHash(recipientId: "r2", amountMinor: 1000, method: .card, note: "n")
    if h1 == h2 && h1 != h3 && h1.count == 64 {
      print("  ✓ paymentPayloadHash is stable and distinct: \(h1.prefix(12))…")
      passed += 1
    } else {
      print("  ✗ Hash mismatch – h1=\(h1) h3=\(h3)")
      failed += 1
    }

    // CHECK 23: bankStateHash produces deterministic output
    print("23. bankStateHash deterministic...")
    let bh1 = bankStateHash(version: 1, balance: 100_000)
    let bh2 = bankStateHash(version: 1, balance: 100_000)
    let bh3 = bankStateHash(version: 2, balance: 100_000)
    if bh1 == bh2 && bh1 != bh3 && bh1.count == 64 {
      print("  ✓ bankStateHash is stable and distinct: \(bh1.prefix(12))…")
      passed += 1
    } else {
      print("  ✗ bankStateHash mismatch")
      failed += 1
    }

    // CHECK 24: PaymentIntentSnapshot fields round-trip
    print("24. PaymentIntentSnapshot fields...")
    let snap = PaymentIntentSnapshot(
      paymentIntentId: "pi-1",
      idempotencyKey: "ik-1",
      businessPayloadHash: "abc",
      status: .pending,
      returnStateHash: "def"
    )
    if snap.paymentIntentId == "pi-1"
      && snap.idempotencyKey == "ik-1"
      && snap.businessPayloadHash == "abc"
      && snap.status == .pending
      && snap.returnStateHash == "def"
      && !snap.isExpired {
      print("  ✓ Snapshot fields are correct")
      passed += 1
    } else {
      print("  ✗ Snapshot fields mismatch")
      failed += 1
    }

    // CHECK 25: Snapshot expiry for terminal status past retention window
    print("25. Snapshot expiry after retention window...")
    let pastWindow = Date().addingTimeInterval(-(PaymentIntentSnapshot.terminalRetentionWindow + 1))
    let expired = PaymentIntentSnapshot(
      paymentIntentId: "pi-2",
      idempotencyKey: "ik-2",
      businessPayloadHash: "x",
      status: .completed,
      updatedAt: pastWindow
    )
    let notExpired = PaymentIntentSnapshot(
      paymentIntentId: "pi-3",
      idempotencyKey: "ik-3",
      businessPayloadHash: "y",
      status: .completed
    )
    if expired.isExpired && !notExpired.isExpired {
      print("  ✓ Expiry correctly tracks terminal retention window")
      passed += 1
    } else {
      print("  ✗ Expiry logic failed: expired.isExpired=\(expired.isExpired) notExpired.isExpired=\(notExpired.isExpired)")
      failed += 1
    }

    // CHECK 26: Active (non-terminal) snapshot is not expired
    print("26. Active snapshot not expired...")
    let active = PaymentIntentSnapshot(
      paymentIntentId: "pi-4",
      idempotencyKey: "ik-4",
      businessPayloadHash: "z",
      status: .pending
    )
    if !active.isExpired {
      print("  ✓ Pending snapshot is not expired")
      passed += 1
    } else {
      print("  ✗ Pending snapshot should not be expired")
      failed += 1
    }

    // CHECK 27: InMemoryPaymentIntentStore save/load/delete
    print("27. InMemoryPaymentIntentStore save/load/delete...")
    let memStore = InMemoryPaymentIntentStore()
    let snap27 = PaymentIntentSnapshot(
      paymentIntentId: "pi-5",
      idempotencyKey: "ik-5",
      businessPayloadHash: "p",
      status: .created
    )
    do {
      try await memStore.save(snap27)
      let loaded = try await memStore.load(idempotencyKey: "ik-5")
      let missing = try await memStore.load(idempotencyKey: "ik-missing")
      try await memStore.delete(idempotencyKey: "ik-5")
      let afterDelete = try await memStore.load(idempotencyKey: "ik-5")
      if loaded?.idempotencyKey == "ik-5"
        && missing == nil
        && afterDelete == nil {
        print("  ✓ InMemoryPaymentIntentStore CRUD works correctly")
        passed += 1
      } else {
        print("  ✗ Store CRUD mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ Store error: \(error)")
      failed += 1
    }

    // CHECK 28: InMemoryPaymentIntentStore loadActive filters terminal/expired
    print("28. InMemoryPaymentIntentStore loadActive filtering...")
    let activeStore = InMemoryPaymentIntentStore()
    do {
      let pending = PaymentIntentSnapshot(
        paymentIntentId: "pi-a", idempotencyKey: "ik-a",
        businessPayloadHash: "1", status: .pending)
      let created = PaymentIntentSnapshot(
        paymentIntentId: "pi-b", idempotencyKey: "ik-b",
        businessPayloadHash: "2", status: .created)
      let done = PaymentIntentSnapshot(
        paymentIntentId: "pi-c", idempotencyKey: "ik-c",
        businessPayloadHash: "3", status: .completed)
      let old = PaymentIntentSnapshot(
        paymentIntentId: "pi-d", idempotencyKey: "ik-d",
        businessPayloadHash: "4", status: .declined,
        updatedAt: Date().addingTimeInterval(-(PaymentIntentSnapshot.terminalRetentionWindow + 60)))
      try await activeStore.save(pending)
      try await activeStore.save(created)
      try await activeStore.save(done)
      try await activeStore.save(old)
      let actives = try await activeStore.loadActive()
      let ids = Set(actives.map { $0.idempotencyKey })
      // pending + created should appear; completed and expired-declined should not
      if ids == Set(["ik-a", "ik-b"]) {
        print("  ✓ loadActive returns only non-terminal, non-expired snapshots")
        passed += 1
      } else {
        print("  ✗ loadActive returned unexpected ids: \(ids)")
        failed += 1
      }
    } catch {
      print("  ✗ Store error: \(error)")
      failed += 1
    }

    // CHECK 29: MeridianClient.resumeActiveIntents without store returns empty
    print("29. resumeActiveIntents without store returns empty...")
    do {
      let client = try MeridianClient(
        baseURL: "http://localhost:8080/api/v1",
        sessionId: "test-session"
      )
      let intents = try await client.resumeActiveIntents()
      if intents.isEmpty {
        print("  ✓ resumeActiveIntents correctly returns [] when no store is configured")
        passed += 1
      } else {
        print("  ✗ Expected empty, got \(intents.count) intent(s)")
        failed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 30: MeridianClient snapshot lifecycle via InMemoryPaymentIntentStore
    print("30. MeridianClient snapshot lifecycle via InMemoryPaymentIntentStore...")
    do {
      let lifecycleStore = InMemoryPaymentIntentStore()
      // We can only test the store write/read path without a live server.
      // Manually exercise the store API to verify it integrates cleanly.
      let key = UUID().uuidString
      let payloadHash = paymentPayloadHash(
        recipientId: "northline-studio", amountMinor: 1000, method: .card, note: "test")
      var snap = PaymentIntentSnapshot(
        paymentIntentId: key,
        idempotencyKey: key,
        businessPayloadHash: payloadHash,
        status: .created
      )
      try await lifecycleStore.save(snap)

      // Transition to pending
      snap.status = .pending
      snap.paymentIntentId = "pay-server-001"
      snap.returnStateHash = bankStateHash(version: 1, balance: 100_000)
      snap.updatedAt = Date()
      try await lifecycleStore.save(snap)

      let loaded = try await lifecycleStore.load(idempotencyKey: key)
      let actives = try await lifecycleStore.loadActive()
      if loaded?.status == .pending
        && loaded?.paymentIntentId == "pay-server-001"
        && actives.count == 1 {
        print("  ✓ Snapshot lifecycle: created → pending correctly stored and retrievable")
        passed += 1
      } else {
        print("  ✗ Lifecycle mismatch: status=\(String(describing: loaded?.status)), actives=\(actives.count)")
        failed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // Summary
    print("\n=== Results ===")
    print("Passed: \(passed)/30")
    print("Failed: \(failed)/30")

    if failed > 0 {
      exit(1)
    }
  }
}
