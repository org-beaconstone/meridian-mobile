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

    let draft = InFlightPaymentDraft(
      recipientId: "northline-studio",
      amount: "18.50",
      reference: "Studio materials",
      method: .card,
      reviewing: true,
      idempotencyKey: "pay-key-114"
    )
    let fiveMinutes: Int64 = SessionBanner.expiringWindowMs

    // CHECK 21: connected copy and non-blocking active state
    print("21. Session banner active copy...")
    let active = SessionBanner.present(nowMs: 0, expiresAtMs: fiveMinutes + 1, activeElsewhere: false)
    if active.state == .active
      && active.message == "Connected to secure payments platform"
      && active.accessibilityLabel == active.message
      && !active.blocksInteraction
      && active.extendActionLabel == nil
      && active.meetsWcagAa()
    {
      print("  ✓ Active banner uses the approved copy and stays non-blocking")
      passed += 1
    } else {
      print("  ✗ Active banner mismatch: \(active.message)")
      failed += 1
    }

    // CHECK 22: expiring soon at the five-minute boundary
    print("22. Session banner expiring soon...")
    let expiring = SessionBanner.present(nowMs: 1_000, expiresAtMs: 1_000 + fiveMinutes, activeElsewhere: false)
    if expiring.state == .expiringSoon
      && expiring.message == "Session expiring soon. Tap to extend."
      && expiring.extendActionLabel == "Tap to extend"
      && !expiring.blocksInteraction
      && expiring.minimumTapTargetPoints >= 48
      && expiring.meetsWcagAa()
    {
      print("  ✓ Expiring banner is an amber non-blocking extend action")
      passed += 1
    } else {
      print("  ✗ Expiring banner mismatch: \(expiring.message)")
      failed += 1
    }

    // CHECK 23: active on another device
    print("23. Session banner active elsewhere...")
    let elsewhere = SessionBanner.present(nowMs: 0, expiresAtMs: fiveMinutes + 60_000, activeElsewhere: true)
    if elsewhere.state == .activeElsewhere
      && elsewhere.message == "Session active on another device."
      && !elsewhere.blocksInteraction
      && elsewhere.extendActionLabel == nil
      && elsewhere.meetsWcagAa()
    {
      print("  ✓ Elsewhere banner stays non-blocking")
      passed += 1
    } else {
      print("  ✗ Elsewhere banner mismatch: \(elsewhere.message)")
      failed += 1
    }

    // CHECK 24: expired blocks and uses approved copy
    print("24. Session banner expired...")
    let expired = SessionBanner.present(nowMs: 5_000, expiresAtMs: 5_000, activeElsewhere: true)
    if expired.state == .expired
      && expired.message == "Session expired. Please re-authenticate to confirm this transfer."
      && expired.blocksInteraction
      && expired.reauthenticateActionLabel == "Re-authenticate"
      && expired.meetsWcagAa()
    {
      print("  ✓ Expired banner blocks interaction and asks for re-authentication")
      passed += 1
    } else {
      print("  ✗ Expired banner mismatch: \(expired.message)")
      failed += 1
    }

    // CHECK 25: extend keeps the in-flight draft and payment key
    print("25. Extend keeps in-flight payment draft...")
    let extended = SessionRefresh.extend(nowMs: 50_000, draft: draft, activeElsewhere: false)
    if extended.draft == draft
      && extended.draft.method == .card
      && extended.draft.idempotencyKey == "pay-key-114"
      && extended.draft.reviewing
      && extended.expiresAtMs == 50_000 + SessionBanner.defaultDurationMs
      && extended.presentation.state == .active
    {
      print("  ✓ Extend refreshes the session without changing payment details")
      passed += 1
    } else {
      print("  ✗ Extend changed the draft or failed to renew the session")
      failed += 1
    }

    // CHECK 26: failed refresh retains expiry, key, and method
    print("26. Uncertain refresh retains session and draft...")
    let retained = SessionRefresh.retain(
      nowMs: 90_000,
      expiresAtMs: 90_000 + 60_000,
      activeElsewhere: false,
      draft: draft
    )
    if retained.draft == draft
      && retained.draft.method == .card
      && retained.draft.idempotencyKey == "pay-key-114"
      && retained.expiresAtMs == 150_000
      && retained.presentation.state == .expiringSoon
    {
      print("  ✓ Failed refresh keeps the payment key and does not extend expiry")
      passed += 1
    } else {
      print("  ✗ Failed refresh changed expiry or draft")
      failed += 1
    }

    // CHECK 27: re-authenticate keeps the transfer draft
    print("27. Re-authenticate keeps transfer draft...")
    let reauthed = SessionRefresh.reauthenticate(nowMs: 10_000, draft: draft)
    if reauthed.draft == draft
      && !reauthed.activeElsewhere
      && reauthed.presentation.state == .active
      && !reauthed.presentation.blocksInteraction
    {
      print("  ✓ Re-authenticate opens a fresh window and keeps the transfer")
      passed += 1
    } else {
      print("  ✗ Re-authenticate changed the draft")
      failed += 1
    }

    // CHECK 28: contrast helper matches black on white
    print("28. WCAG contrast helper...")
    let black = SessionColor(token: "color.black", red: 0, green: 0, blue: 0)
    let white = SessionColor(token: "color.white", red: 255, green: 255, blue: 255)
    let ratio = black.contrastRatio(against: white)
    if abs(ratio - 21.0) < 0.001 && active.contrastRatio() >= 4.5 {
      print("  ✓ Contrast helper reports 21:1 for black on white")
      passed += 1
    } else {
      print("  ✗ Unexpected contrast \(ratio)")
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
