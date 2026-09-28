import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import MeridianSDK

/// XCTest rehearsal suite for the Swift client used by the native app.
/// The suite speaks the shared Spring Boot contract through a local HTTP mock: GBP pence,
/// Adyen card, Worldpay bank, catalog hydration, idempotency, HTTP 202 pending,
/// unavailable retry, and gateway timeout. It does not call a live provider.
final class RehearsalSuite: XCTestCase {
  private var mock: ContractMock!
  private var session: RehearsalSession!

  override func setUp() async throws {
    mock = ContractMock()
    ContractURLProtocol.mock = mock
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ContractURLProtocol.self]
    configuration.timeoutIntervalForRequest = 2
    let urlSession = URLSession(configuration: configuration)
    let client = try MeridianClient(
      baseURL: "http://mock.meridian.test/api/v1",
      sessionId: "room-pay-120",
      urlSession: urlSession,
      timeout: 2
    )
    session = RehearsalSession(client: client)
  }

  override func tearDown() {
    ContractURLProtocol.mock = nil
    mock = nil
  }

  func testGbpPenceRangeRejectsCurrencySwitch() {
    let (min, minError) = parseAmount("0.01")
    XCTAssertEqual(min, 1)
    XCTAssertNil(minError)
    let (max, maxError) = parseAmount("10000.00")
    XCTAssertEqual(max, 1_000_000)
    XCTAssertNil(maxError)
    let (zero, zeroError) = parseAmount("0.00")
    XCTAssertNil(zero)
    XCTAssertEqual(zeroError, "Amount must be greater than zero")
    let (over, overError) = parseAmount("10000.01")
    XCTAssertNil(over)
    XCTAssertEqual(overError, "Amount cannot exceed £10,000")

    let (euroMin, euroMinError) = parseAmount("0.01", currency: "EUR")
    XCTAssertNil(euroMin)
    XCTAssertEqual(euroMinError, "Only GBP integer pence are supported")
    let (euroMax, euroMaxError) = parseAmount("10000.00", currency: "EUR")
    XCTAssertNil(euroMax)
    XCTAssertEqual(euroMaxError, "Only GBP integer pence are supported")
    XCTAssertEqual(baselineProvider(for: .card), .adyen)
    XCTAssertEqual(baselineProvider(for: .bank), .worldpay)
  }

  func testDynamicCatalogHydrationAndLastKnownGood() async {
    let first = await session.hydrateCatalog()
    XCTAssertFalse(first.degraded)
    XCTAssertEqual(first.source, .live)
    XCTAssertEqual(first.catalog?.demoDate, "2026-09-18")
    XCTAssertEqual(first.catalog?.providers.map(\.id), [.adyen, .worldpay])
    XCTAssertEqual(first.catalog?.providers.first?.methods, [.card])
    XCTAssertEqual(first.catalog?.providers.last?.methods, [.bank])

    mock.demoDate = "2026-09-19"
    let refreshed = await session.hydrateCatalog()
    XCTAssertEqual(refreshed.source, .live)
    XCTAssertEqual(refreshed.catalog?.demoDate, "2026-09-19")

    mock.catalogDown = true
    let fallback = await session.hydrateCatalog()
    XCTAssertTrue(fallback.degraded)
    XCTAssertEqual(fallback.source, .lastKnownGood)
    XCTAssertEqual(fallback.catalog?.demoDate, "2026-09-19")
    XCTAssertEqual(fallback.catalog?.providers.map(\.id), [.adyen, .worldpay])
  }

  func testCatalogMissWithoutCacheIsEmpty() async {
    mock.catalogDown = true
    let missing = await session.hydrateCatalog()
    XCTAssertTrue(missing.degraded)
    XCTAssertEqual(missing.source, .empty)
    XCTAssertNil(missing.catalog)
  }

  func testSettlementIdempotencyKeepsSessionAndKey() async {
    let attempt = makeAttempt(amount: 2599, method: .card, key: "settle-key-1")
    guard case let .settled(response, kept) = await session.submit(attempt) else {
      return XCTFail("expected settlement")
    }
    XCTAssertEqual(mock.lastStatus, 200)
    XCTAssertEqual(response.transaction?.id, "txn-1")
    XCTAssertEqual(response.transaction?.provider, .adyen)
    XCTAssertEqual(response.state?.balance, 1_248_050 - 2599)
    XCTAssertEqual(kept.idempotencyKey, "settle-key-1")
    XCTAssertEqual(kept.method, .card)
    XCTAssertEqual(kept.provider, .adyen)
    XCTAssertEqual(mock.sessions, ["room-pay-120"])
    XCTAssertEqual(mock.methods, ["card"])

    guard case let .settled(replay, replayKept) = await session.submit(attempt) else {
      return XCTFail("expected idempotent replay")
    }
    XCTAssertEqual(replay.transaction?.id, "txn-1")
    XCTAssertEqual(replay.state?.balance, 1_248_050 - 2599)
    XCTAssertEqual(mock.debits, 1)
    XCTAssertEqual(replayKept.idempotencyKey, "settle-key-1")
    XCTAssertEqual(mock.sessions, ["room-pay-120", "room-pay-120"])
  }

  func testHttp202PendingDoesNotDebitOrRotateKey() async {
    let attempt = makeAttempt(amount: 100, method: .card, key: "pending-key", scenario: .pending)
    guard case let .pending(response, kept) = await session.submit(attempt) else {
      return XCTFail("expected pending")
    }
    XCTAssertEqual(mock.lastStatus, 202)
    XCTAssertFalse(response.ok)
    XCTAssertEqual(response.code, "PAYMENT_PENDING")
    XCTAssertEqual(response.paymentId, "pay-pending")
    XCTAssertEqual(mock.balance, 1_248_050)
    XCTAssertEqual(kept.idempotencyKey, "pending-key")
    XCTAssertEqual(kept.method, .card)

    guard case .pending = await session.submit(attempt) else {
      return XCTFail("retry must stay pending")
    }
    XCTAssertEqual(mock.balance, 1_248_050)
    XCTAssertEqual(mock.debits, 0)
    XCTAssertEqual(mock.keys, ["pending-key", "pending-key"])
  }

  func testUnavailableRetryStaysOnWorldpayBank() async {
    let down = makeAttempt(amount: 80, method: .bank, key: "bank-key", scenario: .unavailable)
    guard case let .retryable(_, kept) = await session.submit(down) else {
      return XCTFail("expected retryable unavailable")
    }
    XCTAssertEqual(mock.lastStatus, 503)
    XCTAssertEqual(mock.balance, 1_248_050)
    XCTAssertEqual(kept.method, .bank)
    XCTAssertEqual(kept.provider, .worldpay)
    XCTAssertEqual(kept.idempotencyKey, "bank-key")

    let recovered = makeAttempt(amount: 80, method: kept.method, key: kept.idempotencyKey)
    guard case let .settled(response, _) = await session.submit(recovered) else {
      return XCTFail("expected settlement on same key")
    }
    XCTAssertEqual(response.state?.balance, 1_248_050 - 80)
    XCTAssertEqual(response.transaction?.provider, .worldpay)
    XCTAssertEqual(response.transaction?.method, .bank)
    XCTAssertEqual(mock.methods, ["bank", "bank"])
    XCTAssertEqual(mock.keys, ["bank-key", "bank-key"])
    XCTAssertEqual(mock.debits, 1)
  }

  func testGatewayTimeoutRetriesSameCardKeyOnce() async {
    mock.hangNext = true
    let attempt = makeAttempt(amount: 250, method: .card, key: "timeout-key")
    guard case let .retryable(message, kept) = await session.submit(attempt) else {
      return XCTFail("expected timeout retry")
    }
    XCTAssertTrue(message.localizedCaseInsensitiveContains("timeout"))
    XCTAssertEqual(kept.idempotencyKey, "timeout-key")
    XCTAssertEqual(kept.method, .card)
    XCTAssertEqual(kept.provider, .adyen)
    XCTAssertEqual(mock.balance, 1_248_050 - 250)
    XCTAssertEqual(mock.debits, 1)

    guard case let .settled(response, _) = await session.submit(kept) else {
      return XCTFail("retry must replay the settled payment")
    }
    XCTAssertEqual(response.transaction?.id, "txn-1")
    XCTAssertEqual(response.state?.balance, 1_248_050 - 250)
    XCTAssertEqual(mock.debits, 1)
    XCTAssertEqual(mock.methods, ["card", "card"])
  }

  func testIdempotencyMismatchDoesNotMintANewKey() async {
    let original = makeAttempt(amount: 100, method: .card, key: "same-key")
    guard case .settled = await session.submit(original) else {
      return XCTFail("expected settlement")
    }
    let changed = makeAttempt(amount: 200, method: .card, key: "same-key")
    guard case let .rejected(_, kept) = await session.submit(changed) else {
      return XCTFail("expected mismatch rejection")
    }
    XCTAssertEqual(mock.lastStatus, 409)
    XCTAssertEqual(kept.idempotencyKey, "same-key")
    XCTAssertEqual(kept.method, .card)
    XCTAssertEqual(mock.balance, 1_248_050 - 100)
    XCTAssertEqual(mock.debits, 1)
  }

  func testInvalidAmountDoesNotCallTheApi() async {
    let outcome = await session.submit(makeAttempt(amount: 0, method: .bank, key: "zero"))
    guard case let .rejected(_, kept) = outcome else {
      return XCTFail("expected local rejection")
    }
    XCTAssertEqual(kept.idempotencyKey, "zero")
    XCTAssertTrue(mock.methods.isEmpty)
    XCTAssertEqual(mock.balance, 1_248_050)
  }

  private func makeAttempt(
    amount: Int,
    method: PaymentMethod,
    key: String,
    scenario: Scenario = .success
  ) -> PaymentAttempt {
    PaymentAttempt(
      recipientId: "northline-studio",
      amountMinor: amount,
      method: method,
      note: "rehearsal",
      scenario: scenario,
      idempotencyKey: key
    )
  }
}

