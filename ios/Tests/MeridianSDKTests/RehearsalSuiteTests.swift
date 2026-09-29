import XCTest
@testable import MeridianSDK

final class RehearsalSuiteTests: XCTestCase {
  func testJourneyAgainstContractDouble() async throws {
    let double = try ContractDouble()
    defer { double.stop() }
    let api = try MeridianClient(baseURL: double.baseURL, sessionId: "rehearsal-room-1", timeout: 5)
    try await RehearsalJourney.run(api: api)
    let requests = double.requests
    XCTAssertFalse(requests.isEmpty)
    XCTAssertTrue(requests.allSatisfy { $0.session == "rehearsal-room-1" })
    let payments = requests.filter { $0.path == "/api/v1/payments" }
    XCTAssertFalse(payments.isEmpty)
    XCTAssertTrue(payments.allSatisfy { $0.paymentMethod == "card" || $0.paymentMethod == "bank" })
    let grouped = Dictionary(grouping: payments, by: \.idempotencyKey)
    for group in grouped.values {
      XCTAssertEqual(Set(group.map(\.paymentMethod)).count, 1)
    }
  }

  func testTimeoutRetriesSameKeyAndMethod() async throws {
    let double = try ContractDouble()
    defer { double.stop() }
    double.holdNextPayment = true
    let api = try MeridianClient(baseURL: double.baseURL, sessionId: "timeout-room-1", timeout: 0.3)
    let rehearsal = RehearsalClient(api: api)
    let key = UUID().uuidString
    let result = try await rehearsal.submit(
      recipientId: "northline-studio",
      amountMinor: 1000,
      method: .bank,
      note: "timeout",
      idempotencyKey: key
    )
    guard case let .settled(response, retained, method) = result else {
      return XCTFail("expected settled after retry, got \(result)")
    }
    XCTAssertEqual(retained, key)
    XCTAssertEqual(method, .bank)
    XCTAssertEqual(response.transaction?.provider, .worldpay)
    XCTAssertEqual(response.transaction?.method, .bank)
    XCTAssertEqual(response.state?.balance, RehearsalJourney.openingBalance - 1000)
    let calls = double.requests.filter { $0.path == "/api/v1/payments" && $0.idempotencyKey == key }
    XCTAssertGreaterThanOrEqual(calls.count, 2)
    XCTAssertTrue(calls.allSatisfy { $0.paymentMethod == "bank" })
    XCTAssertEqual(double.debitCount("timeout-room-1"), 1)
  }

  func testCatalogFallbackKeepsBaselineProviders() async throws {
    let double = try ContractDouble()
    defer { double.stop() }
    let rehearsal = RehearsalClient(api: try MeridianClient(baseURL: double.baseURL, sessionId: "catalog-room-1"))
    let first = try await rehearsal.hydrateCatalog()
    XCTAssertEqual(Set(first.providers.map(\.id)), [.adyen, .worldpay])
    double.failCatalog = true
    let second = try await rehearsal.hydrateCatalog()
    let fallback = await rehearsal.usingCatalogFallback
    XCTAssertTrue(fallback)
    XCTAssertEqual(second.recipients.map(\.id), first.recipients.map(\.id))
    XCTAssertEqual(second.providers.first { $0.id == .adyen }?.methods, [.card])
    XCTAssertEqual(second.providers.first { $0.id == .worldpay }?.methods, [.bank])
  }

  func testUnknownProviderIsNotAdopted() async throws {
    let double = try ContractDouble()
    defer { double.stop() }
    let rehearsal = RehearsalClient(api: try MeridianClient(baseURL: double.baseURL, sessionId: "provider-room-1"))
    _ = try await rehearsal.hydrateCatalog()
    double.unknownProvider = true
    let kept = try await rehearsal.hydrateCatalog()
    XCTAssertEqual(Set(kept.providers.map(\.id)), [.adyen, .worldpay])
    let fallback = await rehearsal.usingCatalogFallback
    let keptCache = await rehearsal.hasCatalog()
    XCTAssertTrue(fallback)
    XCTAssertTrue(keptCache)
  }

  func testLiveContainerWhenConfigured() async throws {
    guard let base = ProcessInfo.processInfo.environment["MERIDIAN_TEST_API"], !base.isEmpty else {
      throw XCTSkip("MERIDIAN_TEST_API is not set")
    }
    let room = "swift-live-" + String(UUID().uuidString.prefix(8))
    let api = try MeridianClient(baseURL: base, sessionId: room)
    try await RehearsalJourney.run(api: api)
  }
}

private struct CallRecord {
  let path: String
  let session: String?
  let idempotencyKey: String?
  let paymentMethod: String?
}

private struct Stored {
  let id: String
  let recipientId: String
  let amount: Int
  let method: String
  let note: String
  var phase: String
  let provider: String
}

private final class OwnerBox {
  weak var owner: ContractDouble?
}

private final class ContractDouble: @unchecked Sendable {
  private let lock = NSLock()
  private var balances: [String: Int] = [:]
  private var transactions: [String: [[String: Any]]] = [:]
  private var payments: [String: Stored] = [:]
  private var recorded: [CallRecord] = []
  private let server: LocalHTTPServer
  private let box: OwnerBox
  let baseURL: String

