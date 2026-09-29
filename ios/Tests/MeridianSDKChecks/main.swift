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

    // CHECK 21: PaymentIntentStatus terminal flag
    print("21. PaymentIntentStatus terminal flag...")
    if !PaymentIntentStatus.pending.isTerminal
      && PaymentIntentStatus.completed.isTerminal
      && PaymentIntentStatus.declined.isTerminal
      && PaymentIntentStatus.failed.isTerminal
    {
      print("  ✓ PaymentIntentStatus.isTerminal correct for all cases")
      passed += 1
    } else {
      print("  ✗ PaymentIntentStatus.isTerminal incorrect")
      failed += 1
    }

    // CHECK 22: PaymentIntentSnapshot pending is active
    print("22. PaymentIntentSnapshot pending isActive...")
    let pendingSnap = PaymentIntentSnapshot(
      paymentIntentId: "pi-001",
      idempotencyKey: "idem-001",
      businessPayloadHash: "abc",
      status: .pending,
      createdAt: "2026-09-29T10:00:00Z"
    )
    if pendingSnap.isActive && !pendingSnap.isExpired {
      print("  ✓ Pending snapshot isActive=true, isExpired=false")
      passed += 1
    } else {
      print("  ✗ Pending snapshot isActive or isExpired incorrect")
      failed += 1
    }

    // CHECK 23: PaymentIntentSnapshot completed not active
    print("23. PaymentIntentSnapshot completed isActive=false...")
    let completedSnap = PaymentIntentSnapshot(
      paymentIntentId: "pi-002",
      idempotencyKey: "idem-002",
      businessPayloadHash: "abc",
      status: .completed,
      createdAt: "2026-09-29T10:00:00Z",
      resolvedAt: "2026-09-29T10:01:00Z"
    )
    if !completedSnap.isActive && !completedSnap.isExpired {
      print("  ✓ Completed snapshot isActive=false, not yet expired")
      passed += 1
    } else {
      print("  ✗ Completed snapshot flags incorrect")
      failed += 1
    }

    // CHECK 24: PaymentIntentSnapshot expired after retention window
    print("24. PaymentIntentSnapshot isExpired after retention window...")
    let pastDate = ISO8601DateFormatter().string(
      from: Date().addingTimeInterval(-(PaymentIntentSnapshot.retentionWindow + 3600))
    )
    let expiredSnap = PaymentIntentSnapshot(
      paymentIntentId: "pi-003",
      idempotencyKey: "idem-003",
      businessPayloadHash: "abc",
      status: .completed,
      createdAt: "2026-09-28T08:00:00Z",
      resolvedAt: pastDate
    )
    if !expiredSnap.isActive && expiredSnap.isExpired {
      print("  ✓ Snapshot correctly expired after retention window")
      passed += 1
    } else {
      print("  ✗ isExpired logic incorrect for past-retention snapshot")
      failed += 1
    }

    // CHECK 25: PaymentIntentSnapshot pending never expires
    print("25. PaymentIntentSnapshot pending never expires...")
    let oldPending = PaymentIntentSnapshot(
      paymentIntentId: "pi-004",
      idempotencyKey: "idem-004",
      businessPayloadHash: "abc",
      status: .pending,
      createdAt: "2026-01-01T00:00:00Z"
    )
    if !oldPending.isExpired {
      print("  ✓ Pending snapshot without resolvedAt is never expired")
      passed += 1
    } else {
      print("  ✗ Pending snapshot should not expire")
      failed += 1
    }

    // CHECK 26: businessPayloadHash is deterministic
    print("26. businessPayloadHash deterministic...")
    let h1 = businessPayloadHash(
      recipientId: "northline-studio",
      amountMinor: 2599,
      method: .card,
      note: "test note",
      scenario: .success
    )
    let h2 = businessPayloadHash(
      recipientId: "northline-studio",
      amountMinor: 2599,
      method: .card,
      note: "test note",
      scenario: .success
    )
    if h1 == h2 && !h1.isEmpty {
      print("  ✓ businessPayloadHash deterministic: \(h1.prefix(8))…")
      passed += 1
    } else {
      print("  ✗ businessPayloadHash not deterministic")
      failed += 1
    }

    // CHECK 27: businessPayloadHash differs on amount change
    print("27. businessPayloadHash differs on parameter change...")
    let h3 = businessPayloadHash(
      recipientId: "northline-studio",
      amountMinor: 2600,
      method: .card,
      note: "test note",
      scenario: .success
    )
    if h1 != h3 {
      print("  ✓ businessPayloadHash differs when amount changes")
      passed += 1
    } else {
      print("  ✗ businessPayloadHash should differ on amount change")
      failed += 1
    }

    // CHECK 28: businessPayloadHash is 64-char hex
    print("28. businessPayloadHash is 64-char hex...")
    let h4 = businessPayloadHash(
      recipientId: "rec",
      amountMinor: 100,
      method: .bank,
      note: "",
      scenario: .success
    )
    let isHex = h4.count == 64 && h4.allSatisfy { "0123456789abcdef".contains($0) }
    if isHex {
      print("  ✓ businessPayloadHash is 64-char lowercase hex")
      passed += 1
    } else {
      print("  ✗ businessPayloadHash has unexpected format: \(h4)")
      failed += 1
    }

    // CHECK 29: PaymentIntentSnapshot stores returnState
    print("29. PaymentIntentSnapshot stores returnState...")
    let bankState = BankState(version: 2, balance: 950000, transactions: [], budgets: [])
    let snapWithState = PaymentIntentSnapshot(
      paymentIntentId: "pi-005",
      idempotencyKey: "idem-005",
      businessPayloadHash: "deadbeef",
      status: .completed,
      returnState: bankState,
      createdAt: "2026-09-29T12:00:00Z",
      resolvedAt: "2026-09-29T12:00:05Z"
    )
    if snapWithState.returnState?.balance == 950000 {
      print("  ✓ returnState preserved in snapshot")
      passed += 1
    } else {
      print("  ✗ returnState not preserved")
      failed += 1
    }

    // CHECK 30: PaymentIntentStore can be instantiated
    print("30. PaymentIntentStore instantiation...")
    let _ = PaymentIntentStore()
    print("  ✓ PaymentIntentStore() initialised")
    passed += 1

    // Summary
    print("\n=== Results ===")
    print("Passed: \(passed)/30")
    print("Failed: \(failed)/30")

    if failed > 0 {
      exit(1)
    }
  }
}
