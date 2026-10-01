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

    runCustomerAuthenticationChecks(passed: &passed, failed: &failed)

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

private func checkAuth(_ title: String, passed: inout Int, failed: inout Int, _ body: () -> String?) {
  let number = passed + failed + 1
  print("\(number). \(title)...")
  if let problem = body() {
    print("  ✗ \(problem)")
    failed += 1
  } else {
    print("  ✓")
    passed += 1
  }
}

private func stateToken(in url: URL) -> String? {
  URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value
}

private func runCustomerAuthenticationChecks(passed: inout Int, failed: inout Int) {
  let binding = "idempotency-key-do-not-leak"
  let secret = Data(repeating: 7, count: 32)

  checkAuth("issued state is opaque and valid", passed: &passed, failed: &failed) {
    let signer = ReturnStateSigner(secret: secret)
    let token = signer.issue(binding: binding)
    if token.contains(binding) || token.contains("northline") || token.contains("2599") || token.contains("adyen") {
      return "token leaked payment details"
    }
    guard case .accepted = signer.validate(token: token, binding: binding) else { return "valid token rejected" }
    return nil
  }

  checkAuth("tampered signature or binding is invalid", passed: &passed, failed: &failed) {
    let signer = ReturnStateSigner(secret: secret)
    let token = signer.issue(binding: binding)
    let parts = token.split(separator: ".").map(String.init)
    guard parts.count == 4, let first = parts[3].first else { return "unexpected token shape" }
    let flipped = first == Character("A") ? Character("B") : Character("A")
    let tampered = "\(parts[0]).\(parts[1]).\(parts[2]).\(flipped)\(parts[3].dropFirst())"
    guard case .rejected(.invalid) = signer.validate(token: tampered, binding: binding) else { return "tampered token accepted" }
    guard case .rejected(.invalid) = signer.validate(token: token, binding: "other-binding") else { return "wrong binding accepted" }
    guard case .accepted = signer.validate(token: token, binding: binding) else { return "original token was consumed" }
    return nil
  }

  checkAuth("expired return stays expired", passed: &passed, failed: &failed) {
    let clock = ManualClock(1_700_000_000)
    let signer = ReturnStateSigner(secret: secret, ttl: 300, clock: { clock.date }, random: { _ in Data(repeating: 9, count: 16) })
    let token = signer.issue(binding: binding)
    clock.date = Date(timeIntervalSince1970: 1_700_000_300)
    guard case .rejected(.expired) = signer.validate(token: token, binding: binding) else { return "expected expiry" }
    guard case .rejected(.expired) = signer.validate(token: token, binding: binding) else { return "repeat should stay expired" }
    return nil
  }

  checkAuth("accepted return is single use", passed: &passed, failed: &failed) {
    let signer = ReturnStateSigner(secret: secret)
    let token = signer.issue(binding: binding)
    guard case .accepted = signer.validate(token: token, binding: binding) else { return "first use failed" }
    guard case .rejected(.replayed) = signer.validate(token: token, binding: binding) else { return "replay was accepted" }
    return nil
  }

  checkAuth("handoff URL stays on the allowlisted host", passed: &passed, failed: &failed) {
    guard let url = BankAllowlist.handoffURL(stateToken: "v1.nonce.1700000300.sig") else { return "missing handoff URL" }
    guard url.scheme == "https", url.host == BankAllowlist.bankHost, BankAllowlist.permitsHandoff(url) else { return "handoff was not allowlisted" }
    guard !url.absoluteString.contains(binding) else { return "binding leaked into the URL" }
    guard stateToken(in: url) == "v1.nonce.1700000300.sig" else { return "state did not round-trip" }
    return nil
  }

  checkAuth("disallowed bank URLs are not opened", passed: &passed, failed: &failed) {
    let blocked = [
      "http://bank.worldpay.rehearsal.meridian.example/open-banking/authorize?state=abc&redirect_uri=https://app.meridian.example/bank/return",
      "https://user:pass@bank.worldpay.rehearsal.meridian.example/open-banking/authorize?state=abc&redirect_uri=https://app.meridian.example/bank/return",
      "https://bank.worldpay.rehearsal.meridian.example.evil.com/open-banking/authorize?state=abc&redirect_uri=https://app.meridian.example/bank/return",
      "https://evil.example/open-banking/authorize?state=abc&redirect_uri=https://app.meridian.example/bank/return",
      "https://bank.worldpay.rehearsal.meridian.example:8443/open-banking/authorize?state=abc&redirect_uri=https://app.meridian.example/bank/return",
      "https://bank.worldpay.rehearsal.meridian.example/open-banking/authorize?state=abc&redirect_uri=https://evil.example/bank/return",
    ]
    for raw in blocked {
      guard let url = URL(string: raw) else { return "unparseable \(raw)" }
      var opened = 0
      if BankAllowlist.openIfAllowlisted(url, open: { _ in opened += 1; return true }) || opened != 0 {
        return "opened \(raw)"
      }
    }
    return nil
  }

  checkAuth("return listener accepts only the app link", passed: &passed, failed: &failed) {
    let token = "v1.nonce.1700000300.sig"
    guard let link = BankAllowlist.returnURL(stateToken: token) else { return "missing return URL" }
    guard case .token(let parsed) = BankAllowlist.intercept(link), parsed == token else { return "return state mismatch" }
    guard var slash = URLComponents(url: link, resolvingAgainstBaseURL: false) else { return "components failed" }
    slash.path = "/bank/return/"
    guard let slashed = slash.url, case .token(let slashedToken) = BankAllowlist.intercept(slashed), slashedToken == token else {
      return "trailing slash was rejected"
    }
    guard case .missingState = BankAllowlist.intercept(URL(string: "https://app.meridian.example/bank/return")!) else { return "missing state" }
    guard case .notReturnLink = BankAllowlist.intercept(URL(string: "https://evil.example/bank/return?state=\(token)")!) else { return "foreign host accepted" }
    guard case .notReturnLink = BankAllowlist.intercept(URL(string: "http://app.meridian.example/bank/return?state=\(token)")!) else { return "http return accepted" }
    return nil
  }

  checkAuth("invalid, expired, and replayed returns do not submit", passed: &passed, failed: &failed) {
    let clock = ManualClock(1_700_000_000)
    let signer = ReturnStateSigner(secret: secret, clock: { clock.date })
    let attempt = PaymentAttempt(idempotencyKey: binding, method: .bank, signer: signer, enrolledPin: "135790")
    guard let opened = attempt.startHandoff(open: { _ in true }), let token = stateToken(in: opened), let returnURL = BankAllowlist.returnURL(stateToken: token) else {
      return "handoff did not open"
    }
    var submitted: [String] = []
    guard case .safeFailure(.missing, binding) = attempt.resumeAfterReturn(URL(string: "https://app.meridian.example/bank/return")!, submit: { submitted.append($0) }) else {
      return "missing state submitted"
    }
    guard case .safeFailure(.invalid, _) = attempt.resumeAfterReturn(URL(string: "https://app.meridian.example/bank/return?state=v1.bad.1.bad")!, submit: { submitted.append($0) }) else {
      return "invalid state submitted"
    }
    clock.date = Date(timeIntervalSince1970: 1_700_000_301)
    guard case .safeFailure(.expired, binding) = attempt.resumeAfterReturn(returnURL, submit: { submitted.append($0) }) else {
      return "expired state submitted"
    }
    if !submitted.isEmpty || attempt.idempotencyKey != binding || attempt.method != .bank || attempt.submitIfCleared({ submitted.append($0) }) {
      return "payment was recreated"
    }
    let fresh = PaymentAttempt(idempotencyKey: binding, method: .bank, signer: ReturnStateSigner(secret: secret), enrolledPin: "135790")
    guard let live = fresh.startHandoff(open: { _ in true }), let liveToken = stateToken(in: live), let liveReturn = BankAllowlist.returnURL(stateToken: liveToken) else {
      return "second handoff failed"
    }
    guard case .cleared(binding) = fresh.resumeAfterReturn(liveReturn, submit: { submitted.append($0) }) else { return "valid return did not clear" }
    guard case .safeFailure(.replayed, binding) = fresh.resumeAfterReturn(liveReturn, submit: { submitted.append($0) }) else { return "replay cleared again" }
    if submitted != [binding] { return "submitted \(submitted)" }
    return nil
  }

  checkAuth("superseded return cannot create a second payment", passed: &passed, failed: &failed) {
    let attempt = PaymentAttempt(idempotencyKey: binding, method: .bank, signer: ReturnStateSigner(secret: secret), enrolledPin: "")
    guard let first = attempt.startHandoff(open: { _ in true }), let second = attempt.startHandoff(open: { _ in true }), first != second else {
      return "expected two handoffs"
    }
    var submitted: [String] = []
    guard let firstToken = stateToken(in: first), let firstReturn = BankAllowlist.returnURL(stateToken: firstToken) else { return "first state missing" }
    guard case .safeFailure = attempt.resumeAfterReturn(firstReturn, submit: { submitted.append($0) }) else { return "stale return cleared" }
    guard let secondToken = stateToken(in: second), let secondReturn = BankAllowlist.returnURL(stateToken: secondToken) else { return "second state missing" }
    guard case .cleared(binding) = attempt.resumeAfterReturn(secondReturn, submit: { submitted.append($0) }) else { return "current return failed" }
    if submitted != [binding] || attempt.method != .bank { return "wrong submission \(submitted)" }
    return nil
  }

  checkAuth("opener refusal does not arm a return", passed: &passed, failed: &failed) {
    let attempt = PaymentAttempt(idempotencyKey: binding, method: .bank, signer: ReturnStateSigner(secret: secret), enrolledPin: "")
    var opened = 0
    if attempt.startHandoff(open: { _ in opened += 1; return false }) != nil || opened != 1 || attempt.rehearsalReturnURL() != nil {
      return "refused handoff stayed armed"
    }
    var submitted = 0
    if attempt.submitIfCleared({ _ in submitted += 1 }) || submitted != 0 { return "refused handoff submitted" }
    return nil
  }

  checkAuth("card payment requires biometric or PIN", passed: &passed, failed: &failed) {
    let attempt = PaymentAttempt(idempotencyKey: binding, method: .card, signer: ReturnStateSigner(secret: secret), enrolledPin: "135790")
    var opened = 0
    var submitted: [String] = []
    if attempt.startHandoff(open: { _ in opened += 1; return true }) != nil || opened != 0 { return "card opened a bank" }
    if attempt.submitIfCleared({ submitted.append($0) }) { return "card submitted without SCA" }
    guard case .rejected = attempt.resumeAfterSca(biometricAccepted: false, enteredPin: "", submit: { submitted.append($0) }) else { return "empty PIN confirmed" }
    guard case .rejected = attempt.resumeAfterSca(biometricAccepted: false, enteredPin: "135791", submit: { submitted.append($0) }) else { return "wrong PIN confirmed" }
    let shortPin = PaymentAttempt(idempotencyKey: binding, method: .card, signer: ReturnStateSigner(secret: secret), enrolledPin: "123")
    guard case .rejected = shortPin.resumeAfterSca(biometricAccepted: false, enteredPin: "123", submit: { submitted.append($0) }) else { return "short PIN confirmed" }
    if !submitted.isEmpty || attempt.idempotencyKey != binding { return "failed SCA submitted" }
    guard case .confirmed(.biometric) = attempt.resumeAfterSca(biometricAccepted: true, enteredPin: "", submit: { submitted.append($0) }) else { return "biometric rejected" }
    guard case .confirmed(.biometric) = attempt.resumeAfterSca(biometricAccepted: true, enteredPin: "", submit: { submitted.append($0) }) else { return "second biometric changed the decision" }
    if submitted != [binding] { return "biometric submitted \(submitted)" }
    let pinAttempt = PaymentAttempt(idempotencyKey: binding, method: .card, signer: ReturnStateSigner(secret: secret), enrolledPin: "135790")
    guard case .confirmed(.pin) = pinAttempt.resumeAfterSca(biometricAccepted: false, enteredPin: "135790", submit: { submitted.append($0) }) else { return "PIN rejected" }
    if submitted != [binding, binding] { return "PIN submitted \(submitted)" }
    return nil
  }

  checkAuth("uncertain retry keeps the same key", passed: &passed, failed: &failed) {
    let attempt = PaymentAttempt(idempotencyKey: binding, method: .card, signer: ReturnStateSigner(secret: secret), enrolledPin: "135790")
    var keys: [String] = []
    _ = attempt.resumeAfterSca(biometricAccepted: true, enteredPin: "", submit: { keys.append($0) })
    attempt.releaseForRetry()
    if !attempt.canRetry || !attempt.submitIfCleared({ keys.append($0) }) || keys != [binding, binding] { return "retry changed the key \(keys)" }
    attempt.markCompleted()
    if attempt.submitIfCleared({ keys.append($0) }) || keys.count != 2 { return "completed payment submitted again" }
    return nil
  }

  checkAuth("bank return does not clear through SCA", passed: &passed, failed: &failed) {
    let attempt = PaymentAttempt(idempotencyKey: binding, method: .bank, signer: ReturnStateSigner(secret: secret), enrolledPin: "135790")
    var submitted = 0
    guard case .notRequired = attempt.resumeAfterSca(biometricAccepted: true, enteredPin: "135790", submit: { _ in submitted += 1 }) else {
      return "bank SCA cleared the payment"
    }
    if submitted != 0 || attempt.method != .bank { return "bank SCA submitted" }
    return nil
  }

  checkAuth("ignored link does not submit", passed: &passed, failed: &failed) {
    let attempt = PaymentAttempt(idempotencyKey: binding, method: .bank, signer: ReturnStateSigner(secret: secret), enrolledPin: "")
    _ = attempt.startHandoff(open: { _ in true })
    var submitted = 0
    guard case .ignored = attempt.resumeAfterReturn(URL(string: "https://example.com/bank/return?state=v1.a.1.b")!, submit: { _ in submitted += 1 }) else {
      return "foreign link was handled as a return"
    }
    if submitted != 0 || attempt.idempotencyKey != binding { return "foreign link submitted" }
    return nil
  }
}

private final class ManualClock {
  var date: Date
  init(_ seconds: TimeInterval) { date = Date(timeIntervalSince1970: seconds) }
}
