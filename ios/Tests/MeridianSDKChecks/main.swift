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

    // MARK: - SCA Challenge Handler Tests

    // Mock URLProtocol for stubbing HTTP responses
    final class MockURLProtocol: URLProtocol, @unchecked Sendable {
      static var handler: ((URLRequest) -> (Int, Data))?

      override class func canInit(with request: URLRequest) -> Bool { true }
      override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

      override func startLoading() {
        let (statusCode, data) = MockURLProtocol.handler?(request) ?? (200, Data())
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: statusCode,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
      }

      override func stopLoading() {}
    }

    func makeStubClient(handler: @escaping (URLRequest) -> (Int, Data)) throws -> MeridianClient {
      MockURLProtocol.handler = handler
      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [MockURLProtocol.self]
      let stubSession = URLSession(configuration: config)
      return try MeridianClient(
        baseURL: "http://stub.local",
        sessionId: "test-sca",
        urlSession: stubSession
      )
    }

    struct MockBiometricAuthenticator: ScaBiometricAuthenticator {
      let available: Bool
      let succeeds: Bool
      func canAuthenticate() -> Bool { available }
      func authenticate(reason: String) async throws -> Bool { succeeds }
    }

    struct MockPasscodeVerifier: ScaPasscodeVerifier {
      let succeeds: Bool
      func verifyPasscode() async -> Bool { succeeds }
    }

    // CHECK 21: SCA_STEP_UP_REQUIRED response decoding
    print("21. SCA_STEP_UP_REQUIRED response decoding...")
    let scaJson = """
    {
      "ok": false,
      "error": "SCA authentication required",
      "code": "SCA_STEP_UP_REQUIRED",
      "scaChallengeToken": "sca-tok-abc123",
      "challengeExpiresAt": "2099-12-31T23:59:59Z",
      "state": null,
      "transaction": null
    }
    """
    do {
      let response = try JSONDecoder().decode(
        PaymentResponse.self,
        from: scaJson.data(using: .utf8)!
      )
      if !response.ok && response.code == "SCA_STEP_UP_REQUIRED"
        && response.scaChallengeToken == "sca-tok-abc123"
        && response.challengeExpiresAt == "2099-12-31T23:59:59Z"
      {
        print("  ✓ SCA_STEP_UP_REQUIRED decoded: token=\(response.scaChallengeToken!)")
        passed += 1
      } else {
        print("  ✗ SCA response fields mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ SCA decoding failed: \(error)")
      failed += 1
    }

    // CHECK 22: ScaPaymentRequest encodes scaChallengeToken
    print("22. ScaPaymentRequest encodes scaChallengeToken...")
    do {
      let req = ScaPaymentRequest(
        recipientId: "rec-1",
        amountMinor: 15000,
        method: .card,
        note: "test",
        scenario: .success,
        scaChallengeToken: "tok-xyz"
      )
      let encoded = try JSONEncoder().encode(req)
      let json = String(data: encoded, encoding: .utf8) ?? ""
      if json.contains("\"scaChallengeToken\"") && json.contains("tok-xyz") {
        print("  ✓ ScaPaymentRequest encodes scaChallengeToken")
        passed += 1
      } else {
        print("  ✗ scaChallengeToken missing from encoded JSON: \(json)")
        failed += 1
      }
    } catch {
      print("  ✗ ScaPaymentRequest encoding failed: \(error)")
      failed += 1
    }

    // CHECK 23: ScaChallengeHandler – biometric succeeds → .success
    print("23. ScaChallengeHandler biometric success → .success...")
    do {
      let successBody = """
      {"ok":true,"state":{"version":1,"balance":990000,"transactions":[],"budgets":[]},"transaction":null}
      """
      let client23 = try makeStubClient { _ in (200, successBody.data(using: .utf8)!) }
      let handler23 = ScaChallengeHandler(
        client: client23,
        biometricAuthenticator: MockBiometricAuthenticator(available: true, succeeds: true),
        passcodeVerifier: MockPasscodeVerifier(succeeds: false)
      )
      let outcome23 = await handler23.handle(
        scaChallengeToken: "tok-bio",
        challengeExpiresAt: "2099-12-31T23:59:59Z",
        recipientId: "rec-1",
        amountMinor: 15000,
        method: .card,
        note: "test",
        scenario: .success,
        idempotencyKey: "key-1"
      )
      if case .success(let resp) = outcome23, resp.ok {
        print("  ✓ Biometric success produces .success outcome")
        passed += 1
      } else {
        print("  ✗ Expected .success, got: \(outcome23)")
        failed += 1
      }
    } catch {
      print("  ✗ Test setup failed: \(error)")
      failed += 1
    }

    // CHECK 24: ScaChallengeHandler – biometric fails → passcode succeeds → .success
    print("24. ScaChallengeHandler biometric fail → passcode → .success...")
    do {
      let successBody = """
      {"ok":true,"state":{"version":1,"balance":990000,"transactions":[],"budgets":[]},"transaction":null}
      """
      let client24 = try makeStubClient { _ in (200, successBody.data(using: .utf8)!) }
      let handler24 = ScaChallengeHandler(
        client: client24,
        biometricAuthenticator: MockBiometricAuthenticator(available: true, succeeds: false),
        passcodeVerifier: MockPasscodeVerifier(succeeds: true)
      )
      let outcome24 = await handler24.handle(
        scaChallengeToken: "tok-pc",
        challengeExpiresAt: "2099-12-31T23:59:59Z",
        recipientId: "rec-1",
        amountMinor: 15000,
        method: .card,
        note: "test",
        scenario: .success,
        idempotencyKey: "key-2"
      )
      if case .success(let resp) = outcome24, resp.ok {
        print("  ✓ Biometric fail + passcode success produces .success outcome")
        passed += 1
      } else {
        print("  ✗ Expected .success, got: \(outcome24)")
        failed += 1
      }
    } catch {
      print("  ✗ Test setup failed: \(error)")
      failed += 1
    }

    // CHECK 25: ScaChallengeHandler – both fail → .authenticationFailed
    print("25. ScaChallengeHandler both fail → .authenticationFailed...")
    do {
      let client25 = try makeStubClient { _ in (200, Data()) }
      let handler25 = ScaChallengeHandler(
        client: client25,
        biometricAuthenticator: MockBiometricAuthenticator(available: true, succeeds: false),
        passcodeVerifier: MockPasscodeVerifier(succeeds: false)
      )
      let outcome25 = await handler25.handle(
        scaChallengeToken: "tok-fail",
        challengeExpiresAt: "2099-12-31T23:59:59Z",
        recipientId: "rec-1",
        amountMinor: 15000,
        method: .card,
        note: "test",
        scenario: .success,
        idempotencyKey: "key-3"
      )
      if case .authenticationFailed(let msg) = outcome25,
        msg == "Authentication challenge failed. Please verify with your passcode."
      {
        print("  ✓ Both fail produces .authenticationFailed with correct message")
        passed += 1
      } else {
        print("  ✗ Expected .authenticationFailed, got: \(outcome25)")
        failed += 1
      }
    } catch {
      print("  ✗ Test setup failed: \(error)")
      failed += 1
    }

    // CHECK 26: ScaChallengeHandler – expired challenge → .challengeExpired
    print("26. ScaChallengeHandler expired challenge → .challengeExpired...")
    do {
      let client26 = try makeStubClient { _ in (200, Data()) }
      let handler26 = ScaChallengeHandler(
        client: client26,
        biometricAuthenticator: MockBiometricAuthenticator(available: true, succeeds: true),
        passcodeVerifier: MockPasscodeVerifier(succeeds: true)
      )
      let outcome26 = await handler26.handle(
        scaChallengeToken: "tok-exp",
        challengeExpiresAt: "2000-01-01T00:00:00Z",  // already expired
        recipientId: "rec-1",
        amountMinor: 15000,
        method: .card,
        note: "test",
        scenario: .success,
        idempotencyKey: "key-4"
      )
      if case .challengeExpired(let msg) = outcome26,
        msg == "Authentication challenge failed. Please verify with your passcode."
      {
        print("  ✓ Expired challenge produces .challengeExpired with correct message")
        passed += 1
      } else {
        print("  ✗ Expected .challengeExpired, got: \(outcome26)")
        failed += 1
      }
    } catch {
      print("  ✗ Test setup failed: \(error)")
      failed += 1
    }

    // Summary
    print("\n=== Results ===")
    print("Passed: \(passed)/26")
    print("Failed: \(failed)/26")

    if failed > 0 {
      exit(1)
    }
  }
}
