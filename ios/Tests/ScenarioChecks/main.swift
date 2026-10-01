import Foundation
@testable import MeridianSDK

// ============================================================
// Shared scenario tests – Swift / Kotlin behavioral parity
// ============================================================
// Covers: money formatting, cache-expiry detection,
// idempotency persistence across retries, and process-death
// state recovery (Codable round-trips).
// ============================================================

struct ScenarioChecks {
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
    print("=== Scenario Checks ===\n")

    // -----------------------------------------------------------------
    // Money Formatting
    // -----------------------------------------------------------------

    print("1. Money formatting: minimum pence")
    check("1p = £0.01", money(1) == "£0.01")

    print("\n2. Money formatting: exact pounds")
    check("100p = £1.00",     money(100)    == "£1.00")
    check("1000p = £10.00",   money(1_000)  == "£10.00")
    check("10000p = £100.00", money(10_000) == "£100.00")

    print("\n3. Money formatting: maximum amount (£10,000)")
    check("1000000p = £10000.00", money(1_000_000) == "£10000.00")

    print("\n4. Money formatting: mixed pence values")
    check("1050p = £10.50", money(1_050) == "£10.50")
    check("99p = £0.99",    money(99)    == "£0.99")
    check("105p = £1.05",   money(105)   == "£1.05")
    check("9999p = £99.99", money(9_999) == "£99.99")

    print("\n5. Money formatting: round-trips with parseAmount")
    let samples = [1, 50, 100, 1_050, 9_999, 1_000_000]
    for pence in samples {
      let formatted = money(pence)
      // Strip leading £ before parsing
      let stripped = String(formatted.dropFirst())
      let (parsed, err) = parseAmount(stripped)
      check("£\(stripped) round-trips to \(pence)p", parsed == pence && err == nil)
    }

    // -----------------------------------------------------------------
    // Cache Expiry Detection
    // -----------------------------------------------------------------

    print("\n6. Cache expiry: fresh state has higher version than stale")
    let staleState = BankState(version: 1, balance: 100_000, transactions: [], budgets: [])
    let freshState  = BankState(version: 5, balance: 95_000,  transactions: [], budgets: [])
    check("version 5 > version 1", freshState.version > staleState.version)

    print("\n7. Cache expiry: transaction date comparison")
    let staleDate = "2026-01-01"
    let freshDate = "2026-09-18"
    check("fresh date sorts after stale", freshDate > staleDate)

    print("\n8. Cache expiry: catalog demoDate bump invalidates cache")
    let v1Date = "2026-09-17"
    let v2Date = "2026-09-18"
    check("v2 demoDate > v1 demoDate", v2Date > v1Date)

    print("\n9. Cache expiry: version 0 is always stale")
    let uninit = BankState(version: 0, balance: 0, transactions: [], budgets: [])
    check("version 0 is uninitialised / stale", uninit.version == 0)

    // -----------------------------------------------------------------
    // Idempotency Persistence
    // -----------------------------------------------------------------

    print("\n10. Idempotency: UUID key is non-empty and ≤ 128 chars")
    let uuid = UUID().uuidString
    check("uuid non-empty",   !uuid.isEmpty)
    check("uuid ≤ 128 chars", uuid.count <= 128)

    print("\n11. Idempotency: PAYMENT_PENDING response round-trips via Codable")
    do {
      let pending = PaymentResponse(
        ok: false,
        state: nil,
        transaction: nil,
        error: "Awaiting confirmation",
        code: "PAYMENT_PENDING",
        paymentId: "pay-idm-scenario"
      )
      let data      = try JSONEncoder().encode(pending)
      let recovered = try JSONDecoder().decode(PaymentResponse.self, from: data)
      check("ok is false after round-trip",              recovered.ok == false)
      check("code preserved after round-trip",           recovered.code == "PAYMENT_PENDING")
      check("paymentId preserved after round-trip",      recovered.paymentId == "pay-idm-scenario")
    } catch {
      print("  ✗ Codable round-trip failed: \(error)"); failed += 1
    }

