import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MeridianSDK

enum ProviderCatalogChecks {
static func run() async -> (passed: Int, failed: Int) {
  var passed = 0
  var failed = 0
  var number = 20

  func check(_ title: String, _ ok: Bool, detail: String = "") {
    number += 1
    print("\(number). \(title)...")
    if ok {
      print("  ✓ \(title)")
      passed += 1
    } else {
      print("  ✗ \(title)\(detail.isEmpty ? "" : " — \(detail)")")
      failed += 1
    }
  }

  let contractJSON = """
  {
    "demoDate": "2026-09-18",
    "corridor": "GB",
    "recipients": [
      {
        "id": "northline-studio",
        "name": "Northline Studio",
        "initials": "NS",
        "detail": "Design studio",
        "category": "Shopping",
        "color": "#0b3a4a"
      }
    ],
    "providers": [
      {
        "id": "adyen",
        "name": "Adyen",
        "description": "Card payment processor",
        "methods": ["card"],
        "region": "GB"
      },
      {
        "id": "worldpay",
        "name": "Worldpay",
        "description": "Bank transfer processor",
        "methods": ["bank"]
      }
    ]
  }
  """

  // CHECK 21: feature flag
  let flagOff = MeridianFeatureFlags()
  let enabled = MeridianFeatureFlags.fromEnvironment(["MERIDIAN_CONFIG_DRIVEN_CATALOG": "1"])
  let enabledWord = MeridianFeatureFlags.fromEnvironment(["MERIDIAN_CONFIG_DRIVEN_CATALOG": "TRUE"])
  let disabled = MeridianFeatureFlags.fromEnvironment(["MERIDIAN_CONFIG_DRIVEN_CATALOG": "yes"])
  check(
    "Feature flag defaults off and only accepts 1 or true",
    !flagOff.configDrivenProviderCatalog
      && !MeridianFeatureFlags.fromEnvironment([:]).configDrivenProviderCatalog
      && enabled.configDrivenProviderCatalog
      && enabledWord.configDrivenProviderCatalog
      && !disabled.configDrivenProviderCatalog
  )

  // CHECK 22: picker source
  let baseline = PaymentMethodCatalog.safeDefault
  let hardcoded = MethodPickerSource.resolve(flags: flagOff, configuration: baseline)
  let driven = MethodPickerSource.resolve(flags: enabled, configuration: baseline)
  let drivenEmpty = MethodPickerSource.resolve(
    flags: MeridianFeatureFlags(configDrivenProviderCatalog: true),
    configuration: []
  )
  check(
    "Flag off keeps the hardcoded picker; flag on uses catalog options",
    hardcoded == .hardcodedBaseline
      && driven == .catalog(baseline)
      && drivenEmpty == .catalog(baseline)
  )

  // CHECK 23: built-in labels match today's picker
  check(
    "Safe default is Adyen card and Worldpay bank",
    baseline.count == 2
      && baseline[0].id == "adyen_card"
      && baseline[0].wireMethod == .card
      && "\(baseline[0].displayLabel) · \(baseline[0].providerName)" == "Debit card · Adyen"
      && baseline[1].id == "worldpay_bank"
      && baseline[1].wireMethod == .bank
      && "\(baseline[1].displayLabel) · \(baseline[1].providerName)" == "Bank payment · Worldpay"
  )

  // CHECK 24: contract decode
  let contract: CatalogResponse
  do {
    contract = try JSONDecoder().decode(CatalogResponse.self, from: Data(contractJSON.utf8))
    let options = PaymentMethodCatalog.options(from: contract)
    let labels = options?.map { "\($0.displayLabel) · \($0.providerName)" } ?? []
    let wires = options?.map(\.wireMethod) ?? []
    check(
      "GET /catalog contract parses Adyen card and Worldpay bank",
      contract.demoDate == "2026-09-18"
        && contract.providers.map(\.id) == [.adyen, .worldpay]
        && contract.providers.map(\.description) == ["Card payment processor", "Bank transfer processor"]
        && options?.map(\.id) == ["adyen_card", "worldpay_bank"]
        && options?.map(\.providerName) == ["Adyen", "Worldpay"]
        && labels == ["Debit card · Adyen", "Bank payment · Worldpay"]
        && wires == [.card, .bank]
    )
  } catch {
    contract = CatalogResponse(demoDate: "", recipients: [], providers: [])
    check("GET /catalog contract parses Adyen card and Worldpay bank", false, detail: "\(error)")
  }

  // CHECK 25: ignore pairs outside the baseline
  let mismatched = CatalogResponse(
    demoDate: "2026-09-18",
    recipients: [],
    providers: [
      Provider(id: .adyen, name: "Adyen", description: "Card payment processor", methods: [.bank]),
      Provider(id: .worldpay, name: "Worldpay", description: "Bank transfer processor", methods: [.card])
    ]
  )
  let cardOnly = CatalogResponse(
    demoDate: "2026-09-18",
    recipients: [],
    providers: [
      Provider(id: .adyen, name: "Adyen", description: "Card payment processor", methods: [.card, .bank])
    ]
  )
  let cardOptions = PaymentMethodCatalog.options(from: cardOnly)
  check(
    "Parser keeps only the Adyen card and Worldpay bank pairs",
    PaymentMethodCatalog.options(from: mismatched) == nil
      && PaymentMethodCatalog.options(from: CatalogResponse(demoDate: "2026-09-18", recipients: [], providers: [])) == nil
      && cardOptions?.map(\.id) == ["adyen_card"]
  )

  // CHECK 26: unknown provider id does not decode into a method
  let unknownJSON = """
  {
    "demoDate": "2026-09-18",
    "recipients": [],
    "providers": [
      {"id": "unknown", "name": "Unknown", "description": "not used", "methods": ["card"]}
    ]
  }
  """
  let unknownDecoded = try? JSONDecoder().decode(CatalogResponse.self, from: Data(unknownJSON.utf8))
  check("Catalog decode rejects an unknown provider id", unknownDecoded == nil)

  // CHECK 27: cache TTL, fallback, and metrics
  let clock = MutableClock(Date(timeIntervalSince1970: 1_700_000_000))
  let cacheLog = RecordingCatalogLog()
  let cache = ProviderCatalogCache(ttl: 30, clock: { clock.date }, logger: cacheLog)
  let stored = await cache.store(catalog: contract, sessionId: "room-1")
  clock.date = clock.date.addingTimeInterval(29)
  let fresh = await cache.freshConfiguration()
  let afterHit = await cache.currentMetrics()
  clock.date = clock.date.addingTimeInterval(1)
  let expired = await cache.freshConfiguration()
  let malformed = await cache.store(
    catalog: CatalogResponse(demoDate: "2026-09-18", recipients: [], providers: []),
    sessionId: "room-1"
  )
  let afterMalformed = await cache.currentMetrics()
  let successLine = CatalogMetricLine.format(
    event: .success,
    metrics: CatalogFetchMetrics(successCount: 1, failureCount: 0, fallbackToCacheCount: 0),
    sessionId: "room-1",
    detail: "methods=2"
  )
  let failureLine = CatalogMetricLine.format(
    event: .failure,
    metrics: CatalogFetchMetrics(successCount: 1, failureCount: 1, fallbackToCacheCount: 0),
    sessionId: "room-1",
    detail: "malformed_catalog"
  )
  let fallbackLine = CatalogMetricLine.format(
    event: .fallbackToCache,
    metrics: CatalogFetchMetrics(successCount: 1, failureCount: 1, fallbackToCacheCount: 1),
    sessionId: "room-1",
    detail: "last_known_good"
  )
  let cacheLines = cacheLog.snapshot()
  check(
    "Cache honors a 30s TTL and falls back to the last known catalog",
    stored.source == .current
      && stored.options.map(\.id) == ["adyen_card", "worldpay_bank"]
      && fresh?.source == .current
      && fresh?.options.map(\.id) == ["adyen_card", "worldpay_bank"]
      && afterHit == CatalogFetchMetrics(successCount: 1, failureCount: 0, fallbackToCacheCount: 0)
      && expired == nil
      && malformed.source == .lastKnownGood
      && malformed.options.map(\.id) == ["adyen_card", "worldpay_bank"]
      && malformed.catalog?.providers.map(\.id) == [.adyen, .worldpay]
      && afterMalformed == CatalogFetchMetrics(successCount: 1, failureCount: 1, fallbackToCacheCount: 1)
      && cacheLines == [successLine, failureLine, fallbackLine]
  )

  // CHECK 28: timeout with no cache uses the built-in pair and does not count a cache fallback
  let coldLog = RecordingCatalogLog()
  let cold = ProviderCatalogCache(logger: coldLog)
  let timedOut = await cold.fail(detail: CatalogFailureDetail.describe(URLError(.timedOut)), sessionId: "room-2")
  let coldMetrics = await cold.currentMetrics()
  let coldLines = coldLog.snapshot()
  check(
    "Timeout with an empty cache uses the built-in methods",
    CatalogFailureDetail.describe(URLError(.timedOut)) == "timeout"
      && timedOut.source == .safeDefault
      && timedOut.catalog == nil
      && timedOut.options == PaymentMethodCatalog.safeDefault
      && coldMetrics == CatalogFetchMetrics(successCount: 0, failureCount: 1, fallbackToCacheCount: 0)
      && coldLines.count == 1
      && coldLines[0].contains("event=failure")
      && coldLines[0].contains("detail=timeout")
      && !coldLines[0].contains("fallback_to_cache=1")
  )

  // CHECK 29: method id submission and idempotency payload
  let key = "pay-97-retry"
  let headers = PaymentSubmission.headers(idempotencyKey: key)
  do {
    let fromWire = try PaymentSubmission.request(
      recipientId: "northline-studio",
      amountMinor: 2599,
      methodId: "card",
      note: "Rent",
      scenario: .success
    )
    let fromCatalog = try PaymentSubmission.request(
      recipientId: "northline-studio",
      amountMinor: 2599,
      methodId: "adyen_card",
      note: "Rent",
      scenario: .success
    )
    let bank = try PaymentSubmission.request(
      recipientId: "northline-studio",
      amountMinor: 1000,
      methodId: "worldpay_bank",
      note: "Rent",
      scenario: .pending
    )
    let encodedCard = try JSONEncoder().encode(fromWire)
    let encodedCatalog = try JSONEncoder().encode(fromCatalog)
    let cardObject = try JSONSerialization.jsonObject(with: encodedCard) as? [String: Any]
    let bankObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(bank)) as? [String: Any]
    var rejected = false
    do {
      _ = try PaymentSubmission.request(
        recipientId: "northline-studio",
        amountMinor: 2599,
        methodId: "unknown",
        note: "Rent",
        scenario: .success
      )
    } catch MeridianError.validationError {
      rejected = true
    }
    check(
      "Method id maps to card or bank without changing the idempotency key",
      headers == ["Idempotency-Key": key]
        && PaymentSubmission.headers(idempotencyKey: key) == headers
        && encodedCard == encodedCatalog
        && cardObject?["method"] as? String == "card"
        && cardObject?["recipientId"] as? String == "northline-studio"
        && (cardObject?["amountMinor"] as? NSNumber)?.intValue == 2599
        && cardObject?["scenario"] as? String == "success"
        && cardObject?["Idempotency-Key"] == nil
        && cardObject?["idempotencyKey"] == nil
        && bankObject?["method"] as? String == "bank"
        && PaymentMethodCatalog.wireMethod(forMethodId: "bank") == .bank
        && PaymentMethodCatalog.wireMethod(forMethodId: "unknown") == nil
        && rejected
    )
  } catch {
    check("Method id maps to card or bank without changing the idempotency key", false, detail: "\(error)")
  }

