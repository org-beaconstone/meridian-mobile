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

    // CHECK 21: legacy catalog decoder
    print("21. legacy catalog decoder...")
    let legacyCatalog = """
    {"demoDate":"2026-09-18","recipients":[{"id":"alice-001","name":"Alice","initials":"A","detail":"GH Bank","category":"Shopping","color":"#007AFF"}],"providers":[{"id":"adyen","name":"Adyen","description":"Card processor","methods":["card"]},{"id":"worldpay","name":"Worldpay","description":"Bank payment","methods":["bank"]}]}
    """
    if let catalog = PaymentCatalogDecoder.decode(legacyCatalog.data(using: .utf8)!),
      catalog.schema == "legacy",
      catalog.providers.count == 2,
      catalog.currencies == ["GBP"] {
      print("  ✓ Legacy catalog kept both baseline providers")
      passed += 1
    } else {
      print("  ✗ Legacy catalog decoder mismatch")
      failed += 1
    }

    // CHECK 22: dynamic catalog decoder ignores unknown providers
    print("22. dynamic catalog decoder...")
    let dynamicCatalog = """
    {"schema":"dynamic","demoDate":"2026-09-18","recipients":[],"currencies":[{"code":"EUR"},{"code":"USD"},"GBP"],"methods":[{"providerId":"adyen","label":"Adyen","method":"card"},{"providerId":"worldpay","name":"Worldpay","rail":"bank"},{"providerId":"extra","name":"Extra rail","method":"card"}]}
    """
    if let catalog = PaymentCatalogDecoder.decode(dynamicCatalog.data(using: .utf8)!),
      catalog.schema == "dynamic",
      catalog.providers.map(\.id) == [.adyen, .worldpay],
      catalog.currencies == ["EUR", "GBP"] {
      print("  ✓ Dynamic catalog decoded without the unknown provider")
      passed += 1
    } else {
      print("  ✗ Dynamic catalog decoder mismatch")
      failed += 1
    }

    // CHECK 23: non-object catalog does not throw
    print("23. non-object catalog...")
    if PaymentCatalogDecoder.decode(Data("[]".utf8)) == nil && PaymentCatalogDecoder.decode(Data("not-json".utf8)) == nil {
      print("  ✓ Non-object catalog returned nil")
      passed += 1
    } else {
      print("  ✗ Non-object catalog should return nil")
      failed += 1
    }

    // CHECK 24: kill switch and enabled flag parsing
    print("24. feature flag parsing...")
    let missing = FeatureFlagParser.parse(Data("{}".utf8))
    let killed = FeatureFlagParser.parse(Data(#"{"flags":{"enable_mobile_eu_payments":{"enabled":true,"killSwitch":true}}}"#.utf8))
    let enabled = FeatureFlagParser.parse(Data(#"{"enable_mobile_eu_payments":{"enabled":true,"variant":"dynamic"}}"#.utf8))
    if missing?.enabled == false, missing?.variant == "legacy",
      killed?.enabled == false, killed?.variant == "legacy",
      enabled?.enabled == true, enabled?.variant == "dynamic" {
      print("  ✓ Flag parser maps kill switch to legacy and enabled to dynamic")
      passed += 1
    } else {
      print("  ✗ Flag parser mismatch")
      failed += 1
    }

    // CHECK 25: invalid flag payload
    print("25. invalid flag payload...")
    if FeatureFlagParser.parse(Data("[]".utf8)) == nil {
      print("  ✓ Invalid flag payload returned nil")
      passed += 1
    } else {
      print("  ✗ Invalid flag payload should return nil")
      failed += 1
    }

    // CHECK 26: flag cache round trip
    print("26. flag cache...")
    let cache = InMemoryFeatureFlagCache()
    let stored = FeatureFlagEvaluation(key: FeatureFlags.mobileEuPayments, enabled: true, variant: "dynamic", source: "remote")
    cache.write(key: FeatureFlags.cacheKey(sessionId: "room-a"), evaluation: stored)
    let readBack = cache.read(key: FeatureFlags.cacheKey(sessionId: "room-a"))
    let otherRoom = cache.read(key: FeatureFlags.cacheKey(sessionId: "room-b"))
    if readBack == stored && otherRoom == nil {
      print("  ✓ Flag cache is scoped to the rehearsal room")
      passed += 1
    } else {
      print("  ✗ Flag cache mismatch")
      failed += 1
    }

    // CHECK 27: telemetry tags the active variant
    print("27. payment telemetry...")
    let legacyEvent = PaymentTelemetry.event(
      evaluation: .legacy(source: "cache"),
      idempotencyKey: "key-1",
      sessionId: "room-a",
      displayCurrency: "EUR"
    )
    let dynamicEvent = PaymentTelemetry.event(
      evaluation: FeatureFlagEvaluation(key: FeatureFlags.mobileEuPayments, enabled: true, variant: "dynamic", source: "remote"),
      idempotencyKey: "key-1",
      sessionId: "room-a",
      displayCurrency: "EUR"
    )
    if legacyEvent.variant == "legacy", legacyEvent.currency == "GBP",
      PaymentTelemetry.headerValue(legacyEvent) == "enable_mobile_eu_payments=legacy",
      dynamicEvent.variant == "dynamic", dynamicEvent.currency == "EUR",
      PaymentTelemetry.headerValue(dynamicEvent) == "enable_mobile_eu_payments=dynamic" {
      print("  ✓ Telemetry tags legacy and dynamic variants")
      passed += 1
    } else {
      print("  ✗ Telemetry mismatch")
      failed += 1
    }

    // CHECK 28: euro display keeps integer minor units
    print("28. euro display format...")
    if formatMinor(1050, currency: "EUR") == "€10.50" && formatMinor(1050, currency: "GBP") == "£10.50" {
      print("  ✓ Minor-unit formatting stays integer-based")
      passed += 1
    } else {
      print("  ✗ formatMinor mismatch: EUR=\(formatMinor(1050, currency: "EUR")) GBP=\(formatMinor(1050, currency: "GBP"))")
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
