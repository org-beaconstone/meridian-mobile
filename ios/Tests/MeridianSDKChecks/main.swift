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

    // CHECK 21: flag off hides EUR and keeps cached GBP rails
    print("21. flag off uses cached GBP and hides EUR...")
    let cached = [
      PaymentRail(id: "adyen-card-gbp", provider: .adyen, method: .card, currency: .gbp, label: "Debit card · Adyen Cards"),
      PaymentRail(id: "worldpay-bank-gbp", provider: .worldpay, method: .bank, currency: .gbp, label: "Bank payment · Worldpay"),
    ]
    let disabled = resolvePaymentSurface(
      flagEnabled: false,
      providers: [
        Provider(id: .adyen, name: "Adyen EU", description: "Card", methods: [.card], currencies: ["GBP", "EUR"])
      ],
      cachedGbp: cached
    )
    if !disabled.surface.flagEnabled && disabled.surface.usingCachedGbp && disabled.surface.rails.count == 2
      && disabled.surface.rails.allSatisfy({ $0.currency == .gbp })
      && disabled.surface.rails[0].label == "Debit card · Adyen Cards"
      && disabled.surface.rails[0].provider == .adyen && disabled.surface.rails[0].method == .card
      && disabled.surface.rails[1].provider == .worldpay && disabled.surface.rails[1].method == .bank
    {
      print("  ✓ disabled flag keeps cached Adyen card and Worldpay bank")
      passed += 1
    } else {
      print("  ✗ disabled flag did not stay on cached GBP")
      failed += 1
    }

    // CHECK 22: flag on parses catalog and unlocks EUR
    print("22. flag on unlocks EUR rails...")
    let enabled = resolvePaymentSurface(
      flagEnabled: true,
      providers: [
        Provider(id: .adyen, name: "Adyen", description: "Card", methods: [.card], currencies: ["GBP", "EUR"]),
        Provider(id: .worldpay, name: "Worldpay", description: "Bank", methods: [.bank], currencies: ["GBP", "EUR"], regions: ["EU"]),
      ],
      cachedGbp: PaymentRail.gbpBaseline
    )
    if enabled.surface.dynamicCatalogActive && enabled.surface.currencies == [.gbp, .eur]
      && enabled.surface.rails.count == 4
      && enabled.surface.rails[2].id == "adyen-card-eur"
      && enabled.surface.rails[3].id == "worldpay-bank-eur"
      && enabled.surface.rails.allSatisfy({ $0.provider == .adyen || $0.provider == .worldpay })
    {
      print("  ✓ enabled flag parses catalog and shows EUR")
      passed += 1
    } else {
      print("  ✗ enabled flag did not unlock EUR")
      failed += 1
    }

    // CHECK 23: explicit GBP catalog withholds EUR
    print("23. explicit GBP catalog hides EUR...")
    let gbpOnly = resolvePaymentSurface(
      flagEnabled: true,
      providers: [
        Provider(id: .adyen, name: "Adyen", description: "Card", methods: [.card], currencies: ["GBP"]),
        Provider(id: .worldpay, name: "Worldpay", description: "Bank", methods: [.bank], currencies: ["GBP"]),
      ],
      cachedGbp: PaymentRail.gbpBaseline
    )
    if gbpOnly.surface.dynamicCatalogActive && gbpOnly.surface.currencies == [.gbp]
      && gbpOnly.surface.rails.allSatisfy({ $0.currency == .gbp })
    {
      print("  ✓ catalog can withhold EUR while the flag is on")
      passed += 1
    } else {
      print("  ✗ GBP-only catalog still exposed EUR")
      failed += 1
    }

    // CHECK 24: unknown provider is dropped and the list stays populated
    print("24. unknown provider dropped...")
    let unknownJson = """
    {"id":"pilot-rail","name":"Pilot Rail","description":"Ignored","methods":["card"],"currencies":["EUR"]}
    """.data(using: .utf8)!
    let unknown = try? JSONDecoder().decode(Provider.self, from: unknownJson)
    let mixed = resolvePaymentSurface(
      flagEnabled: true,
      providers: [
        Provider(id: .worldpay, name: "Worldpay", description: "Bank", methods: [.bank], regions: ["EU"])
      ],
      cachedGbp: PaymentRail.gbpBaseline
    )
    let labels = mixed.surface.rails.map(\.label).joined(separator: " ")
    if unknown == nil && !labels.contains("Pilot") && mixed.surface.rails.contains(where: { $0.id == "worldpay-bank-eur" })
      && mixed.surface.rails[0].provider == .adyen && mixed.surface.rails[0].method == .card
    {
      print("  ✓ unknown provider is ignored and GBP rails remain")
      passed += 1
    } else {
      print("  ✗ unknown provider leaked or rails emptied")
      failed += 1
    }

    // CHECK 25: kill switch clears an in-review EUR selection
    print("25. kill switch restores GBP review state...")
    let open = resolvePaymentSurface(flagEnabled: true, providers: nil, cachedGbp: PaymentRail.gbpBaseline)
    let reviewing = reconcileSelection(surface: open.surface, currency: .eur, railId: "adyen-card-eur", reviewing: true)
    let closed = resolvePaymentSurface(flagEnabled: false, providers: nil, cachedGbp: open.cachedGbp)
    let settled = reconcileSelection(surface: closed.surface, currency: reviewing.currency, railId: reviewing.railId, reviewing: reviewing.reviewing)
    if open.surface.rails.count == 4 && !closed.surface.flagEnabled && closed.surface.rails.count == 2
      && settled.currency == .gbp && settled.railId == "adyen-card-gbp" && !settled.reviewing
    {
      print("  ✓ kill switch leaves a non-empty GBP list and ends EUR review")
      passed += 1
    } else {
      print("  ✗ kill switch did not restore GBP")
      failed += 1
    }

    // CHECK 26: flag payloads
    print("26. flag payload evaluation...")
    let yes = evaluateMobileEuPaymentsFlag(#"{"enable_mobile_eu_payments":true}"#.data(using: .utf8)!)
    let no = evaluateMobileEuPaymentsFlag(#"{"enable_mobile_eu_payments":false}"#.data(using: .utf8)!)
    let nested = evaluateMobileEuPaymentsFlag(#"{"flags":{"enable_mobile_eu_payments":true}}"#.data(using: .utf8)!)
    let text = evaluateMobileEuPaymentsFlag(#"{"enable_mobile_eu_payments":"true"}"#.data(using: .utf8)!)
    let number = evaluateMobileEuPaymentsFlag(#"{"enable_mobile_eu_payments":1}"#.data(using: .utf8)!)
    let broken = evaluateMobileEuPaymentsFlag(Data("not-json".utf8))
    if yes && !no && nested && text && !number && !broken {
      print("  ✓ flag evaluator accepts booleans and fails closed")
      passed += 1
    } else {
      print("  ✗ flag evaluator mismatch")
      failed += 1
    }

    // CHECK 27: catalog skips an unrecognised provider without dropping recipients
    print("27. catalog skips unknown provider...")
    let mixedCatalog = """
    {"demoDate":"2026-09-18","recipients":[{"id":"alice-001","name":"Alice","initials":"A","detail":"GH Bank","category":"Shopping","color":"#007AFF"}],"providers":[{"id":"pilot-rail","name":"Pilot Rail","description":"Ignored","methods":["card"]},{"id":"adyen","name":"Adyen","description":"Card processor","methods":["card"]}]}
    """
    if let catalog = try? JSONDecoder().decode(CatalogResponse.self, from: mixedCatalog.data(using: .utf8)!),
      catalog.recipients.count == 1, catalog.providers.count == 1, catalog.providers[0].id == .adyen
    {
      print("  ✓ catalog kept Adyen and dropped the unknown provider")
      passed += 1
    } else {
      print("  ✗ catalog decode did not skip the unknown provider")
      failed += 1
    }

    // CHECK 28: remote config fails closed and honours the session header
    print("28. remote config flag...")
    final class ConfigURLProtocol: URLProtocol {
      nonisolated(unsafe) static var status = 200
      nonisolated(unsafe) static var body = Data()
      nonisolated(unsafe) static var lastHeader: String?
      nonisolated(unsafe) static var lastPath: String?
      override class func canInit(with request: URLRequest) -> Bool { true }
      override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
      override func startLoading() {
        Self.lastHeader = request.value(forHTTPHeaderField: "X-Rehearsal-Session")
        Self.lastPath = request.url?.path
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: Self.status,
          httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
      }
      override func stopLoading() {}
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ConfigURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let flagClient = try? MeridianClient(
      baseURL: "http://127.0.0.1:8080/api/v1",
      sessionId: "room-eu",
      urlSession: session
    )
    ConfigURLProtocol.status = 200
    ConfigURLProtocol.body = Data(#"{"enable_mobile_eu_payments":true}"#.utf8)
    let enabledFlag = awaitFlag { await flagClient?.mobileEuPaymentsEnabled() ?? false }
    ConfigURLProtocol.status = 500
    ConfigURLProtocol.body = Data(#"{"enable_mobile_eu_payments":true}"#.utf8)
    let failedFlag = awaitFlag { await flagClient?.mobileEuPaymentsEnabled() ?? true }
    let header = ConfigURLProtocol.lastHeader
    let path = ConfigURLProtocol.lastPath ?? ""
    if enabledFlag && !failedFlag && header == "room-eu" && path.hasSuffix("/config") {
      print("  ✓ config flag uses the rehearsal session and fails closed")
      passed += 1
    } else {
      print("  ✗ remote flag check failed (enabled=\(enabledFlag) failedClosed=\(!failedFlag) header=\(header ?? "nil") path=\(path))")
      failed += 1
    }

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

private func awaitFlag(_ body: @escaping () async -> Bool) -> Bool {
  let box = FlagBox()
  Task {
    let result = await body()
    box.finish(result)
  }
  let deadline = Date().addingTimeInterval(5)
  while !box.isDone && Date() < deadline {
    _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
  }
  return box.isDone && box.value
}

private final class FlagBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored = false
  private var done = false
  var isDone: Bool {
    lock.lock()
    defer { lock.unlock() }
    return done
  }
  var value: Bool {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }
  func finish(_ result: Bool) {
    lock.lock()
    stored = result
    done = true
    lock.unlock()
  }
}
