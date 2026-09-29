import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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

    // CHECK 21: UUID v4 idempotency keys
    print("21. UUID v4 idempotency key...")
    let generatedKey = newPaymentIdempotencyKey()
    if isUuidV4(generatedKey) && !isUuidV4("not-a-uuid") {
      print("  ✓ newPaymentIdempotencyKey() is UUID v4")
      passed += 1
    } else {
      print("  ✗ Expected a UUID v4 key")
      failed += 1
    }

    // CHECK 22: backoff schedule
    print("22. Gateway backoff schedule...")
    let backoff = [
      GatewayRetry.backoffMillis(retryIndex: 0, randomUnit: 0),
      GatewayRetry.backoffMillis(retryIndex: 1, randomUnit: 0),
      GatewayRetry.backoffMillis(retryIndex: 2, randomUnit: 0),
      GatewayRetry.backoffMillis(retryIndex: 0, randomUnit: 1),
    ]
    if backoff == [200, 400, 800, 300] {
      print("  ✓ backoff is 200, 400, 800 ms with jitter")
      passed += 1
    } else {
      print("  ✗ Unexpected backoff: \(backoff)")
      failed += 1
    }

    let orchestratorResult = await runOrchestratorChecks()
    passed += orchestratorResult.passed
    failed += orchestratorResult.failed

    // Summary
    print("\n=== Results ===")
    let total = passed + failed
    print("Passed: \(passed)/\(total)")
    print("Failed: \(failed)/\(total)")

    if failed > 0 {
      exit(1)
    }
  }

  static func runOrchestratorChecks() async -> (passed: Int, failed: Int) {
    var passed = 0
    var failed = 0
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [GatewayStub.self]
    let session = URLSession(configuration: config)
    guard let client = try? MeridianClient(
      baseURL: "http://127.0.0.1:9/api/v1",
      sessionId: "room-keep",
      urlSession: session
    ) else {
      print("  ✗ Could not build orchestrator client")
      failed += 1
      return (passed, failed)
    }

    // CHECK 23: 502 then 200 keeps key, session, method, and amount
    print("23. Gateway 502 retries the same payment...")
    GatewayStub.reset(statuses: [502, 200])
    let sleeps = MillisecondLog()
    let key = newPaymentIdempotencyKey()
    let orchestrator = PaymentOrchestrator(
      client: client,
      sleep: { sleeps.values.append($0) },
      randomUnit: { 0 }
    )
    do {
      let response = try await orchestrator.submit(
        recipientId: "northline-studio",
        amountMinor: 2599,
        method: .bank,
        note: "Studio rent",
        idempotencyKey: key
      )
      if response.ok
        && GatewayStub.seenKeys == [key, key]
        && GatewayStub.seenSessions == ["room-keep", "room-keep"]
        && GatewayStub.seenMethods == ["bank", "bank"]
        && GatewayStub.seenAmounts == [2599, 2599]
        && sleeps.values == [200]
      {
        print("  ✓ 502 retry kept the key, session, bank method, and amount")
        passed += 1
      } else {
        print("  ✗ Retry payload drifted: keys=\(GatewayStub.seenKeys) methods=\(GatewayStub.seenMethods) sleeps=\(sleeps.values)")
        failed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 24: exhausted 502/504 does not mint a new key
    print("24. Exhausted gateway timeout keeps the original key...")
    GatewayStub.reset(statuses: [502, 502, 504])
    sleeps.values = []
    do {
      _ = try await orchestrator.submit(
        recipientId: "northline-studio",
        amountMinor: 1000,
        method: .card,
        idempotencyKey: key
      )
      print("  ✗ Expected the gateway timeout to surface")
      failed += 1
    } catch let MeridianError.httpError(statusCode, message) {
      if statusCode == 504
        && message.contains("same key")
        && GatewayStub.seenKeys == [key, key, key]
        && GatewayStub.seenMethods == ["card", "card", "card"]
        && sleeps.values == [200, 400]
      {
        print("  ✓ Three timeouts kept card and the original key")
        passed += 1
      } else {
        print("  ✗ Exhausted retry mismatch: \(GatewayStub.seenKeys) \(GatewayStub.seenMethods) \(sleeps.values)")
        failed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 25: HTTP 400 is not a gateway retry
    print("25. Business HTTP 400 is not retried...")
    GatewayStub.reset(statuses: [400])
    sleeps.values = []
    do {
      let response = try await orchestrator.submit(
        recipientId: "northline-studio",
        amountMinor: 100,
        method: .card,
        idempotencyKey: key
      )
      if !response.ok && GatewayStub.seenKeys.count == 1 && sleeps.values.isEmpty {
        print("  ✓ HTTP 400 returned without a retry")
        passed += 1
      } else {
        print("  ✗ HTTP 400 was retried")
        failed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }

    // CHECK 26: invalid key never leaves the device
    print("26. Non-UUID key is rejected locally...")
    GatewayStub.reset(statuses: [200])
    do {
      _ = try await orchestrator.submit(
        recipientId: "northline-studio",
        amountMinor: 100,
        method: .card,
        idempotencyKey: "not-a-uuid"
      )
      print("  ✗ Expected local validation to fail")
      failed += 1
    } catch MeridianError.validationError {
      if GatewayStub.seenKeys.isEmpty {
        print("  ✓ Invalid key made no network request")
        passed += 1
      } else {
        print("  ✗ Invalid key still called the API")
        failed += 1
      }
    } catch {
      print("  ✗ Unexpected error: \(error)")
      failed += 1
    }
    return (passed, failed)
  }
}

final class MillisecondLog: @unchecked Sendable {
  var values: [UInt64] = []
}

final class GatewayStub: URLProtocol {
  static var statuses: [Int] = []
  static var seenKeys: [String] = []
  static var seenSessions: [String] = []
  static var seenMethods: [String] = []
  static var seenAmounts: [Int] = []

  static func reset(statuses: [Int]) {
    self.statuses = statuses
    seenKeys = []
    seenSessions = []
    seenMethods = []
    seenAmounts = []
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    GatewayStub.seenKeys.append(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "")
    GatewayStub.seenSessions.append(request.value(forHTTPHeaderField: "X-Rehearsal-Session") ?? "")
    if let body = Self.bodyData(from: request),
      let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    {
      GatewayStub.seenMethods.append(json["method"] as? String ?? "")
      if let amount = json["amountMinor"] as? Int {
        GatewayStub.seenAmounts.append(amount)
      } else if let amount = json["amountMinor"] as? NSNumber {
        GatewayStub.seenAmounts.append(amount.intValue)
      } else {
        GatewayStub.seenAmounts.append(-1)
      }
    } else {
      GatewayStub.seenMethods.append("")
      GatewayStub.seenAmounts.append(-1)
    }
    let status = GatewayStub.statuses.isEmpty ? 200 : GatewayStub.statuses.removeFirst()
    let payload = status == 400
      ? #"{"ok":false,"error":"Invalid amount","code":"BAD_REQUEST"}"#
      : #"{"ok":true,"error":null,"code":null,"state":null,"transaction":null}"#
    let data = payload.data(using: .utf8) ?? Data()
    let response = HTTPURLResponse(
      url: request.url ?? URL(string: "http://127.0.0.1/api/v1/payments")!,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func bodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
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
    return data
  }
}
