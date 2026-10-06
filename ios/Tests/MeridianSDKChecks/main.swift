import CryptoKit
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

    // CHECK 21: SCA stub - always succeed
    print("21. SCA AlwaysSucceedSCAHandler...")
    let scaSucceed = AlwaysSucceedSCAHandler()
    let scaResult21 = await scaSucceed.authenticate(challenge: .any(reason: "Confirm payment"))
    if case .success = scaResult21 {
      print("  ✓ AlwaysSucceedSCAHandler returned .success")
      passed += 1
    } else {
      print("  ✗ Expected .success, got: \(scaResult21)")
      failed += 1
    }

    // CHECK 22: SCA stub - always fail
    print("22. SCA AlwaysFailSCAHandler...")
    let scaFail = AlwaysFailSCAHandler(reason: "Test failure")
    let scaResult22 = await scaFail.authenticate(challenge: .biometric(reason: "Confirm payment"))
    if case let .failed(reason) = scaResult22, reason == "Test failure" {
      print("  ✓ AlwaysFailSCAHandler returned .failed(\"Test failure\")")
      passed += 1
    } else {
      print("  ✗ Expected .failed(\"Test failure\"), got: \(scaResult22)")
      failed += 1
    }

    // CHECK 23: SCA stub - always cancel
    print("23. SCA AlwaysCancelSCAHandler...")
    let scaCancel = AlwaysCancelSCAHandler()
    let scaResult23 = await scaCancel.authenticate(challenge: .pin(reason: "Enter PIN"))
    if case .cancelled = scaResult23 {
      print("  ✓ AlwaysCancelSCAHandler returned .cancelled")
      passed += 1
    } else {
      print("  ✗ Expected .cancelled, got: \(scaResult23)")
      failed += 1
    }

    // CHECK 24: ReturnStateToken round-trip
    print("24. ReturnStateToken round-trip...")
    do {
      let keyData = Data(SHA256.hash(data: Data("test-session".utf8)))
      let key = SymmetricKey(data: keyData)
      let token = try ReturnStateToken.generate(paymentId: "pay-001", signingKey: key)
      let payload = try ReturnStateToken.verify(token: token, signingKey: key)
      if payload.paymentId == "pay-001" && !payload.nonce.isEmpty {
        print("  ✓ Token round-trip: paymentId=\(payload.paymentId)")
        passed += 1
      } else {
        print("  ✗ Payload mismatch: \(payload)")
        failed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 25: ReturnStateToken rejects wrong key
    print("25. ReturnStateToken rejects wrong signing key...")
    do {
      let keyA = SymmetricKey(data: Data(SHA256.hash(data: Data("session-A".utf8))))
      let keyB = SymmetricKey(data: Data(SHA256.hash(data: Data("session-B".utf8))))
      let token = try ReturnStateToken.generate(paymentId: "pay-X", signingKey: keyA)
      do {
        _ = try ReturnStateToken.verify(token: token, signingKey: keyB)
        print("  ✗ Should have rejected mismatched key")
        failed += 1
      } catch HandoffError.invalidReturnState {
        print("  ✓ Token correctly rejected mismatched signing key")
        passed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 26: ReturnStateToken rejects malformed token
    print("26. ReturnStateToken rejects malformed token...")
    do {
      let key = SymmetricKey(data: Data(SHA256.hash(data: Data("session".utf8))))
      do {
        _ = try ReturnStateToken.verify(token: "nodothere", signingKey: key)
        print("  ✗ Should have rejected token with no separator")
        failed += 1
      } catch HandoffError.invalidReturnState {
        print("  ✓ Malformed token correctly rejected")
        passed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 27: ReturnStateValidator accepts valid token
    print("27. ReturnStateValidator accepts valid token...")
    do {
      let key = SymmetricKey(data: Data(SHA256.hash(data: Data("test-session".utf8))))
      let token = try ReturnStateToken.generate(paymentId: "pay-valid", signingKey: key)
      let validator = ReturnStateValidator(signingKey: key, tokenTTL: 300)
      let payload = try await validator.validate(token: token)
      if payload.paymentId == "pay-valid" {
        print("  ✓ Validator accepted fresh token: paymentId=\(payload.paymentId)")
        passed += 1
      } else {
        print("  ✗ Payload mismatch: \(payload)")
        failed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 28: ReturnStateValidator rejects expired token
    print("28. ReturnStateValidator rejects expired token...")
    do {
      let key = SymmetricKey(data: Data(SHA256.hash(data: Data("test-session".utf8))))
      let oldPayload = ReturnStatePayload(
        paymentId: "pay-old",
        issuedAt: Int64(Date().timeIntervalSince1970) - 601,
        nonce: UUID().uuidString
      )
      let token = try ReturnStateToken.sign(payload: oldPayload, signingKey: key)
      let validator = ReturnStateValidator(signingKey: key, tokenTTL: 300)
      do {
        _ = try await validator.validate(token: token)
        print("  ✗ Should have rejected expired token")
        failed += 1
      } catch HandoffError.expiredReturnState {
        print("  ✓ Expired token correctly rejected")
        passed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 29: ReturnStateValidator rejects replayed token
    print("29. ReturnStateValidator rejects replayed token...")
    do {
      let key = SymmetricKey(data: Data(SHA256.hash(data: Data("test-session".utf8))))
      let token = try ReturnStateToken.generate(paymentId: "pay-replay", signingKey: key)
      let validator = ReturnStateValidator(signingKey: key, tokenTTL: 300)
      _ = try await validator.validate(token: token)
      do {
        _ = try await validator.validate(token: token)
        print("  ✗ Should have rejected replayed token")
        failed += 1
      } catch HandoffError.replayedReturnState {
        print("  ✓ Replayed token correctly rejected")
        passed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 30: BankHandoffManager builds handoff URL
    print("30. BankHandoffManager builds handoff URL...")
    do {
      let manager = BankHandoffManager(sessionId: "room-test")
      let bankURL = URL(string: "https://secure.worldpay.com/checkout")!
      let url = try await manager.buildHandoffURL(bankURL: bankURL, paymentId: "pay-wpy", returnScheme: "meridian")
      if url.absoluteString.contains("returnState=") && url.absoluteString.contains("returnScheme=meridian") {
        print("  ✓ Handoff URL built: host=\(url.host ?? "?")")
        passed += 1
      } else {
        print("  ✗ URL missing expected params: \(url)")
        failed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 31: BankHandoffManager rejects HTTP URL
    print("31. BankHandoffManager rejects HTTP (non-HTTPS) URL...")
    do {
      let manager = BankHandoffManager(sessionId: "room-test")
      let bankURL = URL(string: "http://secure.worldpay.com/checkout")!
      do {
        _ = try await manager.buildHandoffURL(bankURL: bankURL, paymentId: "pay-x", returnScheme: "meridian")
        print("  ✗ Should have rejected HTTP URL")
        failed += 1
      } catch HandoffError.disallowedURL {
        print("  ✓ HTTP URL correctly rejected")
        passed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 32: BankHandoffManager rejects non-allowlisted host
    print("32. BankHandoffManager rejects non-allowlisted host...")
    do {
      let manager = BankHandoffManager(sessionId: "room-test")
      let bankURL = URL(string: "https://evil.example.com/steal")!
      do {
        _ = try await manager.buildHandoffURL(bankURL: bankURL, paymentId: "pay-x", returnScheme: "meridian")
        print("  ✗ Should have rejected non-allowlisted host")
        failed += 1
      } catch HandoffError.disallowedURL {
        print("  ✓ Non-allowlisted host correctly rejected")
        passed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 33: BankHandoffManager handles return URL (round-trip)
    print("33. BankHandoffManager handles return URL (full round-trip)...")
    do {
      let manager = BankHandoffManager(sessionId: "room-test")
      let bankURL = URL(string: "https://secure.worldpay.com/checkout")!
      let handoffURL = try await manager.buildHandoffURL(bankURL: bankURL, paymentId: "pay-return", returnScheme: "meridian")
      // Simulate bank redirecting back with the same returnState.
      let components = URLComponents(url: handoffURL, resolvingAgainstBaseURL: false)!
      let returnState = components.queryItems!.first { $0.name == "returnState" }!.value!
      let returnURL = URL(string: "meridian://payment/return?returnState=\(returnState)")!
      let payload = try await manager.handleReturnURL(returnURL)
      if payload.paymentId == "pay-return" {
        print("  ✓ Return URL validated: paymentId=\(payload.paymentId)")
        passed += 1
      } else {
        print("  ✗ Payload mismatch: \(payload)")
        failed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 34: BankHandoffManager rejects missing returnState
    print("34. BankHandoffManager rejects missing returnState param...")
    do {
      let manager = BankHandoffManager(sessionId: "room-test")
      let returnURL = URL(string: "meridian://payment/return?status=ok")!
      do {
        _ = try await manager.handleReturnURL(returnURL)
        print("  ✗ Should have rejected URL with no returnState")
        failed += 1
      } catch HandoffError.missingReturnState {
        print("  ✓ Missing returnState correctly rejected")
        passed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 35: BankHandoffManager rejects cross-session return state
    print("35. BankHandoffManager rejects return state from different session...")
    do {
      let managerA = BankHandoffManager(sessionId: "session-A")
      let managerB = BankHandoffManager(sessionId: "session-B")
      let bankURL = URL(string: "https://secure.worldpay.com/checkout")!
      let handoffURL = try await managerA.buildHandoffURL(bankURL: bankURL, paymentId: "pay-x", returnScheme: "meridian")
      let components = URLComponents(url: handoffURL, resolvingAgainstBaseURL: false)!
      let returnState = components.queryItems!.first { $0.name == "returnState" }!.value!
      let returnURL = URL(string: "meridian://payment/return?returnState=\(returnState)")!
      do {
        _ = try await managerB.handleReturnURL(returnURL)
        print("  ✗ Should have rejected cross-session token")
        failed += 1
      } catch HandoffError.invalidReturnState {
        print("  ✓ Cross-session token correctly rejected")
        passed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 36: BankHandoffManager rejects replayed return URL
    print("36. BankHandoffManager rejects replayed return URL...")
    do {
      let manager = BankHandoffManager(sessionId: "room-replay")
      let bankURL = URL(string: "https://checkout.adyen.com/pay")!
      let handoffURL = try await manager.buildHandoffURL(bankURL: bankURL, paymentId: "pay-rpl", returnScheme: "meridian")
      let components = URLComponents(url: handoffURL, resolvingAgainstBaseURL: false)!
      let returnState = components.queryItems!.first { $0.name == "returnState" }!.value!
      let returnURL = URL(string: "meridian://payment/return?returnState=\(returnState)")!
      // First call succeeds.
      _ = try await manager.handleReturnURL(returnURL)
      // Second call must fail.
      do {
        _ = try await manager.handleReturnURL(returnURL)
        print("  ✗ Should have rejected replayed return URL")
        failed += 1
      } catch HandoffError.replayedReturnState {
        print("  ✓ Replayed return URL correctly rejected")
        passed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 37: BankHandoffManager rejects expired return URL
    print("37. BankHandoffManager rejects expired return URL...")
    do {
      let sessionId = "room-expiry"
      let keyData = Data(SHA256.hash(data: Data(sessionId.utf8)))
      let key = SymmetricKey(data: keyData)
      let oldPayload = ReturnStatePayload(
        paymentId: "pay-exp",
        issuedAt: Int64(Date().timeIntervalSince1970) - 601,
        nonce: UUID().uuidString
      )
      let token = try ReturnStateToken.sign(payload: oldPayload, signingKey: key)
      let manager = BankHandoffManager(sessionId: sessionId, tokenTTL: 300)
      let returnURL = URL(string: "meridian://payment/return?returnState=\(token)")!
      do {
        _ = try await manager.handleReturnURL(returnURL)
        print("  ✗ Should have rejected expired return URL")
        failed += 1
      } catch HandoffError.expiredReturnState {
        print("  ✓ Expired return URL correctly rejected")
        passed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 38: HandoffError descriptions are non-empty
    print("38. HandoffError descriptions are non-empty...")
    let errors: [HandoffError] = [
      .disallowedURL("https://evil.com"),
      .invalidReturnState("bad sig"),
      .expiredReturnState,
      .replayedReturnState,
      .missingReturnState,
    ]
    let allHaveDescriptions = errors.allSatisfy { ($0.errorDescription ?? "").isEmpty == false }
    if allHaveDescriptions {
      print("  ✓ All HandoffError cases have non-empty descriptions")
      passed += 1
    } else {
      print("  ✗ One or more HandoffError cases have empty descriptions")
      failed += 1
    }

    // CHECK 39: SCA challenge reason is accessible
    print("39. SCA challenge reason accessors...")
    let challenges: [SCAChallenge] = [
      .biometric(reason: "bio-reason"),
      .pin(reason: "pin-reason"),
      .any(reason: "any-reason"),
    ]
    let allHaveReason = challenges.allSatisfy { !$0.reason.isEmpty }
    if allHaveReason {
      print("  ✓ All SCAChallenge cases expose a non-empty reason")
      passed += 1
    } else {
      print("  ✗ One or more SCAChallenge cases returned an empty reason")
      failed += 1
    }

    // CHECK 40: Adyen host accepted in BankHandoffManager allowlist
    print("40. BankHandoffManager accepts Adyen allowlisted host...")
    do {
      let manager = BankHandoffManager(sessionId: "adyen-session")
      let bankURL = URL(string: "https://live.adyen.com/hpp/pay.shtml")!
      let url = try await manager.buildHandoffURL(bankURL: bankURL, paymentId: "pay-adyen", returnScheme: "meridian")
      if url.host == "live.adyen.com" && url.absoluteString.contains("returnState=") {
        print("  ✓ Adyen host accepted; returnState attached")
        passed += 1
      } else {
        print("  ✗ Unexpected URL: \(url)")
        failed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // Summary
    let total = 40
    print("\n=== Results ===")
    print("Passed: \(passed)/\(total)")
    print("Failed: \(failed)/\(total)")

    if failed > 0 {
      exit(1)
    }
  }
}