  var failCatalog = false
  var unknownProvider = false
  var holdNextPayment = false

  var requests: [CallRecord] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  init() throws {
    let box = OwnerBox()
    let server = try LocalHTTPServer { start, headers, body in
      guard let owner = box.owner else { return (500, #"{"ok":false,"error":"not ready"}"#) }
      return owner.handle(start: start, headers: headers, body: body)
    }
    self.server = server
    self.box = box
    self.baseURL = "http://127.0.0.1:\(server.port)/api/v1"
    box.owner = self
  }

  func stop() { server.stop() }

  func debitCount(_ room: String) -> Int {
    lock.lock()
    defer { lock.unlock() }
    return transactions[room]?.count ?? 0
  }

  fileprivate func handle(start: String, headers: [String: String], body: String) -> (Int, String) {
    let parts = start.split(separator: " ")
    let path = parts.count >= 2 ? String(parts[1]) : ""
    let session = headers["x-rehearsal-session"]
    var paymentMethod: String?
    if path == "/api/v1/payments",
      let data = body.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      paymentMethod = object["method"] as? String
    }
    lock.lock()
    recorded.append(CallRecord(path: path, session: session, idempotencyKey: headers["idempotency-key"], paymentMethod: paymentMethod))
    lock.unlock()

    switch path {
    case "/api/v1/health":
      return (200, #"{"status":"UP","service":"meridian-api","simulation":true}"#)
    case "/api/v1/catalog":
      if failCatalog {
        return (503, #"{"ok":false,"error":"catalogue down","code":"PROVIDER_UNAVAILABLE"}"#)
      }
      return (200, catalogJSON())
    case "/api/v1/state":
      guard validRoom(session) else {
        return (400, #"{"ok":false,"error":"Invalid rehearsal session","code":"HTTP_400"}"#)
      }
      return (200, json(["version": 1, "balance": balance(session!), "transactions": txns(session!), "budgets": []] as [String: Any]))
    case "/api/v1/reset":
      guard validRoom(session) else {
        return (400, #"{"ok":false,"error":"Invalid rehearsal session","code":"HTTP_400"}"#)
      }
      lock.lock()
      balances[session!] = nil
      transactions[session!] = nil
      payments = payments.filter { !$0.key.hasPrefix("\(session!)|") }
      lock.unlock()
      return (200, json(["ok": true, "state": ["version": 1, "balance": balance(session!), "transactions": txns(session!), "budgets": []]] as [String: Any]))
    case "/api/v1/payments":
      return payment(session: session, key: headers["idempotency-key"], body: body)
    default:
      return (404, #"{"ok":false,"error":"Not found","code":"HTTP_404"}"#)
    }
  }

  private func payment(session: String?, key: String?, body: String) -> (Int, String) {
    guard validRoom(session), let key, key.range(of: "^[A-Za-z0-9_-]{1,100}$", options: .regularExpression) != nil else {
      return (400, #"{"ok":false,"error":"Invalid rehearsal session","code":"HTTP_400"}"#)
    }
    guard let data = body.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return (400, #"{"ok":false,"error":"Invalid JSON","code":"INVALID_JSON"}"#)
    }
    let recipientId = object["recipientId"] as? String ?? ""
    let amount = (object["amountMinor"] as? NSNumber)?.intValue ?? -1
    let method = object["method"] as? String ?? ""
    let note = object["note"] as? String ?? ""
    let scenario = object["scenario"] as? String ?? "success"
    guard let person = people[recipientId], (1...1_000_000).contains(amount), method == "card" || method == "bank", note.count <= 200 else {
      return (400, #"{"ok":false,"error":"Invalid payment","code":"HTTP_400"}"#)
    }
    guard ["success", "declined", "unavailable", "pending"].contains(scenario) else {
      return (400, #"{"ok":false,"error":"Unknown scenario","code":"HTTP_400"}"#)
    }
    let provider = method == "card" ? "adyen" : "worldpay"
    lock.lock()
    defer { lock.unlock() }
    let storageKey = "\(session!)|" + key
    if var existing = payments[storageKey] {
      if existing.recipientId != recipientId || existing.amount != amount || existing.method != method || existing.note != note {
        return (409, #"{"ok":false,"error":"Idempotency key belongs to a different payment","code":"HTTP_409"}"#)
      }
      if existing.phase == "completed" {
        let txn = (transactions[session!] ?? []).first { ($0["id"] as? String) == existing.id } ?? [:]
        return (200, json(["ok": true, "state": stateObject(session!), "transaction": txn] as [String: Any]))
      }
      if existing.phase == "pending" {
        return (202, pendingBody(existing.id))
      }
      return finish(&existing, session: session!, amount: amount, scenario: scenario, person: person, method: method, note: note, recipientId: recipientId, storageKey: storageKey)
    }
    var created = Stored(
      id: UUID().uuidString,
      recipientId: recipientId,
      amount: amount,
      method: method,
      note: note,
      phase: "prepared",
      provider: provider
    )
    return finish(&created, session: session!, amount: amount, scenario: scenario, person: person, method: method, note: note, recipientId: recipientId, storageKey: storageKey)
  }

  private func finish(
    _ stored: inout Stored,
    session: String,
    amount: Int,
    scenario: String,
    person: (String, String),
    method: String,
    note: String,
    recipientId: String,
    storageKey: String
  ) -> (Int, String) {
    let current = balances[session] ?? RehearsalJourney.openingBalance
    if current < amount {
      return (400, #"{"ok":false,"error":"Insufficient available balance","code":"HTTP_400"}"#)
    }
    switch scenario {
    case "pending":
      stored.phase = "pending"
      payments[storageKey] = stored
      return (202, pendingBody(stored.id))
    case "declined":
      stored.phase = "declined"
      payments[storageKey] = stored
      return (422, #"{"ok":false,"error":"Payment declined. No debit was made.","code":"PAYMENT_DECLINED"}"#)
    case "unavailable":
      stored.phase = "unavailable"
      payments[storageKey] = stored
      return (503, #"{"ok":false,"error":"Provider unavailable before authorization. No debit was made.","code":"PROVIDER_UNAVAILABLE"}"#)
    default:
      stored.phase = "completed"
      payments[storageKey] = stored
      balances[session] = current - amount
      let txn: [String: Any] = [
        "id": stored.id,
        "reference": "MER-TEST",
        "recipientId": recipientId,
        "name": person.0,
        "category": person.1,
        "amount": amount,
        "date": "2026-09-18",
        "provider": stored.provider,
        "method": method,
        "status": "completed",
        "note": note,
      ]
      transactions[session, default: []].append(txn)
      let hold = holdNextPayment
      holdNextPayment = false
      let body = json(["ok": true, "state": stateObject(session), "transaction": txn] as [String: Any])
      return (hold ? 0 : 200, body)
    }
  }

  private func stateObject(_ session: String) -> [String: Any] {
    [
      "version": 1,
      "balance": balances[session] ?? RehearsalJourney.openingBalance,
      "transactions": transactions[session] ?? [],
      "budgets": [],
    ]
  }

  private func balance(_ session: String) -> Int {
    lock.lock()
    defer { lock.unlock() }
    return balances[session] ?? RehearsalJourney.openingBalance
  }

  private func txns(_ session: String) -> [[String: Any]] {
    lock.lock()
    defer { lock.unlock() }
    return transactions[session] ?? []
  }

  private func validRoom(_ session: String?) -> Bool {
    guard let session else { return false }
    return session.range(of: "^[A-Za-z0-9_-]{3,64}$", options: .regularExpression) != nil
  }

  private func pendingBody(_ id: String) -> String {
    #"{"ok":false,"error":"Payment pending confirmation. Do not create another payment.","code":"PAYMENT_PENDING","paymentId":"\#(id)"}"#
  }

  private func catalogJSON() -> String {
    let providers = unknownProvider
      ? """
      [{"id":"adyen","name":"Adyen","description":"Card payment processor","methods":["card"]},{"id":"worldpay","name":"Worldpay","description":"Bank transfer processor","methods":["bank"]},{"id":"other","name":"Other","description":"Not in the baseline","methods":["card"]}]
      """
      : """
      [{"id":"adyen","name":"Adyen","description":"Card payment processor","methods":["card"]},{"id":"worldpay","name":"Worldpay","description":"Bank transfer processor","methods":["bank"]}]
      """
    let recipients = """
    [{"id":"northline-studio","name":"Northline Studio","initials":"NS","detail":"Design tools & materials","category":"Shopping","color":"#FF6B6B"},{"id":"octavia-energy","name":"Octavia Energy","initials":"OE","detail":"Electricity & gas supplier","category":"Bills","color":"#4ECDC4"},{"id":"maya-chen","name":"Maya Chen","initials":"MC","detail":"Yoga & wellness classes","category":"Lifestyle","color":"#95E1D3"},{"id":"birch-bloom","name":"Birch & Bloom","initials":"BB","detail":"Organic café & bistro","category":"Food & drink","color":"#FFD93D"},{"id":"london-transit","name":"London Transit","initials":"LT","detail":"Public transport & taxis","category":"Transport","color":"#6BCB77"}]
    """
    return "{\"demoDate\":\"2026-09-18\",\"recipients\":\(recipients),\"providers\":\(providers)}"
  }

  private func json(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value),
      let data = try? JSONSerialization.data(withJSONObject: value),
      let text = String(data: data, encoding: .utf8) else { return "{}" }
    return text
  }

  private var people: [String: (String, String)] {
    [
      "northline-studio": ("Northline Studio", "Shopping"),
      "octavia-energy": ("Octavia Energy", "Bills"),
      "maya-chen": ("Maya Chen", "Lifestyle"),
      "birch-bloom": ("Birch & Bloom", "Food & drink"),
      "london-transit": ("London Transit", "Transport"),
    ]
  }
}
