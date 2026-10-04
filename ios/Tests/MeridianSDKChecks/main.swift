import Foundation
@testable import MeridianSDK

final class ScriptedHTTP: URLProtocol, @unchecked Sendable {
  struct Call {
    let session: String?
    let idempotency: String?
    let verification: String?
    let body: String
  }

  static let lock = NSLock()
  static var calls: [Call] = []
  static var script: [(Int, String)] = []

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let body = Self.readBody(request)
    Self.lock.lock()
    Self.calls.append(
      Call(
        session: request.value(forHTTPHeaderField: "X-Rehearsal-Session"),
        idempotency: request.value(forHTTPHeaderField: "Idempotency-Key"),
        verification: request.value(forHTTPHeaderField: ScaVerification.headerName),
        body: body
      )
    )
    let next = Self.script.isEmpty ? (500, #"{"ok":false,"error":"empty script","code":"EMPTY"}"#) : Self.script.removeFirst()
    Self.lock.unlock()
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: next.0,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(next.1.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}

  private static func readBody(_ request: URLRequest) -> String {
    if let data = request.httpBody {
      return String(data: data, encoding: .utf8) ?? ""
    }
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    defer { buffer.deallocate() }
    var data = Data()
    while stream.hasBytesAvailable {
      let count = stream.read(buffer, maxLength: 4096)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return String(data: data, encoding: .utf8) ?? ""
  }

  static func reset(script next: [(Int, String)]) {
    lock.lock()
    calls = []
    script = next
    lock.unlock()
  }
}

final class PromptLog: @unchecked Sendable {
  var prompts: [String] = []
  var accept = true
}

struct LoggingHandler: ScaChallengeHandler {
  let log: PromptLog
  func confirmEuropeanPayment(prompt: String) async -> Bool {
    log.prompts.append(prompt)
    return log.accept
  }
}

final class ScriptedClock: @unchecked Sendable {
  var times: [Date]
  init(_ times: [Date]) { self.times = times }
  func now() -> Date {
    if times.count > 1 { return times.removeFirst() }
    return times[0]
  }
}

func scaSession() -> URLSession {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [ScriptedHTTP.self]
  return URLSession(configuration: config)
}

func isoDate(_ value: String) -> Date {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter.date(from: value)!
}

func scaBody(token: String, expiry: String) -> String {
  #"{"ok":false,"code":"SCA_STEP_UP_REQUIRED","error":"Strong customer authentication required","challengeToken":"\#(token)","challengeExpiresAt":"\#(expiry)"}"#
}

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

    let future = "2099-01-01T00:00:00.000Z"
    let tokenName = "cht_european_1"

    // CHECK 21: local verification token and latency budget
    print("21. SCA verification token...")
    do {
      let proof = try ScaVerification.token(for: tokenName)
      if ScaVerification.latencyBudgetMs == 300 && proof == "sca_v1_7e0e3ab4c6566286" {
        print("  ✓ local proof \(proof) within 300 ms")
        passed += 1
      } else {
        print("  ✗ Unexpected proof \(proof)")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 22: expiry boundary
    print("22. SCA expiry boundary...")
    let boundary = PaymentResponse(
      ok: false,
      state: nil,
      transaction: nil,
      error: "Strong customer authentication required",
      code: ScaCopy.code,
      paymentId: nil,
      challengeToken: tokenName,
      challengeExpiresAt: "2026-10-04T09:30:00Z"
    )
    let open = assessSca(statusCode: 202, body: boundary)
    let closedChallenge = ScaChallenge(token: tokenName, expiresAt: isoDate("2026-10-04T09:30:00Z"))
    if case let .ready(challenge) = open,
      challenge == closedChallenge,
      !challenge.isExpired(at: isoDate("2026-10-04T09:29:59Z")),
      challenge.isExpired(at: isoDate("2026-10-04T09:30:00Z")) {
      print("  ✓ challenge is open before expiry and closed at the instant")
      passed += 1
    } else {
      print("  ✗ expiry boundary mismatch")
      failed += 1
    }

    func pay(_ client: MeridianClient) async throws -> PaymentResponse {
      try await client.submitPayment(
        recipientId: "northline-studio",
        amountMinor: 2599,
        method: .card,
        note: "European rehearsal",
        idempotencyKey: "idem-sca-1"
      )
    }

    // CHECK 23: successful biometric resubmits the original key and proof
    print("23. SCA resubmits original idempotency key...")
    let prompts = PromptLog()
    ScriptedHTTP.reset(script: [
      (202, scaBody(token: tokenName, expiry: future)),
      (200, #"{"ok":true,"paymentId":"tx-sca","error":null,"code":null}"#),
    ])
    do {
      let client = try MeridianClient(
        baseURL: "http://127.0.0.1:8080/api/v1",
        sessionId: "sca-room",
        urlSession: scaSession(),
        scaHandler: LoggingHandler(log: prompts)
      )
      let paid = try await pay(client)
      let calls = ScriptedHTTP.calls
      let proof = try ScaVerification.token(for: tokenName)
      if paid.ok,
        prompts.prompts == [ScaCopy.europeanPayment],
        calls.count == 2,
        calls[0].session == "sca-room",
        calls[1].session == "sca-room",
        calls[0].idempotency == "idem-sca-1",
        calls[1].idempotency == "idem-sca-1",
        calls[0].verification == nil,
        calls[1].verification == proof,
        calls[0].body == calls[1].body,
        !calls[1].body.contains("challengeVerification") {
        print("  ✓ same session, key, and body; verification header on retry")
        passed += 1
      } else {
        print("  ✗ resubmit mismatch \(calls)")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 24: expired challenge does not prompt or resubmit
    print("24. expired SCA challenge...")
    prompts.prompts = []
    ScriptedHTTP.reset(script: [(202, scaBody(token: tokenName, expiry: "2020-01-01T00:00:00Z"))])
    do {
      let client = try MeridianClient(
        baseURL: "http://127.0.0.1:8080/api/v1",
        sessionId: "sca-room",
        urlSession: scaSession(),
        scaHandler: LoggingHandler(log: prompts)
      )
      _ = try await pay(client)
      print("  ✗ expired challenge should ask for a new payment")
      failed += 1
    } catch MeridianError.scaReinitiate(let message) {
      if message == ScaCopy.expired && prompts.prompts.isEmpty && ScriptedHTTP.calls.count == 1 {
        print("  ✓ expired window asks the user to start again")
        passed += 1
      } else {
        print("  ✗ expiry handling mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 25: cancelled biometric does not resubmit
    print("25. cancelled biometric...")
    prompts.prompts = []
    prompts.accept = false
    ScriptedHTTP.reset(script: [(202, scaBody(token: tokenName, expiry: future))])
    do {
      let client = try MeridianClient(
        baseURL: "http://127.0.0.1:8080/api/v1",
        sessionId: "sca-room",
        urlSession: scaSession(),
        scaHandler: LoggingHandler(log: prompts)
      )
      _ = try await pay(client)
      print("  ✗ cancel should keep the payment unsent")
      failed += 1
    } catch MeridianError.scaCancelled {
      if ScriptedHTTP.calls.count == 1 && prompts.prompts.count == 1 {
        print("  ✓ cancel keeps the original payment key for retry")
        passed += 1
      } else {
        print("  ✗ cancel still resubmitted")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 26: window expires while the dialog is open
    print("26. SCA window expires during biometric...")
    prompts.accept = true
    prompts.prompts = []
    ScriptedHTTP.reset(script: [(202, scaBody(token: tokenName, expiry: "2026-10-04T09:30:00Z"))])
    let clock = ScriptedClock([isoDate("2026-10-04T09:00:00Z"), isoDate("2026-10-04T09:30:00Z")])
    do {
      let client = try MeridianClient(
        baseURL: "http://127.0.0.1:8080/api/v1",
        sessionId: "sca-room",
        urlSession: scaSession(),
        scaHandler: LoggingHandler(log: prompts),
        now: { clock.now() }
      )
      _ = try await pay(client)
      print("  ✗ late expiry should not resubmit")
      failed += 1
    } catch MeridianError.scaReinitiate(let message) {
      if message == ScaCopy.expired && prompts.prompts.count == 1 && ScriptedHTTP.calls.count == 1 {
        print("  ✓ expiry after biometric asks the user to start again")
        passed += 1
      } else {
        print("  ✗ late expiry mismatch prompts=\(prompts.prompts.count) calls=\(ScriptedHTTP.calls.count)")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 27: malformed challenge
    print("27. malformed SCA challenge...")
    prompts.prompts = []
    ScriptedHTTP.reset(script: [(202, #"{"ok":false,"code":"SCA_STEP_UP_REQUIRED","error":"missing token"}"#)])
    do {
      let client = try MeridianClient(
        baseURL: "http://127.0.0.1:8080/api/v1",
        sessionId: "sca-room",
        urlSession: scaSession(),
        scaHandler: LoggingHandler(log: prompts)
      )
      _ = try await pay(client)
      print("  ✗ malformed challenge should fail")
      failed += 1
    } catch MeridianError.scaMalformed {
      if prompts.prompts.isEmpty && ScriptedHTTP.calls.count == 1 {
        print("  ✓ malformed challenge does not prompt")
        passed += 1
      } else {
        print("  ✗ malformed challenge prompted")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 28: pending is not an SCA challenge
    print("28. pending is not SCA...")
    prompts.prompts = []
    ScriptedHTTP.reset(script: [(202, #"{"ok":false,"code":"PAYMENT_PENDING","error":"Payment pending confirmation","paymentId":"pay-1"}"#)])
    do {
      let client = try MeridianClient(
        baseURL: "http://127.0.0.1:8080/api/v1",
        sessionId: "sca-room",
        urlSession: scaSession(),
        scaHandler: LoggingHandler(log: prompts)
      )
      let pending = try await pay(client)
      if !pending.ok && pending.code == "PAYMENT_PENDING" && prompts.prompts.isEmpty && ScriptedHTTP.calls.count == 1 {
        print("  ✓ pending response stays on the original key")
        passed += 1
      } else {
        print("  ✗ pending was treated as SCA")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 29: a second challenge asks the user to start again
    print("29. repeated SCA challenge...")
    prompts.prompts = []
    ScriptedHTTP.reset(script: [
      (202, scaBody(token: tokenName, expiry: future)),
      (202, scaBody(token: tokenName, expiry: future)),
    ])
    do {
      let client = try MeridianClient(
        baseURL: "http://127.0.0.1:8080/api/v1",
        sessionId: "sca-room",
        urlSession: scaSession(),
        scaHandler: LoggingHandler(log: prompts)
      )
      _ = try await pay(client)
      print("  ✗ repeated challenge should stop")
      failed += 1
    } catch MeridianError.scaReinitiate(let message) {
      if message == ScaCopy.rejected && prompts.prompts.count == 1 && ScriptedHTTP.calls.count == 2 {
        print("  ✓ unaccepted challenge asks the user to start again")
        passed += 1
      } else {
        print("  ✗ repeated challenge mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 30: HTTP errors still surface
    print("30. HTTP error during payment...")
    prompts.prompts = []
    ScriptedHTTP.reset(script: [(500, #"{"ok":false,"error":"boom","code":"HTTP_500"}"#)])
    do {
      let client = try MeridianClient(
        baseURL: "http://127.0.0.1:8080/api/v1",
        sessionId: "sca-room",
        urlSession: scaSession(),
        scaHandler: LoggingHandler(log: prompts)
      )
      _ = try await pay(client)
      print("  ✗ HTTP 500 should throw")
      failed += 1
    } catch MeridianError.httpError(let status, _) {
      if status == 500 && prompts.prompts.isEmpty {
        print("  ✓ HTTP 500 is reported and does not prompt")
        passed += 1
      } else {
        print("  ✗ unexpected HTTP handling")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
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
