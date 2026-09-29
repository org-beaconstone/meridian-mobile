import CryptoKit
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

    // CHECK 21: SCAChallenge default type is biometric
    print("21. SCAChallenge default type is biometric...")
    let challenge21 = SCAChallenge(paymentId: "pay-001", amountMinor: 5000, recipientName: "Birch & Bloom")
    if challenge21.type == .biometric && challenge21.paymentId == "pay-001" && challenge21.amountMinor == 5000 {
      print("  ✓ SCAChallenge defaults to biometric")
      passed += 1
    } else {
      print("  ✗ SCAChallenge fields mismatch")
      failed += 1
    }

    // CHECK 22: SCAChallenge explicit pin type
    print("22. SCAChallenge explicit pin type...")
    let challenge22 = SCAChallenge(paymentId: "pay-002", amountMinor: 10000, recipientName: "Northline Studio", type: .pin)
    if challenge22.type == .pin {
      print("  ✓ SCAChallenge pin type set correctly")
      passed += 1
    } else {
      print("  ✗ SCAChallenge pin type mismatch")
      failed += 1
    }

    // CHECK 23: BankHandoff allowlist contains Worldpay domains
    print("23. BankHandoff allowlist contains Worldpay domains...")
    if BankHandoff.allowedHosts.contains("payments.worldpay.com") && BankHandoff.allowedHosts.contains("secure.worldpay.com") {
      print("  ✓ Worldpay domains present in allowlist")
      passed += 1
    } else {
      print("  ✗ Worldpay domains missing from allowlist")
      failed += 1
    }

    // CHECK 24: buildHandoffURL rejects HTTP scheme
    print("24. buildHandoffURL rejects HTTP scheme...")
    do {
      let key = SymmetricKey(data: Data(repeating: 0x42, count: 32))
      _ = try BankHandoff.buildHandoffURL(
        bankURL: URL(string: "http://payments.worldpay.com/auth")!,
        paymentId: "pay-001", returnURLScheme: "meridian", signingKey: key)
      print("  ✗ Should have rejected HTTP URL")
      failed += 1
    } catch BankHandoffError.domainNotAllowed {
      print("  ✓ HTTP URL correctly rejected")
      passed += 1
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 25: buildHandoffURL rejects unknown domain
    print("25. buildHandoffURL rejects unknown domain...")
    do {
      let key = SymmetricKey(data: Data(repeating: 0x42, count: 32))
      _ = try BankHandoff.buildHandoffURL(
        bankURL: URL(string: "https://evil.bank.example.com/auth")!,
        paymentId: "pay-001", returnURLScheme: "meridian", signingKey: key)
      print("  ✗ Should have rejected unknown domain")
      failed += 1
    } catch BankHandoffError.domainNotAllowed {
      print("  ✓ Unknown domain correctly rejected")
      passed += 1
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 26: buildHandoffURL produces URL with state and redirect_uri
    print("26. buildHandoffURL produces state and redirect_uri params...")
    do {
      let key = SymmetricKey(data: Data(repeating: 0x42, count: 32))
      let url = try BankHandoff.buildHandoffURL(
        bankURL: URL(string: "https://payments.worldpay.com/auth")!,
        paymentId: "pay-123", returnURLScheme: "meridian", signingKey: key)
      let urlStr = url.absoluteString
      if urlStr.contains("state=") && urlStr.contains("redirect_uri=") && urlStr.hasPrefix("https://payments.worldpay.com") {
        print("  ✓ Handoff URL has state and redirect_uri: \(url.host ?? "")")
        passed += 1
      } else {
        print("  ✗ Handoff URL missing required params: \(urlStr)")
        failed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 27: validateReturnURL succeeds with valid round-trip token
    print("27. validateReturnURL succeeds with valid token...")
    do {
      let key = SymmetricKey(data: Data(repeating: 0x7A, count: 32))
      let token = try BankHandoff.makeStateToken(paymentId: "pay-789", signingKey: key)
      let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
      let returnURL = URL(string: "meridian://payment/return?state=\(encoded)")!
      var nonces = Set<String>()
      let state27 = try BankHandoff.validateReturnURL(returnURL, signingKey: key, usedNonces: &nonces)
      if state27.paymentId == "pay-789" && nonces.count == 1 {
        print("  ✓ validateReturnURL succeeded: paymentId=\(state27.paymentId)")
        passed += 1
      } else {
        print("  ✗ ReturnState fields mismatch or nonce not recorded")
        failed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 28: validateReturnURL fails with tampered signature
    print("28. validateReturnURL fails with tampered signature...")
    do {
      let key = SymmetricKey(data: Data(repeating: 0x7A, count: 32))
      let token = try BankHandoff.makeStateToken(paymentId: "pay-tamper", signingKey: key)
      let parts = token.split(separator: ".", maxSplits: 1).map(String.init)
      let tampered = "\(parts[0]).AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
      let encoded = tampered.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tampered
      let returnURL = URL(string: "meridian://payment/return?state=\(encoded)")!
      var nonces = Set<String>()
      _ = try BankHandoff.validateReturnURL(returnURL, signingKey: key, usedNonces: &nonces)
      print("  ✗ Should have thrown invalidSignature")
      failed += 1
    } catch BankHandoffError.invalidSignature {
      print("  ✓ Tampered signature correctly rejected")
      passed += 1
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 29: validateReturnURL fails when token is expired
    print("29. validateReturnURL fails when expired...")
    do {
      let key = SymmetricKey(data: Data(repeating: 0x7A, count: 32))
      let token = try BankHandoff.makeStateToken(paymentId: "pay-exp", signingKey: key)
      let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
      let returnURL = URL(string: "meridian://payment/return?state=\(encoded)")!
      var nonces = Set<String>()
      // maxAgeSeconds = 0 forces expiry for any token
      _ = try BankHandoff.validateReturnURL(returnURL, signingKey: key, usedNonces: &nonces, maxAgeSeconds: 0)
      print("  ✗ Should have thrown tokenExpired")
      failed += 1
    } catch BankHandoffError.tokenExpired {
      print("  ✓ Expired token correctly rejected")
      passed += 1
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 30: validateReturnURL fails on replay (second use of same token)
    print("30. validateReturnURL fails on replay...")
    do {
      let key = SymmetricKey(data: Data(repeating: 0x7A, count: 32))
      let token = try BankHandoff.makeStateToken(paymentId: "pay-replay", signingKey: key)
      let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
      let returnURL = URL(string: "meridian://payment/return?state=\(encoded)")!
      var nonces = Set<String>()
      _ = try BankHandoff.validateReturnURL(returnURL, signingKey: key, usedNonces: &nonces)  // First: OK
      _ = try BankHandoff.validateReturnURL(returnURL, signingKey: key, usedNonces: &nonces)  // Second: replay
      print("  ✗ Should have thrown tokenReplayed")
      failed += 1
    } catch BankHandoffError.tokenReplayed {
      print("  ✓ Replayed token correctly rejected")
      passed += 1
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 31: validateReturnURL fails when state param is missing
    print("31. validateReturnURL fails with missing state param...")
    do {
      let key = SymmetricKey(data: Data(repeating: 0x7A, count: 32))
      let returnURL = URL(string: "meridian://payment/return")!
      var nonces = Set<String>()
      _ = try BankHandoff.validateReturnURL(returnURL, signingKey: key, usedNonces: &nonces)
      print("  ✗ Should have thrown malformedToken")
      failed += 1
    } catch BankHandoffError.malformedToken {
      print("  ✓ Missing state param correctly rejected")
      passed += 1
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 32: validateReturnURL fails with wrong signing key
    print("32. validateReturnURL fails with wrong signing key...")
    do {
      let key = SymmetricKey(data: Data(repeating: 0x7A, count: 32))
      let wrongKey = SymmetricKey(data: Data(repeating: 0x3B, count: 32))
      let token = try BankHandoff.makeStateToken(paymentId: "pay-wrongkey", signingKey: key)
      let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
      let returnURL = URL(string: "meridian://payment/return?state=\(encoded)")!
      var nonces = Set<String>()
      _ = try BankHandoff.validateReturnURL(returnURL, signingKey: wrongKey, usedNonces: &nonces)
      print("  ✗ Should have thrown invalidSignature")
      failed += 1
    } catch BankHandoffError.invalidSignature {
      print("  ✓ Wrong key correctly rejected")
      passed += 1
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // Summary
    print("\n=== Results ===")
    print("Passed: \(passed)/32")
    print("Failed: \(failed)/32")

    if failed > 0 {
      exit(1)
    }
  }
}
