import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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

    // CHECK 21: SCA prompt and failure copy
    print("21. SCA copy...")
    if ScaStepUp.biometricPrompt == "Confirm with Face ID / Fingerprint to authorize European payment"
      && ScaStepUp.failureMessage == "Authentication challenge failed. Please verify with your passcode."
    {
      print("  ✓ Biometric prompt and failure message match the rehearsal copy")
      passed += 1
    } else {
      print("  ✗ SCA copy mismatch")
      failed += 1
    }

    // CHECK 22: timestamp equivalence
    print("22. SCA timestamp parsing...")
    let zulu = parseScaTimestamp("2026-09-28T21:45:00Z")
    let offset = parseScaTimestamp("2026-09-28T22:45:00+01:00")
    let fractional = parseScaTimestamp("2026-09-28T21:45:00.123Z")
    if let zulu, zulu == offset, let fractional, abs(fractional.timeIntervalSince(zulu) - 0.123) < 0.0005 {
      print("  ✓ Zulu, offset, and fractional timestamps agree")
      passed += 1
    } else {
      print("  ✗ Timestamp parsing failed")
      failed += 1
    }

    let futureBody = """
    {
      "ok": false,
      "code": "SCA_STEP_UP_REQUIRED",
      "challenge": {
        "payload": "challenge-payload",
        "expiresAt": "2099-01-01T00:00:00Z",
        "scaChallengeToken": "token-123"
      }
    }
    """
    let payment = InFlightPayment(
      recipientId: "northline-studio",
      amountMinor: 4500,
      method: .card,
      note: "Studio supplies",
      scenario: .success,
      idempotencyKey: "idem-original"
    )
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    // CHECK 23: extract payload and fall back without releasing the token
    print("23. SCA extract and biometric fallback...")
    do {
      let body = try JSONDecoder().decode(PaymentResponse.self, from: Data(futureBody.utf8))
      let handler = ScaChallengeHandler.begin(statusCode: 202, body: body, payment: payment, now: now)
      if let handler, case let .biometric(challenge) = handler.phase, challenge.payload == "challenge-payload",
        handler.resubmission() == nil
      {
        let passcode = handler.biometricUnavailableOrFailed(now: now)
        let rejected = passcode.passcodeRejected(now: now)
        if case let .passcode(_, message) = rejected.phase,
          message == ScaStepUp.failureMessage,
          rejected.payment == payment,
          rejected.resubmission() == nil
        {
          print("  ✓ Fallback keeps recipient, amount, and idempotency key")
          passed += 1
        } else {
          print("  ✗ Fallback did not retain the payment")
          failed += 1
        }
      } else {
        print("  ✗ Challenge was not extracted")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 24: passcode success resubmits the original key and method
    print("24. SCA resubmit payload...")
    let flatBody = """
    {
      "ok": false,
      "code": "SCA_STEP_UP_REQUIRED",
      "challengePayload": "opaque-payload",
      "expirationTimestamp": "2099-06-01T12:00:00Z",
      "scaChallengeToken": "token-from-gateway"
    }
    """
    do {
      let body = try JSONDecoder().decode(PaymentResponse.self, from: Data(flatBody.utf8))
      let ready = ScaChallengeHandler.begin(statusCode: 202, body: body, payment: payment, now: now)?
        .biometricUnavailableOrFailed(now: now)
        .passcodeVerified(now: now)
      let retry = ready?.resubmission()
      if retry?.idempotencyKey == payment.idempotencyKey,
        retry?.method == .card,
        retry?.amountMinor == 4500,
        retry?.recipientId == "northline-studio",
        retry?.scaChallengeToken == "token-from-gateway",
        RehearsalPasscode.matches(entered: "135790", enrolled: "135790"),
        !RehearsalPasscode.matches(entered: "000000", enrolled: "135790")
      {
        print("  ✓ Resubmit keeps the original key, method, and token")
        passed += 1
      } else {
        print("  ✗ Resubmit payload mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 25: expired challenge does not resubmit
    print("25. Expired SCA challenge...")
    let staleBody = """
    {
      "ok": false,
      "code": "SCA_STEP_UP_REQUIRED",
      "challenge": "stale-payload",
      "expiresAt": "2000-01-01T00:00:00Z",
      "scaChallengeToken": "stale-token"
    }
    """
    do {
      let stale = try JSONDecoder().decode(PaymentResponse.self, from: Data(staleBody.utf8))
      let pending = try JSONDecoder().decode(
        PaymentResponse.self,
        from: Data(#"{"ok":false,"code":"PAYMENT_PENDING"}"#.utf8)
      )
      let handler = ScaChallengeHandler.begin(statusCode: 202, body: stale, payment: payment, now: Date())
      let ignored = ScaChallengeHandler.begin(statusCode: 202, body: pending, payment: payment, now: now)
      let wrongStatus = ScaChallengeHandler.begin(statusCode: 400, body: stale, payment: payment, now: now)
      if case let .failed(message) = handler?.phase,
        message == ScaStepUp.failureMessage,
        handler?.payment == payment,
        handler?.resubmission() == nil,
        ignored == nil,
        wrongStatus == nil
      {
        print("  ✓ Expired challenge retains the payment and does not resubmit")
        passed += 1
      } else {
        print("  ✗ Expiry handling mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 26: token is omitted until verification
    print("26. Payment body omits scaChallengeToken until set...")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let plain = PaymentRequest(
      recipientId: "northline-studio",
      amountMinor: 4500,
      method: .card,
      note: "Lunch",
      scenario: .success
    )
    let withToken = PaymentRequest(
      recipientId: "northline-studio",
      amountMinor: 4500,
      method: .card,
      note: "Lunch",
      scenario: .success,
      scaChallengeToken: "token-123"
    )
    let plainJson = String(data: try! encoder.encode(plain), encoding: .utf8) ?? ""
    let tokenJson = String(data: try! encoder.encode(withToken), encoding: .utf8) ?? ""
    if !plainJson.contains("scaChallengeToken") && tokenJson.contains("\"scaChallengeToken\":\"token-123\"")
      && tokenJson.contains("\"method\":\"card\"") && tokenJson.contains("\"amountMinor\":4500")
    {
      print("  ✓ Token is encoded only after verification")
      passed += 1
    } else {
      print("  ✗ Encoding mismatch: \(plainJson) / \(tokenJson)")
      failed += 1
    }

    // CHECK 27: HTTP 202 step-up then resubmit with the same key
    print("27. HTTP 202 SCA resubmit...")
    if runScaTransportCheck() {
      print("  ✓ Same idempotency key and scaChallengeToken on the second POST")
      passed += 1
    } else {
      print("  ✗ SCA transport check failed")
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

private final class ScaURLProtocol: URLProtocol {
  nonisolated(unsafe) static var hits: [(key: String?, session: String?, body: String)] = []

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let body = requestBody(request)
    let key = request.value(forHTTPHeaderField: "Idempotency-Key")
    let session = request.value(forHTTPHeaderField: "X-Rehearsal-Session")
    Self.hits.append((key, session, body))
    let responseBody: String
    let status: Int
    if body.contains("scaChallengeToken") {
      status = 200
      responseBody = #"{"ok":true,"paymentId":"pay-sca"}"#
    } else {
      status = 202
      responseBody = #"{"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"payload":"challenge-payload","expiresAt":"2099-01-01T00:00:00Z","scaChallengeToken":"token-123"}}"#
    }
    let response = HTTPURLResponse(
      url: request.url ?? URL(string: "http://127.0.0.1/payments")!,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(responseBody.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

private func requestBody(_ request: URLRequest) -> String {
  if let body = request.httpBody, !body.isEmpty {
    return String(data: body, encoding: .utf8) ?? ""
  }
  guard let stream = request.httpBodyStream else { return "" }
  stream.open()
  defer { stream.close() }
  var data = Data()
  let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
  defer { buffer.deallocate() }
  while stream.hasBytesAvailable {
    let read = stream.read(buffer, maxLength: 1024)
    if read <= 0 { break }
    data.append(buffer, count: read)
  }
  return String(data: data, encoding: .utf8) ?? ""
}

private func runScaTransportCheck() -> Bool {
  ScaURLProtocol.hits = []
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [ScaURLProtocol.self]
  let session = URLSession(configuration: configuration)
  guard let client = try? MeridianClient(
    baseURL: "http://127.0.0.1:8080/api/v1",
    sessionId: "sca-room",
    urlSession: session
  ) else { return false }

  let box = ResultBox()
  let semaphore = DispatchSemaphore(value: 0)
  Task {
    do {
      let key = "idem-sca-1"
      let first = try await client.submitPayment(
        recipientId: "northline-studio",
        amountMinor: 4500,
        method: .card,
        note: "European rehearsal",
        idempotencyKey: key
      )
      let payment = InFlightPayment(
        recipientId: "northline-studio",
        amountMinor: 4500,
        method: .card,
        note: "European rehearsal",
        scenario: .success,
        idempotencyKey: key
      )
      guard first.statusCode == 202, let ready = ScaChallengeHandler.begin(
        statusCode: first.statusCode,
        body: first.body,
        payment: payment,
        now: Date()
      )?.biometricSucceeded(now: Date()), let retry = ready.resubmission() else {
        box.ok = false
        semaphore.signal()
        return
      }
      let second = try await client.submitPayment(
        recipientId: retry.recipientId,
        amountMinor: retry.amountMinor,
        method: retry.method,
        note: retry.note,
        scenario: retry.scenario,
        idempotencyKey: retry.idempotencyKey,
        scaChallengeToken: retry.scaChallengeToken
      )
      let hits = ScaURLProtocol.hits
      box.ok = second.statusCode == 200 && second.body.ok
        && hits.count == 2
        && hits[0].key == key && hits[1].key == key
        && hits[0].session == "sca-room" && hits[1].session == "sca-room"
        && !hits[0].body.contains("scaChallengeToken")
        && hits[1].body.contains("\"scaChallengeToken\":\"token-123\"")
        && hits[1].body.contains("\"method\":\"card\"")
        && retry.method == .card
    } catch {
      box.ok = false
    }
    semaphore.signal()
  }
  if semaphore.wait(timeout: .now() + 5) == .timedOut {
    return false
  }
  return box.ok
}

private final class ResultBox: @unchecked Sendable {
  var ok = false
}
