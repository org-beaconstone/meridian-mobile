import Foundation
@testable import MeridianSDK

final class CatalogCheckLog {
  var passed = 0
  var failed = 0
  private var number = 20

  func expect(_ condition: Bool, _ name: String, _ detail: String = "") {
    number += 1
    if condition {
      print("\(number). \(name)...")
      print("  ✓ \(name)")
      passed += 1
    } else {
      print("\(number). \(name)...")
      print("  ✗ \(name) \(detail)")
      failed += 1
    }
  }
}

func runCatalogChecks() -> (passed: Int, failed: Int) {
  let log = CatalogCheckLog()
  checkOpenCatalog(log)
  checkExpiry(log)
  checkUrl(log)
  #if canImport(CryptoKit)
  checkEncryption(log)
  let semaphore = DispatchSemaphore(value: 0)
  Task {
    await checkHttp(log)
    semaphore.signal()
  }
  semaphore.wait()
  #endif
  return (log.passed, log.failed)
}

private func checkOpenCatalog(_ log: CatalogCheckLog) {
  let json = """
  {
    "accountScope": "everyday",
    "corridor": "GB",
    "currency": "GBP",
    "ttlSeconds": 300,
    "generatedBy": "catalog-service",
    "routingHint": {"lane": "future"},
    "methods": [
      {
        "id": "card-adyen",
        "method": "card",
        "provider": "adyen",
        "displayName": "Debit card",
        "requiresLiveEligibility": false,
        "capabilities": ["pay", {"kind": "future"}],
        "futureSettlementWindow": "T+2",
        "wallet": {"type": "later"}
      },
      {"futureOnly": true},
      {
        "id": "bank-worldpay",
        "method": "bank",
        "provider": "worldpay",
        "displayName": 12,
        "requiresLiveEligibility": true,
        "capabilities": ["pay", "live-eligibility"]
      }
    ]
  }
  """
  do {
    let catalog = try parsePaymentMethodsCatalog(json: json)
    log.expect(catalog.ignoredAttributeNames == ["generatedBy", "routingHint"], "open catalog ignores unknown attributes")
    log.expect(catalog.methods.count == 2, "malformed descriptor is skipped", "count \(catalog.methods.count)")
    let card = catalog.methods.first
    log.expect(card?.provider == "adyen" && card?.capabilities == ["pay"], "descriptor keeps known fields")
    log.expect(card?.ignoredAttributeNames == ["futureSettlementWindow", "wallet"], "unknown descriptor attributes are listed")
    let bank = catalog.methods.dropFirst().first
    log.expect(bank?.displayName == "" && bank?.requiresFreshEligibility == true, "non-string display name does not crash")
    let resolved = CatalogExpiryPolicy.resolve(catalog: try catalog.forRequest(accountScope: "everyday", corridor: "GB", currency: "GBP"), storedAtEpochMs: 0, nowEpochMs: 0, fromCache: false)
    log.expect(resolved.payableBaseline.map(\.provider) == ["adyen", "worldpay"], "baseline stays Adyen card and Worldpay bank")
  } catch {
    log.expect(false, "open catalog parses", String(describing: error))
  }
}

private func checkExpiry(_ log: CatalogCheckLog) {
  let catalog = PaymentMethodsCatalog(
    accountScope: "everyday",
    corridor: "GB",
    currency: "GBP",
    ttlSeconds: 300,
    methods: [
      PaymentMethodDescriptor(id: "card-adyen", method: "card", provider: "adyen", displayName: "Debit card", currency: "GBP", corridor: "GB", capabilities: ["pay"]),
      PaymentMethodDescriptor(id: "bank-worldpay", method: "bank", provider: "worldpay", displayName: "Bank payment", currency: "GBP", corridor: "GB", requiresLiveEligibility: true, capabilities: ["pay", "live-eligibility"]),
      PaymentMethodDescriptor(id: "later", method: "card", provider: "unreleased", displayName: "Later", currency: "GBP", corridor: "GB"),
    ]
  )
  let fresh = CatalogExpiryPolicy.resolve(catalog: catalog, storedAtEpochMs: 0, nowEpochMs: 299_999, fromCache: true)
  log.expect(!fresh.stale && fresh.payableBaseline.map(\.provider) == ["adyen", "worldpay"], "fresh catalog keeps live eligibility")
  log.expect(!fresh.payableBaseline.contains { $0.provider == "unreleased" }, "unreleased provider is not payable")
  let stale = CatalogExpiryPolicy.resolve(catalog: catalog, storedAtEpochMs: 0, nowEpochMs: 300_000, fromCache: true)
  log.expect(stale.failClosed && stale.payableBaseline.map(\.provider) == ["adyen"] && stale.withheld.map(\.provider) == ["worldpay"], "stale live eligibility fails closed")
}

