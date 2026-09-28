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

    let catalogResult = await runCatalogChecks()
    passed += catalogResult.passed
    failed += catalogResult.failed

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

private struct CatalogCheckResult {
  var passed = 0
  var failed = 0

  mutating func expect(_ name: String, _ condition: Bool) {
    if condition {
      print("  ✓ \(name)")
      passed += 1
    } else {
      print("  ✗ \(name)")
      failed += 1
    }
  }
}

private final class CatalogHTTPStub: URLProtocol, @unchecked Sendable {
  static let lock = NSLock()
  static var handler: ((URLRequest) throws -> (Int, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.lock.lock()
    let handler = Self.handler
    Self.lock.unlock()
    guard let handler, let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    do {
      let (status, body) = try handler(request)
      let response = HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }
  override func stopLoading() {}
}

private final class CatalogClock: @unchecked Sendable {
  var date: Date
  init(_ date: Date) { self.date = date }
  func now() -> Date { date }
}

private func catalogJSON(providers: String, corridors: String = #"[{"id":"gb-domestic","source":"GB","destination":"GB","currency":"GBP"},{"id":"closed","source":"GB","destination":"GB","currency":"GBP","available":false}]"#) -> Data {
  let json = """
  {
    "demoDate": "saved",
    "recipients": [
      {"id":"northline-studio","name":"Northline Studio","initials":"NS","detail":"Design","category":"Shopping","color":"#111111"}
    ],
    "providers": \(providers),
    "corridors": \(corridors)
  }
  """
  return Data(json.utf8)
}

private let baselineProviders = #"""
[{"id":"adyen","name":"Adyen","description":"Card payment processor","methods":["card"]},{"id":"worldpay","name":"Worldpay","description":"Bank payment processor","methods":["bank"]}]
"""#

private final class CatalogScript: @unchecked Sendable {
  var status = 200
  var body = catalogJSON(providers: baselineProviders)
  var hits = 0
}

private func runCatalogChecks() async -> CatalogCheckResult {
  var result = CatalogCheckResult()
  print("21. Catalog cache, fallback, and baseline providers...")
  let clock = CatalogClock(Date(timeIntervalSince1970: 10))
  let store = MemoryCatalogStore()
  let script = CatalogScript()
  CatalogHTTPStub.handler = { request in
    script.hits += 1
    if request.value(forHTTPHeaderField: "X-Rehearsal-Session") == nil {
      throw URLError(.userAuthenticationRequired)
    }
    return (script.status, script.body)
  }
  URLProtocol.registerClass(CatalogHTTPStub.self)
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [CatalogHTTPStub.self]
  let session = URLSession(configuration: configuration)
  do {
    let client = try MeridianClient(
      baseURL: "http://catalog.test/api/v1",
      sessionId: "room-a",
      urlSession: session,
      catalogStore: store,
      catalogTtl: 1,
      now: { clock.now() }
    )
    let first = try await client.getCatalog()
    result.expect("catalog decodes both baseline providers", first.providers.map(\.id) == ["adyen", "worldpay"])
    result.expect("catalog decodes recipients", first.recipients.map(\.id) == ["northline-studio"])
    result.expect("unavailable corridors are hidden", first.corridors.map(\.id) == ["gb-domestic"])
    let firstWasFallback = await client.catalogUsingFallback
    result.expect("fresh catalog is not a fallback", firstWasFallback == false)
    let cached = try await client.getCatalog()
    result.expect("fresh cache skips the network", script.hits == 1 && cached.providers.map(\.id) == ["adyen", "worldpay"])

    clock.date = clock.date.addingTimeInterval(5)
    script.status = 502
    script.body = Data(#"{"error":"bad gateway"}"#.utf8)
    let gateway = try await client.getCatalog()
    let gatewayWasFallback = await client.catalogUsingFallback
    result.expect("HTTP 502 reuses the saved catalog", gateway.recipients.map(\.id) == ["northline-studio"] && gatewayWasFallback)

    script.status = 500
    let internalError = try await client.getCatalog()
    result.expect("HTTP 500 reuses the saved catalog", internalError.providers.map(\.id) == ["adyen", "worldpay"])

    script.status = 504
    let timeout = try await client.getCatalog()
    result.expect("HTTP 504 keeps Adyen card and Worldpay bank", timeout.activeBaselineMethods() == Set([PaymentMethod.card, PaymentMethod.bank]))

    script.status = 200
    script.body = catalogJSON(providers: #"[{"id":"adyen","name":"Adyen","description":"Card payment processor","methods":["card"],"available":false},{"id":"worldpay","name":"Worldpay","description":"Bank payment processor","methods":["bank"]}]"#)
    let hidden = try await client.getCatalog()
    result.expect("unavailable Adyen is hidden", hidden.providers.map(\.id) == ["worldpay"] && hidden.activeBaselineMethods() == Set([PaymentMethod.bank]))

    clock.date = clock.date.addingTimeInterval(5)
    script.body = catalogJSON(providers: #"[{"id":"adyen","name":"Adyen","description":"Card payment processor","methods":["card"]},{"id":"unknown","name":"Unknown","description":"Unrecognized","methods":["card"]}]"#)
    let rejected = try await client.getCatalog()
    let saved = store.read(cacheKey: "http://catalog.test/api/v1\nroom-a")
    result.expect(
      "unrecognized provider falls back",
      rejected.providers.map(\.id) == ["worldpay"] && saved?.catalog.providers.contains { $0.id == "unknown" } == false
    )

    script.status = 400
    script.body = Data(#"{"error":"bad request"}"#.utf8)
    clock.date = clock.date.addingTimeInterval(5)
    var threw400 = false
    do {
      _ = try await client.getCatalog()
    } catch let error as MeridianError {
      if case let .httpError(code, _) = error, code == 400 { threw400 = true }
    }
    result.expect("HTTP 400 is not treated as a catalog", threw400)

    let other = try MeridianClient(
      baseURL: "http://catalog.test/api/v1",
      sessionId: "room-b",
      urlSession: session,
      catalogStore: store,
      catalogTtl: 1,
      now: { clock.now() }
    )
    script.status = 504
    let isolated = try await other.getCatalog()
    result.expect("sessions do not share catalogs", isolated.recipients.isEmpty && isolated.providers.map(\.id) == ["adyen", "worldpay"])

    script.status = 200
    script.body = catalogJSON(providers: baselineProviders)
    CatalogHTTPStub.handler = { _ in throw URLError(.notConnectedToInternet) }
    clock.date = clock.date.addingTimeInterval(5)
    let offline = try await client.getCatalog()
    let offlineWasFallback = await client.catalogUsingFallback
    result.expect("offline load reuses the saved catalog", offline.recipients.map(\.id) == ["northline-studio"] && offlineWasFallback)
  } catch {
    print("  ✗ catalog checks threw \(error)")
    result.failed += 1
  }

  print("22. Encrypted catalog storage...")
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("meridian-catalog-\(UUID().uuidString)", isDirectory: true)
  do {
    let encrypted = try EncryptedFileCatalogStore(directory: directory)
    try encrypted.write(cacheKey: "room-secret", entry: CachedCatalog(catalog: baselineCatalog(), fetchedAtEpochMs: 42))
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    let blobURL = files.first { $0.lastPathComponent.hasSuffix(".catalog") }
    let blob = try Data(contentsOf: blobURL!)
    let text = String(decoding: blob, as: UTF8.self)
    let isJsonObject = !blob.isEmpty && blob[0] == UInt8(ascii: "{")
    result.expect("catalog file is not plaintext", !text.contains("worldpay") && !text.contains("adyen") && !isJsonObject)
    let reopened = try EncryptedFileCatalogStore(directory: directory)
    let loaded = reopened.read(cacheKey: "room-secret")
    result.expect(
      "encrypted catalog round-trips",
      loaded?.fetchedAtEpochMs == 42 && loaded?.catalog.providers.map(\.id) == ["adyen", "worldpay"]
    )
    result.expect("other cache keys stay empty", reopened.read(cacheKey: "other") == nil)
  } catch {
    print("  ✗ encrypted catalog checks threw \(error)")
    result.failed += 1
  }
  try? FileManager.default.removeItem(at: directory)
  return result
}
