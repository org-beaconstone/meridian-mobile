import Foundation
@testable import MeridianSDK

struct CheckFailed: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

private let catalogNow: Int64 = 1_700_000_000_000
private let catalogFixture = """
{
  "accountScope": "everyday",
  "corridor": "gb",
  "currency": "gbp",
  "ttlSeconds": 120,
  "generatedBy": "rehearsal",
  "methods": [
    {
      "id": "card-adyen",
      "method": "card",
      "provider": "adyen",
      "displayName": "Debit card",
      "capabilities": ["charge", "live_eligibility", "future_capability"],
      "requiresLiveEligibility": false,
      "ttlSeconds": 30,
      "enabled": true,
      "routingWeight": 10,
      "metadata": {"region": "uk"}
    },
    {
      "id": "bank-worldpay",
      "method": "bank",
      "provider": "worldpay",
      "displayName": "Bank payment",
      "capabilities": ["charge"],
      "requiresLiveEligibility": false,
      "ttlSeconds": 600,
      "enabled": true,
      "settlementHint": "batch"
    },
    {
      "id": "card-adyen-off",
      "method": "card",
      "provider": "adyen",
      "displayName": "Debit card offline",
      "enabled": false
    },
    {
      "id": "eur-skip",
      "method": "card",
      "provider": "adyen",
      "displayName": "Other currency",
      "currency": "EUR"
    },
    {"displayName": "missing id"},
    {
      "id": "bad-flag",
      "method": "card",
      "provider": "adyen",
      "displayName": "Bad flag",
      "enabled": 1
    },
    "not-an-object"
  ]
}
""".data(using: .utf8)!

