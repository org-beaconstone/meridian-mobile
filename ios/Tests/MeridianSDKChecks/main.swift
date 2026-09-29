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

    let catalog = waitFor { await runCatalogChecks() }
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

final class CheckClock {
  var millis: Int64 = 1_700_000_000_000
}

final class CatalogStubProtocol: URLProtocol {
  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
      return
    }
    do {
      let (status, body) = try handler(request)
      let response = HTTPURLResponse(
        url: request.url!,
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

struct CheckTally {
  var passed = 0
  var failed = 0
  mutating func ok(_ name: String) {
    passed += 1
    print("  ✓ \(name)")
  }
  mutating func bad(_ name: String, _ detail: String) {
    failed += 1
    print("  ✗ \(name): \(detail)")
  }
}

func waitFor<T>(_ work: @escaping () async -> T) -> T {
  let box = UncheckedBox<T>()
  let sem = DispatchSemaphore(value: 0)
  Task.detached {
    box.value = await work()
    sem.signal()
  }
  let deadline = Date().addingTimeInterval(20)
  while sem.wait(timeout: .now() + 0.05) == .timedOut {
    if Date() > deadline {
      print("  ✗ catalog checks timed out")
      exit(1)
    }
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
  }
  return box.value!
}

final class UncheckedBox<T> {
  var value: T?
}

func catalogDocument(providers: String, corridors: String = "[]") -> Data {
  let json = """
  {"demoDate":"2026-09-18","recipients":[{"id":"northline-studio","name":"CACHE-TOKEN-XYZZY","initials":"NS","detail":"Design","category":"Shopping","color":"#112233"}],"providers":[\(providers)],"corridors":\(corridors)}
  """
  return Data(json.utf8)
}

let adyenProvider = #"{"id":"adyen","name":"Adyen","description":"Card payment processor","methods":["card"]}"#
let worldpayProvider = #"{"id":"worldpay","name":"Worldpay","description":"Bank payment processor","methods":["bank"]}"#
let gbpCorridors = #"[{"id":"gb-card","provider":"adyen","method":"card","currency":"GBP"},{"id":"gb-bank","provider":"worldpay","method":"bank","currency":"GBP"}]"#

func runCatalogChecks() async -> CheckTally {
  var tally = CheckTally()
  print("21. Catalog availability defaults to offered...")
  let decoder = JSONDecoder()
  let legacy = catalogDocument(providers: adyenProvider + "," + worldpayProvider, corridors: gbpCorridors)
  do {
    let catalog = try decoder.decode(CatalogResponse.self, from: legacy)
    if catalog.providers.allSatisfy(\.available) && catalog.corridors.count == 2 && catalog.activeProviders.count == 2 {
      tally.ok("legacy catalog stays available and keeps GBP corridors")
    } else {
      tally.bad("legacy catalog", "availability or corridors mismatch")
    }
  } catch {
    tally.bad("legacy catalog", "decode failed")
  }

  print("22. Unavailable baseline provider is hidden...")
  let hidden = catalogDocument(
    providers: #"{"id":"adyen","name":"Adyen","description":"Card payment processor","methods":["card"],"available":false},\#(worldpayProvider)"#
  )
  do {
    let catalog = try decoder.decode(CatalogResponse.self, from: hidden)
    let active = catalog.activeProviders
    if active.count == 1 && active[0].id == .worldpay {
      tally.ok("unavailable Adyen omitted from active presentation")
    } else {
      tally.bad("unavailable provider", "active count \(active.count)")
    }
  } catch {
    tally.bad("unavailable provider", "decode threw")
  }

  print("23. Unrecognized provider id is rejected...")
  let unknown = catalogDocument(
    providers: adyenProvider + "," + #"{"id":"unrecognized","name":"X","description":"Y","methods":["card"]}"#
  )
  if (try? decoder.decode(CatalogResponse.self, from: unknown)) == nil {
    tally.ok("unrecognized provider id does not decode into the catalog")
  } else {
    tally.bad("unrecognized provider", "payload was accepted")
  }

  print("24. Baseline pairing rejects a swapped method...")
  let swapped = CatalogResponse(
    demoDate: "2026-09-18",
    recipients: [],
    providers: [
      Provider(id: .adyen, name: "Adyen", description: "Card", methods: [.bank])
    ]
  )
  if ProviderBaseline.accept(swapped) == nil && ProviderBaseline.accept(ProviderBaseline.fallbackCatalog()) != nil {
    tally.ok("Adyen stays card and Worldpay stays bank")
  } else {
    tally.bad("baseline pairing", "accept() mismatch")
  }

  print("25. Encrypted catalog file round-trip...")
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("meridian-catalog-\(UUID().uuidString)", isDirectory: true)
  let store = EncryptedFileCatalogStore(directory: directory)
  let tokenCatalog = try? decoder.decode(CatalogResponse.self, from: legacy)
  if let tokenCatalog {
    store.save(StoredCatalog(fetchedAtEpochMillis: 42, catalog: tokenCatalog))
    let blob = directory.appendingPathComponent("catalog.bin")
    let bytes = (try? Data(contentsOf: blob)) ?? Data()
    let leaked = bytes.range(of: Data("CACHE-TOKEN-XYZZY".utf8)) != nil
    let restored = store.load()
    if !leaked && restored?.catalog.recipients.first?.name == "CACHE-TOKEN-XYZZY" && restored?.fetchedAtEpochMillis == 42 {
      tally.ok("catalog blob is encrypted and restores the saved payload")
    } else {
      tally.bad("encrypted store", "leaked=\(leaked) restored=\(restored != nil)")
    }
  } else {
    tally.bad("encrypted store", "fixture did not decode")
  }
  try? FileManager.default.removeItem(at: directory)

  print("26. Cached catalog survives gateway and offline errors...")
  URLProtocol.registerClass(CatalogStubProtocol.self)
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [CatalogStubProtocol.self]
  let session = URLSession(configuration: config)
  let memory = InMemoryCatalogStore()
  let clock = CheckClock()
  let hits = CheckClock()
  hits.millis = 0
  do {
    let client = try MeridianClient(
      baseURL: "http://127.0.0.1:8080/api/v1",
      sessionId: "catalog-check",
      urlSession: session,
      catalogTTL: 300,
      catalogStore: memory,
      now: { Date(timeIntervalSince1970: TimeInterval(clock.millis) / 1000) }
    )
    CatalogStubProtocol.handler = { request in
      guard request.url?.path.hasSuffix("/catalog") == true else {
        return (404, Data("{}".utf8))
      }
      hits.millis += 1
      return (200, catalogDocument(providers: adyenProvider + "," + worldpayProvider, corridors: gbpCorridors))
    }
    let first = await client.loadCatalog()
    if first.origin == .network && first.catalog.activeProviders.count == 2 && hits.millis == 1 {
      tally.ok("first catalog load stores the network payload")
    } else {
      tally.bad("network load", "origin \(first.origin) hits \(hits.millis)")
    }

    CatalogStubProtocol.handler = { _ in
      hits.millis += 1
      return (500, Data("nope".utf8))
    }
    let fresh = await client.loadCatalog()
    if fresh.origin == .cache && hits.millis == 1 && fresh.catalog.activeProviders.count == 2 {
      tally.ok("fresh cache skips the network until TTL")
    } else {
      tally.bad("ttl", "origin \(fresh.origin) hits \(hits.millis)")
    }

    clock.millis += 301_000
    let after500 = await client.loadCatalog()
    CatalogStubProtocol.handler = { _ in (502, Data()) }
    let after502 = await client.loadCatalog()
    CatalogStubProtocol.handler = { _ in (504, Data()) }
    let after504 = await client.loadCatalog()
    if after500.origin == .fallback && after502.origin == .fallback && after504.origin == .fallback
      && after504.catalog.providers.map(\.id) == [.adyen, .worldpay] {
      tally.ok("HTTP 500, 502, and 504 reuse the last accepted catalog")
    } else {
      tally.bad("gateway fallback", "origins \(after500.origin) \(after502.origin) \(after504.origin)")
    }

    CatalogStubProtocol.handler = { _ in
      throw URLError(.notConnectedToInternet)
    }
    let offline = await client.loadCatalog()
    CatalogStubProtocol.handler = { _ in
      (200, catalogDocument(providers: adyenProvider + "," + #"{"id":"unrecognized","name":"X","description":"Y","methods":["card"]}"#))
    }
    let rejected = await client.loadCatalog()
    if offline.origin == .fallback && rejected.origin == .fallback && rejected.catalog.activeProviders.count == 2 {
      tally.ok("offline and unrecognized catalogs keep the saved baseline")
    } else {
      tally.bad("offline fallback", "offline \(offline.origin) rejected \(rejected.origin)")
    }

    CatalogStubProtocol.handler = { _ in
      (200, catalogDocument(providers: #"{"id":"adyen","name":"Adyen","description":"Card payment processor","methods":["card"],"available":false},\#(worldpayProvider)"#))
    }
    let flagged = await client.loadCatalog()
    if flagged.origin == .network && flagged.catalog.activeProviders.map(\.id) == [.worldpay] {
      tally.ok("unavailable provider is stored and left out of active presentation")
    } else {
      tally.bad("flagged provider", "origin \(flagged.origin) count \(flagged.catalog.activeProviders.count)")
    }
  } catch {
    tally.bad("catalog client", "setup failed")
  }

  print("27. Empty cache falls back to the compiled baseline...")
  let empty = InMemoryCatalogStore()
  CatalogStubProtocol.handler = { _ in (500, Data()) }
  do {
    let client = try MeridianClient(
      baseURL: "http://127.0.0.1:8080/api/v1",
      sessionId: "catalog-empty",
      urlSession: session,
      catalogTTL: 300,
      catalogStore: empty,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
    let baseline = await client.loadCatalog()
    let ids = baseline.catalog.providers.map(\.id)
    if baseline.origin == .baseline && ids == [.adyen, .worldpay] {
      tally.ok("gateway error with no cache uses Adyen and Worldpay")
    } else {
      tally.bad("compiled baseline", "origin \(baseline.origin)")
    }
  } catch {
    tally.bad("compiled baseline", "setup failed")
  }

  return tally
}