  let transport = await runCatalogTransportChecks()
  check(
    "Client caches catalog fetches and posts the wire method with the same idempotency key",
    transport.ok,
    detail: transport.detail
  )

  return (passed, failed)
}

private static func runCatalogTransportChecks() async -> (ok: Bool, detail: String) {
  ScriptedCatalogProtocol.reset(body: Data(catalogContractJSON.utf8))
  let clock = MutableClock(Date(timeIntervalSince1970: 1_700_000_000))
  let log = RecordingCatalogLog()
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [ScriptedCatalogProtocol.self]
  let session = URLSession(configuration: configuration)
  let client: MeridianClient
  do {
    client = try MeridianClient(
      baseURL: "http://127.0.0.1:8080/api/v1",
      sessionId: "catalog-room",
      urlSession: session,
      catalogTTL: ProviderCatalogCache.defaultTTL,
      catalogClock: { clock.date },
      catalogLogger: log
    )
  } catch {
    return (false, "init \(error)")
  }

  let first = await client.loadProviderConfiguration()
  let catalogRequests = ScriptedCatalogProtocol.requests.filter {
    $0.url?.absoluteString.contains("/catalog") == true
  }
  guard first.source == .current, first.options.map(\.id) == ["adyen_card", "worldpay_bank"] else {
    return (false, "first source \(first.source) ids \(first.options.map(\.id))")
  }
  guard catalogRequests.count == 1, catalogRequests[0].timeoutInterval == ProviderCatalogCache.fetchTimeout else {
    return (false, "catalog timeout \(catalogRequests.first?.timeoutInterval ?? -1) count \(catalogRequests.count)")
  }
  guard catalogRequests[0].value(forHTTPHeaderField: "X-Rehearsal-Session") == "catalog-room" else {
    return (false, "missing rehearsal session on catalog")
  }

  clock.date = clock.date.addingTimeInterval(10)
  let cached = await client.loadProviderConfiguration()
  let afterCache = ScriptedCatalogProtocol.requests.filter {
    $0.url?.absoluteString.contains("/catalog") == true
  }
  guard cached.source == .current, afterCache.count == 1 else {
    return (false, "ttl hit refetched \(afterCache.count)")
  }

  clock.date = clock.date.addingTimeInterval(ProviderCatalogCache.defaultTTL)
  ScriptedCatalogProtocol.failCatalogWithTimeout = true
  let timedOut = await client.loadProviderConfiguration()
  let metrics = await client.providerCatalogMetrics()
  let lines = log.snapshot()
  guard timedOut.source == .lastKnownGood,
        timedOut.options.map(\.id) == ["adyen_card", "worldpay_bank"],
        metrics == CatalogFetchMetrics(successCount: 1, failureCount: 1, fallbackToCacheCount: 1),
        lines.contains(where: { $0.contains("event=failure") && $0.contains("detail=timeout") && $0.contains("session=catalog-room") }),
        lines.contains(where: { $0.contains("event=fallback_to_cache") })
  else {
    return (false, "timeout fallback metrics \(metrics) lines \(lines)")
  }

  ScriptedCatalogProtocol.failCatalogWithTimeout = false
  ScriptedCatalogProtocol.catalogStatus = 200
  ScriptedCatalogProtocol.catalogBody = Data("{".utf8)
  clock.date = clock.date.addingTimeInterval(ProviderCatalogCache.defaultTTL)
  let malformed = await client.loadProviderConfiguration()
  let afterMalformed = await client.providerCatalogMetrics()
  guard malformed.source == .lastKnownGood,
        malformed.options.map(\.id) == ["adyen_card", "worldpay_bank"],
        afterMalformed.failureCount == 2,
        afterMalformed.fallbackToCacheCount == 2
  else {
    return (false, "malformed fallback \(malformed.source) metrics \(afterMalformed)")
  }

  let idempotencyKey = "catalog-room-payment"
  do {
    let catalogPayment = try await client.submitPayment(
      recipientId: "northline-studio",
      amountMinor: 2599,
      method: "adyen_card",
      note: "Rent",
      scenario: .success,
      idempotencyKey: idempotencyKey
    )
    let wirePayment = try await client.submitPayment(
      recipientId: "northline-studio",
      amountMinor: 2599,
      method: "card",
      note: "Rent",
      scenario: .success,
      idempotencyKey: idempotencyKey
    )
    guard catalogPayment.ok, wirePayment.ok else { return (false, "payment not ok") }
  } catch {
    return (false, "submit \(error)")
  }

  let payments = ScriptedCatalogProtocol.requests.filter {
    $0.url?.absoluteString.contains("/payments") == true
  }
  guard payments.count == 2 else { return (false, "payment count \(payments.count)") }
  let bodies = payments.compactMap { requestBody($0) }
  guard bodies.count == 2 else { return (false, "missing payment body") }
  let methods = bodies.compactMap { data -> String? in
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["method"] as? String
  }
  let keys = payments.map { $0.value(forHTTPHeaderField: "Idempotency-Key") }
  let sessions = payments.map { $0.value(forHTTPHeaderField: "X-Rehearsal-Session") }
  guard methods == ["card", "card"], keys == [idempotencyKey, idempotencyKey], sessions == ["catalog-room", "catalog-room"] else {
    return (false, "methods \(methods) keys \(keys) sessions \(sessions)")
  }

  var rejectedUnknown = false
  do {
    _ = try await client.submitPayment(
      recipientId: "northline-studio",
      amountMinor: 2599,
      method: "unknown",
      note: "Rent",
      idempotencyKey: idempotencyKey
    )
  } catch MeridianError.validationError {
    rejectedUnknown = true
  } catch {
    return (false, "unexpected unknown-method error \(error)")
  }
  let paymentCountAfterReject = ScriptedCatalogProtocol.requests.filter {
    $0.url?.absoluteString.contains("/payments") == true
  }.count
  guard rejectedUnknown, paymentCountAfterReject == 2 else {
    return (false, "unknown method was sent")
  }

  ScriptedCatalogProtocol.reset(body: Data(catalogContractJSON.utf8))
  let plainSession = URLSession(configuration: {
    let item = URLSessionConfiguration.ephemeral
    item.protocolClasses = [ScriptedCatalogProtocol.self]
    return item
  }())
  do {
    let plain = try MeridianClient(
      baseURL: "http://127.0.0.1:8080/api/v1",
      sessionId: "catalog-room",
      urlSession: plainSession
    )
    _ = try await plain.getCatalog()
  } catch {
    return (false, "plain catalog \(error)")
  }
  let plainCatalog = ScriptedCatalogProtocol.requests.filter {
    $0.url?.absoluteString.contains("/catalog") == true
  }
  guard plainCatalog.count == 1, plainCatalog[0].timeoutInterval == 60 else {
    return (false, "default catalog timeout \(plainCatalog.first?.timeoutInterval ?? -1)")
  }
  return (true, "")
}