final class ContractMock: @unchecked Sendable {
  let lock = NSLock()
  var balance = 1_248_050
  var catalogDown = false
  var demoDate = "2026-09-18"
  var hangNext = false
  var debits = 0
  var lastStatus = 0
  var methods: [String] = []
  var keys: [String] = []
  var sessions: [String] = []
  var stored: [String: StoredPayment] = [:]
  var sequence = 0
}

struct StoredPayment {
  let payload: String
  let phase: String
  let id: String
  let amount: Int
  let method: String
  let recipientId: String
  let note: String
}

final class ContractURLProtocol: URLProtocol, @unchecked Sendable {
  static let gate = NSLock()
  static var mock: ContractMock?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let mock = Self.mock, let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    let path = url.path
    let session = request.value(forHTTPHeaderField: "X-Rehearsal-Session")
    let key = request.value(forHTTPHeaderField: "Idempotency-Key")
    let text = Self.bodyString(request)
    let reply = mock.reply(path: path, session: session, key: key, body: text)
    if reply.timedOut {
      client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
      return
    }
    let response = HTTPURLResponse(
      url: url,
      statusCode: reply.status,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func bodyString(_ request: URLRequest) -> String {
    if let body = request.httpBody {
      return String(data: body, encoding: .utf8) ?? ""
    }
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

private struct ProtocolReply {
  let status: Int
  let body: String
  let timedOut: Bool
}

extension ContractMock {
  fileprivate func reply(path: String, session: String?, key: String?, body: String) -> ProtocolReply {
    lock.lock()
    defer { lock.unlock() }
    if path.hasSuffix("/catalog") {
      return catalog()
    }
    if path.hasSuffix("/payments") {
      return payment(session: session, key: key, body: body)
    }
    if path.hasSuffix("/state") {
      return ProtocolReply(status: 200, body: stateJSON(), timedOut: false)
    }
    return ProtocolReply(status: 404, body: #"{"ok":false,"error":"not found"}"#, timedOut: false)
  }

  private func catalog() -> ProtocolReply {
    if catalogDown {
      return ProtocolReply(
        status: 503,
        body: #"{"ok":false,"error":"catalog unavailable","code":"PROVIDER_UNAVAILABLE"}"#,
        timedOut: false
      )
    }
    let body = """
    {"demoDate":"\(demoDate)","recipients":[{"id":"northline-studio","name":"Northline Studio","initials":"NS","detail":"Design tools & materials","category":"Shopping","color":"#FF6B6B"}],"providers":[{"id":"adyen","name":"Adyen","description":"Card payment processor","methods":["card"]},{"id":"worldpay","name":"Worldpay","description":"Bank transfer processor","methods":["bank"]}]}
    """
    return ProtocolReply(status: 200, body: body, timedOut: false)
  }

  private func payment(session: String?, key: String?, body: String) -> ProtocolReply {
    guard let session, !session.isEmpty, let key, !key.isEmpty else {
      lastStatus = 400
      return ProtocolReply(status: 400, body: #"{"ok":false,"error":"Session and idempotency key are required","code":"HTTP_400"}"#, timedOut: false)
    }
    sessions.append(session)
    keys.append(key)
    let parsed = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
    let recipient = parsed?["recipientId"] as? String ?? ""
    let amount = Self.jsonInt(parsed?["amountMinor"])
    let method = parsed?["method"] as? String ?? ""
    let note = parsed?["note"] as? String ?? ""
    let scenario = parsed?["scenario"] as? String ?? "success"
    methods.append(method)
    let payload = "\(recipient)|\(amount)|\(method)|\(note)"
    if let existing = stored[key], existing.payload != payload {
      lastStatus = 409
      return ProtocolReply(status: 409, body: #"{"ok":false,"error":"Idempotency key belongs to a different payment","code":"HTTP_409"}"#, timedOut: false)
    }
    if let existing = stored[key], existing.phase == "settled" {
      lastStatus = 200
      return ProtocolReply(status: 200, body: settledJSON(existing), timedOut: false)
    }
    if let existing = stored[key], existing.phase == "pending" {
      lastStatus = 202
      return ProtocolReply(status: 202, body: pendingJSON(existing.id), timedOut: false)
    }
    if scenario == "pending" {
      let record = StoredPayment(payload: payload, phase: "pending", id: "pay-pending", amount: amount, method: method, recipientId: recipient, note: note)
      stored[key] = record
      lastStatus = 202
      return ProtocolReply(status: 202, body: pendingJSON(record.id), timedOut: false)
    }
    if scenario == "unavailable" {
      lastStatus = 503
      return ProtocolReply(status: 503, body: #"{"ok":false,"code":"PROVIDER_UNAVAILABLE","error":"Provider unavailable before authorization. No debit was made."}"#, timedOut: false)
    }
    sequence += 1
    let record = StoredPayment(payload: payload, phase: "settled", id: "txn-\(sequence)", amount: amount, method: method, recipientId: recipient, note: note)
    balance -= amount
    debits += 1
    stored[key] = record
    let timedOut = hangNext
    hangNext = false
    lastStatus = timedOut ? 0 : 200
    return ProtocolReply(status: 200, body: settledJSON(record), timedOut: timedOut)
  }

  private func pendingJSON(_ id: String) -> String {
    #"{"ok":false,"error":"Payment pending confirmation. Do not create another payment.","code":"PAYMENT_PENDING","paymentId":"\#(id)"}"#
  }

  private static func jsonInt(_ value: Any?) -> Int {
    switch value {
    case let number as Int:
      return number
    case let number as NSNumber:
      return number.intValue
    case let number as Double:
      return Int(number)
    default:
      return 0
    }
  }

  private func provider(_ method: String) -> String {
    method == "card" ? "adyen" : "worldpay"
  }

  private func settledJSON(_ record: StoredPayment) -> String {
    let transaction = """
    {"id":"\(record.id)","reference":"MER-\(record.id)","recipientId":"\(record.recipientId)","name":"Northline Studio","category":"Shopping","amount":\(record.amount),"date":"2026-09-18","provider":"\(provider(record.method))","method":"\(record.method)","status":"completed","note":"\(record.note)"}
    """
    return #"{"ok":true,"state":\#(stateJSON(transaction)),"transaction":\#(transaction)}"#
  }

  private func stateJSON(_ transaction: String? = nil) -> String {
    let transactions = transaction.map { "[\($0)]" } ?? "[]"
    return #"{"version":1,"balance":\#(balance),"transactions":\#(transactions),"budgets":[]}"#
  }
}
