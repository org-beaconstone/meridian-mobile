import Foundation
@testable import MeridianSDK

@main
struct MeridianSDKChecks {
  static func main() async throws {
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

    // CHECK 21: bounded jittered backoff
    print("21. bounded jittered backoff...")
    let low = StatusBackoff.backoffMillis(attemptIndex: 0, randomUnit: 0)
    let high = StatusBackoff.backoffMillis(attemptIndex: 0, randomUnit: 1)
    let capped = StatusBackoff.backoffMillis(attemptIndex: 10, randomUnit: 1)
    if low == 250 && high == 500 && capped == StatusBackoff.maxMs && high > low {
      print("  ✓ backoff stays inside 250...4000ms")
      passed += 1
    } else {
      print("  ✗ unexpected backoff low=\(low) high=\(high) capped=\(capped)")
      failed += 1
    }

    // CHECK 22: decline stops polling and is not resubmitted on recovery
    print("22. decline stops polling...")
    let declinePoll = await pollResult(statuses: ["declined"])
    if declinePoll.result.phase == .declined && declinePoll.result.attempts == 1 && declinePoll.sleeps.isEmpty {
      print("  ✓ declined intent stops after one lookup")
      passed += 1
    } else {
      print("  ✗ decline poll phase=\(declinePoll.result.phase) attempts=\(declinePoll.result.attempts) sleeps=\(declinePoll.sleeps)")
      failed += 1
    }
    let declinedSnapshot = sampleSnapshot(phase: .declined, intentId: "pi-declined")
    if recoveryAction(for: declinedSnapshot) == .showDecline
      && recoveryFeedback(for: .declined).contains("will not be submitted again")
    {
      print("  ✓ stored decline does not resume a submission")
      passed += 1
    } else {
      print("  ✗ decline recovery action was wrong")
      failed += 1
    }

    // CHECK 23: processing, pending, and unknown keep polling until success
    print("23. polls processing, pending, and unknown...")
    let successPoll = await pollResult(statuses: ["processing", "pending", "mystery", "succeeded"])
    if successPoll.result.phase == .succeeded && successPoll.result.attempts == 4 && successPoll.sleeps.count == 3 && successPoll.sleeps.allSatisfy({ $0 <= StatusBackoff.maxMs }) {
      print("  ✓ non-terminal statuses poll with bounded backoff")
      passed += 1
    } else {
      print("  ✗ success poll phase=\(successPoll.result.phase) attempts=\(successPoll.result.attempts) sleeps=\(successPoll.sleeps)")
      failed += 1
    }
    if case .poll(let intentId) = recoveryAction(for: sampleSnapshot(phase: .processing, intentId: "pi-open")),
      intentId == "pi-open",
      recoveryAction(for: sampleSnapshot(phase: .pending, intentId: "pi-pending")) == .poll(intentId: "pi-pending"),
      recoveryAction(for: sampleSnapshot(phase: .unknown, intentId: nil)) == .holdUnknown
    {
      print("  ✓ restart resumes a status check and holds an unknown payment without an id")
      passed += 1
    } else {
      print("  ✗ recovery action mismatch")
      failed += 1
    }

    // CHECK 24: receipt fields
    print("24. success receipt...")
    let receipt = makeReceipt(
      snapshot: sampleSnapshot(phase: .succeeded, intentId: "pi-1"),
      intent: PaymentIntent(
        id: "pi-1",
        status: "succeeded",
        amountMinor: 2599,
        currency: "GBP",
        recipientName: "Northline Studio",
        supportReference: "SUP-140-7781",
        note: "Materials",
        provider: "adyen"
      )
    )
    if receipt.recipientName == "Northline Studio" && receipt.amountMinor == 2599 && receipt.supportReference == "SUP-140-7781" {
      print("  ✓ receipt has recipient, amount, and support reference")
      passed += 1
    } else {
      print("  ✗ receipt mismatch \(receipt)")
      failed += 1
    }

    // CHECK 25: v2 URL and snapshot file
    print("25. intent URL and stored snapshot...")
    let base = URL(string: "http://127.0.0.1:8080/api/v1")!
    let intentURL = try paymentIntentURL(baseURL: base, id: "pi_77")
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("meridian-snapshots-\(UUID().uuidString).json")
    let store = FileIntentSnapshotStore(fileURL: file)
    store.save(sampleSnapshot(phase: .pending, intentId: "pi-new", sessionId: "room-b", updatedAt: "2026-09-18T11:00:00Z"))
    store.save(sampleSnapshot(phase: .declined, intentId: "pi-old", sessionId: "room-a", updatedAt: "2026-09-18T10:00:00Z"))
    let restored = FileIntentSnapshotStore(fileURL: file).latestRecoverable()
    if intentURL.absoluteString == "http://127.0.0.1:8080/api/v2/payment-intents/pi_77"
      && restored?.intentId == "pi-new"
    {
      print("  ✓ v2 status URL and restart snapshot")
      passed += 1
    } else {
      print("  ✗ url=\(intentURL.absoluteString) restored=\(restored?.intentId ?? "nil")")
      failed += 1
    }

    let total = passed + failed
    print("\n=== Results ===")
    print("Passed: \(passed)/\(total)")
    print("Failed: \(failed)/\(total)")

    if failed > 0 {
      exit(1)
    }
  }
}

private func sampleSnapshot(
  phase: IntentPhase,
  intentId: String?,
  sessionId: String = "room-1",
  updatedAt: String = "2026-09-18T12:00:00Z"
) -> IntentSnapshot {
  IntentSnapshot(
    intentId: intentId,
    sessionId: sessionId,
    baseURL: "http://127.0.0.1:8080/api/v1",
    idempotencyKey: "11111111-1111-4111-8111-111111111111",
    recipientId: "northline-studio",
    recipientName: "Northline Studio",
    amountMinor: 1500,
    method: "card",
    note: "Materials",
    phase: phase,
    provider: "adyen",
    updatedAt: updatedAt
  )
}

private final class PollCapture: @unchecked Sendable {
  var remaining: [String]
  var sleeps: [UInt64] = []
  init(_ statuses: [String]) { remaining = statuses }
}

private func pollResult(statuses: [String]) async -> (result: StatusPollResult, sleeps: [UInt64]) {
  let capture = PollCapture(statuses)
  let poller = PaymentStatusPoller(
    getIntent: { _ in
      let status = capture.remaining.isEmpty ? "unknown" : capture.remaining.removeFirst()
      return PaymentIntent(
        id: "pi-1",
        status: status,
        amountMinor: 1500,
        currency: "GBP",
        recipientName: "Northline Studio"
      )
    },
    sleep: { delay in capture.sleeps.append(delay) },
    randomUnit: { 0 },
    maxElapsedMs: 60_000
  )
  let result = await poller.poll(intentId: "pi-1")
  return (result, capture.sleeps)
}
