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

    func expect(_ name: String, _ condition: Bool, _ detail: String) {
      let number = passed + failed + 1
      print("\(number). \(name)...")
      if condition {
        print("  ✓ \(detail)")
        passed += 1
      } else {
        print("  ✗ \(detail)")
        failed += 1
      }
    }

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let draft = PaymentDraft(
      recipientId: "northline-studio",
      amountText: "12.50",
      reference: "Studio deposit",
      method: .card,
      reviewing: true,
      idempotencyKey: "pay-key-1"
    )

    let active = presentSession(sessionForPhase(.active, now: now), now: now)
    expect("active session banner", active.phase == .active && active.tone == .success && active.action == nil && active.clockLabel == nil, active.title)

    let expiring = presentSession(sessionForPhase(.expiring, now: now), now: now)
    expect(
      "expiring session shows time and refresh",
      expiring.phase == .expiring && expiring.tone == .warning && expiring.action == .refresh
        && expiring.remainingSeconds == SessionTiming.previewExpiringSeconds
        && expiring.clockLabel == "1:30"
        && expiring.message.contains("1 minute 30 seconds remaining")
        && expiring.actionLabel == "Refresh session",
      expiring.message
    )

    let boundary = presentSession(
      .active(expiresAt: now.addingTimeInterval(TimeInterval(SessionTiming.expiringThresholdSeconds))),
      now: now
    )
    expect("threshold is expiring", boundary.phase == .expiring && boundary.clockLabel == "2:00", boundary.clockLabel ?? "")

    let stillActive = presentSession(
      .active(expiresAt: now.addingTimeInterval(TimeInterval(SessionTiming.expiringThresholdSeconds + 1))),
      now: now
    )
    expect("just outside threshold stays active", stillActive.phase == .active && stillActive.action == nil, stillActive.title)

    let oneSecond = presentSession(.active(expiresAt: now.addingTimeInterval(1)), now: now)
    expect("one second remaining", oneSecond.remainingSeconds == 1 && oneSecond.message.hasPrefix("1 second remaining") && oneSecond.clockLabel == "0:01", oneSecond.message)

    let derivedExpired = presentSession(.active(expiresAt: now), now: now)
    let explicitExpired = presentSession(.expired, now: now)
    expect(
      "elapsed active session presents as expired",
      derivedExpired.phase == .expired && derivedExpired.tone == .danger && derivedExpired.action == .signIn
        && derivedExpired.title == explicitExpired.title && derivedExpired.message == explicitExpired.message,
      derivedExpired.message
    )

    let elsewhere = presentSession(.activeElsewhere(deviceName: "  "), now: now)
    expect(
      "active elsewhere recovery",
      elsewhere.phase == .activeElsewhere && elsewhere.tone == .information && elsewhere.action == .continueHere
        && elsewhere.message.contains("another device"),
      elsewhere.message
    )

    let named = presentSession(.activeElsewhere(deviceName: "Meridian web"), now: now)
    expect("named other device", named.message.contains("Meridian web"), named.message)

    let signedOut = presentSession(.signedOut, now: now)
    expect(
      "signed out keeps payment context in guidance",
      signedOut.phase == .signedOut && signedOut.tone == .neutral && signedOut.action == .signIn
        && signedOut.message.contains("amount, recipient and reference"),
      signedOut.title
    )

    let unknown = presentSession(.unknown, now: now)
    expect(
      "unknown session recovery",
      unknown.phase == .unknown && unknown.tone == .attention && unknown.action == .tryAgain
        && unknown.message.contains("payment details stay on this screen"),
      unknown.title
    )

    let titles = SessionPhase.allCases.map { presentSession(sessionForPhase($0, now: now), now: now).title }
    let tones = SessionPhase.allCases.map { presentSession(sessionForPhase($0, now: now), now: now).tone }
    expect("distinct titles and tones", Set(titles).count == 6 && Set(tones).count == 6, titles.joined(separator: ", "))

    expect("remaining phrases", formatRemaining(0) == "0 seconds" && formatRemaining(2) == "2 seconds" && formatRemaining(60) == "1 minute" && formatRemaining(61) == "1 minute 1 second" && formatRemaining(120) == "2 minutes", formatRemaining(61))

    let refreshed = applySessionAction(session: sessionForPhase(.expiring, now: now), action: .refresh, now: now, apiReachable: true, payment: draft)
    expect(
      "refresh extends session and returns the same payment draft",
      refreshed.payment == draft && refreshed.announcement.contains("unchanged"),
      refreshed.announcement
    )
    if case let .active(expiresAt) = refreshed.session {
      expect("refresh expiry window", expiresAt == now.addingTimeInterval(TimeInterval(SessionTiming.lengthSeconds)), "\(expiresAt)")
    } else {
      expect("refresh expiry window", false, "session was not active")
    }

    let held = CustomerSession.active(expiresAt: now.addingTimeInterval(45))
    let failedRefresh = applySessionAction(session: held, action: .refresh, now: now, apiReachable: false, payment: draft)
    expect(
      "failed refresh keeps session and payment draft",
      failedRefresh.session == held && failedRefresh.payment == draft && failedRefresh.announcement.contains("still here"),
      failedRefresh.announcement
    )

    let signedIn = applySessionAction(session: .expired, action: .signIn, now: now, apiReachable: false, payment: draft)
    expect("sign in from expired keeps draft", signedIn.payment == draft && signedIn.announcement.contains("Payment details are unchanged"), signedIn.announcement)

    let continued = applySessionAction(session: .activeElsewhere(deviceName: "Meridian web"), action: .continueHere, now: now, apiReachable: false, payment: draft)
    expect("continue here keeps draft", continued.payment == draft, continued.announcement)

    let stillUnknown = applySessionAction(session: .unknown, action: .tryAgain, now: now, apiReachable: false, payment: draft)
    expect(
      "try again offline stays unknown without clearing draft",
      stillUnknown.session == .unknown && stillUnknown.payment == draft && stillUnknown.announcement.contains("still here"),
      stillUnknown.announcement
    )

    let confirmed = applySessionAction(session: .unknown, action: .tryAgain, now: now, apiReachable: true, payment: draft)
    expect("try again online confirms session and keeps draft", confirmed.payment == draft && confirmed.announcement.contains("unchanged"), confirmed.announcement)

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
