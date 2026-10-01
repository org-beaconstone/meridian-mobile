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

    // CHECK 21: legacy GBP adapter
    print("21. legacy GBP pence adapter...")
    let legacy = Money.fromLegacyGbpPence(1050)
    let roundTrip = try? legacy.legacyGbpPence()
    let eurLegacy = try? Money(currencyCode: "EUR", minorUnits: 100, minorUnitExponent: 2).legacyGbpPence()
    let wide = Money.fromLegacyGbpPence(Int(Int32.max) + 1)
    let widePence = try? wide.legacyGbpPence()
    if legacy.currencyCode == "GBP" && legacy.minorUnits == 1050 && legacy.minorUnitExponent == 2
      && roundTrip == 1050 && eurLegacy == nil && widePence == nil
    {
      print("  ✓ legacy adapter round-trips 1050 and rejects EUR / Int32 overflow")
      passed += 1
    } else {
      print("  ✗ legacy adapter mismatch")
      failed += 1
    }

    // CHECK 22: conversion precision without floating point
    print("22. conversion precision...")
    do {
      let euros = try Money.parse("10.5", currencyCode: "EUR", minorUnitExponent: 2)
      let exact = try Money.parse("90071992547409.93", currencyCode: "EUR", minorUnitExponent: 2)
      let sum = try Money.parse("0.10", currencyCode: "EUR", minorUnitExponent: 2)
        .adding(try Money.parse("0.20", currencyCode: "EUR", minorUnitExponent: 2))
      let viaFloat = Int64(("90071992547409.93" as NSString).doubleValue * 100.0)
      if euros.minorUnits == 1050 && euros.plainDecimal() == "10.50"
        && exact.minorUnits == 9_007_199_254_740_993 && exact.plainDecimal() == "90071992547409.93"
        && sum.minorUnits == 30 && sum.plainDecimal() == "0.30"
        && viaFloat != exact.minorUnits
      {
        print("  ✓ decimal conversion stays exact past the float mantissa")
        passed += 1
      } else {
        print("  ✗ precision mismatch exact=\(exact.minorUnits) float=\(viaFloat) sum=\(sum.plainDecimal())")
        failed += 1
      }
    } catch {
      print("  ✗ precision threw: \(error)")
      failed += 1
    }

    // CHECK 23: overflow protection
    print("23. overflow protection...")
    var overflowed = 0
    do { _ = try Money.parse("92233720368547759.00", currencyCode: "GBP", minorUnitExponent: 2) }
    catch MoneyError.overflow { overflowed += 1 } catch { print("  unexpected parse error \(error)") }
    do {
      _ = try Money(currencyCode: "GBP", minorUnits: Int64.max, minorUnitExponent: 2)
        .adding(try Money(currencyCode: "GBP", minorUnits: 1, minorUnitExponent: 2))
    } catch MoneyError.overflow { overflowed += 1 } catch { print("  unexpected add error \(error)") }
    do {
      _ = try Money.fromLegacyGbpPence(1)
        .adding(try Money(currencyCode: "EUR", minorUnits: 1, minorUnitExponent: 2))
    } catch MoneyError.currencyMismatch { overflowed += 1 } catch { print("  unexpected mix error \(error)") }
    do { _ = try Money(currencyCode: "EUR", minorUnits: 1, minorUnitExponent: 0) }
    catch MoneyError.exponentMismatch { overflowed += 1 } catch { print("  unexpected exponent error \(error)") }
    if overflowed == 4 {
      print("  ✓ overflow, mixed currency, and EUR exponent are rejected")
      passed += 1
    } else {
      print("  ✗ expected 4 rejections, got \(overflowed)")
      failed += 1
    }

    // CHECK 24: migration JSON
    print("24. migration JSON...")
    do {
      let legacyAmount = try MoneyMigration.decodeAmount("3500")
      let legacyField = try MoneyMigration.decodeAmountField(
        "amount",
        in: #"{"id":"txn-001","amount":3500,"note":"Breakfast"}"#
      )
      let eur = try MoneyMigration.decodeAmountField(
        "amount",
        in: #"{"id":"txn-eu","amount":{"currencyCode":"EUR","minorUnits":199,"minorUnitExponent":2}}"#
      )
      let wideAmount = try MoneyMigration.decodeAmountField(
        "amount",
        in: #"{"amount":9007199254740993}"#
      )
      let reordered = try MoneyMigration.decodeAmount(
        #"{"minorUnitExponent":2,"minorUnits":1050,"currencyCode":"EUR"}"#
      )
      let precise = try Money(currencyCode: "EUR", minorUnits: 9_007_199_254_740_993, minorUnitExponent: 2)
      let encoded = precise.toJSON()
      let decoded = try Money.fromJSON(encoded)
      let legacyPence = try legacyField.legacyGbpPence()
      let eurExpected = try Money(currencyCode: "EUR", minorUnits: 199, minorUnitExponent: 2)
      var rejected = 0
      if (try? MoneyMigration.decodeAmount("10.5")) == nil { rejected += 1 }
      if (try? MoneyMigration.decodeAmount("9223372036854775808")) == nil { rejected += 1 }
      if legacyAmount == Money.fromLegacyGbpPence(3500)
        && legacyPence == 3500
        && eur == eurExpected
        && wideAmount.minorUnits == 9_007_199_254_740_993
        && wideAmount.plainDecimal() == "90071992547409.93"
        && reordered.currencyCode == "EUR" && reordered.minorUnits == 1050
        && encoded == #"{"currencyCode":"EUR","minorUnits":9007199254740993,"minorUnitExponent":2}"#
        && decoded == precise
        && rejected == 2
      {
        print("  ✓ legacy integers and ISO-4217 objects decode exactly")
        passed += 1
      } else {
        print("  ✗ JSON migration mismatch encoded=\(encoded)")
        failed += 1
      }
    } catch {
      print("  ✗ JSON migration threw: \(error)")
      failed += 1
    }

    // CHECK 25: locale formatting
    print("25. EUR and GBP locale formatting...")
    let en = Locale(identifier: "en_GB")
    let de = Locale(identifier: "de_DE")
    let fr = Locale(identifier: "fr_FR")
    let gbp = Money.fromLegacyGbpPence(1_248_050).formatted(locale: en)
    let eurEn = (try? Money(currencyCode: "EUR", minorUnits: 1050, minorUnitExponent: 2).formatted(locale: en)) ?? ""
    let eurDe = (try? Money(currencyCode: "EUR", minorUnits: 1050, minorUnitExponent: 2).formatted(locale: de)) ?? ""
    let eurDeNeg = (try? Money(currencyCode: "EUR", minorUnits: -1050, minorUnitExponent: 2).formatted(locale: de)) ?? ""
    let eurFr = (try? Money(currencyCode: "EUR", minorUnits: 123_456, minorUnitExponent: 2).formatted(locale: fr)) ?? ""
    let grouped = money(1_000_000)
    if gbp == "£12,480.50" && eurEn == "€10.50" && eurDe == "10,50 €" && eurDeNeg == "-10,50 €"
      && eurFr == "1\u{00A0}234,56\u{00A0}€" && grouped == "£10,000.00"
    {
      print("  ✓ locale formatting matches exponent and separators")
      passed += 1
    } else {
      print("  ✗ format mismatch gbp=\(gbp) eurEn=\(eurEn) eurDe=\(eurDe) eurFr=\(eurFr) grouped=\(grouped)")
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
