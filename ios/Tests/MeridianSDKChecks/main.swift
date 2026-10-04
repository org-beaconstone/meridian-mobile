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

    func sampleBinding(amount: Int = 2599) -> ScaPaymentBinding {
      ScaPaymentBinding(
        recipientId: "northline-studio",
        amountMinor: amount,
        method: .card,
        idempotencyKey: "pay-key-1"
      )
    }

    func session() -> ScaChallengeSession {
      ScaChallengeSession(
        binding: sampleBinding(),
        challengeId: "challenge-1",
        nonce: { "nonce-1" }
      )
    }

    func enter(_ pin: String, into session: inout ScaChallengeSession, at date: Date) -> ScaVerification? {
      var verification: ScaVerification?
      for scalar in pin {
        guard let digit = Int(String(scalar)) else { continue }
        verification = session.appendDigit(digit, at: date)
      }
      return verification
    }

    let moment = Date(timeIntervalSince1970: 1_700_000_000)

    print("21. HMAC-SHA256 known vector...")
    let vectorKey = SymmetricKey(data: Data("key".utf8))
    let vectorCode = HMAC<SHA256>.authenticationCode(
      for: Data("The quick brown fox jumps over the lazy dog".utf8),
      using: vectorKey
    )
    let vectorHex = Data(vectorCode).map { String(format: "%02x", $0) }.joined()
    if vectorHex == "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8" {
      print("  ✓ HMAC-SHA256 vector")
      passed += 1
    } else {
      print("  ✗ Unexpected HMAC \(vectorHex)")
      failed += 1
    }

    print("22. Biometric rejection banner...")
    var rejected = session()
    rejected.rejectBiometrics()
    if rejected.phase == .passcode
      && rejected.rejectionBanner == ScaChallenge.rejectionBanner
      && rejected.biometric == .rejected
      && rejected.verification == nil
    {
      print("  ✓ Rejection opens the passcode sheet with the banner")
      passed += 1
    } else {
      print("  ✗ Rejection banner mismatch")
      failed += 1
    }

    print("23. Bypass and unavailable omit the banner...")
    var bypassed = session()
    bypassed.bypassBiometrics()
    var unavailable = session()
    unavailable.markBiometricsUnavailable()
    if bypassed.rejectionBanner == nil && bypassed.biometric == .bypassed
      && unavailable.rejectionBanner == nil && unavailable.biometric == .unavailable
    {
      print("  ✓ Bypass and unavailable stay on passcode without the rejection banner")
      passed += 1
    } else {
      print("  ✗ Banner was set for bypass or unavailable")
      failed += 1
    }

    print("24. Biometric success token...")
    var biometric = session()
    let biometricVerification = biometric.succeedBiometrics(at: moment)
    let biometricPayload = biometricVerification.flatMap {
      ScaSigner.rehearsal().authenticatedPayload($0.scaChallengeToken)
    }
    if biometricVerification?.factors == [.inherence, .possession]
      && biometricVerification?.biometric == .succeeded
      && biometricPayload?.contains("inherence+possession") == true
      && biometricPayload?.contains(ScaChallenge.rehearsalPin) == false
      && ScaSigner.rehearsal().verify(
        token: biometricVerification?.scaChallengeToken ?? "",
        binding: sampleBinding()
      )
    {
      print("  ✓ Biometric success signs inherence and possession")
      passed += 1
    } else {
      print("  ✗ Biometric token mismatch")
      failed += 1
    }

    print("25. Masked passcode and rate limit...")
    var masking = session()
    masking.rejectBiometrics()
    _ = masking.appendDigit(1, at: moment)
    _ = masking.appendDigit(2, at: moment)
    let masked = masking.maskedPasscode()
    _ = masking.appendDigit(77, at: moment)
    let ignored = masking.enteredCount == 2
    masking.deleteDigit(at: moment)
    let deleted = masking.enteredCount == 1 && masking.maskedPasscode() == "•○○○○○"
    var passcode = session()
    passcode.rejectBiometrics()
    for _ in 0..<4 {
      _ = enter("000000", into: &passcode, at: moment)
    }
    let stillWrong = passcode.verification == nil && passcode.secondsLocked(at: moment) == 0
    _ = enter("000000", into: &passcode, at: moment)
    let locked = passcode.secondsLocked(at: moment) == 30
      && passcode.passcodeMessage == ScaChallenge.tooManyAttempts
    _ = enter(ScaChallenge.rehearsalPin, into: &passcode, at: moment.addingTimeInterval(29))
    let blocked = passcode.verification == nil
    let verified = enter(
      ScaChallenge.rehearsalPin,
      into: &passcode,
      at: moment.addingTimeInterval(30)
    )
    let payload = verified.flatMap { ScaSigner.rehearsal().authenticatedPayload($0.scaChallengeToken) }
    let token = verified?.scaChallengeToken ?? ""
    let tampered: String = {
      guard let separator = token.firstIndex(of: "."), token.index(after: separator) < token.endIndex else {
        return "x"
      }
      let signatureStart = token.index(after: separator)
      let replacement: Character = token[signatureStart] == "A" ? "B" : "A"
      return String(token[..<signatureStart]) + String(replacement) + String(token[token.index(after: signatureStart)...])
    }()
    if masked == "••○○○○" && stillWrong && locked && blocked
      && verified?.factors == [.knowledge, .possession]
      && verified?.biometric == .rejected
      && token.contains(ScaChallenge.rehearsalPin) == false
      && payload?.contains("knowledge+possession") == true
      && payload?.contains(ScaChallenge.rehearsalPin) == false
      && ScaSigner.rehearsal().verify(token: token, binding: sampleBinding())
      && !ScaSigner.rehearsal().verify(token: token, binding: sampleBinding(amount: 2600))
      && !ScaSigner.rehearsal().verify(token: tampered, binding: sampleBinding())
      && !String(describing: passcode).contains(ScaChallenge.rehearsalPin)
    {
      print("  ✓ Passcode is masked, rate-limited, and packaged into scaChallengeToken")
      passed += 1
    } else {
      print("  ✗ Passcode challenge mismatch")
      failed += 1
    }

    print("26. Payment JSON stays on the API contract...")
    let encoded = try? JSONEncoder().encode(
      PaymentRequest(
        recipientId: "northline-studio",
        amountMinor: 2599,
        method: .card,
        note: "Coffee",
        scenario: .success
      )
    )
    let json = encoded.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    if json.contains("\"amountMinor\":2599")
      && !json.contains("scaChallengeToken")
      && !json.contains(ScaChallenge.rehearsalPin)
    {
      print("  ✓ Payment body omits the challenge token and passcode")
      passed += 1
    } else {
      print("  ✗ Payment JSON contained SCA material")
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