private func checkUrl(_ log: CatalogCheckLog) {
  do {
    let url = try buildPaymentMethodsURL(baseURL: "http://10.0.2.2:8080/api/v1/", accountScope: "everyday", corridor: "GB")
    log.expect(
      url.absoluteString == "http://10.0.2.2:8080/api/v2/payment-methods?accountScope=everyday&corridor=GB&currency=GBP",
      "payment methods URL is v2 GBP",
      url.absoluteString
    )
  } catch {
    log.expect(false, "payment methods URL is v2 GBP", String(describing: error))
  }
  do {
    _ = try buildPaymentMethodsURL(baseURL: "http://127.0.0.1:8080/api/v1", accountScope: "everyday", corridor: "GB", currency: "EUR")
    log.expect(false, "non-GBP currency is rejected")
  } catch MeridianError.validationError(_) {
    log.expect(true, "non-GBP currency is rejected")
  } catch {
    log.expect(false, "non-GBP currency is rejected", String(describing: error))
  }
}

#if canImport(CryptoKit)
private func checkEncryption(_ log: CatalogCheckLog) {
  do {
    let key = Data(repeating: 7, count: 32)
    let sealer = try AesGcmCatalogSealer(key: key)
    let store = MemoryProtectedBlobStore()
    let cache = CatalogCache(store: store, sealer: sealer)
    let catalog = try sampleCatalog().forRequest(accountScope: "everyday", corridor: "GB", currency: "GBP")
    try cache.write(catalog: catalog, storedAtEpochMs: 5_000)
    let storageKey = try cache.storageKey(accountScope: "everyday", corridor: "GB", currency: "GBP")
    log.expect(storageKey == "everyday\u{001f}GB\u{001f}GBP", "cache key is scope, corridor, and currency")
    let blob = store.read(storageKey: storageKey) ?? Data()
    let latin = String(data: blob, encoding: .isoLatin1) ?? ""
    log.expect(blob.prefix(4) == Data("MRC1".utf8) && !latin.contains("adyen") && !latin.contains("everyday"), "cache blob is encrypted")
    let resolved = cache.read(accountScope: "everyday", corridor: "GB", currency: "GBP", nowEpochMs: 5_000)
    log.expect(resolved?.payableBaseline.map(\.provider) == ["adyen", "worldpay"], "encrypted cache round trip")
    var tampered = blob
    if !tampered.isEmpty {
      tampered[tampered.index(before: tampered.endIndex)] &+= 1
    }
    store.write(storageKey: storageKey, blob: tampered)
    log.expect(cache.read(accountScope: "everyday", corridor: "GB", currency: "GBP", nowEpochMs: 5_000) == nil && store.read(storageKey: storageKey) == nil, "tampered blob fails closed")
    let first = try sealer.seal(Data("same".utf8))
    let second = try sealer.seal(Data("same".utf8))
    log.expect(first != second && (try sealer.open(first)) == Data("same".utf8), "AES-GCM uses a fresh nonce")
  } catch {
    log.expect(false, "encrypted cache", String(describing: error))
  }
}

