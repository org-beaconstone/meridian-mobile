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

    // CHECK 21: paymentMethodDescriptors derives card descriptor from catalog
    print("21. paymentMethodDescriptors card descriptor...")
    let cardProvider = Provider(id: "adyen", name: "Adyen", description: "Card processor", methods: ["card"])
    let cardDescriptors = paymentMethodDescriptors(from: [cardProvider])
    if cardDescriptors.count == 1,
       cardDescriptors[0].id == "adyen:card",
       cardDescriptors[0].method == .card,
       cardDescriptors[0].providerId == "adyen",
       cardDescriptors[0].providerName == "Adyen",
       cardDescriptors[0].requiresBankChoice == false,
       cardDescriptors[0].eligible == true {
      print("  ✓ Card descriptor correct: id=\(cardDescriptors[0].id)")
      passed += 1
    } else {
      print("  ✗ Card descriptor mismatch, got: \(cardDescriptors)")
      failed += 1
    }

    // CHECK 22: paymentMethodDescriptors derives bank descriptor from catalog
    print("22. paymentMethodDescriptors bank descriptor...")
    let bankProvider = Provider(id: "worldpay", name: "Worldpay", description: "Bank transfer", methods: ["bank"])
    let bankDescriptors = paymentMethodDescriptors(from: [bankProvider])
    if bankDescriptors.count == 1,
       bankDescriptors[0].id == "worldpay:bank",
       bankDescriptors[0].method == .bank,
       bankDescriptors[0].requiresBankChoice == true,
       bankDescriptors[0].logoSymbol == "building.columns.fill" {
      print("  ✓ Bank descriptor correct: requiresBankChoice=\(bankDescriptors[0].requiresBankChoice)")
      passed += 1
    } else {
      print("  ✗ Bank descriptor mismatch, got: \(bankDescriptors)")
      failed += 1
    }

    // CHECK 23: paymentMethodDescriptors handles multiple providers
    print("23. paymentMethodDescriptors multiple providers...")
    let multiDescriptors = paymentMethodDescriptors(from: [cardProvider, bankProvider])
    if multiDescriptors.count == 2,
       multiDescriptors[0].providerId == "adyen",
       multiDescriptors[1].providerId == "worldpay" {
      print("  ✓ Multiple providers: \(multiDescriptors.count) descriptors, order preserved")
      passed += 1
    } else {
      print("  ✗ Expected 2 descriptors in provider order, got: \(multiDescriptors.count)")
      failed += 1
    }

    // CHECK 24: paymentMethodDescriptors skips unknown method strings
    print("24. paymentMethodDescriptors skips unknown methods...")
    let unknownProvider = Provider(id: "x", name: "X", description: "", methods: ["wire", "card"])
    let mixed = paymentMethodDescriptors(from: [unknownProvider])
    if mixed.count == 1 && mixed[0].method == .card {
      print("  ✓ Unknown method 'wire' skipped, 'card' retained")
      passed += 1
    } else {
      print("  ✗ Expected 1 descriptor ('card'), got: \(mixed.count)")
      failed += 1
    }

    // CHECK 25: paymentMethodDescriptors empty catalog yields empty list
    print("25. paymentMethodDescriptors empty catalog...")
    let empty = paymentMethodDescriptors(from: [])
    if empty.isEmpty {
      print("  ✓ Empty catalog yields empty descriptor list")
      passed += 1
    } else {
      print("  ✗ Expected empty list, got \(empty.count) descriptors")
      failed += 1
    }

    // CHECK 26: demoBanks contains expected entries
    print("26. demoBanks list...")
    let barclays = demoBanks.first(where: { $0.id == "barclays" })
    let monzo = demoBanks.first(where: { $0.id == "monzo" })
    if demoBanks.count == 8, barclays?.sortCode == "20-00-00", monzo?.name == "Monzo" {
      print("  ✓ demoBanks has \(demoBanks.count) entries, sort codes present")
      passed += 1
    } else {
      print("  ✗ demoBanks unexpected content, count=\(demoBanks.count)")
      failed += 1
    }

    // CHECK 27: BankOption filtering by name (case-insensitive)
    print("27. BankOption search filtering...")
    let queryLloyds = "lloy"
    let filtered = demoBanks.filter { $0.name.localizedCaseInsensitiveContains(queryLloyds) }
    if filtered.count == 1 && filtered[0].id == "lloyds" {
      print("  ✓ Search 'lloy' matches Lloyds only")
      passed += 1
    } else {
      print("  ✗ Expected 1 match for 'lloy', got \(filtered.count)")
      failed += 1
    }

    // CHECK 28: Transaction decodes provider as String (not enum)
    print("28. Transaction provider is String...")
    let txnJson = """
    {
      "id": "txn-1", "reference": "REF-1", "recipientId": "rec-1",
      "name": "Test", "category": "Shopping", "amount": 500,
      "date": "2026-09-01", "provider": "adyen",
      "method": "card", "status": "completed", "note": ""
    }
    """
    do {
      let decoder = JSONDecoder()
      let txn = try decoder.decode(Transaction.self, from: txnJson.data(using: .utf8)!)
      if txn.provider == "adyen" {
        print("  ✓ Transaction.provider decoded as String: \"\(txn.provider)\"")
        passed += 1
      } else {
        print("  ✗ Expected provider \"adyen\", got \"\(txn.provider)\"")
        failed += 1
      }
    } catch {
      print("  ✗ Decoding failed: \(error)")
      failed += 1
    }

    // CHECK 29: Provider.id decodes as String
    print("29. Provider.id is String...")
    let providerJson = """
    {"id": "worldpay", "name": "Worldpay", "description": "Bank transfer", "methods": ["bank"]}
    """
    do {
      let decoder = JSONDecoder()
      let provider = try decoder.decode(Provider.self, from: providerJson.data(using: .utf8)!)
      if provider.id == "worldpay" {
        print("  ✓ Provider.id decoded as String: \"\(provider.id)\"")
        passed += 1
      } else {
        print("  ✗ Expected id \"worldpay\", got \"\(provider.id)\"")
        failed += 1
      }
    } catch {
      print("  ✗ Decoding failed: \(error)")
      failed += 1
    }

    // Summary
    print("\n=== Results ===")
    print("Passed: \(passed)/29")
    print("Failed: \(failed)/29")

    if failed > 0 {
      exit(1)
    }
  }
}
