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

    let idempotency = runIdempotencyChecks()
    passed += idempotency.passed
    failed += idempotency.failed

    // Summary
    let total = passed + failed
    print("\n=== Results ===")
    print("Passed: \(passed)/\(total)")
    print("Failed: \(failed)/\(total)")

    if failed > 0 {
      exit(1)
    }
  }

  static func runIdempotencyChecks() -> (passed: Int, failed: Int) {
    var passed = 0
    var failed = 0
    func check(_ name: String, _ ok: Bool) {
      if ok {
        print("  ✓ \(name)")
        passed += 1
      } else {
        print("  ✗ \(name)")
        failed += 1
      }
    }

    print("21. UUID v4 shape and uniqueness...")
    let keys = (0..<32).map { _ in IdempotencyKeyManager.secureUuidV4() }
    check("32 distinct UUID v4 keys", Set(keys).count == 32 && keys.allSatisfy(IdempotencyKeyManager.isUuidV4))

    print("22. TTL is 24 hours...")
    check("ttl is 86400000 ms", IdempotencyKeyManager.twentyFourHoursMillis == 86_400_000)

    print("23. retry and challenge reuse one key...")
    var now: Int64 = 1_000
    var generated = 0
    let manager = try! IdempotencyKeyManager(
      store: MemoryIdempotencyStore(),
      clock: { now },
      uuidGenerator: {
        generated += 1
        return String(format: "00000000-0000-4000-8000-%012d", generated)
      }
    )
    let attempt = PaymentAttempt(recipientId: "rec-1", amountMinor: 100, method: "card", note: "note", scenario: "success")
    let key = try! manager.begin(transactionId: "tx-1", fingerprint: attempt.fingerprint())
    let retried = try! manager.keyForRetry(transactionId: "tx-1", fingerprint: attempt.fingerprint())
    let challenged = try! manager.keyForChallenge(transactionId: "tx-1", fingerprint: attempt.fingerprint())
    check("one generated key reused", key == retried && key == challenged && generated == 1)

    print("24. settle and cancel purge the cache...")
    try! manager.begin(transactionId: "other")
    try! manager.settle(transactionId: "tx-1")
    try! manager.cancel(transactionId: "other")
    var missing = false
    do { _ = try manager.keyForRetry(transactionId: "tx-1") } catch MeridianError.missingIdempotencyKey(_) { missing = true } catch { missing = false }
    check("purged keys are gone", manager.storedRecords().isEmpty && missing)

    print("25. 24-hour expiry blocks reuse...")
    let held = try! manager.begin(transactionId: "aging", fingerprint: attempt.fingerprint())
    now = 1_000 + IdempotencyKeyManager.twentyFourHoursMillis - 1
    let stillValid = try! manager.keyForRetry(transactionId: "aging", fingerprint: attempt.fingerprint()) == held
    now = 1_000 + IdempotencyKeyManager.twentyFourHoursMillis
    var expired = false
    do { _ = try manager.keyForChallenge(transactionId: "aging") } catch MeridianError.idempotencyKeyExpired(_) { expired = true } catch { expired = false }
    check("expired key is retained but not returned", stillValid && expired && manager.activeKey(transactionId: "aging") == nil && manager.storedRecords().count == 1)

    print("26. fingerprint mismatch keeps the original key...")
    now = 50
    let bound = try! IdempotencyKeyManager(store: MemoryIdempotencyStore(), clock: { now })
    let original = PaymentAttempt(recipientId: "rec-1", amountMinor: 100, method: "card", note: "note", scenario: "success")
    let boundKey = try! bound.begin(transactionId: "tx-1", fingerprint: original.fingerprint())
    let changed = PaymentAttempt(recipientId: "rec-1", amountMinor: 200, method: "card", note: "note", scenario: "success")
    var mismatched = false
    do { _ = try bound.keyForRetry(transactionId: "tx-1", fingerprint: changed.fingerprint()) } catch MeridianError.validationError(_) { mismatched = true } catch { mismatched = false }
    let unchanged = try! bound.keyForChallenge(transactionId: "tx-1", fingerprint: original.fingerprint())
    check("mismatch does not rotate the key", mismatched && unchanged == boundKey)

    print("27. fingerprint round trip...")
    let noted = PaymentAttempt(recipientId: "northline-studio", amountMinor: 2599, method: "card", note: "line\\one\u{1f}next", scenario: "success")
    check("note text survives the fingerprint", PaymentAttempt.fromFingerprint(noted.fingerprint()) == noted)

    print("28. file store reloads the same key...")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("meridian-idempotency-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = FileIdempotencyStore.fileURL(directory: directory, sessionId: "room/1")
    let first = try! IdempotencyKeyManager(store: FileIdempotencyStore(fileURL: file), clock: { 4_000 })
    let stored = try! first.begin(transactionId: "tx-9", fingerprint: original.fingerprint())
    let second = try! IdempotencyKeyManager(store: FileIdempotencyStore(fileURL: file), clock: { 4_000 })
    let reloaded = try! second.keyForRetry(transactionId: "tx-9", fingerprint: original.fingerprint())
    try! second.settle(transactionId: "tx-9")
    let third = try! IdempotencyKeyManager(store: FileIdempotencyStore(fileURL: file), clock: { 4_000 })
    check("persisted key reloads and settle removes it", stored == reloaded && third.storedRecords().isEmpty)
    try? FileManager.default.removeItem(at: directory)

    print("29. managed POST /payments keeps one header across retry and challenge...")
    let transport = runTransportCheck()
    check("header, retry, challenge, expiry and settlement", transport)

    return (passed, failed)
  }

  static func runTransportCheck() -> Bool {
    final class PaymentCapture: URLProtocol {
      static let gate = NSLock()
      static var keys: [String] = []
      static var hits = 0
      override class func canInit(with request: URLRequest) -> Bool { true }
      override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
      override func startLoading() {
        let header = request.value(forHTTPHeaderField: "Idempotency-Key") ?? ""
        PaymentCapture.gate.lock()
        PaymentCapture.keys.append(header)
        PaymentCapture.hits += 1
        let hit = PaymentCapture.hits
        PaymentCapture.gate.unlock()
        let pending = hit < 4
        let body = pending
          ? #"{"ok":false,"code":"PAYMENT_PENDING","paymentId":"pay-1","error":"Awaiting confirmation"}"#
          : #"{"ok":true,"paymentId":"pay-1","transaction":{"id":"txn-1","reference":"r","recipientId":"rec-1","name":"Northline","category":"Shopping","amount":100,"date":"2026-10-04","provider":"adyen","method":"card","status":"completed","note":""}}"#
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: pending ? 202 : 200,
          httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
      }
      override func stopLoading() {}
    }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [PaymentCapture.self]
    let session = URLSession(configuration: config)
    var generated = 0
    let manager = try! IdempotencyKeyManager(
      store: MemoryIdempotencyStore(),
      clock: { 9_000 },
      uuidGenerator: {
        generated += 1
        return String(format: "00000000-0000-4000-8000-%012d", generated)
      }
    )
    let client = try! MeridianClient(
      baseURL: "http://127.0.0.1:9/api/v1",
      sessionId: "test-session",
      urlSession: session,
      idempotency: manager
    )
    let semaphore = DispatchSemaphore(value: 0)
    let result = Box(false)
    Task {
      defer { semaphore.signal() }
      do {
        let first = try await client.submitPayment(recipientId: "rec-1", amountMinor: 100, method: .card, transactionId: "local-1")
        let retried = try await client.retryPayment(transactionId: "local-1", recipientId: "rec-1", amountMinor: 100, method: .card)
        let challenged = try await client.submitChallenge(transactionId: "local-1", recipientId: "rec-1", amountMinor: 100, method: .card)
        let settled = try await client.submitPayment(recipientId: "rec-1", amountMinor: 100, method: .card, transactionId: "local-1")
        var missing = false
        do { _ = try await client.retryPayment(transactionId: "local-1", recipientId: "rec-1", amountMinor: 100, method: .card) } catch MeridianError.missingIdempotencyKey(_) { missing = true } catch { missing = false }
        let hitsAfterSettle = PaymentCapture.hits
        try manager.begin(transactionId: "local-3", fingerprint: PaymentAttempt(recipientId: "rec-1", amountMinor: 100, method: "card", note: "", scenario: "success").fingerprint())
        var mismatched = false
        do { _ = try await client.retryPayment(transactionId: "local-3", recipientId: "rec-1", amountMinor: 250, method: .card) } catch MeridianError.validationError(_) { mismatched = true } catch { mismatched = false }
        let expected = String(format: "00000000-0000-4000-8000-%012d", 1)
        result.value = !first.ok && !retried.ok && !challenged.ok && settled.ok && missing && mismatched
          && PaymentCapture.keys.prefix(4).allSatisfy { $0 == expected }
          && manager.storedRecords().count == 1
          && PaymentCapture.hits == hitsAfterSettle
          && generated == 2
      } catch {
        print("  transport error: \(error)")
        result.value = false
      }
    }
    let finished = semaphore.wait(timeout: .now() + 10)
    return finished == .success && result.value
  }
}

private final class Box {
  var value: Bool
  init(_ value: Bool) { self.value = value }
}
