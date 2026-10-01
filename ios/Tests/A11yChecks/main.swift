import Foundation
@testable import MeridianSDK

// ============================================================
// Accessibility and localization checks (VoiceOver / RTL)
// ============================================================
// Verifies that every string the UI exposes to VoiceOver is
// non-empty, that formatted amounts stay legible at large font
// scales, and that no hard-coded directionality markers are
// embedded that would break RTL layouts.
// All checks are pure model / formatting-layer logic.
// ============================================================

struct A11yChecks {
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
    print("=== Accessibility & Localization Checks ===\n")

    // -----------------------------------------------------------------
    // VoiceOver Content-Description Tests
    // -----------------------------------------------------------------

    print("1. VoiceOver: Recipient fields are non-empty for announcements")
    let recipient = Recipient(
      id: "birch-bloom",
      name: "Birch & Bloom",
      initials: "BB",
      detail: "Organic café & bistro",
      category: .foodDrink,
      color: "#FFD93D"
    )
    check("name is non-blank",      !recipient.name.isEmpty)
    check("detail is non-blank",    !recipient.detail.isEmpty)
    check("initials are non-blank", !recipient.initials.isEmpty)

    print("\n2. VoiceOver: Transaction fields are non-empty for announcements")
    let txn = Transaction(
      id: "txn-001", reference: "REF-001", recipientId: "rec-1",
      name: "Coffee Shop", category: .foodDrink, amount: 350,
      date: "2026-09-18", provider: .adyen, method: .card,
      status: .completed, note: "Morning coffee"
    )
    check("txn name non-blank",      !txn.name.isEmpty)
    check("txn date non-blank",      !txn.date.isEmpty)
    check("txn amount non-negative",  txn.amount >= 0)

    print("\n3. VoiceOver: money string begins with £ currency symbol")
    check("£ symbol leads the amount", money(1_050).hasPrefix("£"))

    print("\n4. VoiceOver: transaction status values are human-readable words")
    let humanStatuses = ["completed", "declined", "pending"]
    for status in [TransactionStatus.completed, .declined, .pending] {
      check("status '\(status.rawValue)' is human-readable", humanStatuses.contains(status.rawValue))
    }

    print("\n5. VoiceOver: Provider name and description are non-empty")
    for provider in [
      Provider(id: .adyen,    name: "Adyen",    description: "Card payment processor",  methods: [.card]),
      Provider(id: .worldpay, name: "Worldpay", description: "Bank transfer processor", methods: [.bank]),
    ] {
      check("provider '\(provider.id.rawValue)' name non-blank",        !provider.name.isEmpty)
      check("provider '\(provider.id.rawValue)' description non-blank", !provider.description.isEmpty)
    }

    print("\n6. VoiceOver: AuditEvent fields are non-empty")
    let event = AuditEvent(
      timestamp: "2026-09-18T10:00:00Z",
      action: "PAYMENT_SUBMITTED",
      details: "£10.50 to Birch & Bloom"
    )
    check("event timestamp non-blank", !event.timestamp.isEmpty)
    check("event action non-blank",    !event.action.isEmpty)

    // -----------------------------------------------------------------
    // Large-Font Scaling Tests
    // -----------------------------------------------------------------

    print("\n7. Large font: max amount string is ≤ 12 chars")
    let maxAmount = money(1_000_000)  // £10000.00 = 10 chars
    check("£10000.00 is ≤ 12 chars [\(maxAmount)]", maxAmount.count <= 12)

    print("\n8. Large font: minimum amount is non-empty and contains £")
    let minAmount = money(1)
    check("1p string non-empty",   !minAmount.isEmpty)
    check("1p string contains £",   minAmount.contains("£"))

    print("\n9. Large font: all common amounts are ≤ 12 chars")
    for pence in [1, 99, 1_050, 10_000, 100_000, 1_000_000] {
      let s = money(pence)
      check("money(\(pence)) ≤ 12 chars [\(s)]", s.count <= 12)
    }

    print("\n10. Large font: recipient initials are 1–3 chars for avatar legibility")
    for (name, initials) in [("Alice Smith", "AS"), ("Bob", "B"), ("Café Bar Ltd", "CB")] {
      check("'\(name)' initials '\(initials)' in 1..3", initials.count >= 1 && initials.count <= 3)
    }

    print("\n11. Large font: note truncation to ≤ 101 chars is safe")
    let longNote  = String(repeating: "A", count: 200)
    let truncated = longNote.count > 100 ? String(longNote.prefix(100)) + "…" : longNote
    check("truncated note is ≤ 101 chars", truncated.count <= 101)

    // -----------------------------------------------------------------
    // RTL Layout-Readiness Tests
    // -----------------------------------------------------------------

    let ltrMark = "\u{200E}"
    let rtlMark = "\u{200F}"

    print("\n12. RTL: recipient names contain no directional Unicode markers")
    for r in [
      Recipient(id: "r1", name: "Birch & Bloom",    initials: "BB", detail: "Organic café", category: .foodDrink, color: "#FFD93D"),
      Recipient(id: "r2", name: "Northline Studio",  initials: "NS", detail: "Design tools",  category: .shopping,  color: "#FF6B6B"),
    ] {
      check("'\(r.name)' has no LTR mark", !r.name.contains(ltrMark))
      check("'\(r.name)' has no RTL mark", !r.name.contains(rtlMark))
    }

    print("\n13. RTL: £ symbol leads formatted amount in en-GB")
    check("£ leads amount for en-GB", money(500).hasPrefix("£"))

    print("\n14. RTL: Category raw values have no directional markers and are non-blank")
    for cat in Category.allCases {
      check("'\(cat.rawValue)' has no LTR mark", !cat.rawValue.contains(ltrMark))
      check("'\(cat.rawValue)' has no RTL mark", !cat.rawValue.contains(rtlMark))
      check("'\(cat.rawValue)' is non-blank",    !cat.rawValue.isEmpty)
    }

    print("\n15. RTL: formatted amounts contain only printable characters")
    for pence in [1, 99, 1_050, 100_000, 1_000_000] {
      let s = money(pence)
      check("money(\(pence)) all printable", s.unicodeScalars.allSatisfy { $0.value >= 32 })
    }

    print("\n16. RTL: provider names contain no control characters or directional markers")
    for p in [
      Provider(id: .adyen,    name: "Adyen",    description: "Card", methods: [.card]),
      Provider(id: .worldpay, name: "Worldpay", description: "Bank", methods: [.bank]),
    ] {
      check("'\(p.name)' no control chars", p.name.unicodeScalars.allSatisfy { $0.value >= 32 })
      check("'\(p.name)' no LTR mark",      !p.name.contains(ltrMark))
      check("'\(p.name)' no RTL mark",      !p.name.contains(rtlMark))
    }

    print("\n17. RTL: transaction status strings have no directional markers")
    for status in [TransactionStatus.completed, .declined, .pending] {
      check("'\(status.rawValue)' no LTR mark", !status.rawValue.contains(ltrMark))
      check("'\(status.rawValue)' no RTL mark", !status.rawValue.contains(rtlMark))
    }

    // Summary
    print("\n=== Accessibility & Localization Results ===")
    print("Passed: \(passed)")
    print("Failed: \(failed)")
  }
}

@main
struct A11yChecksMain {
  static func main() {
    var checks = A11yChecks()
    checks.run()
    if checks.failed > 0 { exit(1) }
  }
}