private static let catalogContractJSON = """
{
  "demoDate": "2026-09-18",
  "recipients": [
    {
      "id": "northline-studio",
      "name": "Northline Studio",
      "initials": "NS",
      "detail": "Design studio",
      "category": "Shopping",
      "color": "#0b3a4a"
    }
  ],
  "providers": [
    {"id": "adyen", "name": "Adyen", "description": "Card payment processor", "methods": ["card"]},
    {"id": "worldpay", "name": "Worldpay", "description": "Bank transfer processor", "methods": ["bank"]}
  ]
}
"""

private static func requestBody(_ request: URLRequest) -> Data? {
  if let body = request.httpBody, !body.isEmpty { return body }
  guard let stream = request.httpBodyStream else { return nil }
  stream.open()
  defer { stream.close() }
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 4096)
  while stream.hasBytesAvailable {
    let count = stream.read(&buffer, maxLength: buffer.count)
    if count <= 0 { break }
    data.append(buffer, count: count)
  }
  return data
}

private final class MutableClock: @unchecked Sendable {
  var date: Date
  init(_ date: Date) { self.date = date }
}

private final class RecordingCatalogLog: CatalogMetricLogging, @unchecked Sendable {
  private let lock = NSLock()
  private var lines: [String] = []

  func log(event: CatalogMetricEvent, metrics: CatalogFetchMetrics, sessionId: String, detail: String) {
    let line = CatalogMetricLine.format(event: event, metrics: metrics, sessionId: sessionId, detail: detail)
    lock.lock()
    lines.append(line)
    lock.unlock()
  }

  func snapshot() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return lines
  }
}

private final class ScriptedCatalogProtocol: URLProtocol, @unchecked Sendable {
  static let lock = NSLock()
  static var requests: [URLRequest] = []
  static var catalogBody = Data()
  static var catalogStatus = 200
  static var failCatalogWithTimeout = false

  static func reset(body: Data) {
    lock.lock()
    requests = []
    catalogBody = body
    catalogStatus = 200
    failCatalogWithTimeout = false
    lock.unlock()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let request = self.request
    Self.lock.lock()
    Self.requests.append(request)
    let url = request.url?.absoluteString ?? ""
    let failTimeout = Self.failCatalogWithTimeout && url.contains("/catalog")
    let status = url.contains("/catalog") ? Self.catalogStatus : 200
    let body: Data
    if url.contains("/payments") {
      body = Data("{\"ok\":true}".utf8)
    } else if url.contains("/catalog") {
      body = Self.catalogBody
    } else {
      body = Data("{}".utf8)
    }
    Self.lock.unlock()

    if failTimeout {
      client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
      return
    }
    guard let url = request.url,
          let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
}