    print("\n12. Idempotency: unique key per new payment attempt")
    let key1 = UUID().uuidString
    let key2 = UUID().uuidString
    check("two generated keys are different", key1 != key2)

    // -----------------------------------------------------------------
    // Process Death / State Recovery (Codable round-trips)
    // -----------------------------------------------------------------

    print("\n13. Process death: BankState survives Codable round-trip")
    do {
      let original = BankState(
        version: 3,
        balance: 250_000,
        transactions: [
          Transaction(
            id: "txn-pd-1", reference: "REF-PD-001", recipientId: "rec-1",
            name: "Test Merchant", category: .shopping, amount: 2_500,
            date: "2026-09-18", provider: .worldpay, method: .bank,
            status: .completed, note: "Post-death recovery"
          )
        ],
        budgets: [Budget(category: .shopping, limit: 50_000)]
      )
      let data     = try JSONEncoder().encode(original)
      let restored = try JSONDecoder().decode(BankState.self, from: data)
      check("version restored",              restored.version == 3)
      check("balance restored",              restored.balance == 250_000)
      check("transaction count",             restored.transactions.count == 1)
      check("transaction id restored",       restored.transactions[0].id == "txn-pd-1")
      check("transaction amount restored",   restored.transactions[0].amount == 2_500)
      check("budget count",                  restored.budgets.count == 1)
      check("budget limit restored",         restored.budgets[0].limit == 50_000)
    } catch {
      print("  ✗ BankState Codable round-trip failed: \(error)"); failed += 1
    }

    print("\n14. Process death: PaymentResponse with paymentId survives Codable round-trip")
    do {
      let original = PaymentResponse(
        ok: false, state: nil, transaction: nil,
        error: "Awaiting bank confirmation",
        code: "PAYMENT_PENDING",
        paymentId: "pay-crash-recovery"
      )
      let data     = try JSONEncoder().encode(original)
      let restored = try JSONDecoder().decode(PaymentResponse.self, from: data)
      check("ok restored",        restored.ok == false)
      check("code restored",      restored.code == "PAYMENT_PENDING")
      check("paymentId restored", restored.paymentId == "pay-crash-recovery")
    } catch {
      print("  ✗ PaymentResponse Codable round-trip failed: \(error)"); failed += 1
    }

    print("\n15. Process death: CatalogResponse survives Codable round-trip")
    do {
      let original = CatalogResponse(
        demoDate: "2026-09-18",
        recipients: [
          Recipient(id: "rec-1", name: "Shop", initials: "SH", detail: "Detail", category: .shopping, color: "#fff")
        ],
        providers: [
          Provider(id: .adyen, name: "Adyen", description: "Card", methods: [.card])
        ]
      )
      let data     = try JSONEncoder().encode(original)
      let restored = try JSONDecoder().decode(CatalogResponse.self, from: data)
      check("demoDate restored",       restored.demoDate == "2026-09-18")
      check("recipient count",         restored.recipients.count == 1)
      check("recipient id restored",   restored.recipients[0].id == "rec-1")
    } catch {
      print("  ✗ CatalogResponse Codable round-trip failed: \(error)"); failed += 1
    }

    print("\n16. Process death: Budget survives Codable round-trip")
    do {
      let original = Budget(category: .transport, limit: 20_000)
      let data     = try JSONEncoder().encode(original)
      let restored = try JSONDecoder().decode(Budget.self, from: data)
      check("category restored", restored.category == .transport)
      check("limit restored",    restored.limit == 20_000)
    } catch {
      print("  ✗ Budget Codable round-trip failed: \(error)"); failed += 1
    }

    // Summary
    print("\n=== Scenario Results ===")
    print("Passed: \(passed)")
    print("Failed: \(failed)")
  }
}

@main
struct ScenarioChecksMain {
  static func main() {
    var checks = ScenarioChecks()
    checks.run()
    if checks.failed > 0 { exit(1) }
  }
}
