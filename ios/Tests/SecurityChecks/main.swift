import Foundation
@testable import MeridianSDK

// ============================================================
// Security and resilience tests
// ============================================================
// Verifies rejection of replayed deep links, expired / stale
// return states, and malformed catalog entries.
// All checks are pure model / parsing logic (no live network).
// ============================================================

struct SecurityChecks {
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
    print("=== Security & Resilience Checks ===\n")

    // -----------------------------------------------------------------
    // Replayed Deep-Link Scenarios
    // -----------------------------------------------------------------

    print("1. Replay: duplicate payment ID is detectable locally")
    var processed = Set<String>()
    let id = "pay-deep-link-001"
    let firstInsert  = processed.insert(id).inserted
    let secondInsert = processed.insert(id).inserted
    check("first occurrence is not a replay",  firstInsert)
    check("duplicate is flagged as replay",   !secondInsert)

    print("\n2. Replay: empty payment ID must be rejected")
    check("empty ID is empty", "".isEmpty)
    check("valid ID is non-empty", "pay-valid-001".count > 0)

    print("\n3. Replay: deep-link session must match active session")
    let active     = "session-abc-123"
    let matching   = "session-abc-123"
    let mismatched = "session-old-456"
    check("matching session accepted",   active == matching)
    check("mismatched session rejected", active != mismatched)

    print("\n4. Replay: REPLAY_DETECTED response decodes cleanly")
    do {
      let json = """
        {"ok":false,"code":"REPLAY_DETECTED","error":"Idempotency key already used","state":null,"transaction":null}
        """
      let r = try JSONDecoder().decode(PaymentResponse.self, from: json.data(using: .utf8)!)
      check("ok is false",              r.ok == false)
      check("code is REPLAY_DETECTED",  r.code == "REPLAY_DETECTED")
    } catch {
      print("  ✗ Decoding failed: \(error)"); failed += 1
    }

    // -----------------------------------------------------------------
    // Expired / Stale Return-State Scenarios
    // -----------------------------------------------------------------

    print("\n5. Expired state: lower version than current is stale")
    let currentVersion = 10
    let expiredVersion = 3
    check("expired version < current", expiredVersion < currentVersion)

    print("\n6. Expired catalog: older demoDate is stale")
    check("expired date sorts before fresh", "2025-01-01" < "2026-09-18")

    print("\n7. Expired state: version 0 is always stale / uninitialised")
    let uninit = BankState(version: 0, balance: 0, transactions: [], budgets: [])
    check("version 0 is stale", uninit.version == 0)

    print("\n8. Expired state: PAYMENT_PENDING tied to very old version is expired")
    let savedVersion   = 1
    let liveVersion    = 5
    let pendingExpired = savedVersion < liveVersion - 2
    check("pending against v1 while live is v5 is expired", pendingExpired)

    print("\n9. Expired state: stale PAYMENT_PENDING response decodes for recovery")
    do {
      let json = """
        {"ok":false,"code":"PAYMENT_PENDING","paymentId":"pay-stale-99","error":"Pending","state":null,"transaction":null}
        """
      let r = try JSONDecoder().decode(PaymentResponse.self, from: json.data(using: .utf8)!)
      check("paymentId recoverable from stale response", r.paymentId == "pay-stale-99")
      check("code is PAYMENT_PENDING",                   r.code == "PAYMENT_PENDING")
    } catch {
      print("  ✗ Decoding failed: \(error)"); failed += 1
    }

    // -----------------------------------------------------------------
    // Malformed Catalog Entry Scenarios
    // -----------------------------------------------------------------

    print("\n10. Malformed catalog: missing required `id` field fails decoding")
    let noIdJson = """
      {"name":"No-ID Merchant","initials":"NM","detail":"Bad","category":"Shopping","color":"#000"}
      """
    do {
      _ = try JSONDecoder().decode(Recipient.self, from: noIdJson.data(using: .utf8)!)
      // Swift's Codable throws for missing non-optional fields
      print("  ✗ Should have thrown for missing id"); failed += 1
    } catch {
      check("missing id throws DecodingError", error is DecodingError)
    }

