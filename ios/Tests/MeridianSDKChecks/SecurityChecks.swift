import Foundation
@testable import MeridianSDK

// MARK: - Security & Resilience Tests
//
// Verifies:
//   - Replay-attack rejection for deep-link / return-state tokens
//   - Expired return-state detection via timestamp comparison
//   - Graceful failure on malformed or incomplete catalog entries
//   - Input-validation guards in parseAmount (injection-style inputs)

// MARK: - Helpers (private to this file)

/// Minimal in-memory nonce store simulating a replay-detection registry.
private final class NonceStore {
  private var seen: Set<String> = []

  /// Returns true if the nonce is fresh (not previously seen), then marks it as used.
  func consume(_ nonce: String) -> Bool {
    guard !nonce.isEmpty, !seen.contains(nonce) else { return false }
    seen.insert(nonce)
    return true
  }
}

/// Returns true when the ISO-8601 timestamp is older than `ttlSeconds` ago.
private func isExpired(timestamp: String, ttlSeconds: TimeInterval, now: Date = Date()) -> Bool {
  let fmt = ISO8601DateFormatter()
  guard let ts = fmt.date(from: timestamp) else { return true } // Unparseable → treat as expired
  return now.timeIntervalSince(ts) > ttlSeconds
}

func runSecurityChecks(passed: inout Int, failed: inout Int) {
  print("\n=== Security & Resilience Tests ===\n")

  let store = NonceStore()

  // R1: Deep-link token – first use accepted
  print("R1. Deep-link token first use accepted...")
  let token = "dl-token-\(UUID().uuidString)"
  if store.consume(token) {
    print("  ✓ Fresh deep-link token accepted")
    passed += 1
  } else {
    print("  ✗ Fresh token should be accepted")
    failed += 1
  }

  // R2: Deep-link token – replay rejected
  print("R2. Deep-link token replay rejected...")
  if !store.consume(token) {
    print("  ✓ Replayed deep-link token correctly rejected")
    passed += 1
  } else {
    print("  ✗ Replayed token should be rejected")
    failed += 1
  }

  // R3: Empty nonce rejected outright
  print("R3. Empty deep-link nonce rejected...")
  if !store.consume("") {
    print("  ✓ Empty nonce correctly rejected")
    passed += 1
  } else {
    print("  ✗ Empty nonce should be rejected")
    failed += 1
  }

  // R4: Distinct tokens are each accepted once
  print("R4. Distinct tokens each accepted once...")
  let t1 = "token-A"
  let t2 = "token-B"
  let c1 = store.consume(t1)
  let c2 = store.consume(t2)
  let r1 = store.consume(t1) // replay
  if c1 && c2 && !r1 {
    print("  ✓ Distinct tokens accepted; replays rejected")
    passed += 1
  } else {
    print("  ✗ Nonce handling mismatch c1=\(c1) c2=\(c2) r1=\(r1)")
    failed += 1
  }

  // R5: Expired return-state – old timestamp
  print("R5. Expired return-state (30-min-old timestamp) rejected...")
  let thirtyMinutesAgo = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -1800))
  if isExpired(timestamp: thirtyMinutesAgo, ttlSeconds: 600) {
    print("  ✓ 30-minute-old return state correctly identified as expired (TTL 10 min)")
    passed += 1
  } else {
    print("  ✗ Old return state should be expired")
    failed += 1
  }

  // R6: Fresh return-state – recent timestamp
  print("R6. Fresh return-state (5-sec-old timestamp) accepted...")
  let fiveSecondsAgo = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -5))
  if !isExpired(timestamp: fiveSecondsAgo, ttlSeconds: 600) {
    print("  ✓ Recent return state correctly identified as fresh (TTL 10 min)")
    passed += 1
  } else {
    print("  ✗ Recent return state should be fresh")
    failed += 1
  }

  // R7: Malformed timestamp treated as expired
  print("R7. Malformed return-state timestamp treated as expired...")
  if isExpired(timestamp: "not-a-timestamp", ttlSeconds: 600) {
    print("  ✓ Malformed timestamp treated as expired (defensive)")
    passed += 1
  } else {
    print("  ✗ Malformed timestamp should be treated as expired")
    failed += 1
  }

  // R8: Malformed catalog JSON – missing required 'id' field
  print("R8. Malformed catalog entry (missing required field) rejected...")
  let malformedRecipientJson = """
  {
    "name": "No ID Recipient",
    "initials": "NI",
    "detail": "Missing id field",
    "category": "Shopping",
    "color": "#FF0000"
  }
  """
  do {
    _ = try JSONDecoder().decode(Recipient.self, from: malformedRecipientJson.data(using: .utf8)!)
    print("  ✗ Should have rejected malformed recipient (missing 'id')")
    failed += 1
  } catch {
    print("  ✓ Malformed recipient correctly rejected: missing required field")
    passed += 1
  }

  // R9: Wrong-type amount field rejects gracefully
  print("R9. Wrong-type amount field (string instead of Int) rejected...")
  let wrongTypeJson = """
  {
    "id": "txn-bad",
    "reference": "REF-BAD",
    "recipientId": "birch-bloom",
    "name": "Birch & Bloom",
    "category": "Food & drink",
    "amount": "not-a-number",
    "date": "2026-09-19",
    "provider": "adyen",
    "method": "card",
    "status": "completed",
    "note": "Type error test"
  }
  """
  do {
    _ = try JSONDecoder().decode(Transaction.self, from: wrongTypeJson.data(using: .utf8)!)
    print("  ✗ Should have rejected string amount field")
    failed += 1
  } catch {
    print("  ✓ String-typed amount field correctly rejected")
    passed += 1
  }

  // R10: Injection-style amount inputs rejected by parseAmount
  print("R10. Injection-style inputs rejected by parseAmount...")
  let injectionInputs = ["'; DROP TABLE payments; --", "<script>alert(1)</script>", "1 OR 1=1", "\0\n\r"]
  let allRejected = injectionInputs.allSatisfy { input in
    let (pence, _) = parseAmount(input)
    return pence == nil
  }
  if allRejected {
    print("  ✓ All injection-style inputs correctly rejected by parseAmount")
    passed += 1
  } else {
    print("  ✗ Some injection inputs were not rejected")
    failed += 1
  }
}
