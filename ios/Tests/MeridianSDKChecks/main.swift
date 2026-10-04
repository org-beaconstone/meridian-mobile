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

    // CHECK 21: gateway backoff retries only 502 and 504
    print("21. retry policy backoff...")
    let policy = RetryPolicy(jitter: { _ in 0 })
    let delays = [
      policy.delayMillis(beforeAttempt: 2),
      policy.delayMillis(beforeAttempt: 3),
      policy.delayMillis(beforeAttempt: 4),
      policy.delayMillis(beforeAttempt: 8),
    ]
    if policy.maxAttempts == 3 && delays == [200, 400, 800, 1600]
      && policy.retriesHTTPStatus(502) && policy.retriesHTTPStatus(504)
      && !policy.retriesHTTPStatus(503) && !policy.retriesHTTPStatus(500) && !policy.retriesHTTPStatus(409) {
      print("  ✓ 502/504 backoff is 200, 400, 800 capped at 1600")
      passed += 1
    } else {
      print("  ✗ Unexpected retry schedule \(delays)")
      failed += 1
    }

    // CHECK 22: degraded Adyen card prompts Worldpay bank, and ignores other provider ids
    print("22. corridor fallback stays on the rehearsed rails...")
    let health = SessionHealth(
      status: "DEGRADED",
      simulation: true,
      corridors: [
        CorridorHealth(id: "EU", status: "outage", currency: "EUR", rails: [RailHealth(method: "card", provider: "adyen", status: "outage")]),
        CorridorHealth(
          id: "GB",
          status: "degraded",
          currency: "GBP",
          rails: [
            RailHealth(method: "card", provider: "adyen", status: "degraded"),
            RailHealth(method: "bank", provider: "unlisted", status: "healthy"),
            RailHealth(method: "bank", provider: "worldpay", status: "healthy"),
          ]
        ),
      ]
    )
    if case let .switchRail(prompt) = corridorNotice(for: health, selected: .card),
      prompt.corridorId == "GB", prompt.alternateMethod == .bank, baselineProvider(for: prompt.alternateMethod) == .worldpay,
      corridorNotice(for: health, selected: .bank) == nil {
      print("  ✓ degraded card prompts bank payment")
      passed += 1
    } else {
      print("  ✗ Corridor notice did not stay on Adyen card / Worldpay bank")
      failed += 1
    }

    // CHECK 23: no healthy rehearsed rail means no provider switch
    print("23. corridor outage without a healthy rehearsed rail...")
    let outage = SessionHealth(
      status: "DOWN",
      corridors: [
        CorridorHealth(
          id: "GB",
          status: "outage",
          currency: "GBP",
          rails: [
            RailHealth(method: "card", provider: "adyen", status: "outage"),
            RailHealth(method: "bank", provider: "worldpay", status: "degraded"),
            RailHealth(method: "card", provider: "unlisted", status: "healthy"),
          ]
        )
      ]
    )
    if case let .unavailable(_, message) = corridorNotice(for: outage, selected: .card), !message.contains("unlisted") {
      print("  ✓ outage banner does not name an unlisted provider")
      passed += 1
    } else {
      print("  ✗ Outage should not offer an unlisted provider")
      failed += 1
    }

    // CHECK 24: session health JSON
    print("24. session health JSON...")
    let healthJSON = """
    {"status":"DEGRADED","simulation":true,"region":"uk","corridors":[{"id":"GB","currency":"GBP","status":"degraded","rails":[{"method":"bank","provider":"worldpay","status":"outage","latencyMs":10}]}]}
    """
    if let decoded = try? JSONDecoder().decode(SessionHealth.self, from: Data(healthJSON.utf8)),
      decoded.simulation == true,
      case .unavailable = corridorNotice(for: decoded, selected: .bank) {
      print("  ✓ session health decoded")
      passed += 1
    } else {
      print("  ✗ Session health decoding failed")
      failed += 1
    }

    let transport = DispatchSemaphore(value: 0)
    let delayLog = DelayLog()
    let tally = CheckTally()
    let worker = Task {
      defer { transport.signal() }
      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [ScriptedTransport.self]
      let session = URLSession(configuration: config)
      ScriptedTransport.reset(responses: [502, 504, 200])
      do {
        let client = try MeridianClient(
          baseURL: "http://127.0.0.1:9/api/v1",
          sessionId: "swift-room",
          urlSession: session,
          retryPolicy: RetryPolicy(jitter: { _ in 0 }),
          sleeper: { millis in delayLog.values.append(millis) }
        )
        let paid = try await client.submitPayment(
          recipientId: "northline-studio",
          amountMinor: 2500,
          method: .card,
          note: "Studio materials",
          idempotencyKey: "swift-key"
        )
        let sameKey = ScriptedTransport.keys == ["swift-key", "swift-key", "swift-key"]
        let sameBody = Set(ScriptedTransport.bodies).count == 1 && (ScriptedTransport.bodies.first?.contains("\"method\":\"card\"") ?? false)
        let sameSession = ScriptedTransport.sessions == ["swift-room", "swift-room", "swift-room"]
        if paid.ok && paid.paymentId == "pay-swift" && sameKey && sameBody && sameSession && delayLog.values == [200, 400] {
          print("25. gateway retry kept the payment key...")
          print("  ✓ 502 then 504 retried with the same key and card body")
          tally.pass()
        } else {
          print("25. gateway retry kept the payment key...")
          print("  ✗ ok=\(paid.ok) keys=\(ScriptedTransport.keys) delays=\(delayLog.values) bodies=\(ScriptedTransport.bodies)")
          tally.fail()
        }

        ScriptedTransport.reset(responses: [502, 502, 502])
        delayLog.values.removeAll()
        do {
          _ = try await client.submitPayment(
            recipientId: "northline-studio",
            amountMinor: 100,
            method: .bank,
            note: "rent",
            idempotencyKey: "swift-exhaust"
          )
          print("26. exhausted gateway retries...")
          print("  ✗ Expected retries to exhaust")
          tally.fail()
        } catch let error as MeridianError {
          if case let .retriesExhausted(status, attempts, _) = error,
            status == 502, attempts == 3, ScriptedTransport.keys == ["swift-exhaust", "swift-exhaust", "swift-exhaust"] {
            print("26. exhausted gateway retries...")
            print("  ✓ three 502s kept swift-exhaust")
            tally.pass()
          } else {
            print("26. exhausted gateway retries...")
            print("  ✗ Unexpected error \(error) keys=\(ScriptedTransport.keys)")
            tally.fail()
          }
        }

        ScriptedTransport.reset(responses: [200])
        let updates = await client.pollSessionHealth(every: .milliseconds(20))
        var polls = 0
        for await snapshot in updates {
          polls += 1
          if polls >= 2 {
            let healthPaths = ScriptedTransport.paths.filter { $0.contains("/session/health") }
            if snapshot.reachable, case let .switchRail(prompt) = snapshot.health.flatMap({ corridorNotice(for: $0, selected: .card) }),
              prompt.alternateMethod == .bank, healthPaths.count >= 2 {
              print("27. session health polling...")
              print("  ✓ polled /session/health and prompted the bank rail")
              tally.pass()
            } else {
              print("27. session health polling...")
              print("  ✗ paths=\(ScriptedTransport.paths) reachable=\(snapshot.reachable)")
              tally.fail()
            }
            await client.stopSessionHealthPolling()
            break
          }
        }
      } catch {
        print("25-27. transport checks...")
        print("  ✗ \(error)")
        tally.fail(3)
      }
    }
    if transport.wait(timeout: .now() + 8) != .success {
      worker.cancel()
      print("25-27. transport checks...")
      print("  ✗ Timed out")
      if tally.passed + tally.failed == 0 { failed += 3 }
    }
    passed += tally.passed
    failed += tally.failed

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

