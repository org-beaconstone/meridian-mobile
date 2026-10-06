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
      if state.version == 1 && state.balance == Money.gbpPence(1_248_050) {
        print("  ✓ BankState decoded: v=\(state.version), balance=\(state.balance.minorUnits) \(state.balance.currencyCode)")
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

    // CHECK 21: legacy integer decodes as GBP pence
    print("21. legacy integer money...")
    do {
      let money = try JSONDecoder().decode(Money.self, from: Data("3500".utf8))
      if money == Money.gbpPence(3500) && money.minorUnitExponent == 2 && money.currencyCode == "GBP" {
        print("  ✓ legacy 3500 is GBP 3500 exponent 2")
        passed += 1
      } else {
        print("  ✗ unexpected legacy money \(money)")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 22: ISO-4217 object and legacy amount field
    print("22. multi-currency JSON...")
    do {
      let eur = try JSONDecoder().decode(
        Money.self,
        from: Data(#"{"currencyCode":"EUR","minorUnits":1999,"minorUnitExponent":2}"#.utf8)
      )
      let fromAmount = try JSONDecoder().decode(
        Money.self,
        from: Data(#"{"amount":1999,"currencyCode":"EUR"}"#.utf8)
      )
      let encoded = try JSONEncoder().encode(eur)
      let roundTrip = try JSONDecoder().decode(Money.self, from: encoded)
      if eur == fromAmount && roundTrip == eur && eur.minorUnits == 1999 {
        print("  ✓ EUR object, legacy amount field, and round trip")
        passed += 1
      } else {
        print("  ✗ multi-currency decode mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 23: conversion precision beyond binary floating point
    print("23. conversion precision...")
    do {
      let small = try Money.parseMajor("0.10", currencyCode: "GBP")
      let classic = try Money.parseMajor("0.29", currencyCode: "EUR")
      let price = try Money.parseMajor("19.99", currencyCode: "EUR")
      let wide = try Money.parseMajor("90071992547409.91", currencyCode: "GBP")
      let padded = try Money.parseMajor("10.5", currencyCode: "GBP")
      let sum = try price.adding(try Money.parseMajor("0.01", currencyCode: "EUR"))
      if small.minorUnits == 10
        && classic.minorUnits == 29
        && price.minorUnits == 1999
        && price.majorDecimal() == "19.99"
        && wide.minorUnits == 9_007_199_254_740_991
        && wide.majorDecimal() == "90071992547409.91"
        && padded.minorUnits == 1050
        && sum.minorUnits == 2000
      {
        print("  ✓ minor units stay exact")
        passed += 1
      } else {
        print("  ✗ precision mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 24: overflow protection
    print("24. overflow protection...")
    do {
      var overflowed = false
      do {
        _ = try Money.parseMajor("92233720368547758.08", currencyCode: "GBP")
      } catch MoneyError.overflow {
        overflowed = true
      }
      let atLimit = try Money.parseMajor("92233720368547758.07", currencyCode: "GBP")
      var addOverflow = false
      do { _ = try atLimit.adding(Money.gbpPence(1)) } catch MoneyError.overflow { addOverflow = true }
      var mismatch = false
      do { _ = try Money.gbpPence(1).adding(try Money(currencyCode: "EUR", minorUnits: 1, minorUnitExponent: 2)) } catch MoneyError.currencyMismatch { mismatch = true }
      var badExponent = false
      do { _ = try Money(currencyCode: "EUR", minorUnits: 1, minorUnitExponent: 0) } catch MoneyError.exponentMismatch { badExponent = true }
      var notGbp = false
      do { _ = try Money(currencyCode: "EUR", minorUnits: 100, minorUnitExponent: 2).requireLegacyGbpPence() } catch MoneyError.notLegacyGbp { notGbp = true }
      if overflowed && atLimit.minorUnits == Int64.max && addOverflow && mismatch && badExponent && notGbp {
        print("  ✓ overflow, exponent, and legacy GBP guards")
        passed += 1
      } else {
        print("  ✗ guard mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 25: EUR and GBP locale formatting
    print("25. EUR and GBP formatting...")
    do {
      let pounds = Money.gbpPence(1_248_050)
      let euros = try Money(currencyCode: "EUR", minorUnits: 1_248_050, minorUnitExponent: 2)
      let en = Locale(identifier: "en_GB")
      let de = Locale(identifier: "de_DE")
      let gbpEn = pounds.formatted(locale: en)
      let eurEn = euros.formatted(locale: en)
      let eurDe = euros.formatted(locale: de)
      let gbpDe = pounds.formatted(locale: de)
      let penny = Money.gbpPence(1).formatted(locale: en)
      if gbpEn == "£12,480.50"
        && eurEn == "€12,480.50"
        && eurDe == "12.480,50\u{00A0}€"
        && gbpDe == "12.480,50\u{00A0}£"
        && penny == "£0.01"
      {
        print("  ✓ locale formats")
        passed += 1
      } else {
        print("  ✗ gbpEn=\(gbpEn) eurEn=\(eurEn) eurDe=\(eurDe) gbpDe=\(gbpDe) penny=\(penny)")
        failed += 1
      }
    } catch {
      print("  ✗ \(error)")
      failed += 1
    }

    // CHECK 26: non-integral JSON is rejected
    print("26. non-integral JSON...")
    do {
      _ = try JSONDecoder().decode(Money.self, from: Data("10.5".utf8))
      print("  ✗ accepted a fractional minor-unit value")
      failed += 1
    } catch {
      print("  ✓ fractional JSON rejected")
      passed += 1
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