func runPaymentMethodCatalogChecks(passed: inout Int, failed: inout Int) {
  catalogCheck("21. open descriptor ignores unknown attributes", passed: &passed, failed: &failed) {
    let scope = try CatalogScope.parse(accountScope: " everyday ", corridor: "gb", currency: "gbp")
    let catalog = try parsePaymentMethodsCatalog(catalogFixture, expected: scope)
    try expect(catalog.accountScope == "everyday" && catalog.corridor == "GB" && catalog.currency == "GBP", "scope")
    try expect(catalog.methods.map(\.id) == ["card-adyen", "bank-worldpay", "card-adyen-off"], "methods \(catalog.methods.map(\.id))")
    let card = catalog.methods[0]
    try expect(card.provider == "adyen" && card.method == "card" && card.displayName == "Debit card", "card fields")
    try expect(card.capabilities == ["charge", "live_eligibility", "future_capability"], "capabilities")
    try expect(card.requiresLiveEligibility, "live eligibility capability")
    try expect(catalog.methods.allSatisfy { $0.provider == "adyen" || $0.provider == "worldpay" }, "baseline providers")
  }

  catalogCheck("22. non-GBP catalog rejected without a provider fallback", passed: &passed, failed: &failed) {
    do {
      _ = try CatalogScope.parse(accountScope: "everyday", corridor: "GB", currency: "EUR")
      throw CheckFailed("EUR should be rejected")
    } catch let error as MeridianError {
      if case let .validationError(message) = error {
        try expect(message.contains("GBP"), message)
      } else {
        throw CheckFailed("unexpected \(error)")
      }
    }
  }

  catalogCheck("23. payment methods URL stays on the API origin", passed: &passed, failed: &failed) {
    let scope = try CatalogScope.parse(accountScope: "everyday", corridor: "gb", currency: "gbp")
    let url = try paymentMethodsURL(baseURL: "http://127.0.0.1:8080/api/v1/", scope: scope)
    try expect(url.path == "/api/v2/payment-methods", url.path)
    try expect(url.query == "accountScope=everyday&corridor=GB&currency=GBP", url.query ?? "")
    let scoped = try CatalogScope.parse(accountScope: "acct:everyday", corridor: "eea", currency: "GBP")
    let encoded = try paymentMethodsURL(baseURL: "http://127.0.0.1:8080/api/v1", scope: scoped)
    let encodedItems = URLComponents(url: encoded, resolvingAgainstBaseURL: false)?.queryItems
    try expect(encodedItems?.first { $0.name == "accountScope" }?.value == "acct:everyday", encoded.query ?? "")
    try expect(encodedItems?.first { $0.name == "corridor" }?.value == "EEA", encoded.query ?? "")
    try expect(encodedItems?.first { $0.name == "currency" }?.value == "GBP", encoded.query ?? "")
  }

  catalogCheck("24. encrypted cache is scoped and fails closed when tampered", passed: &passed, failed: &failed) {
    let store = MemoryCatalogBlobStore()
    let cache = CatalogCache(store: store, keys: MemoryCatalogKeyProvider())
    let gb = try CatalogScope.parse(accountScope: "everyday", corridor: "GB", currency: "GBP")
    let eea = try CatalogScope.parse(accountScope: "everyday", corridor: "EEA", currency: "GBP")
    try cache.store(scope: gb, rawJSON: catalogFixture, nowEpochMs: catalogNow)
    let fresh = try cache.read(scope: gb, nowEpochMs: catalogNow)
    try expect(fresh?.methods.map(\.id) == ["card-adyen", "bank-worldpay"], "fresh methods")
    try expect(fresh?.fromCache == true && fresh?.stale == false && fresh?.withheldLiveEligibility == 0, "fresh flags")
    let ciphertext = store.peek(key: gb.storageKey) ?? Data()
    let leaked = String(decoding: ciphertext, as: UTF8.self)
    try expect(!leaked.contains("card-adyen") && !leaked.contains("Debit card"), "ciphertext leaked plaintext")
    try expect(try cache.read(scope: eea, nowEpochMs: catalogNow) == nil, "other corridor should miss")
    store.copy(from: gb.storageKey, to: eea.storageKey)
    do {
      _ = try cache.read(scope: eea, nowEpochMs: catalogNow)
      throw CheckFailed("cross-scope blob should fail authentication")
    } catch is MeridianError {
    }
    var tampered = ciphertext
    if tampered.isEmpty { throw CheckFailed("missing blob") }
    tampered[tampered.index(before: tampered.endIndex)] &+= 1
    try store.write(key: gb.storageKey, data: tampered)
    do {
      _ = try cache.read(scope: gb, nowEpochMs: catalogNow)
      throw CheckFailed("tampered blob should fail closed")
    } catch is MeridianError {
    }
  }

  catalogCheck("25. stale live eligibility is withheld", passed: &passed, failed: &failed) {
    let cache = CatalogCache(store: MemoryCatalogBlobStore(), keys: MemoryCatalogKeyProvider())
    let scope = try CatalogScope.parse(accountScope: "everyday", corridor: "GB", currency: "GBP")
    try cache.store(scope: scope, rawJSON: catalogFixture, nowEpochMs: catalogNow)
    let atMethodTtl = try cache.read(scope: scope, nowEpochMs: catalogNow + 30_000)
    try expect(atMethodTtl?.methods.map(\.id) == ["bank-worldpay"], "method ttl")
    try expect(atMethodTtl?.withheldLiveEligibility == 1 && atMethodTtl?.stale == false, "method ttl flags")
    let atCatalogTtl = try cache.read(scope: scope, nowEpochMs: catalogNow + 120_000)
    try expect(atCatalogTtl?.methods.map(\.id) == ["bank-worldpay"], "catalog ttl")
    try expect(atCatalogTtl?.stale == true && atCatalogTtl?.methods.first?.provider == "worldpay", "static method remains")
  }

  catalogCheck("26. fetch uses one session and the same cache key", passed: &passed, failed: &failed) {
    let recorder = RequestRecorder()
    defer { CatalogURLProtocol.handler = nil }
    CatalogURLProtocol.handler = { request in
      recorder.calls += 1
      recorder.urls.append(request.url?.absoluteString ?? "")
      recorder.sessions.append(request.value(forHTTPHeaderField: "X-Rehearsal-Session") ?? "")
      recorder.idempotency.append(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "")
      let status = recorder.calls == 1 ? 200 : 503
      let body = recorder.calls == 1 ? catalogFixture : Data("{\"ok\":false}".utf8)
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, body)
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CatalogURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = try MeridianClient(
      baseURL: "http://127.0.0.1:8080/api/v1",
      sessionId: "everyday-room",
      urlSession: session
    )
    let cache = CatalogCache(store: MemoryCatalogBlobStore(), keys: MemoryCatalogKeyProvider())
    let fresh = try awaitCatalog {
      try await cache.resolve(
        client: client,
        accountScope: "everyday",
        corridor: "gb",
        currency: "GBP",
        nowEpochMs: catalogNow
      )
    }
    try expect(fresh.fromCache == false && fresh.methods.map(\.id) == ["card-adyen", "bank-worldpay"], "fresh fetch")
    let stale = try awaitCatalog {
      try await cache.resolve(
        client: client,
        accountScope: "everyday",
        corridor: "GB",
        currency: "gbp",
        nowEpochMs: catalogNow + 30_000
      )
    }
    try expect(stale.fromCache && stale.methods.map(\.id) == ["bank-worldpay"], "cached static method")
    try expect(stale.withheldLiveEligibility == 1, "withheld")
    try expect(recorder.urls.count == 2 && recorder.urls[0] == recorder.urls[1], "urls \(recorder.urls)")
    try expect(recorder.urls[0].contains("/api/v2/payment-methods"), recorder.urls[0])
    try expect(recorder.sessions == ["everyday-room", "everyday-room"], "session")
    try expect(recorder.idempotency == ["", ""], "idempotency must stay unset")
  }

  catalogCheck("27. http failure without a cache does not invent providers", passed: &passed, failed: &failed) {
    defer { CatalogURLProtocol.handler = nil }
    CatalogURLProtocol.handler = { request in
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 503,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, Data("{\"ok\":false}".utf8))
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CatalogURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = try MeridianClient(
      baseURL: "http://127.0.0.1:8080/api/v1",
      sessionId: "everyday-room",
      urlSession: session
    )
    let cache = CatalogCache(store: MemoryCatalogBlobStore(), keys: MemoryCatalogKeyProvider())
    do {
      _ = try awaitCatalog {
        try await cache.resolve(
          client: client,
          accountScope: "everyday",
          corridor: "GB",
          currency: "GBP",
          nowEpochMs: catalogNow
        )
      }
      throw CheckFailed("missing cache should surface the HTTP error")
    } catch let error as MeridianError {
      if case let .httpError(statusCode, _) = error {
        try expect(statusCode == 503, "status \(statusCode)")
      } else if case .catalogUnavailable = error {
        throw CheckFailed("fail closed should keep the HTTP error when nothing is cached")
      } else {
        throw CheckFailed("unexpected \(error)")
      }
    }
  }
}

private final class RequestRecorder: @unchecked Sendable {
  var urls: [String] = []
  var sessions: [String] = []
  var idempotency: [String] = []
  var calls = 0
}

private func catalogCheck(
  _ title: String,
  passed: inout Int,
  failed: inout Int,
  body: () throws -> Void
) {
  print(title)
  do {
    try body()
    print("  ✓")
    passed += 1
  } catch {
    print("  ✗ \(error)")
    failed += 1
  }
}

private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw CheckFailed(message) }
}

private func awaitCatalog<T>(_ body: @escaping () async throws -> T) throws -> T {
  final class Box: @unchecked Sendable {
    var result: Result<T, Error>?
  }
  let box = Box()
  let semaphore = DispatchSemaphore(value: 0)
  Task {
    do { box.result = .success(try await body()) }
    catch { box.result = .failure(error) }
    semaphore.signal()
  }
  if semaphore.wait(timeout: .now() + 5) == .timedOut {
    throw CheckFailed("catalog fetch timed out")
  }
  return try box.result!.get()
}

private final class CatalogURLProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
