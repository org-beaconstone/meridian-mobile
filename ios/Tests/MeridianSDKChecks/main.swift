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

    let extra = await extraChecks()
    passed += extra.passed
    failed += extra.failed

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

private func extraChecks() async -> (passed: Int, failed: Int) {
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

  print("21. Catalog accepts every configured provider...")
  let catalogJson = """
  {
    "demoDate": "2026-09-18",
    "recipients": [],
    "providers": [
      {"id": "adyen", "name": "Adyen", "description": "Card processor", "methods": ["card"]},
      {"id": "worldpay", "name": "Worldpay", "description": "Bank processor", "methods": ["bank"]},
      {"id": "configured-provider", "name": "Configured provider", "description": "Server configured", "methods": ["transfer", "wallet"]}
    ]
  }
  """
  let decoder = JSONDecoder()
  let catalog = try? decoder.decode(CatalogResponse.self, from: Data(catalogJson.utf8))
  let options = catalog?.paymentMethodOptions ?? []
  check(
    "catalog providers become one option per method",
    options.map(\.id) == ["adyen_card", "worldpay_bank", "configured-provider_transfer", "configured-provider_wallet"]
      && options.map(\.methodId) == ["card", "bank", "transfer", "wallet"]
      && options.map(\.displayLabel) == ["Card · Adyen", "Bank · Worldpay", "Transfer · Configured provider", "Wallet · Configured provider"]
  )
  let blanks = CatalogResponse(
    demoDate: "",
    recipients: [],
    providers: [Provider(id: "configured-provider", name: "Configured provider", description: "", methods: ["", "transfer"])]
  )
  check("blank method ids are not offered", blanks.paymentMethodOptions.map(\.methodId) == ["transfer"])

  print("22. Confirmed selection does not substitute another method...")
  check(
    "selected catalog method is submitted as-is",
    PaymentRouting.methodId(in: catalog ?? emptyCatalog(), selectedOptionId: "configured-provider_transfer") == "transfer"
  )
  check(
    "missing selection does not fall back",
    PaymentRouting.methodId(in: catalog ?? emptyCatalog(), selectedOptionId: "missing") == nil
  )
  check(
    "refresh keeps the current option",
    catalog.map { PaymentRouting.selectionId(in: $0, current: "worldpay_bank") } == "worldpay_bank"
  )
  check(
    "refresh uses the first option only when the current one is gone",
    catalog.map { PaymentRouting.selectionId(in: $0, current: "") } == "adyen_card"
  )

  print("23. Transaction records any provider id...")
  let transactionJson = """
  {
    "id": "txn-extra",
    "reference": "REF-1",
    "recipientId": "northline-studio",
    "name": "Northline Studio",
    "category": "Shopping",
    "amount": 100,
    "date": "2026-09-18",
    "provider": "configured-provider",
    "method": "transfer",
    "status": "completed",
    "note": ""
  }
  """
  let transaction = try? decoder.decode(Transaction.self, from: Data(transactionJson.utf8))
  check(
    "unknown provider and method decode",
    transaction?.provider == "configured-provider" && transaction?.method == "transfer"
  )

  print("24. Payment body keeps the method id...")
  let payload = PaymentRequest(
    recipientId: "northline-studio",
    amountMinor: 100,
    method: "transfer",
    note: "note",
    scenario: .success
  )
  let encoded = (try? JSONEncoder().encode(payload)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
  check("encoded method is the catalog method", encoded?["method"] as? String == "transfer")

  print("25. Catalog cache falls back, then expires...")
  var cache = CatalogCache(ttl: 60)
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  check("empty cache has no fallback", cache.fallback(at: now)?.providers == nil)
  if let catalog {
    cache.store(catalog, at: now)
    let within = cache.fallback(at: now.addingTimeInterval(30))
    let expired = cache.fallback(at: now.addingTimeInterval(61))
    check(
      "fallback is the fetched catalog inside the time-to-live",
      within?.providers.map(\.id) == ["adyen", "worldpay", "configured-provider"]
    )
    check("expired cache is not reused", expired?.providers == nil)
  } else {
    check("fallback is the fetched catalog inside the time-to-live", false)
    check("expired cache is not reused", false)
  }

  print("26. Client reuses the last catalog and does not rewrite the method...")
  let transportResult = await transportChecks()
  passed += transportResult.passed
  failed += transportResult.failed

  print("27. UI and model have no hardcoded provider picker...")
  let source = sourceChecks()
  passed += source.passed
  failed += source.failed

  return (passed, failed)
}

private func emptyCatalog() -> CatalogResponse {
  CatalogResponse(demoDate: "", recipients: [], providers: [])
}

private final class LockedBox<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: T
  init(_ value: T) { self.value = value }
  func withLock<R>(_ body: (inout T) -> R) -> R {
    lock.lock()
    defer { lock.unlock() }
    return body(&value)
  }
}

