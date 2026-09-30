import Foundation
@testable import MeridianSDK

enum CorridorChecks {
  static func run(passed: inout Int, failed: inout Int) {
  func expect(_ name: String, _ condition: Bool) {
    if condition {
      print("  ✓ \(name)")
      passed += 1
    } else {
      print("  ✗ \(name)")
      failed += 1
    }
  }

  let euCatalog = """
  "catalogVersion": 2,
  "catalogs": [
    {"version": 1, "corridors": ["GB"]},
    {"version": 2, "corridors": ["GB", "EU"]}
  ]
  """

  func ids(_ controls: CorridorControls, _ account: String = "acct") -> [String] {
    controls.visibleMethods(accountId: account).map(\.id)
  }

  print("21. default rails are Adyen and Worldpay...")
  let defaults = CorridorControls()
  expect(
    "default GB rails",
    ids(defaults) == ["adyen-card-gb", "worldpay-bank-gb"]
      && defaults.visibleMethods(accountId: "acct").allSatisfy { $0.provider == .adyen || $0.provider == .worldpay }
  )

  print("22. flags are independent...")
  let flags = CorridorControls()
  let independent = flags.applyServerPayload(
    Data(
      """
      {"flags":{"multi_provider_selection":false,"european_corridor":true},\(euCatalog)}
      """.utf8
    )
  )
  expect("multi off and EU on", independent && !flags.flags.multiProviderSelection && flags.flags.europeanCorridorEnabled)
  expect("single provider on both corridors", ids(flags) == ["adyen-card-gb", "adyen-card-eu"])
  _ = flags.applyServerPayload(
    Data(
      """
      {"flags":{"multi_provider_selection":true,"european_corridor":false}}
      """.utf8
    )
  )
  expect(
    "multi on and EU off",
    flags.flags.multiProviderSelection && !flags.flags.europeanCorridorEnabled
      && ids(flags) == ["adyen-card-gb", "worldpay-bank-gb"] && flags.activeCatalog.version == 2
  )

  print("23. dark launch hides Europe and records telemetry...")
  let dark = CorridorControls()
  _ = dark.applyServerPayload(
    Data(
      """
      {"flags":{"multi_provider_selection":true,"european_corridor":true,"dark_launch":true},\(euCatalog)}
      """.utf8
    )
  )
  let resolved = dark.resolve(accountId: "acct")
  _ = dark.resolve(accountId: "acct")
  expect(
    "dark launch telemetry",
    resolved.allSatisfy { $0.corridor == .gb } && dark.telemetry.count == 1
      && dark.telemetry[0].europeanMethodsHidden && dark.telemetry[0].corridor == "EU"
      && dark.telemetry[0].catalogVersion == 2
  )

  print("24. canary accounts...")
  let canary = CorridorControls()
  _ = canary.applyServerPayload(
    Data(
      """
      {"flags":{"european_corridor":true,"multi_provider_selection":true},"controlledAccounts":["controlled-eu"],\(euCatalog)}
      """.utf8
    )
  )
  expect(
    "canary sees EU",
    ids(canary, "controlled-eu").contains("adyen-card-eu") && !ids(canary, "everyone-else").contains("adyen-card-eu")
  )
  _ = canary.applyServerPayload(
    Data(
      """
      {"flags":{"european_corridor":true,"dark_launch":true,"multi_provider_selection":true},"canaryAccounts":["controlled-eu"]}
      """.utf8
    )
  )
  _ = canary.resolve(accountId: "controlled-eu")
  expect(
    "dark launch hides the canary",
    !ids(canary, "controlled-eu").contains("adyen-card-eu") && canary.telemetry.last?.europeanMethodsHidden == true
  )

  print("25. kill switch preserves status and receipt...")
  let kill = CorridorControls()
  let created = kill.createIntent(
    idempotencyKey: "key-1",
    accountId: "acct",
    recipientId: "northline-studio",
    amountMinor: 2500,
    note: "Studio",
    methodId: "adyen-card-gb"
  )
  var createdId = ""
  if case let .success(intent) = created {
    createdId = intent.id
    _ = kill.complete(intentId: intent.id, reference: "REF-1")
  }
  _ = kill.applyServerPayload(Data(#"{"flags":{"payments_kill_switch":true}}"#.utf8))
  let blocked = kill.createIntent(
    idempotencyKey: "key-2",
    accountId: "acct",
    recipientId: "northline-studio",
    amountMinor: 100,
    methodId: "adyen-card-gb"
  )
  let retry = kill.createIntent(
    idempotencyKey: "key-1",
    accountId: "acct",
    recipientId: "other",
    amountMinor: 1,
    methodId: "worldpay-bank-gb"
  )
  expect(
    "kill switch",
    kill.flags.killSwitch && blocked == .failure(.killSwitch) && kill.status(intentId: createdId) == .completed
      && kill.receipt(intentId: createdId)?.reference == "REF-1"
  )
  if case let .success(intent) = retry {
    expect("retry keeps the original intent", intent.id == createdId && intent.provider == .adyen)
  } else {
    expect("retry keeps the original intent", false)
  }

  print("26. catalog rollback keeps the in-flight snapshot...")
  let rollback = CorridorControls()
  _ = rollback.applyServerPayload(
    Data(
      """
      {"flags":{"european_corridor":true,"multi_provider_selection":true},\(euCatalog)}
      """.utf8
    )
  )
  let euIntent = rollback.createIntent(
    idempotencyKey: "eu-key",
    accountId: "acct",
    recipientId: "northline-studio",
    amountMinor: 1_000_000,
    methodId: "worldpay-bank-eu"
  )
  var snapshotVersion = 0
  var intentId = ""
  if case let .success(intent) = euIntent {
    snapshotVersion = intent.snapshot.version
    intentId = intent.id
  }
  _ = rollback.applyServerPayload(
    Data(
      """
      {"flags":{"european_corridor":true,"multi_provider_selection":true},"catalogVersion":1}
      """.utf8
    )
  )
  let stored = rollback.intent(id: intentId)
  expect(
    "snapshot survives rollback",
    snapshotVersion == 2 && rollback.activeCatalog.version == 1
      && stored?.snapshot.version == 2
      && stored?.snapshot.methods.contains { $0.id == "worldpay-bank-eu" } == true
      && !rollback.activeCatalog.methods.contains { $0.id == "worldpay-bank-eu" }
      && rollback.snapshotRemainsValid(intentId: intentId)
      && rollback.status(intentId: intentId) == .inFlight
      && !rollback.rollbackCatalog(to: 99)
      && rollback.rollbackCatalog(to: 2)
      && rollback.intent(id: intentId)?.snapshot.version == 2
  )

  print("27. numeric flags and corrupt payloads...")
  let parsing = CorridorControls()
  _ = parsing.applyServerPayload(Data(#"{"flags":{"payments_kill_switch":true}}"#.utf8))
  let corruptKept = !parsing.applyServerPayload(Data("nope".utf8)) && !parsing.applyServerPayload(Data("[]".utf8))
    && parsing.flags.killSwitch && parsing.blocksNewIntent(idempotencyKey: "fresh")
  _ = parsing.applyServerPayload(
    Data(
      """
      {"flags":{"payments_kill_switch":1,"european_corridor":1,"dark_launch":1,"multi_provider_selection":0}}
      """.utf8
    )
  )
  expect(
    "numbers do not enable flags",
    corruptKept && !parsing.flags.killSwitch && !parsing.flags.europeanCorridorEnabled && !parsing.flags.darkLaunch
      && !parsing.flags.multiProviderSelection && ids(parsing) == ["adyen-card-gb"]
  )
  _ = parsing.applyServerPayload(
    Data(
      """
      {"payments_kill_switch":true,"flags":{"payments_kill_switch":false},"dark_launch":"TRUE","european_corridor":"true"}
      """.utf8
    )
  )
  expect(
    "nested flag wins and string true enables",
    !parsing.flags.killSwitch && parsing.flags.darkLaunch && parsing.flags.europeanCorridorEnabled
  )

  print("28. hidden method and amount...")
  let rejected = CorridorControls()
  let hidden = rejected.createIntent(
    idempotencyKey: "hidden",
    accountId: "acct",
    recipientId: "northline-studio",
    amountMinor: 100,
    methodId: "adyen-card-eu"
  )
  let amount = rejected.createIntent(
    idempotencyKey: "amount",
    accountId: "acct",
    recipientId: "northline-studio",
    amountMinor: 1_000_001,
    methodId: "adyen-card-gb"
  )
  expect("hidden EU method", hidden == .failure(.methodUnavailable) && rejected.intent(id: "intent-1") == nil)
  expect("amount range", amount == .failure(.invalidAmount))
  }
}

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

    CorridorChecks.run(passed: &passed, failed: &failed)

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
