import Foundation
@testable import MeridianSDK

// ============================================================
// Consumer-driven contract tests – catalog & payment schemas
// ============================================================
// Validates backward compatibility with legacy integer (pence)
// payloads and forward compatibility when unknown optional fields
// (e.g. a future `currency` hint) appear in API responses.
// ============================================================

struct ContractChecks {
  var passed = 0
  var failed = 0

  mutating func check(_ label: String, _ condition: Bool) {
    if condition {
      print("  ✓ \(label)")
      passed += 1
    } else {
      print("  ✗ \(label)")
      failed += 1
    }
  }

  mutating func run() {
    print("=== Contract Checks ===\n")

    // -----------------------------------------------------------------
    // Catalog schema contracts
    // -----------------------------------------------------------------

    print("1. Catalog: required fields decode correctly")
    do {
      let json = """
        {
          "demoDate": "2026-09-18",
          "recipients": [
            {"id":"birch-bloom","name":"Birch & Bloom","initials":"BB","detail":"Café","category":"Food & drink","color":"#FFD93D"}
          ],
          "providers": [
            {"id":"adyen",    "name":"Adyen",    "description":"Card","methods":["card"]},
            {"id":"worldpay", "name":"Worldpay", "description":"Bank","methods":["bank"]}
          ]
        }
        """
      let catalog = try JSONDecoder().decode(CatalogResponse.self, from: json.data(using: .utf8)!)
      check("demoDate present", catalog.demoDate == "2026-09-18")
      check("one recipient",    catalog.recipients.count == 1)
      check("recipient id",     catalog.recipients[0].id == "birch-bloom")
      check("two providers",    catalog.providers.count == 2)
      check("adyen present",    catalog.providers.contains { $0.id == .adyen })
      check("worldpay present", catalog.providers.contains { $0.id == .worldpay })
    } catch {
      print("  ✗ Decoding failed: \(error)"); failed += 1
    }

    print("\n2. Catalog: legacy integer pence amount decodes and formats")
    do {
      let json = """
        {
          "version":1,"balance":500000,
          "transactions":[{
            "id":"txn-legacy","reference":"REF-001","recipientId":"rec-001",
            "name":"Legacy","category":"Shopping","amount":1050,
            "date":"2026-01-01","provider":"adyen","method":"card",
            "status":"completed","note":"legacy"
          }],
          "budgets":[]
        }
        """
      let state = try JSONDecoder().decode(BankState.self, from: json.data(using: .utf8)!)
      check("amount is 1050 pence", state.transactions[0].amount == 1050)
      check("formats to £10.50",    money(1050) == "£10.50")
    } catch {
      print("  ✗ Decoding failed: \(error)"); failed += 1
    }

    print("\n3. Catalog: unknown `currency` field is silently ignored")
    do {
      let json = """
        {"demoDate":"2026-09-18","currency":"GBP","recipients":[],"providers":[]}
        """
      let catalog = try JSONDecoder().decode(CatalogResponse.self, from: json.data(using: .utf8)!)
      check("demoDate still correct",    catalog.demoDate == "2026-09-18")
      check("recipients empty (ignore)", catalog.recipients.isEmpty)
    } catch {
      print("  ✗ Unknown-field tolerance failed: \(error)"); failed += 1
    }

    print("\n4. Catalog: only adyen and worldpay provider IDs are present")
    do {
      let json = """
        {
          "demoDate":"2026-09-18","recipients":[],
          "providers":[
            {"id":"adyen",    "name":"Adyen",    "description":"Card","methods":["card"]},
            {"id":"worldpay", "name":"Worldpay", "description":"Bank","methods":["bank"]}
          ]
        }
        """
      let catalog = try JSONDecoder().decode(CatalogResponse.self, from: json.data(using: .utf8)!)
      let ids = Set(catalog.providers.map(\.id))
      check("only adyen and worldpay", ids == [.adyen, .worldpay])
    } catch {
      print("  ✗ Decoding failed: \(error)"); failed += 1
    }

    print("\n5. Catalog: all five category strings decode")
    let categoryPairs: [(String, Category)] = [
      ("Shopping",    .shopping),
      ("Food & drink",.foodDrink),
      ("Transport",   .transport),
      ("Bills",       .bills),
      ("Lifestyle",   .lifestyle),
    ]
    for (raw, expected) in categoryPairs {
      do {
        let json = """
          {"id":"r","name":"N","initials":"N","detail":"D","category":"\(raw)","color":"#000"}
          """
        let r = try JSONDecoder().decode(Recipient.self, from: json.data(using: .utf8)!)
        check("category \(raw) decodes", r.category == expected)
      } catch {
        print("  ✗ \(raw) decode failed: \(error)"); failed += 1
      }
    }

    // -----------------------------------------------------------------
    // Payment intent schema contracts
    // -----------------------------------------------------------------

    print("\n6. Payment request: amountMinor is integer pence (round-trips)")
    do {
      let req = PaymentRequest(recipientId: "birch-bloom", amountMinor: 500, method: .card, note: "Coffee", scenario: .success)
      let data = try JSONEncoder().encode(req)
      let decoded = try JSONDecoder().decode(PaymentRequest.self, from: data)
      check("amountMinor preserved", decoded.amountMinor == 500)
      check("recipientId preserved", decoded.recipientId == "birch-bloom")
    } catch {
      print("  ✗ Round-trip failed: \(error)"); failed += 1
    }

    print("\n7. Payment response: ok field is mandatory boolean")
    do {
      let successJSON = """{"ok":true,"state":null,"transaction":null}"""
      let failJSON    = """{"ok":false,"error":"Declined","code":"DECLINED","state":null,"transaction":null}"""
      let success = try JSONDecoder().decode(PaymentResponse.self, from: successJSON.data(using: .utf8)!)
      let failure = try JSONDecoder().decode(PaymentResponse.self, from: failJSON.data(using: .utf8)!)
      check("ok:true is true",   success.ok == true)
      check("ok:false is false", failure.ok == false)
    } catch {
      print("  ✗ Decoding failed: \(error)"); failed += 1
    }

    print("\n8. Payment response: paymentId present for PAYMENT_PENDING")
    do {
      let json = """
        {"ok":false,"code":"PAYMENT_PENDING","paymentId":"pay-abc-123","error":"Awaiting","state":null,"transaction":null}
        """
      let r = try JSONDecoder().decode(PaymentResponse.self, from: json.data(using: .utf8)!)
      check("ok is false",              r.ok == false)
      check("code is PAYMENT_PENDING",  r.code == "PAYMENT_PENDING")
      check("paymentId is present",     r.paymentId == "pay-abc-123")
    } catch {
      print("  ✗ Decoding failed: \(error)"); failed += 1
    }

    print("\n9. Payment response: unknown currency fields are silently ignored")
    do {
      let json = """
        {"ok":true,"currency":"GBP","currencyMinorUnits":2,"state":{"version":1,"balance":100000,"transactions":[],"budgets":[]},"transaction":null}
        """
      let decoder = JSONDecoder()
      let r = try decoder.decode(PaymentResponse.self, from: json.data(using: .utf8)!)
      check("ok is true",         r.ok == true)
      check("balance present",    r.state?.balance == 100_000)
    } catch {
      print("  ✗ Unknown-field tolerance failed: \(error)"); failed += 1
    }

    print("\n10. BankState: version is a non-negative integer")
    do {
      let json = """{"version":42,"balance":0,"transactions":[],"budgets":[]}"""
      let state = try JSONDecoder().decode(BankState.self, from: json.data(using: .utf8)!)
      check("version is 42",          state.version == 42)
      check("version is non-negative", state.version >= 0)
    } catch {
      print("  ✗ Decoding failed: \(error)"); failed += 1
    }

    print("\n11. BankState: budget limit is integer pence")
    do {
      let json = """{"category":"Shopping","limit":100000}"""
      let budget = try JSONDecoder().decode(Budget.self, from: json.data(using: .utf8)!)
      check("limit is 100000",        budget.limit == 100_000)
      check("formats as £1000.00",    money(budget.limit) == "£1000.00")
    } catch {
      print("  ✗ Decoding failed: \(error)"); failed += 1
    }

    print("\n12. Payment method values: card and bank only")
    let methodJSON: [(String, PaymentMethod)] = [
      ("""{"recipientId":"r","amountMinor":100,"method":"card","note":"","scenario":"success"}""", .card),
      ("""{"recipientId":"r","amountMinor":100,"method":"bank","note":"","scenario":"success"}""", .bank),
    ]
    for (json, expected) in methodJSON {
      do {
        let req = try JSONDecoder().decode(PaymentRequest.self, from: json.data(using: .utf8)!)
        check("method \(expected.rawValue) decodes", req.method == expected)
      } catch {
        print("  ✗ method decode failed: \(error)"); failed += 1
      }
    }

    // Summary
    print("\n=== Contract Results ===")
    print("Passed: \(passed)")
    print("Failed: \(failed)")
  }
}

@main
struct ContractChecksMain {
  static func main() {
    var checks = ContractChecks()
    checks.run()
    if checks.failed > 0 { exit(1) }
  }
}
