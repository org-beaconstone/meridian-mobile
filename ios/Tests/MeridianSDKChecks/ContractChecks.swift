import Foundation
@testable import MeridianSDK

// MARK: - Consumer Contract Tests
//
// Verifies backward-compatibility guarantees for:
//   - Legacy integer-pence payloads (amount/balance as bare Int)
//   - Extended catalog/payment schemas with additional optional fields
//   - Adyen + Worldpay provider baseline (no third provider)
//   - Missing optional fields decode to nil rather than crashing

func runContractChecks(passed: inout Int, failed: inout Int) {
  print("\n=== Contract Tests ===\n")

  // C1: Legacy Transaction – bare integer amount field
  print("C1. Legacy Transaction integer amount field...")
  let legacyTxnJson = """
  {
    "id": "txn-legacy-001",
    "reference": "REF-20260905-001",
    "recipientId": "birch-bloom",
    "name": "Birch & Bloom",
    "category": "Food & drink",
    "amount": 3500,
    "date": "2026-09-05",
    "provider": "worldpay",
    "method": "bank",
    "status": "completed",
    "note": "Legacy payload"
  }
  """
  do {
    let txn = try JSONDecoder().decode(Transaction.self, from: legacyTxnJson.data(using: .utf8)!)
    if txn.amount == 3500 && txn.provider == .worldpay && txn.method == .bank {
      print("  ✓ Legacy integer amount decoded: \(txn.amount) pence")
      passed += 1
    } else {
      print("  ✗ Field mismatch – amount=\(txn.amount)")
      failed += 1
    }
  } catch {
    print("  ✗ Decoding failed: \(error)")
    failed += 1
  }

  // C2: CatalogResponse with extended unknown field (forward-compat)
  print("C2. CatalogResponse tolerates extra unknown fields...")
  let extendedCatalogJson = """
  {
    "demoDate": "2026-09-18",
    "schemaVersion": "2.0",
    "currencyCode": "GBP",
    "recipients": [
      {
        "id": "birch-bloom",
        "name": "Birch & Bloom",
        "initials": "BB",
        "detail": "Organic café",
        "category": "Food & drink",
        "color": "#FFD93D"
      }
    ],
    "providers": [
      {
        "id": "adyen",
        "name": "Adyen",
        "description": "Card payment processor",
        "methods": ["card"]
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
  do {
    let catalog = try JSONDecoder().decode(CatalogResponse.self, from: extendedCatalogJson.data(using: .utf8)!)
    if catalog.demoDate == "2026-09-18" && catalog.recipients.count == 1 && catalog.providers.count == 2 {
      print("  ✓ Extended catalog decoded – unknown fields silently ignored")
      passed += 1
    } else {
      print("  ✗ Field mismatch – recipients=\(catalog.recipients.count) providers=\(catalog.providers.count)")
      failed += 1
    }
  } catch {
    print("  ✗ Decoding failed: \(error)")
    failed += 1
  }

  // C3: Provider baseline – exactly Adyen (card) and Worldpay (bank)
  print("C3. Provider baseline: Adyen card + Worldpay bank only...")
  do {
    let catalog = try JSONDecoder().decode(CatalogResponse.self, from: extendedCatalogJson.data(using: .utf8)!)
    let providerIds = catalog.providers.map { $0.id }
    let hasAdyen = providerIds.contains(.adyen)
    let hasWorldpay = providerIds.contains(.worldpay)
    let adyen = catalog.providers.first { $0.id == .adyen }
    let worldpay = catalog.providers.first { $0.id == .worldpay }
    if hasAdyen && hasWorldpay
        && adyen?.methods.contains(.card) == true
        && worldpay?.methods.contains(.bank) == true
        && catalog.providers.count == 2 {
      print("  ✓ Provider baseline correct: adyen/card + worldpay/bank (no third provider)")
      passed += 1
    } else {
      print("  ✗ Provider baseline mismatch")
      failed += 1
    }
  } catch {
    print("  ✗ Decoding failed: \(error)")
    failed += 1
  }

  // C4: PaymentResponse – legacy format (no paymentId)
  print("C4. PaymentResponse legacy format (no paymentId field)...")
  let legacyPaymentJson = """
  {
    "ok": true,
    "state": {
      "version": 1,
      "balance": 1244951,
      "transactions": [],
      "budgets": []
    },
    "transaction": {
      "id": "txn-002",
      "reference": "REF-20260919-002",
      "recipientId": "birch-bloom",
      "name": "Birch & Bloom",
      "category": "Food & drink",
      "amount": 3099,
      "date": "2026-09-19",
      "provider": "adyen",
      "method": "card",
      "status": "completed",
      "note": "Coffee"
    }
  }
  """
  do {
    let response = try JSONDecoder().decode(PaymentResponse.self, from: legacyPaymentJson.data(using: .utf8)!)
    if response.ok && response.paymentId == nil && response.transaction?.amount == 3099 {
      print("  ✓ Legacy PaymentResponse decoded – paymentId absent as expected")
      passed += 1
    } else {
      print("  ✗ Field mismatch – ok=\(response.ok) paymentId=\(response.paymentId ?? "nil")")
      failed += 1
    }
  } catch {
    print("  ✗ Decoding failed: \(error)")
    failed += 1
  }

  // C5: PaymentResponse – new format with paymentId (pending state)
  print("C5. PaymentResponse extended format with paymentId...")
  let pendingPaymentJson = """
  {
    "ok": false,
    "error": "Payment pending confirmation",
    "code": "PAYMENT_PENDING",
    "paymentId": "pay-uuid-abc123",
    "state": null,
    "transaction": null
  }
  """
  do {
    let response = try JSONDecoder().decode(PaymentResponse.self, from: pendingPaymentJson.data(using: .utf8)!)
    if !response.ok && response.code == "PAYMENT_PENDING" && response.paymentId == "pay-uuid-abc123" {
      print("  ✓ Extended PaymentResponse with paymentId decoded correctly")
      passed += 1
    } else {
      print("  ✗ Field mismatch – ok=\(response.ok) code=\(response.code ?? "nil") paymentId=\(response.paymentId ?? "nil")")
      failed += 1
    }
  } catch {
    print("  ✗ Decoding failed: \(error)")
    failed += 1
  }

  // C6: BankState – legacy integer balance field
  print("C6. BankState legacy integer balance field...")
  let legacyStateJson = """
  {
    "version": 1,
    "balance": 1248050,
    "transactions": [],
    "budgets": []
  }
  """
  do {
    let state = try JSONDecoder().decode(BankState.self, from: legacyStateJson.data(using: .utf8)!)
    if state.balance == 1_248_050 && state.version == 1 {
      print("  ✓ BankState legacy integer balance decoded: \(state.balance) pence")
      passed += 1
    } else {
      print("  ✗ Field mismatch – balance=\(state.balance)")
      failed += 1
    }
  } catch {
    print("  ✗ Decoding failed: \(error)")
    failed += 1
  }

  // C7: BankState – with extended metadata field (forward-compat)
  print("C7. BankState tolerates extra metadata fields...")
  let extendedStateJson = """
  {
    "version": 2,
    "balance": 500000,
    "currency": "GBP",
    "lastSyncedAt": "2026-09-19T12:00:00Z",
    "transactions": [],
    "budgets": []
  }
  """
  do {
    let state = try JSONDecoder().decode(BankState.self, from: extendedStateJson.data(using: .utf8)!)
    if state.balance == 500_000 && state.version == 2 {
      print("  ✓ BankState extra metadata fields ignored – balance=\(state.balance) pence")
      passed += 1
    } else {
      print("  ✗ Field mismatch – balance=\(state.balance)")
      failed += 1
    }
  } catch {
    print("  ✗ Decoding failed: \(error)")
    failed += 1
  }

  // C8: PaymentRequest round-trips through JSON encode/decode
  print("C8. PaymentRequest JSON encode/decode round-trip...")
  let request = PaymentRequest(
    recipientId: "northline-studio",
    amountMinor: 2599,
    method: .card,
    note: "Design tools",
    scenario: .success
  )
  do {
    let encoded = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(PaymentRequest.self, from: encoded)
    if decoded.recipientId == request.recipientId
        && decoded.amountMinor == request.amountMinor
        && decoded.method == request.method {
      print("  ✓ PaymentRequest round-trip: amountMinor=\(decoded.amountMinor) method=\(decoded.method.rawValue)")
      passed += 1
    } else {
      print("  ✗ Round-trip mismatch")
      failed += 1
    }
  } catch {
    print("  ✗ Encode/decode failed: \(error)")
    failed += 1
  }

  // C9: Missing optional PaymentResponse fields decode to nil
  print("C9. Missing optional PaymentResponse fields decode to nil...")
  let minimalPaymentJson = """
  {
    "ok": false,
    "error": "Declined",
    "code": "DECLINED"
  }
  """
  do {
    let response = try JSONDecoder().decode(PaymentResponse.self, from: minimalPaymentJson.data(using: .utf8)!)
    if !response.ok && response.state == nil && response.transaction == nil && response.paymentId == nil {
      print("  ✓ Optional fields absent → nil, no crash")
      passed += 1
    } else {
      print("  ✗ Expected nil optionals, got state=\(String(describing: response.state))")
      failed += 1
    }
  } catch {
    print("  ✗ Decoding failed: \(error)")
    failed += 1
  }

  // C10: CatalogResponse with all five categories represented in recipients
  print("C10. Catalog categories cover all five domain values...")
  let allCategoriesJson = """
  {
    "demoDate": "2026-09-18",
    "recipients": [
      {"id": "r1", "name": "Shop", "initials": "SH", "detail": "d1", "category": "Shopping", "color": "#FF0000"},
      {"id": "r2", "name": "Cafe", "initials": "CA", "detail": "d2", "category": "Food & drink", "color": "#00FF00"},
      {"id": "r3", "name": "Bus", "initials": "BU", "detail": "d3", "category": "Transport", "color": "#0000FF"},
      {"id": "r4", "name": "Bill", "initials": "BI", "detail": "d4", "category": "Bills", "color": "#FF00FF"},
      {"id": "r5", "name": "Gym", "initials": "GY", "detail": "d5", "category": "Lifestyle", "color": "#FFFF00"}
    ],
    "providers": []
  }
  """
  do {
    let catalog = try JSONDecoder().decode(CatalogResponse.self, from: allCategoriesJson.data(using: .utf8)!)
    let categories = catalog.recipients.map { $0.category }
    let allPresent = Category.allCases.allSatisfy { categories.contains($0) }
    if allPresent && catalog.recipients.count == 5 {
      print("  ✓ All five categories decoded in catalog recipients")
      passed += 1
    } else {
      print("  ✗ Category mismatch – decoded: \(categories.map { $0.rawValue })")
      failed += 1
    }
  } catch {
    print("  ✗ Decoding failed: \(error)")
    failed += 1
  }
}