private func transportChecks() async -> (passed: Int, failed: Int) {
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

  let catalogBody = """
  {"demoDate":"2026-09-18","recipients":[],"providers":[
    {"id":"adyen","name":"Adyen","description":"Card processor","methods":["card"]},
    {"id":"worldpay","name":"Worldpay","description":"Bank processor","methods":["bank"]},
    {"id":"configured-provider","name":"Configured provider","description":"Server configured","methods":["transfer"]}
  ]}
  """.data(using: .utf8)!
  let script = LockedBox<[(Int, Data)]>([])
  let seen = LockedBox<[URLRequest]>([])
  let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
    seen.withLock { $0.append(request) }
    let next = script.withLock { box -> (Int, Data) in
      box.isEmpty ? (500, Data("{}".utf8)) : box.removeFirst()
    }
    let response = HTTPURLResponse(
      url: request.url ?? URL(string: "http://127.0.0.1/api/v1")!,
      statusCode: next.0,
      httpVersion: "HTTP/1.1",
      headerFields: nil
    )!
    return (next.1, response)
  }
  let clock = LockedBox(Date(timeIntervalSince1970: 1_700_000_000))
  do {
    let client = try MeridianClient(
      baseURL: "http://127.0.0.1:8080/api/v1",
      sessionId: "room-catalog",
      catalogTTL: 60,
      now: { clock.withLock { $0 } },
      transport: transport
    )
    script.withLock { $0 = [(500, Data())] }
    var initialFailed = false
    do { _ = try await client.getCatalog() } catch { initialFailed = true }
    let initialFromCache = await client.didServeCatalogFromCache()
    check("first catalog failure has no built-in provider list", initialFailed && initialFromCache == false)

    script.withLock { $0 = [(200, catalogBody), (503, Data("nope".utf8))] }
    let fresh = try await client.getCatalog()
    let freshFromCache = await client.didServeCatalogFromCache()
    check("catalog fetch returns every provider", fresh.paymentMethodOptions.count == 3 && freshFromCache == false)
    clock.withLock { $0 = $0.addingTimeInterval(30) }
    let cached = try await client.getCatalog()
    let cachedFromCache = await client.didServeCatalogFromCache()
    check(
      "failed fetch reuses the last catalog",
      cached.providers.map(\.id) == fresh.providers.map(\.id) && cachedFromCache
    )
    clock.withLock { $0 = $0.addingTimeInterval(90) }
    script.withLock { $0 = [(503, Data("nope".utf8))] }
    var expired = false
    do { _ = try await client.getCatalog() } catch { expired = true }
    let expiredFromCache = await client.didServeCatalogFromCache()
    check("catalog older than the time-to-live is not served", expired && expiredFromCache == false)

    let methodId = PaymentRouting.methodId(in: fresh, selectedOptionId: "configured-provider_transfer")
    let key = "idem-catalog-1"
    let paymentOk = #"{"ok":true,"state":null,"transaction":null}"#.data(using: .utf8)!
    script.withLock { $0 = [(200, paymentOk), (500, Data())] }
    _ = try await client.submitPayment(
      recipientId: "northline-studio",
      amountMinor: 250,
      method: methodId ?? "",
      note: "catalog route",
      idempotencyKey: key
    )
    var retryThrew = false
    do {
      _ = try await client.submitPayment(
        recipientId: "northline-studio",
        amountMinor: 250,
        method: methodId ?? "",
        note: "catalog route",
        idempotencyKey: key
      )
    } catch {
      retryThrew = true
    }
    let posts = seen.withLock { $0 }.filter { $0.httpMethod == "POST" }
    let methods = posts.map { request -> String? in
      guard let body = request.httpBody,
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
      else { return nil }
      return json["method"] as? String
    }
    let keys = posts.map { $0.value(forHTTPHeaderField: "Idempotency-Key") }
    let sessions = posts.map { $0.value(forHTTPHeaderField: "X-Rehearsal-Session") }
    check("payment posts the selected method twice", methods == ["transfer", "transfer"] && retryThrew)
    check("retry keeps the idempotency key and session", keys == [key, key] && sessions == ["room-catalog", "room-catalog"])
  } catch {
    print("  ✗ transport checks errored: \(error)")
    failed += 1
  }
  return (passed, failed)
}

private func sourceChecks() -> (passed: Int, failed: Int) {
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
  let iosRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let app = (try? String(contentsOf: iosRoot.appendingPathComponent("App/MeridianApp.swift"), encoding: .utf8)) ?? ""
  let model = (try? String(contentsOf: iosRoot.appendingPathComponent("MeridianSDK/Sources/MeridianSDK/Model.swift"), encoding: .utf8)) ?? ""
  let client = (try? String(contentsOf: iosRoot.appendingPathComponent("MeridianSDK/Sources/MeridianSDK/MeridianClient.swift"), encoding: .utf8)) ?? ""
  let forbidden = ["PaymentMethod.card", "PaymentMethod.bank", "Adyen", "Worldpay", "adyen", "worldpay", "Debit card", "Bank payment", "FeatureFlag", "featureFlag"]
  let uncertainRetry = app.range(of: "catch {message=\"Outcome may be unknown").map { start in
    app[start.lowerBound...].prefix(while: { $0 != "}" })
  }
  check("payment screen source is present", !app.isEmpty && !model.isEmpty && !client.isEmpty)
  check(
    "payment screen has no provider enum or brand picker",
    !app.isEmpty && forbidden.allSatisfy { !app.contains($0) } && app.contains("paymentMethodOptions") && app.contains("PaymentRouting.methodId")
  )
  check(
    "uncertain payment retry does not replace the idempotency key",
    uncertainRetry.map { !$0.contains("UUID") } ?? false
  )
  check(
    "model has no closed provider or method enum",
    !model.contains("enum PaymentMethod") && !model.contains("enum ProviderId") && !model.contains("adyen") && !model.contains("worldpay") && !model.contains("case card") && !model.contains("case bank")
  )
  check(
    "client does not name baseline providers",
    !client.contains("adyen") && !client.contains("worldpay") && !client.contains("PaymentMethod")
  )
  return (passed, failed)
}
