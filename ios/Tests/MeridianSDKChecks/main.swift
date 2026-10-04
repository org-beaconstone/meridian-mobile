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

    let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // CHECK 21: exactly five minutes stays active
    print("21. five minutes remaining stays active...")
    let activeUntil = epoch.addingTimeInterval(sessionWarningWindow)
    if case .banner(.active) = sessionPhase(presence: .here, expiresAt: activeUntil, now: epoch),
      !sessionRequiresReauthentication(presence: .here, expiresAt: activeUntil, now: epoch) {
      print("  ✓ exactly 5 minutes is active and does not block")
      passed += 1
    } else {
      print("  ✗ exactly 5 minutes should stay active")
      failed += 1
    }

    // CHECK 22: under five minutes is the amber warning copy
    print("22. under five minutes warns without blocking...")
    let expiringAt = epoch.addingTimeInterval(sessionWarningWindow - 1)
    let expiringCopy = sessionBannerCopy(.expiringSoon, remaining: 4 * 60)
    let expiringPalette = sessionBannerPalette(.expiringSoon)
    if case .banner(.expiringSoon) = sessionPhase(presence: .here, expiresAt: expiringAt, now: epoch),
      !sessionRequiresReauthentication(presence: .here, expiresAt: expiringAt, now: epoch),
      expiringCopy.message == sessionExpiringMessage,
      expiringCopy.accessibilityLabel == "Session expiring soon. Tap to extend. 4 minutes remaining.",
      expiringCopy.indicator == "warning",
      expiringPalette.backgroundToken == "color.background.warning",
      expiringPalette.foregroundToken == "color.text.warning" {
      print("  ✓ expiring banner is non-blocking amber warning copy")
      passed += 1
    } else {
      print("  ✗ expiring state mismatch")
      failed += 1
    }

    // CHECK 23: full expiry is the only blocking re-auth
    print("23. full expiry requires re-authentication...")
    let signedOut = sessionPhase(presence: .signedOut, expiresAt: epoch.addingTimeInterval(-60), now: epoch)
    if sessionRequiresReauthentication(presence: .here, expiresAt: epoch, now: epoch),
      sessionRequiresReauthentication(presence: .elsewhere, expiresAt: epoch, now: epoch),
      !sessionRequiresReauthentication(presence: .signedOut, expiresAt: epoch.addingTimeInterval(-60), now: epoch),
      signedOut == .banner(.signedOut) {
      print("  ✓ modal only after complete expiry")
      passed += 1
    } else {
      print("  ✗ re-authentication gate mismatch")
      failed += 1
    }

    // CHECK 24: active elsewhere and signed-out indicators
    print("24. elsewhere and signed-out banners...")
    let elsewhere = sessionPhase(presence: .elsewhere, expiresAt: epoch.addingTimeInterval(10 * 60), now: epoch)
    let elsewhereExpiring = sessionPhase(presence: .elsewhere, expiresAt: epoch.addingTimeInterval(60), now: epoch)
    if elsewhere == .banner(.activeElsewhere),
      elsewhereExpiring == .banner(.expiringSoon),
      sessionBannerCopy(.active).indicator == "check",
      sessionBannerCopy(.activeElsewhere).message == "Session active on another device.",
      sessionBannerCopy(.signedOut).message == "Signed out.",
      sessionBannerCopy(.signedOut).indicator == "signed-out" {
      print("  ✓ active, elsewhere, and signed-out copy")
      passed += 1
    } else {
      print("  ✗ session banner copy mismatch")
      failed += 1
    }

    // CHECK 25: refresh keeps the payment draft
    print("25. in-place refresh keeps the payment draft...")
    let draft = PaymentFormDraft(
      recipientId: "northline-studio",
      amount: "18.25",
      reference: "Studio rent",
      method: .bank,
      reviewing: true,
      idempotencyKey: "pay-key-171"
    )
    let refreshed = refreshSessionInPlace(
      draft: draft,
      session: PaymentSessionClock(presence: .elsewhere, expiresAt: epoch.addingTimeInterval(30)),
      now: epoch
    )
    if refreshed.draft == draft,
      refreshed.session.presence == .here,
      refreshed.session.expiresAt == epoch.addingTimeInterval(paymentSessionTtl),
      sessionPhase(presence: refreshed.session.presence, expiresAt: refreshed.session.expiresAt, now: epoch) == .banner(.active) {
      print("  ✓ refresh keeps amount, reference, method, review, and idempotency key")
      passed += 1
    } else {
      print("  ✗ refresh changed the payment draft")
      failed += 1
    }

    // CHECK 26: banner text contrast is at least 4.5:1
    print("26. banner contrast meets WCAG 2.1 AA...")
    let warningRatio = contrastRatio(foregroundHex: "#9E4C00", backgroundHex: "#FFF5DB")
    let palettesPass = SessionBannerState.allCases.allSatisfy { state in
      let palette = sessionBannerPalette(state)
      return contrastRatio(foregroundHex: palette.foregroundHex, backgroundHex: palette.backgroundHex) >= 4.5
    }
    if warningRatio >= 4.5 && warningRatio < 6 && palettesPass {
      print("  ✓ each banner foreground/background pair is at least 4.5:1")
      passed += 1
    } else {
      print("  ✗ contrast below 4.5:1 or formula drifted (\(warningRatio))")
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