private final class CatalogHTTPStub: URLProtocol {
  static var handler: ((URLRequest) -> (Int, Data))?
  static var paths: [String] = []
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.paths.append(request.url?.path ?? "")
    guard let handler = Self.handler, let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    let (status, data) = handler(request)
    let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

private func checkHttp(_ log: CatalogCheckLog) async {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [CatalogHTTPStub.self]
  let session = URLSession(configuration: configuration)
  let body = """
  {"accountScope":"everyday","corridor":"GB","currency":"GBP","ttlSeconds":300,"futureSettlementWindow":"T+2","methods":[
    {"id":"card-adyen","method":"card","provider":"adyen","displayName":"Debit card","currency":"GBP","corridor":"GB","requiresLiveEligibility":false,"capabilities":["pay"],"wallet":{"type":"later"}},
    {"id":"bank-worldpay","method":"bank","provider":"worldpay","displayName":"Bank payment","requiresLiveEligibility":true,"capabilities":["pay","live-eligibility"]},
    {"id":"elsewhere","method":"card","provider":"adyen","currency":"GBP","corridor":"EU"}
  ]}
  """.data(using: .utf8)!
  let hits = CatalogHitCount()
  CatalogHTTPStub.paths = []
  CatalogHTTPStub.handler = { request in
    hits.value += 1
    let sessionOk = request.value(forHTTPHeaderField: "X-Rehearsal-Session") == "room-kept"
    let noKey = request.value(forHTTPHeaderField: "Idempotency-Key") == nil
    if !sessionOk || !noKey { return (500, Data("header".utf8)) }
    if hits.value == 1 { return (200, body) }
    return (503, Data("{\"error\":\"unavailable\"}".utf8))
  }
  do {
    let client = try MeridianClient(baseURL: "http://127.0.0.1:8080/api/v1", sessionId: "room-kept", urlSession: session)
    let cache = CatalogCache(store: MemoryProtectedBlobStore(), sealer: try AesGcmCatalogSealer(key: Data(repeating: 4, count: 32)))
    let clock = CatalogClock(value: 1_000)
    let service = PaymentMethodCatalogService(client: client, cache: cache, clock: { clock.value })
    let fresh = try await service.load(accountScope: "everyday", corridor: "GB")
    log.expect(!fresh.fromCache && fresh.payableBaseline.map(\.provider) == ["adyen", "worldpay"] && !fresh.available.contains { $0.id == "elsewhere" }, "fetch deserializes the GBP catalog")
    let cached = try await service.load(accountScope: "everyday", corridor: "GB")
    log.expect(cached.fromCache && hits.value == 1, "fresh cache skips the network", "hits \(hits.value)")
    clock.value = 1_000 + 300_000
    let fallback = try await service.load(accountScope: "everyday", corridor: "GB")
    log.expect(fallback.fromCache && fallback.failClosed && fallback.payableBaseline.map(\.provider) == ["adyen"] && fallback.withheld.map(\.provider) == ["worldpay"], "HTTP failure reuses the same cached catalog")
    log.expect(CatalogHTTPStub.paths.allSatisfy { $0 == "/api/v2/payment-methods" } && hits.value == 2, "timeout does not call another provider", CatalogHTTPStub.paths.joined(separator: ","))
  } catch {
    log.expect(false, "catalog HTTP client", String(describing: error))
  }

  CatalogHTTPStub.handler = { _ in (503, Data("{\"error\":\"no\"}".utf8)) }
  CatalogHTTPStub.paths = []
  do {
    let client = try MeridianClient(baseURL: "http://127.0.0.1:8080/api/v1", sessionId: "room-kept", urlSession: session)
    let cache = CatalogCache(store: MemoryProtectedBlobStore(), sealer: try AesGcmCatalogSealer(key: Data(repeating: 5, count: 32)))
    _ = try await PaymentMethodCatalogService(client: client, cache: cache).load(accountScope: "everyday", corridor: "GB")
    log.expect(false, "HTTP failure without cache does not invent a baseline")
  } catch let error as MeridianError {
    if case let .httpError(statusCode, _) = error {
      log.expect(statusCode == 503 && CatalogHTTPStub.paths == ["/api/v2/payment-methods"], "HTTP failure without cache does not invent a baseline")
    } else {
      log.expect(false, "HTTP failure without cache does not invent a baseline", String(describing: error))
    }
  } catch {
    log.expect(false, "HTTP failure without cache does not invent a baseline", String(describing: error))
  }
}

private final class CatalogHitCount {
  var value = 0
}

private final class CatalogClock {
  var value: Int64
  init(value: Int64) { self.value = value }
}

private func sampleCatalog() -> PaymentMethodsCatalog {
  PaymentMethodsCatalog(
    accountScope: "everyday",
    corridor: "GB",
    currency: "GBP",
    ttlSeconds: 300,
    methods: [
      PaymentMethodDescriptor(id: "card-adyen", method: "card", provider: "adyen", displayName: "Debit card", currency: "GBP", corridor: "GB", capabilities: ["pay"]),
      PaymentMethodDescriptor(id: "bank-worldpay", method: "bank", provider: "worldpay", displayName: "Bank payment", currency: "GBP", corridor: "GB", requiresLiveEligibility: true, capabilities: ["pay", "live-eligibility"]),
    ]
  )
}
#endif
