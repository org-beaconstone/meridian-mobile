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

    let catalog = runCatalogChecks()
    passed += catalog.passed
    failed += catalog.failed

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

private struct CheckTally {
  var passed = 0
  var failed = 0
  mutating func pass(_ name: String) {
    print("  ✓ \(name)")
    passed += 1
  }
  mutating func fail(_ name: String) {
    print("  ✗ \(name)")
    failed += 1
  }
}

private final class Once<T>: @unchecked Sendable {
  var value: T?
}

private func awaitResult<T>(_ work: @escaping () async -> T) -> T {
  let box = Once<T>()
  let semaphore = DispatchSemaphore(value: 0)
  Task.detached {
    box.value = await work()
    semaphore.signal()
  }
  semaphore.wait()
  return box.value!
}

private final class CatalogHTTPStub: URLProtocol, @unchecked Sendable {
  struct Scripted {
    var status: Int = 200
    var body: Data = Data()
    var headers: [String: String] = ["Content-Type": "application/json"]
    var error: Error?
  }
  static let lock = NSLock()
  static var script: ((URLRequest) -> Scripted)?
  static var urls: [String] = []

  static func reset() {
    lock.lock()
    script = nil
    urls = []
    lock.unlock()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    CatalogHTTPStub.lock.lock()
    CatalogHTTPStub.urls.append(request.url?.absoluteString ?? "")
    let scripted = CatalogHTTPStub.script?(request)
    CatalogHTTPStub.lock.unlock()
    guard let scripted else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    if let error = scripted.error {
      client?.urlProtocol(self, didFailWithError: error)
      return
    }
    let response = HTTPURLResponse(
      url: request.url ?? URL(string: "http://127.0.0.1/catalog")!,
      statusCode: scripted.status,
      httpVersion: "HTTP/1.1",
      headerFields: scripted.headers
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: scripted.body)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

private func stubSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [CatalogHTTPStub.self]
  return URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
}

private func sampleCatalogJSON(extraProvider: Bool) -> Data {
  let extra = extraProvider
    ? #",{"id":"other","name":"Other","description":"Unbound","methods":["card"],"currencies":["GBP"]}"#
    : ""
  let json = """
  {
    "demoDate": "2026-09-18",
    "recipients": [{"id":"northline-studio","name":"Northline Studio","initials":"NS","detail":"Design","category":"Shopping","color":"#fff"}],
    "providers": [
      {"id":"worldpay","name":"Worldpay","description":"Bank","methods":["bank_transfer"],"supportedCurrencies":["GBP"]},
      {"id":"adyen","name":"Renamed","description":"Injected","methods":["card"],"currencies":["EUR","GBP"],"corridors":[{"id":"gb-card","method":"card","currency":"GBP","country":"gb"}]}\(extra)
    ]
  }
  """
  return Data(json.utf8)
}

private func runCatalogChecks() -> (passed: Int, failed: Int) {
  var tally = CheckTally()
  print("21. Static provider binding...")
  let ids = ProviderId.allCases.map(\.rawValue)
  if ids == ["adyen", "worldpay"]
    && ProviderId.adyen.checkoutLabel == "Debit card · Adyen"
    && ProviderId.worldpay.checkoutLabel == "Bank payment · Worldpay"
    && ProviderId.adyen.paymentMethod == .card
    && ProviderId.worldpay.paymentMethod == .bank {
    tally.pass("ProviderId remains Adyen card and Worldpay bank")
  } else {
    tally.fail("ProviderId binding changed: \(ids)")
  }

  print("22. Dynamic provider decode is not the static enum...")
  let unknown = Data(#"{"id":"other","name":"Other","description":"x","methods":["card"]}"#.utf8)
  do {
    _ = try JSONDecoder().decode(Provider.self, from: unknown)
    tally.fail("Static Provider accepted an unbound id")
  } catch {
    tally.pass("Static Provider rejected unbound id")
  }
  do {
    let dynamic = try JSONDecoder().decode(DynamicProvider.self, from: unknown)
    if dynamic.id == "other" {
      tally.pass("DynamicProvider decoded unbound id")
    } else {
      tally.fail("DynamicProvider id mismatch")
    }
  } catch {
    tally.fail("DynamicProvider decode failed: \(error)")
  }

  print("23. Baseline projection...")
  let decoded = try? JSONDecoder().decode(CatalogResponse.self, from: sampleCatalogJSON(extraProvider: true))
  let projected = decoded.map(projectBaselineCatalog)
  if projected?.providers.map(\.id) == ["adyen", "worldpay"]
    && projected?.providers.first?.name == "Adyen"
    && projected?.providers.first?.currencies == ["GBP"]
    && projected?.providers.first?.corridors.first?.method == "card"
    && projected?.providers.first?.corridors.first?.id == "gb-card"
    && projected?.providers.last?.corridors.first?.method == "bank"
    && projected?.recipients.count == 1
    && projected?.providers.contains(where: { $0.id == "other" || $0.name == "Other" || $0.name == "Renamed" }) == false {
    tally.pass("Projection keeps Adyen card and Worldpay bank in GBP")
  } else {
    tally.fail("Projection mismatch: \(String(describing: projected?.providers.map(\.id)))")
  }

  guard let seeded = projected else {
    tally.fail("Projected catalog missing")
    return (tally.passed, tally.failed)
  }

  print("24. Encrypted catalog cache...")
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("meridian-catalog-\(UUID().uuidString)")
  do {
    let cache = try FileEncryptedCatalogCache(directory: directory, useKeychain: false)
    cache.save(sessionId: "room-a", catalog: seeded)
    let blob = cache.ciphertext(sessionId: "room-a") ?? Data()
    let stored = String(data: blob, encoding: .utf8) ?? ""
    let restored = try FileEncryptedCatalogCache(directory: directory, useKeychain: false)
    let loaded = restored.load(sessionId: "room-a")
    if loaded?.recipients.first?.name == "Northline Studio"
      && loaded?.providers.map(\.id) == ["adyen", "worldpay"]
      && restored.load(sessionId: "room-b") == nil
      && !stored.contains("Northline")
      && !stored.contains("adyen")
      && !blob.isEmpty {
      tally.pass("Encrypted cache round-trip stays opaque")
    } else {
      tally.fail("Encrypted cache round-trip failed")
    }
  } catch {
    tally.fail("Encrypted cache setup failed: \(error)")
  }

  print("25. Catalog network projection and cache...")
  CatalogHTTPStub.reset()
  CatalogHTTPStub.script = { request in
    guard request.value(forHTTPHeaderField: "X-Rehearsal-Session") == "room-1",
          request.timeoutInterval == 15 else {
      return CatalogHTTPStub.Scripted(status: 400)
    }
    return CatalogHTTPStub.Scripted(status: 200, body: sampleCatalogJSON(extraProvider: true))
  }
  let network = awaitResult { () -> CatalogLoad in
    let client = try! MeridianClient(baseURL: "http://127.0.0.1:9/api/v1", sessionId: "room-1", urlSession: stubSession())
    let cache = MemoryEncryptedCatalogCache()
    let loaded = await client.loadCatalog(cache: cache)
    let blob = cache.ciphertext(sessionId: "room-1") ?? Data()
    let stored = String(data: blob, encoding: .utf8) ?? ""
    if blob.isEmpty || stored.contains("Other") || stored.contains("Northline") {
      return CatalogLoad(catalog: nil, origin: nil)
    }
    return loaded
  }
  let urls = CatalogHTTPStub.urls
  if network.origin == .network
    && network.catalog?.providers.map(\.id) == ["adyen", "worldpay"]
    && network.catalog?.providers.first?.corridors.first?.country == "GB"
    && urls.count == 1
    && urls.first?.hasSuffix("/api/v1/catalog") == true {
    tally.pass("GET /catalog cached one projected response")
  } else {
    tally.fail("Network catalog failed: \(urls)")
  }

  print("26. HTTP 500 uses the saved catalog once...")
  CatalogHTTPStub.reset()
  let serverFailure = awaitResult { () -> (CatalogLoad, Int) in
    let cache = MemoryEncryptedCatalogCache()
    cache.save(sessionId: "room-1", catalog: seeded)
    CatalogHTTPStub.script = { _ in CatalogHTTPStub.Scripted(status: 500, body: Data("{\"error\":\"down\"}".utf8)) }
    let client = try! MeridianClient(baseURL: "http://127.0.0.1:9/api/v1", sessionId: "room-1", urlSession: stubSession())
    let loaded = await client.loadCatalog(cache: cache)
    return (loaded, CatalogHTTPStub.urls.count)
  }
  if serverFailure.0.origin == .cache
    && serverFailure.0.catalog?.recipients.first?.name == "Northline Studio"
    && serverFailure.1 == 1 {
    tally.pass("HTTP 500 fell back to cache without a second request")
  } else {
    tally.fail("HTTP 500 fallback failed")
  }

  print("27. Timeout uses the saved catalog once...")
  CatalogHTTPStub.reset()
  let timedOut = awaitResult { () -> (CatalogLoad, Int) in
    let cache = MemoryEncryptedCatalogCache()
    cache.save(sessionId: "room-1", catalog: seeded)
    CatalogHTTPStub.script = { _ in CatalogHTTPStub.Scripted(error: URLError(.timedOut)) }
    let client = try! MeridianClient(baseURL: "http://127.0.0.1:9/api/v1", sessionId: "room-1", urlSession: stubSession())
    let loaded = await client.loadCatalog(cache: cache)
    return (loaded, CatalogHTTPStub.urls.count)
  }
  if timedOut.0.origin == .cache && timedOut.1 == 1 {
    tally.pass("Timeout fell back to cache without another host")
  } else {
    tally.fail("Timeout fallback failed")
  }

  print("28. HTTP 400 does not use the cache...")
  CatalogHTTPStub.reset()
  let rejected = awaitResult { () -> CatalogLoad in
    let cache = MemoryEncryptedCatalogCache()
    cache.save(sessionId: "room-1", catalog: seeded)
    CatalogHTTPStub.script = { _ in CatalogHTTPStub.Scripted(status: 400, body: Data("{\"error\":\"bad\"}".utf8)) }
    let client = try! MeridianClient(baseURL: "http://127.0.0.1:9/api/v1", sessionId: "room-1", urlSession: stubSession())
    return await client.loadCatalog(cache: cache)
  }
  if rejected.catalog == nil && rejected.origin == nil {
    tally.pass("HTTP 400 did not substitute the cache")
  } else {
    tally.fail("HTTP 400 unexpectedly returned a catalog")
  }

  print("29. Redirect is not followed...")
  CatalogHTTPStub.reset()
  let redirected = awaitResult { () -> (CatalogLoad, [String]) in
    CatalogHTTPStub.script = { _ in
      CatalogHTTPStub.Scripted(status: 302, headers: ["Location": "http://evil.example/collect", "Content-Type": "application/json"])
    }
    let client = try! MeridianClient(baseURL: "http://127.0.0.1:9/api/v1", sessionId: "room-1", urlSession: stubSession())
    let loaded = await client.loadCatalog(cache: MemoryEncryptedCatalogCache())
    return (loaded, CatalogHTTPStub.urls)
  }
  if redirected.0.catalog == nil
    && redirected.1.count == 1
    && redirected.1.allSatisfy({ !$0.contains("evil.example") }) {
    tally.pass("Catalog redirect was not followed")
  } else {
    tally.fail("Redirect behavior failed: \(redirected.1)")
  }

  return (tally.passed, tally.failed)
}