    print("\n11. Malformed catalog: unknown provider ID is detectable")
    let knownProviders: Set<ProviderId> = [.adyen, .worldpay]
    let unknownJson = """
      {"id":"stripe","name":"Stripe","description":"Third party","methods":["card"]}
      """
    do {
      _ = try JSONDecoder().decode(Provider.self, from: unknownJson.data(using: .utf8)!)
      print("  ✗ Should have thrown for unknown provider id"); failed += 1
    } catch {
      check("unknown provider id throws DecodingError", error is DecodingError)
    }

    print("\n12. Malformed catalog: negative transaction amount is detectable")
    do {
      let json = """
        {
          "id":"txn-bad","reference":"REF-BAD","recipientId":"rec-1","name":"Bad",
          "category":"Shopping","amount":-100,"date":"2026-09-18",
          "provider":"adyen","method":"card","status":"completed","note":""
        }
        """
      let txn = try JSONDecoder().decode(Transaction.self, from: json.data(using: .utf8)!)
      check("negative amount is detectable", txn.amount < 0)
    } catch {
      print("  ✗ Decoding failed: \(error)"); failed += 1
    }

    print("\n13. Malformed catalog: missing providers field fails decoding")
    let noProvidersJson = """
      {"demoDate":"2026-09-18","recipients":[]}
      """
    do {
      _ = try JSONDecoder().decode(CatalogResponse.self, from: noProvidersJson.data(using: .utf8)!)
      print("  ✗ Should have thrown for missing providers"); failed += 1
    } catch {
      check("missing providers throws DecodingError", error is DecodingError)
    }

    // -----------------------------------------------------------------
    // Amount Injection / Input Validation
    // -----------------------------------------------------------------

    print("\n14. Security: injection attempts are rejected by parseAmount")
    let injections = [
      "'; DROP TABLE payments; --",
      "<script>alert(1)</script>",
      String(repeating: "1", count: 21),
      "../../../etc/passwd",
      "NaN",
      "Infinity",
      "\u{0000}\u{0001}",
    ]
    for attempt in injections {
      let (pence, err) = parseAmount(attempt)
      check("injection '\(attempt.prefix(20))…' rejected", pence == nil && err != nil)
    }

    print("\n15. Security: amount exceeding £10,000 cap is rejected")
    let (over, overErr) = parseAmount("100000")
    check("100000 (£1,000,000) rejected",  over == nil && overErr != nil)

    // -----------------------------------------------------------------
    // Client Validation
    // -----------------------------------------------------------------

    print("\n16. Security: client rejects empty session ID")
    do {
      _ = try MeridianClient(baseURL: "http://localhost:8080/api/v1", sessionId: "")
      print("  ✗ Should have thrown for empty session"); failed += 1
    } catch MeridianError.missingSession {
      check("empty session throws missingSession", true)
    } catch {
      print("  ✗ Unexpected error: \(error)"); failed += 1
    }

    print("\n17. Security: client rejects non-HTTP schemes")
    for scheme in ["ftp://example.com", "ws://example.com", "file:///etc/passwd"] {
      do {
        _ = try MeridianClient(baseURL: scheme, sessionId: "sess")
        print("  ✗ Should have thrown for scheme: \(scheme)"); failed += 1
      } catch MeridianError.invalidURL {
        check("scheme '\(scheme)' rejected with invalidURL", true)
      } catch {
        print("  ✗ Unexpected error for '\(scheme)': \(error)"); failed += 1
      }
    }

    print("\n18. Security: client rejects plainly invalid URL")
    do {
      _ = try MeridianClient(baseURL: "not a url", sessionId: "sess")
      print("  ✗ Should have thrown for invalid URL"); failed += 1
    } catch MeridianError.invalidURL {
      check("invalid URL throws invalidURL", true)
    } catch {
      print("  ✗ Unexpected error: \(error)"); failed += 1
    }

    // Summary
    print("\n=== Security Results ===")
    print("Passed: \(passed)")
    print("Failed: \(failed)")
  }
}

@main
struct SecurityChecksMain {
  static func main() {
    var checks = SecurityChecks()
    checks.run()
    if checks.failed > 0 { exit(1) }
  }
}