private final class DelayLog: @unchecked Sendable {
  var values: [Int] = []
}

private final class CheckTally: @unchecked Sendable {
  var passed = 0
  var failed = 0
  func pass() { passed += 1 }
  func fail(_ count: Int = 1) { failed += count }
}

private final class ScriptedTransport: URLProtocol, @unchecked Sendable {
  static let gate = NSLock()
  static var responses: [Int] = []
  static var keys: [String] = []
  static var bodies: [String] = []
  static var sessions: [String] = []
  static var paths: [String] = []

  static func reset(responses: [Int]) {
    gate.lock()
    self.responses = responses
    keys = []
    bodies = []
    sessions = []
    paths = []
    gate.unlock()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path ?? ""
    let key = request.value(forHTTPHeaderField: "Idempotency-Key") ?? ""
    let session = request.value(forHTTPHeaderField: "X-Rehearsal-Session") ?? ""
    let body = Self.readBody(request)
    Self.gate.lock()
    Self.paths.append(path)
    if !key.isEmpty { Self.keys.append(key) }
    if !body.isEmpty { Self.bodies.append(body) }
    Self.sessions.append(session)
    let status: Int
    if path.contains("/session/health") {
      status = 200
    } else if Self.responses.isEmpty {
      status = 502
    } else {
      status = Self.responses.removeFirst()
    }
    Self.gate.unlock()

    let payload: String
    if path.contains("/session/health") {
      payload = #"{"status":"DEGRADED","simulation":true,"corridors":[{"id":"GB","currency":"GBP","status":"degraded","rails":[{"method":"card","provider":"adyen","status":"outage"},{"method":"bank","provider":"worldpay","status":"healthy"}]}]}"#
    } else if status == 200 {
      payload = #"{"ok":true,"paymentId":"pay-swift"}"#
    } else {
      payload = ""
    }
    let data = Data(payload.utf8)
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func readBody(_ request: URLRequest) -> String {
    if let body = request.httpBody, let text = String(data: body, encoding: .utf8) { return text }
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let count = stream.read(buffer, maxLength: 1024)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return String(data: data, encoding: .utf8) ?? ""
  }
}
