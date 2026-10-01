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

    // MARK: - Telemetry checks

    // CHECK 21: hashIdempotencyKey produces 64-char hex
    print("21. hashIdempotencyKey produces 64-char hex...")
    let hash21 = hashIdempotencyKey("some-key")
    if hash21.count == 64 && hash21.allSatisfy({ $0.isHexDigit }) {
      print("  ✓ hashIdempotencyKey: 64-char hex string")
      passed += 1
    } else {
      print("  ✗ Expected 64 hex chars, got \(hash21.count) chars: \(hash21)")
      failed += 1
    }

    // CHECK 22: hashIdempotencyKey is deterministic
    print("22. hashIdempotencyKey is deterministic...")
    let h22a = hashIdempotencyKey("deterministic-key")
    let h22b = hashIdempotencyKey("deterministic-key")
    if h22a == h22b {
      print("  ✓ hashIdempotencyKey: same input → same hash")
      passed += 1
    } else {
      print("  ✗ Hash is not deterministic")
      failed += 1
    }

    // CHECK 23: hashIdempotencyKey is unique for different inputs
    print("23. hashIdempotencyKey unique for different inputs...")
    let h23a = hashIdempotencyKey("key-alpha")
    let h23b = hashIdempotencyKey("key-beta")
    if h23a != h23b {
      print("  ✓ hashIdempotencyKey: different inputs → different hashes")
      passed += 1
    } else {
      print("  ✗ Different keys produced the same hash")
      failed += 1
    }

    // CHECK 24: hashIdempotencyKey known SHA-256 value
    print("24. hashIdempotencyKey known SHA-256 value...")
    let expected24 = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
    let actual24 = hashIdempotencyKey("test")
    if actual24 == expected24 {
      print("  ✓ SHA-256(\"test\") matches known value")
      passed += 1
    } else {
      print("  ✗ Expected \(expected24), got \(actual24)")
      failed += 1
    }

    // CHECK 25: sanitizeForLog strips query parameters
    print("25. sanitizeForLog strips URL query parameters...")
    let input25 = "https://provider.example.com/callback?token=abc123&session=xyz"
    let result25 = sanitizeForLog(input25)
    if result25.contains("?[REDACTED]") && !result25.contains("abc123") {
      print("  ✓ sanitizeForLog: query params redacted")
      passed += 1
    } else {
      print("  ✗ Query params not redacted: \(result25)")
      failed += 1
    }

    // CHECK 26: sanitizeForLog redacts bearer token
    print("26. sanitizeForLog redacts bearer token...")
    let input26 = "Authorization: bearer eyJhbGciOiJSUzI1NiJ9.payload.sig"
    let result26 = sanitizeForLog(input26)
    if result26.contains("[REDACTED]") && !result26.contains("eyJhbGciOiJSUzI1NiJ9") {
      print("  ✓ sanitizeForLog: bearer token redacted")
      passed += 1
    } else {
      print("  ✗ Bearer token not redacted: \(result26)")
      failed += 1
    }

    // CHECK 27: sanitizeForLog leaves plain text unchanged
    print("27. sanitizeForLog leaves plain text unchanged...")
    let input27 = "payment completed for recipient northline-studio"
    let result27 = sanitizeForLog(input27)
    if result27 == input27 {
      print("  ✓ sanitizeForLog: plain text unchanged")
      passed += 1
    } else {
      print("  ✗ Plain text was modified: \(result27)")
      failed += 1
    }

    // CHECK 28: TraceContext.generate() produces 32-char traceId
    print("28. TraceContext.generate() produces 32-char traceId...")
    let ctx28 = TraceContext.generate()
    if ctx28.traceId.count == 32 && ctx28.traceId.allSatisfy({ $0.isHexDigit }) {
      print("  ✓ TraceContext.traceId: 32-char hex")
      passed += 1
    } else {
      print("  ✗ traceId length=\(ctx28.traceId.count): \(ctx28.traceId)")
      failed += 1
    }

    // CHECK 29: TraceContext.generate() produces 16-char spanId
    print("29. TraceContext.generate() produces 16-char spanId...")
    let ctx29 = TraceContext.generate()
    if ctx29.spanId.count == 16 && ctx29.spanId.allSatisfy({ $0.isHexDigit }) {
      print("  ✓ TraceContext.spanId: 16-char hex")
      passed += 1
    } else {
      print("  ✗ spanId length=\(ctx29.spanId.count): \(ctx29.spanId)")
      failed += 1
    }

    // CHECK 30: traceparent format is "00-{32hex}-{16hex}-01"
    print("30. TraceContext.traceparent format...")
    let ctx30 = TraceContext.generate()
    let parts30 = ctx30.traceparent.split(separator: "-", maxSplits: 3).map(String.init)
    if parts30.count == 4 && parts30[0] == "00" && parts30[1].count == 32
        && parts30[2].count == 16 && parts30[3] == "01" {
      print("  ✓ traceparent: 00-{32hex}-{16hex}-01")
      passed += 1
    } else {
      print("  ✗ traceparent malformed: \(ctx30.traceparent)")
      failed += 1
    }

    // CHECK 31: TraceContext.generate() produces unique IDs
    print("31. TraceContext.generate() produces unique IDs...")
    let ctx31a = TraceContext.generate()
    let ctx31b = TraceContext.generate()
    if ctx31a.traceId != ctx31b.traceId && ctx31a.spanId != ctx31b.spanId {
      print("  ✓ TraceContext: unique traceId and spanId per generate()")
      passed += 1
    } else {
      print("  ✗ TraceContext generated duplicate IDs")
      failed += 1
    }

    // CHECK 32: TelemetryConfig default sampling rate
    print("32. TelemetryConfig default sampling rate...")
    let cfg32 = TelemetryConfig()
    if cfg32.failedJourneySampleRate == 1.0 {
      print("  ✓ TelemetryConfig: default failedJourneySampleRate = 1.0")
      passed += 1
    } else {
      print("  ✗ Expected 1.0, got \(cfg32.failedJourneySampleRate)")
      failed += 1
    }

    // CHECK 33: TelemetryConfig with custom rate
    print("33. TelemetryConfig with custom rate 0.5...")
    let cfg33 = TelemetryConfig(failedJourneySampleRate: 0.5)
    if cfg33.failedJourneySampleRate == 0.5 {
      print("  ✓ TelemetryConfig: custom rate 0.5 accepted")
      passed += 1
    } else {
      print("  ✗ Expected 0.5, got \(cfg33.failedJourneySampleRate)")
      failed += 1
    }

    // CHECK 34: AuditLogEntry.toLogLine() contains required fields and no raw key
    print("34. AuditLogEntry.toLogLine() format and sanitization...")
    let rawKey34 = "raw-idempotency-secret-key-7890"
    let entry34 = AuditLogEntry(
      traceId: "abcdef1234567890abcdef1234567890",
      timestamp: "2026-09-18T12:00:00Z",
      event: "payment.completed",
      outcome: "success",
      hashedIdempotencyKey: hashIdempotencyKey(rawKey34),
      catalogAgeDays: 7,
      methodCount: 2,
      scaInvoked: false,
      latencyMs: 120,
      amountMinor: 2500,
      paymentMethod: "card"
    )
    let line34 = entry34.toLogLine()
    let ok34 = line34.contains("trace=abcdef1234567890abcdef1234567890")
      && line34.contains("event=payment.completed")
      && line34.contains("outcome=success")
      && line34.contains("idem_hash=")
      && line34.contains("catalog_age_days=7")
      && line34.contains("method_count=2")
      && line34.contains("sca=false")
      && line34.contains("latency_ms=120")
      && line34.contains("amount_pence=2500")
      && line34.contains("method=card")
      && !line34.contains(rawKey34)
    if ok34 {
      print("  ✓ AuditLogEntry.toLogLine(): fields present, raw key absent")
      passed += 1
    } else {
      print("  ✗ Log line incorrect: \(line34)")
      failed += 1
    }

    // CHECK 35: AuditLogEntry.toLogLine() omits nil fields
    print("35. AuditLogEntry.toLogLine() omits nil fields...")
    let entry35 = AuditLogEntry(
      traceId: "abc",
      timestamp: "2026-09-18T12:00:00Z",
      event: "payment.completed"
    )
    let line35 = entry35.toLogLine()
    let ok35 = !line35.contains("outcome=")
      && !line35.contains("idem_hash=")
      && !line35.contains("latency_ms=")
      && line35.contains("trace=abc")
      && line35.contains("event=payment.completed")
    if ok35 {
      print("  ✓ AuditLogEntry.toLogLine(): nil fields omitted")
      passed += 1
    } else {
      print("  ✗ Nil fields included or required fields missing: \(line35)")
      failed += 1
    }

    // CHECK 36: TelemetryConfig callback is invoked
    print("36. TelemetryConfig callback is invoked...")
    var callbackInvoked = false
    let cfg36 = TelemetryConfig(
      failedJourneySampleRate: 1.0,
      onEntry: { _ in callbackInvoked = true }
    )
    let entry36 = AuditLogEntry(
      traceId: "abc", timestamp: "2026-09-18T12:00:00Z", event: "payment.completed"
    )
    cfg36.onEntry(entry36)
    if callbackInvoked {
      print("  ✓ TelemetryConfig: onEntry callback invoked")
      passed += 1
    } else {
      print("  ✗ TelemetryConfig: onEntry callback was not invoked")
      failed += 1
    }

    // Summary
    print("\n=== Results ===")
    print("Passed: \(passed)/36")
    print("Failed: \(failed)/36")

    if failed > 0 {
      exit(1)
    }
  }
}
