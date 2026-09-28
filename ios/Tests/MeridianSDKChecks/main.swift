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

    let extra = await runTelemetryChecks()
    passed += extra.passed
    failed += extra.failed

    let total = passed + failed
    print("\n=== Results ===")
    print("Passed: \(passed)/\(total)")
    print("Failed: \(failed)/\(total)")

    if failed > 0 {
      exit(1)
    }
  }
}

private final class CheckTally {
  var passed = 0
  var failed = 0
  func expect(_ title: String, _ condition: Bool) {
    if condition {
      print("  ✓ \(title)")
      passed += 1
    } else {
      print("  ✗ \(title)")
      failed += 1
    }
  }
}

private final class RehearsalURLProtocol: URLProtocol {
  static let lock = NSLock()
  static var handler: ((URLRequest) -> (Int, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let active: ((URLRequest) -> (Int, Data))?
    Self.lock.lock()
    active = Self.handler
    Self.lock.unlock()
    guard let active, let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    let (status, data) = active(request)
    if status == 0 {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
      return
    }
    let response = HTTPURLResponse(
      url: url,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

private func rehearsalClient() throws -> MeridianClient {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [RehearsalURLProtocol.self]
  return try MeridianClient(
    baseURL: "http://127.0.0.1:8080/api/v1",
    sessionId: "room-telemetry",
    urlSession: URLSession(configuration: configuration)
  )
}

private func runTelemetryChecks() async -> CheckTally {
  let tally = CheckTally()
  let pan = "4111111111111111"
  let iban = "GB29NWBK60161331926819"
  let noteIban = "DE89370400440532013000"
  let spacedIban = "GB29 NWBK 6016 1331 9268 19"
  let spacedPan = "4111-1111-1111-1111"
  print("21. W3C traceparent and route selection...")
  let header = TraceContext.root().traceparent
  tally.expect("traceparent shape", TraceContext.isValidTraceparent(header))
  tally.expect(
    "all-zero trace rejected",
    !TraceContext.isValidTraceparent("00-\(String(repeating: "0", count: 32))-\(String(repeating: "1", count: 16))-01")
  )
  tally.expect("catalog route", shouldInjectTraceparent(path: "/catalog"))
  tally.expect("payments route", shouldInjectTraceparent(path: "/api/v1/payments"))
  tally.expect("session health route", shouldInjectTraceparent(path: "/session/health"))
  tally.expect("plain health excluded", !shouldInjectTraceparent(path: "/health"))
  tally.expect("state excluded", !shouldInjectTraceparent(path: "/state"))

  print("22. Sanitizer redacts PAN and IBAN...")
  tally.expect("compact PAN", TelemetrySanitizer.redact(pan) == "[REDACTED_PAN]")
  tally.expect("spaced PAN", TelemetrySanitizer.redact(spacedPan) == "[REDACTED_PAN]")
  tally.expect("compact IBAN", TelemetrySanitizer.redact(iban) == "[REDACTED_IBAN]")
  tally.expect("german IBAN", TelemetrySanitizer.redact(noteIban) == "[REDACTED_IBAN]")
  tally.expect("spaced IBAN", TelemetrySanitizer.redact(spacedIban) == "[REDACTED_IBAN]")
  let mixed = TelemetrySanitizer.redact("card \(pan) iban \(iban) ref rent")
  tally.expect("mixed redaction keeps context", !mixed.contains(pan) && !mixed.contains(iban) && mixed.contains("rent"))
  tally.expect("balance untouched", TelemetrySanitizer.redact("balance 1248050") == "balance 1248050")

  print("23. Attribute policy drops secrets...")
  let policy = TelemetryLog()
  policy.recordError(
    code: iban,
    stage: "gateway_roundtrip",
    attributes: [
      "note": noteIban,
      "detail": pan,
      "error.message": "declined \(pan) \(spacedIban)",
      "payment.provider": "other",
      "payment.method": "card",
      "outcome": "DECLINED",
    ]
  )
  let policyText = policy.rendered()
  tally.expect(
    "policy rendering is sanitized",
    !policyText.contains(pan) && !policyText.contains(iban) && !policyText.contains(noteIban)
      && !policyText.contains("other") && policyText.contains("REDACTED_CODE")
      && policyText.contains("[REDACTED_PAN]") && policyText.contains("payment.method=card")
  )

  print("24. Local biometric prompt span...")
  let biometricClient = try? MeridianClient(baseURL: "http://127.0.0.1:9/api/v1", sessionId: "telemetry-room")
  let accepted = await biometricClient?.resolveLocalBiometricPrompt(method: .card)
  let prompt = biometricClient?.telemetry.spans().first { $0.name == "biometric.prompt" }
  tally.expect(
    "accepted biometric span",
    accepted?.accepted == true && accepted?.fallback == false && prompt?.status == "ok"
      && prompt?.attributes["payment.provider"] == "adyen" && (prompt?.durationMillis ?? -1) >= 0
  )
  let fallback = await biometricClient?.resolveLocalBiometricPrompt(method: .bank, accepted: true, available: false)
  let fallbackEvent = biometricClient?.telemetry.events().first { $0.name == "sca.fallback" }
  tally.expect(
    "biometric SCA fallback stays local",
    fallback?.fallback == true && fallback?.accepted == false
      && fallbackEvent?.errorCode == "SCA_CHALLENGE_FALLBACK"
      && fallbackEvent?.failureStage == "biometric_prompt"
      && fallbackEvent?.attributes["payment.provider"] == "worldpay"
  )
  _ = await biometricClient?.resolveLocalBiometricPrompt(method: .card, accepted: false)
  tally.expect(
    "declined biometric event",
    biometricClient?.telemetry.events().contains { $0.errorCode == "BIOMETRIC_DECLINED" && $0.failureStage == "biometric_prompt" } == true
  )

  print("25. Traced catalog, payment, and session health...")
  let healthCalls = CheckCounter()
  let paymentCalls = CheckCounter()
  RehearsalURLProtocol.lock.lock()
  RehearsalURLProtocol.handler = { request in
    let path = request.url?.path ?? ""
    let trace = request.value(forHTTPHeaderField: "traceparent")
    if path.hasSuffix("/catalog") {
      let json = """
      {"demoDate":"2026-09-18","recipients":[{"id":"northline-studio","name":"Northline","initials":"NS","detail":"\(iban)","category":"Shopping","color":"#111111"}],"providers":[{"id":"adyen","name":"Adyen","description":"Card","methods":["card"]}]}
      """
      return (trace.map { TraceContext.isValidTraceparent($0) } == true) ? (200, Data(json.utf8)) : (500, Data("{}".utf8))
    }
    if path.hasSuffix("/payments") {
      paymentCalls.value += 1
      let valid = trace.map { TraceContext.isValidTraceparent($0) } == true
        && request.value(forHTTPHeaderField: "Idempotency-Key") == "same-key"
        && request.value(forHTTPHeaderField: "X-Rehearsal-Session") == "room-telemetry"
      let code = paymentCalls.value == 1 ? "DECLINED" : "SCA_REQUIRED"
      let json = """
      {"ok":false,"code":"\(code)","error":"card \(pan) iban \(iban)"}
      """
      return valid ? (422, Data(json.utf8)) : (500, Data("{}".utf8))
    }
    if path.hasSuffix("/session/health") {
      guard trace.map({ TraceContext.isValidTraceparent($0) }) == true else {
        return (500, Data("{}".utf8))
      }
      let json: String
      switch healthCalls.value {
      case 0, 1:
        json = #"{"status":"UP","service":"meridian-api","simulation":true}"#
      default:
        json = #"{"status":"degraded","corridors":[{"id":"adyen-card","provider":"adyen","method":"card","state":"degraded"},{"id":"other-wallet","provider":"other","method":"card","state":"degraded"}]}"#
      }
      healthCalls.value += 1
      return (200, Data(json.utf8))
    }
    if path.hasSuffix("/state") || path.hasSuffix("/health") {
      if trace != nil { return (500, Data("{}".utf8)) }
      if path.hasSuffix("/health") {
        return (200, Data(#"{"status":"UP","service":"meridian-api","simulation":true}"#.utf8))
      }
      return (200, Data(#"{"version":1,"balance":1248050,"transactions":[],"budgets":[]}"#.utf8))
    }
    return (404, Data("{}".utf8))
  }
  RehearsalURLProtocol.lock.unlock()

  do {
    let client = try rehearsalClient()
    let catalog = try await client.getCatalog()
    let parse = client.telemetry.spans().first { $0.name == "catalog.parse" }
    tally.expect(
      "catalog parse span omits IBAN",
      catalog.recipients.first?.detail == iban && parse?.status == "ok" && parse?.parentSpanId?.isEmpty == false
        && (parse?.durationMillis ?? -1) >= 0 && !client.telemetry.rendered().contains(iban)
    )
    _ = try await client.getState()
    let health = try await client.getHealth()
    tally.expect("untraced health still decodes", health.status == "UP")
    let declined = try await client.submitPayment(
      recipientId: "northline-studio",
      amountMinor: 2500,
      method: .card,
      note: noteIban,
      scenario: .declined,
      idempotencyKey: "same-key"
    )
    let gateway = client.telemetry.spans().first { $0.name == "payment.gateway" }
    let gatewayError = client.telemetry.events().first { $0.name == "client.error" && $0.failureStage == "gateway_roundtrip" }
    let rendered = client.telemetry.rendered()
    tally.expect(
      "gateway error is sanitized",
      declined.code == "DECLINED" && gateway?.status == "error" && gateway?.parentSpanId == nil
        && gateway?.attributes["payment.provider"] == "adyen" && gatewayError?.errorCode == "DECLINED"
        && !rendered.contains(pan) && !rendered.contains(iban) && !rendered.contains(noteIban)
    )
    let challenged = try await client.submitPayment(
      recipientId: "northline-studio",
      amountMinor: 2500,
      method: .card,
      note: "rent",
      scenario: .unavailable,
      idempotencyKey: "same-key"
    )
    tally.expect(
      "SCA fallback does not open another provider call",
      challenged.code == "SCA_REQUIRED" && paymentCalls.value == 2
        && client.telemetry.events().contains { $0.name == "sca.fallback" && $0.errorCode == "SCA_REQUIRED" && $0.failureStage == "sca_challenge" }
    )
    let first = await client.checkSessionHealth()
    let changes = client.telemetry.events().filter { $0.name == "session.connection_changed" }.count
    let second = await client.checkSessionHealth()
    let afterSecond = client.telemetry.events().filter { $0.name == "session.connection_changed" }.count
    let third = await client.checkSessionHealth()
    let degraded = client.telemetry.events().first { $0.name == "corridor.degraded" && $0.attributes["corridor.id"] == "adyen-card" }
    tally.expect(
      "corridor degrade is recorded once",
      first.connectionState == "healthy" && second.connectionState == "healthy"
        && afterSecond == changes
        && third.connectionState == "degraded" && degraded?.attributes["payment.provider"] == "adyen"
        && !client.telemetry.rendered().contains("other")
    )
  } catch {
    tally.expect("traced HTTP rehearsal \(error)", false)
  }

  print("26. Network failure keeps the failure stage...")
  RehearsalURLProtocol.lock.lock()
  RehearsalURLProtocol.handler = { _ in (0, Data()) }
  RehearsalURLProtocol.lock.unlock()
  if let client = try? rehearsalClient() {
    var threw = false
    do {
      _ = try await client.submitPayment(
        recipientId: "northline-studio",
        amountMinor: 100,
        method: .bank,
        note: noteIban,
        idempotencyKey: "kept-key"
      )
    } catch {
      threw = true
    }
    let rendered = client.telemetry.rendered()
    tally.expect(
      "network error span omits IBAN",
      threw && rendered.contains("NETWORK_ERROR") && rendered.contains("gateway_roundtrip")
        && client.telemetry.spans().contains { $0.name == "payment.gateway" && $0.status == "error" && $0.attributes["payment.provider"] == "worldpay" }
        && !rendered.contains(noteIban)
    )
  } else {
    tally.expect("network client init", false)
  }
  return tally
}

private final class CheckCounter: @unchecked Sendable {
  var value = 0
}
