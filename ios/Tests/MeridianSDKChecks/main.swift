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

    await runProviderConfigChecks(passed: &passed, failed: &failed)

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

private func check(_ name: String, _ ok: Bool, passed: inout Int, failed: inout Int) {
  if ok {
    print("  ✓ \(name)")
    passed += 1
  } else {
    print("  ✗ \(name)")
    failed += 1
  }
}

private let agreedCatalog = """
{
  "demoDate": "2026-09-18",
  "recipients": [
    {"id": "northline-studio", "name": "Northline Studio", "initials": "NS", "detail": "Design tools", "category": "Shopping", "color": "#FF6B6B"}
  ],
  "providers": [
    {"id": "adyen", "name": "Adyen", "description": "Card payment processor", "methods": ["card"]},
    {"id": "worldpay", "name": "Worldpay", "description": "Bank transfer processor", "methods": ["bank"]}
  ]
}
"""

private func runProviderConfigChecks(passed: inout Int, failed: inout Int) async {
  print("21. Agreed /catalog shape maps to PaymentMethodOption...")
  do {
    let catalog = try JSONDecoder().decode(CatalogResponse.self, from: Data(agreedCatalog.utf8))
    let options = ProviderConfiguration.options(from: catalog)
    check(
      "fixture providers become adyen_card and worldpay_bank",
      options == ProviderConfiguration.baseline,
      passed: &passed,
      failed: &failed
    )
  } catch {
    check("catalog contract decode failed: \(error)", false, passed: &passed, failed: &failed)
  }

  print("22. Display names come from catalog; ids stay canonical...")
  let renamed = """
  {
    "demoDate": "2026-09-18",
    "recipients": [],
    "providers": [
      {"id": "worldpay", "name": "WORLDPAY", "description": "Bank transfer processor", "methods": ["bank", "bank"]},
      {"id": "adyen", "name": "ADYEN", "description": "Card payment processor", "methods": ["card"]}
    ]
  }
  """
  do {
    let catalog = try JSONDecoder().decode(CatalogResponse.self, from: Data(renamed.utf8))
    let options = ProviderConfiguration.options(from: catalog)
    check(
      "catalog order and provider names are kept; duplicate methods collapse",
      options?.map(\.id) == ["worldpay_bank", "adyen_card"]
        && options?.map(\.providerName) == ["WORLDPAY", "ADYEN"]
        && options?.map(\.displayLabel) == ["Bank payment", "Debit card"]
        && options?.map(\.method) == [.bank, .card],
      passed: &passed,
      failed: &failed
    )
  } catch {
    check("renamed catalog decode failed: \(error)", false, passed: &passed, failed: &failed)
  }

  print("23. Incomplete or crossed catalog is not a provider list...")
  let crossed = """
  {
    "demoDate": "2026-09-18",
    "recipients": [],
    "providers": [
      {"id": "adyen", "name": "Adyen", "description": "Card payment processor", "methods": ["bank"]},
      {"id": "worldpay", "name": "Worldpay", "description": "Bank transfer processor", "methods": ["card"]}
    ]
  }
  """
  let adyenOnly = """
  {
    "demoDate": "2026-09-18",
    "recipients": [],
    "providers": [
      {"id": "adyen", "name": "Adyen", "description": "Card payment processor", "methods": ["card"]}
    ]
  }
  """
  let unknownProvider = """
  {
    "demoDate": "2026-09-18",
    "recipients": [],
    "providers": [
      {"id": "other", "name": "Other", "description": "unused", "methods": ["card"]}
    ]
  }
  """
  do {
    let crossedCatalog = try JSONDecoder().decode(CatalogResponse.self, from: Data(crossed.utf8))
    let onlyAdyen = try JSONDecoder().decode(CatalogResponse.self, from: Data(adyenOnly.utf8))
    let unknownFailed = (try? JSONDecoder().decode(CatalogResponse.self, from: Data(unknownProvider.utf8))) == nil
    check(
      "crossed pairs, a single provider, and an unknown id do not become options",
      ProviderConfiguration.options(from: crossedCatalog) == nil
        && ProviderConfiguration.options(from: onlyAdyen) == nil
        && unknownFailed,
      passed: &passed,
      failed: &failed
    )
  } catch {
    check("incomplete catalog decode failed: \(error)", false, passed: &passed, failed: &failed)
  }

  print("24. Unconfirmed catalog extension does not replace the provider list...")
  let extended = """
  {
    "demoDate": "2026-09-18",
    "recipients": [],
    "methodOptions": [{"id": "other", "displayLabel": "Other", "providerName": "Other"}],
    "providers": [
      {"id": "adyen", "name": "Adyen", "description": "Card payment processor", "methods": ["card"]},
      {"id": "worldpay", "name": "Worldpay", "description": "Bank transfer processor", "methods": ["bank"]}
    ]
  }
  """
  do {
    let catalog = try JSONDecoder().decode(CatalogResponse.self, from: Data(extended.utf8))
    check(
      "agreed providers still map to the two live options",
      ProviderConfiguration.options(from: catalog) == ProviderConfiguration.baseline,
      passed: &passed,
      failed: &failed
    )
  } catch {
    check("extended catalog decode failed: \(error)", false, passed: &passed, failed: &failed)
  }

  print("25. Flag off keeps the hardcoded list and skips the network...")
  let idle = FakeTransport()
  do {
    let client = try MeridianClient(
      baseURL: "https://meridian.test/api/v1",
      sessionId: "room-flag-off",
      transport: idle
    )
    let options = await client.paymentMethodOptions()
    let metrics = await client.providerConfigMetrics()
    check(
      "baseline options, no request, no metrics",
      options == ProviderConfiguration.baseline && idle.requests.isEmpty && metrics.events.isEmpty,
      passed: &passed,
      failed: &failed
    )
  } catch {
    check("flag-off client failed: \(error)", false, passed: &passed, failed: &failed)
  }

  print("26. Flag on loads /catalog over HTTPS and records success...")
  let catalogTransport = FakeTransport(steps: [.json(status: 200, body: agreedCatalog, headers: ["X-Correlation-Id": "corr-ok"])])
  let capture = MetricCapture()
  do {
    let client = try MeridianClient(
      baseURL: "https://meridian.test/api/v1/",
      sessionId: "room-config",
      transport: catalogTransport,
      features: MeridianFeatures(configDrivenProviders: true),
      metricsHandler: { capture.record($0) }
    )
    let options = await client.paymentMethodOptions()
    let metrics = await client.providerConfigMetrics()
    let request = catalogTransport.requests.first
    check(
      "HTTPS catalog fetch keeps the session and emits success",
      options == ProviderConfiguration.baseline
        && catalogTransport.requests.count == 1
        && request?.httpMethod == "GET"
        && request?.url?.scheme == "https"
        && request?.url?.path.hasSuffix("/catalog") == true
        && header(request, "X-Rehearsal-Session") == "room-config"
        && metrics.fetchSuccess == 1
        && metrics.fetchFailure == 0
        && metrics.events.first?.correlationId == "corr-ok"
        && metrics.events.first?.sessionId == "room-config"
        && capture.events == metrics.events,
      passed: &passed,
      failed: &failed
    )
  } catch {
    check("config fetch client failed: \(error)", false, passed: &passed, failed: &failed)
  }

  print("27. Fresh cache skips refetch; expired cache fetches again...")
  let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
  let ttlTransport = FakeTransport(steps: [
    .json(status: 200, body: agreedCatalog),
    .json(status: 200, body: agreedCatalog),
  ])
  do {
    let client = try MeridianClient(
      baseURL: "https://meridian.test/api/v1",
      sessionId: "room-ttl",
      transport: ttlTransport,
      features: MeridianFeatures(configDrivenProviders: true),
      providerCacheTTL: 30,
      now: { clock.now() }
    )
    _ = await client.paymentMethodOptions()
    clock.advance(29)
    _ = await client.paymentMethodOptions()
    let beforeExpiry = ttlTransport.requests.count
    clock.advance(1)
    _ = await client.paymentMethodOptions()
    let metrics = await client.providerConfigMetrics()
    check(
      "TTL suppresses the second call and allows the third",
      beforeExpiry == 1 && ttlTransport.requests.count == 2 && metrics.fetchSuccess == 2,
      passed: &passed,
      failed: &failed
    )
  } catch {
    check("ttl client failed: \(error)", false, passed: &passed, failed: &failed)
  }

  print("28. Fetch failure falls back to last-known-good and keeps correlation...")
  let fallbackClock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
  let fallbackTransport = FakeTransport(steps: [
    .json(status: 200, body: agreedCatalog, headers: ["X-Request-Id": "req-1"]),
    .json(
      status: 503,
      body: #"{"ok":false,"error":"unavailable","code":"HTTP_503","correlationId":"corr-body"}"#,
      headers: ["X-Correlation-Id": "corr-header"]
    ),
  ])
  do {
    let client = try MeridianClient(
      baseURL: "https://meridian.test/api/v1",
      sessionId: "room-fallback",
      transport: fallbackTransport,
      features: MeridianFeatures(configDrivenProviders: true),
      providerCacheTTL: 10,
      now: { fallbackClock.now() }
    )
    let first = await client.paymentMethodOptions()
    fallbackClock.advance(11)
    let second = await client.paymentMethodOptions()
    let metrics = await client.providerConfigMetrics()
    let failure = metrics.events.first { $0.kind == .fetchFailure }
    let fallback = metrics.events.first { $0.kind == .fallbackToCache }
    check(
      "stale cache is served after HTTP 503 without dropping a provider",
      first == ProviderConfiguration.baseline
        && second == first
        && metrics.fetchSuccess == 1
        && metrics.fetchFailure == 1
        && metrics.fallbackToCache == 1
        && metrics.fallbackToBaseline == 0
        && failure?.correlationId == "corr-header"
        && failure?.sessionId == "room-fallback"
        && failure?.reason == "http-503 code=HTTP_503"
        && fallback?.correlationId == "corr-header"
        && fallback?.reason == failure?.reason,
      passed: &passed,
      failed: &failed
    )
  } catch {
    check("fallback client failed: \(error)", false, passed: &passed, failed: &failed)
  }

  print("29. Timeout with no cache returns the baseline and does not throw...")
  let timeoutTransport = FakeTransport(steps: [.error(URLError(.timedOut))])
  do {
    let client = try MeridianClient(
      baseURL: "https://meridian.test/api/v1",
      sessionId: "room-timeout",
      transport: timeoutTransport,
      features: MeridianFeatures(configDrivenProviders: true)
    )
    let options = await client.paymentMethodOptions()
    let metrics = await client.providerConfigMetrics()
    check(
      "timeout uses the two-provider baseline",
      options == ProviderConfiguration.baseline
        && metrics.fetchFailure == 1
        && metrics.fallbackToBaseline == 1
        && metrics.fallbackToCache == 0
        && metrics.events.allSatisfy { $0.sessionId == "room-timeout" && $0.reason == "timeout" },
      passed: &passed,
      failed: &failed
    )
  } catch {
    check("timeout client failed: \(error)", false, passed: &passed, failed: &failed)
  }

  print("30. Malformed catalog falls back to cache...")
  let malformedClock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
  let malformedTransport = FakeTransport(steps: [
    .json(status: 200, body: agreedCatalog),
    .json(status: 200, body: #"{"demoDate":"2026-09-18","providers":"nope"}"#, headers: ["X-Correlation-Id": "corr-bad"]),
  ])
  do {
    let client = try MeridianClient(
      baseURL: "https://meridian.test/api/v1",
      sessionId: "room-malformed",
      transport: malformedTransport,
      features: MeridianFeatures(configDrivenProviders: true),
      providerCacheTTL: 5,
      now: { malformedClock.now() }
    )
    _ = await client.paymentMethodOptions()
    malformedClock.advance(6)
    let options = await client.paymentMethodOptions()
    let metrics = await client.providerConfigMetrics()
    check(
      "malformed body keeps the cached Adyen and Worldpay options",
      options == ProviderConfiguration.baseline
        && metrics.fallbackToCache == 1
        && metrics.events.contains { $0.kind == .fetchFailure && $0.reason == "malformed-catalog" && $0.correlationId == "corr-bad" },
      passed: &passed,
      failed: &failed
    )
  } catch {
    check("malformed client failed: \(error)", false, passed: &passed, failed: &failed)
  }

  print("31. method id submit keeps the idempotency key and logs the provider...")
  let paymentBody = """
  {
    "ok": true,
    "state": null,
    "transaction": {
      "id": "tx-1",
      "reference": "MER-TX1",
      "recipientId": "northline-studio",
      "name": "Northline Studio",
      "category": "Shopping",
      "amount": 2599,
      "date": "2026-09-18",
      "provider": "adyen",
      "method": "card",
      "status": "completed",
      "note": "desk"
    },
    "error": null,
    "code": null,
    "paymentId": "tx-1"
  }
  """
  let paymentTransport = FakeTransport(steps: [
    .json(status: 200, body: paymentBody),
    .json(status: 200, body: paymentBody),
  ])
  do {
    let client = try MeridianClient(
      baseURL: "https://meridian.test/api/v1",
      sessionId: "room-pay",
      transport: paymentTransport
    )
    let first = try await client.submitPayment(
      recipientId: "northline-studio",
      amountMinor: 2599,
      methodId: "adyen_card",
      note: "desk",
      idempotencyKey: "idem-keep-1"
    )
    let second = try await client.submitPayment(
      recipientId: "northline-studio",
      amountMinor: 2599,
      methodId: "adyen_card",
      note: "desk",
      idempotencyKey: "idem-keep-1"
    )
    let logs = await client.paymentTransactionLogs()
    let bodies = paymentTransport.requests.map { wireMethod($0) }
    let keys = paymentTransport.requests.map { header($0, "Idempotency-Key") }
    check(
      "same key, card method, provider logged on the transaction",
      first.ok && second.ok
        && keys == ["idem-keep-1", "idem-keep-1"]
        && bodies == ["card", "card"]
        && paymentTransport.requests.allSatisfy { header($0, "X-Rehearsal-Session") == "room-pay" }
        && logs.count == 2
        && logs.allSatisfy {
          $0.action == "payment.submitted"
            && $0.idempotencyKey == "idem-keep-1"
            && $0.methodId == "adyen_card"
            && $0.providerName == "Adyen"
            && $0.method == .card
            && $0.transactionId == "tx-1"
            && $0.paymentId == "tx-1"
            && $0.reference == "MER-TX1"
            && $0.sessionId == "room-pay"
        },
      passed: &passed,
      failed: &failed
    )
  } catch {
    check("method id payment failed: \(error)", false, passed: &passed, failed: &failed)
  }

  print("32. Unknown method id does not submit or switch provider...")
  let blocked = FakeTransport()
  do {
    let client = try MeridianClient(
      baseURL: "https://meridian.test/api/v1",
      sessionId: "room-unknown",
      transport: blocked
    )
    var rejected = false
    do {
      _ = try await client.submitPayment(
        recipientId: "northline-studio",
        amountMinor: 100,
        methodId: "adyen_bank",
        idempotencyKey: "idem-should-not-send"
      )
    } catch MeridianError.validationError {
      rejected = true
    }
    let logs = await client.paymentTransactionLogs()
    check(
      "unknown id makes no payment request",
      rejected && blocked.requests.isEmpty && logs.isEmpty,
      passed: &passed,
      failed: &failed
    )
  } catch {
    check("unknown method client failed: \(error)", false, passed: &passed, failed: &failed)
  }

  print("33. Catalog timeout does not change provider or idempotency key...")
  let bankBody = """
  {
    "ok": false,
    "state": null,
    "transaction": null,
    "error": "Payment pending confirmation",
    "code": "PAYMENT_PENDING",
    "paymentId": "tx-pending"
  }
  """
  let timeoutThenPay = FakeTransport(steps: [
    .error(URLError(.timedOut)),
    .json(status: 202, body: bankBody),
  ])
  do {
    let client = try MeridianClient(
      baseURL: "https://meridian.test/api/v1",
      sessionId: "room-same-provider",
      transport: timeoutThenPay,
      features: MeridianFeatures(configDrivenProviders: true)
    )
    let response = try await client.submitPayment(
      recipientId: "northline-studio",
      amountMinor: 100,
      methodId: "worldpay_bank",
      note: "pending",
      scenario: .pending,
      idempotencyKey: "idem-bank-1"
    )
    let logs = await client.paymentTransactionLogs()
    let payment = timeoutThenPay.requests.last
    check(
      "timeout still submits Worldpay bank with the original key",
      response.code == "PAYMENT_PENDING"
        && timeoutThenPay.requests.count == 2
        && timeoutThenPay.requests.first?.url?.path.hasSuffix("/catalog") == true
        && payment?.url?.path.hasSuffix("/payments") == true
        && header(payment, "Idempotency-Key") == "idem-bank-1"
        && wireMethod(payment) == "bank"
        && logs.first?.providerName == "Worldpay"
        && logs.first?.methodId == "worldpay_bank"
        && logs.first?.method == .bank
        && logs.first?.paymentId == "tx-pending"
        && logs.first?.transactionId == nil,
      passed: &passed,
      failed: &failed
    )
  } catch {
    check("timeout payment failed: \(error)", false, passed: &passed, failed: &failed)
  }

  print("34. Error-body request id is kept when the response has no correlation header...")
  let errorURL = URL(string: "https://meridian.test/api/v1/catalog")!
  let errorResponse = HTTPURLResponse(url: errorURL, statusCode: 503, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
  let errorBody = Data(#"{"ok":false,"error":"unavailable","code":"HTTP_503","requestId":"req-from-body"}"#.utf8)
  check(
    "requestId in the error body correlates the failure",
    MeridianClient.correlationIdentifier(from: errorResponse, body: errorBody) == "req-from-body",
    passed: &passed,
    failed: &failed
  )

  print("35. Enum submit still sends the method and the supplied key...")
  let enumTransport = FakeTransport(steps: [.json(status: 200, body: paymentBody)])
  do {
    let client = try MeridianClient(
      baseURL: "http://127.0.0.1:8080/api/v1",
      sessionId: "room-enum",
      transport: enumTransport
    )
    _ = try await client.submitPayment(
      recipientId: "northline-studio",
      amountMinor: 2599,
      method: .card,
      note: "desk",
      idempotencyKey: "idem-enum-1"
    )
    let logs = await client.paymentTransactionLogs()
    check(
      "card enum stays card and logs Adyen",
      header(enumTransport.requests.first, "Idempotency-Key") == "idem-enum-1"
        && wireMethod(enumTransport.requests.first) == "card"
        && logs.first?.methodId == "adyen_card"
        && logs.first?.providerName == "Adyen",
      passed: &passed,
      failed: &failed
    )
  } catch {
    check("enum payment failed: \(error)", false, passed: &passed, failed: &failed)
  }
}

private func header(_ request: URLRequest?, _ name: String) -> String? {
  request?.allHTTPHeaderFields?.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
}

private func wireMethod(_ request: URLRequest?) -> String? {
  guard let data = request?.httpBody,
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else { return nil }
  return json["method"] as? String
}

private final class ManualClock: @unchecked Sendable {
  private let lock = NSLock()
  private var current: Date

  init(_ date: Date) {
    current = date
  }

  func now() -> Date {
    lock.lock()
    defer { lock.unlock() }
    return current
  }

  func advance(_ interval: TimeInterval) {
    lock.lock()
    current.addTimeInterval(interval)
    lock.unlock()
  }
}

private final class MetricCapture: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [ProviderConfigMetricEvent] = []

  var events: [ProviderConfigMetricEvent] {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  func record(_ event: ProviderConfigMetricEvent) {
    lock.lock()
    stored.append(event)
    lock.unlock()
  }
}

private struct TransportStep {
  var status: Int
  var body: Data
  var headers: [String: String]
  var error: Error?

  static func json(status: Int, body: String, headers: [String: String] = [:]) -> TransportStep {
    TransportStep(status: status, body: Data(body.utf8), headers: headers, error: nil)
  }

  static func error(_ error: Error) -> TransportStep {
    TransportStep(status: 0, body: Data(), headers: [:], error: error)
  }
}

private final class FakeTransport: MeridianHTTPTransport, @unchecked Sendable {
  private let lock = NSLock()
  private var steps: [TransportStep]
  private var storedRequests: [URLRequest] = []

  var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return storedRequests
  }

  init(steps: [TransportStep] = []) {
    self.steps = steps
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    let step: TransportStep? = {
      lock.lock()
      defer { lock.unlock() }
      storedRequests.append(request)
      guard !steps.isEmpty else { return nil }
      return steps.removeFirst()
    }()
    guard let step else { throw URLError(.badServerResponse) }
    if let error = step.error { throw error }
    guard let url = request.url,
          let response = HTTPURLResponse(url: url, statusCode: step.status, httpVersion: "HTTP/1.1", headerFields: step.headers)
    else { throw URLError(.badServerResponse) }
    return (step.body, response)
  }
}
