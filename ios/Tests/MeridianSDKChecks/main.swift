import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MeridianSDK

final class FxQuoteURLProtocol: URLProtocol {
  static var handler: ((URLRequest) -> (Int, Data))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    let (status, data) = handler(request)
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

private func runFxQuoteHttpCheck() -> Bool {
  final class Box: @unchecked Sendable {
    var quoteBody: [String: Any] = [:]
    var paymentBody: [String: Any] = [:]
    var quoteSession = ""
    var paymentQuoteId = ""
    var paymentKey = ""
  }
  let box = Box()
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [FxQuoteURLProtocol.self]
  let session = URLSession(configuration: config)
  FxQuoteURLProtocol.handler = { request in
    let path = request.url?.path ?? ""
    let rawBody: Data = {
      if let body = request.httpBody { return body }
      guard let stream = request.httpBodyStream else { return Data() }
      stream.open()
      defer { stream.close() }
      var data = Data()
      let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
      defer { buffer.deallocate() }
      while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: 1024)
        if count <= 0 { break }
        data.append(buffer, count: count)
      }
      return data
    }()
    let body = (try? JSONSerialization.jsonObject(with: rawBody) as? [String: Any]) ?? [:]
    if path.hasSuffix("/fx/quote") {
      box.quoteBody = body
      box.quoteSession = request.value(forHTTPHeaderField: "X-Rehearsal-Session") ?? ""
      let payload = #"{"quoteId":"quote-1","rate":"1.17","sourceCurrency":"GBP","targetCurrency":"EUR","sourceAmountMinor":1250,"targetAmountMinor":1463,"expiresInSeconds":60}"#
      return (200, Data(payload.utf8))
    }
    box.paymentBody = body
    box.paymentQuoteId = body["quoteId"] as? String ?? ""
    box.paymentKey = request.value(forHTTPHeaderField: "Idempotency-Key") ?? ""
    return (200, Data(#"{"ok":true}"#.utf8))
  }
  let semaphore = DispatchSemaphore(value: 0)
  var succeeded = false
  Task {
    do {
      let client = try MeridianClient(baseURL: "http://127.0.0.1:9/api/v1", sessionId: "fx-room", urlSession: session)
      let quote = try await client.requestFxQuote(sourceCurrency: "GBP", targetCurrency: "EUR", amountMinor: 1250)
      let paid = try await client.submitPayment(
        recipientId: "northline-studio",
        amountMinor: 1250,
        method: .card,
        note: "Invoice",
        idempotencyKey: "key-kept",
        quoteId: quote.quoteId
      )
      succeeded = paid.ok
        && box.quoteSession == "fx-room"
        && box.quoteBody["sourceCurrency"] as? String == "GBP"
        && box.quoteBody["targetCurrency"] as? String == "EUR"
        && box.quoteBody["amountMinor"] as? Int == 1250
        && box.paymentQuoteId == "quote-1"
        && box.paymentKey == "key-kept"
        && box.paymentBody["method"] as? String == "card"
    } catch {
      succeeded = false
    }
    semaphore.signal()
  }
  semaphore.wait()
  return succeeded
}

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

    // CHECK 21: FX quote decodes a numeric rate and id alias
    print("21. FX quote decoding...")
    let quoteJson = """
    {"id":"q-9","rate":1.1714,"amountMinor":500,"targetAmountMinor":586,"expiresInSeconds":60,"expiresAt":"2026-10-04T09:00:15Z","sourceCurrency":"GBP","targetCurrency":"EUR"}
    """
    do {
      let decoded = try JSONDecoder().decode(FxQuote.self, from: Data(quoteJson.utf8))
      let lockedAt = ISO8601DateFormatter().date(from: "2026-10-04T09:00:00Z")!
      let locked = lockQuote(decoded, sourceCurrency: "GBP", targetCurrency: "EUR", amountMinor: 500, lockedAt: lockedAt)
      let full = lockQuote(
        FxQuote(quoteId: "q-full", rate: "1.17", expiresInSeconds: 120),
        sourceCurrency: "GBP",
        targetCurrency: "EUR",
        amountMinor: 500,
        lockedAt: lockedAt
      )
      if decoded.quoteId == "q-9" && decoded.rate == "1.1714"
        && locked.expiresAt.timeIntervalSince(lockedAt) == 15
        && full.remainingSeconds(at: lockedAt) == 60
        && full.isExpired(at: lockedAt.addingTimeInterval(60))
        && full.remainingSeconds(at: lockedAt.addingTimeInterval(59.1)) == 1
      {
        print("  ✓ FX quote locks for at most 60s and honours a sooner server expiry")
        passed += 1
      } else {
        print("  ✗ FX quote lock mismatch")
        failed += 1
      }
    } catch {
      print("  ✗ FX quote decoding failed: \(error)")
      failed += 1
    }

    // CHECK 22: stale quote blocks submission; GBP does not need one
    print("22. Rate lock submission guard...")
    let now = ISO8601DateFormatter().date(from: "2026-10-04T09:00:00Z")!
    let active = lockQuote(
      FxQuote(quoteId: "quote-1", sourceCurrency: "GBP", targetCurrency: "EUR", sourceAmountMinor: 1250, rate: "1.17"),
      sourceCurrency: "GBP",
      targetCurrency: "EUR",
      amountMinor: 1250,
      lockedAt: now
    )
    let missing = rateLockBlockReason(sourceCurrency: "GBP", targetCurrency: "EUR", amountMinor: 1250, quote: nil, now: now)
    let expired = rateLockBlockReason(sourceCurrency: "GBP", targetCurrency: "EUR", amountMinor: 1250, quote: active, now: now.addingTimeInterval(60))
    let gbp = rateLockBlockReason(sourceCurrency: "GBP", targetCurrency: "GBP", amountMinor: 1250, quote: nil, now: now)
    if missing == FxCopy.unavailable && expired == FxCopy.expired && gbp == nil {
      print("  ✓ Missing and expired locks block cross-currency confirmation")
      passed += 1
    } else {
      print("  ✗ Submission guard mismatch")
      failed += 1
    }

    // CHECK 23: payment JSON attaches quoteId only when present
    print("23. Payment payload quoteId...")
    let withQuote = PaymentRequest(recipientId: "northline-studio", amountMinor: 1250, method: .card, note: "Invoice", scenario: .success, quoteId: "quote-1")
    let withoutQuote = PaymentRequest(recipientId: "northline-studio", amountMinor: 1250, method: .bank, note: "Invoice", scenario: .success)
    let withObject = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(withQuote)) as? [String: Any]
    let withoutObject = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(withoutQuote)) as? [String: Any]
    if withObject?["quoteId"] as? String == "quote-1" && withoutObject?["quoteId"] == nil {
      print("  ✓ quoteId is attached only for a locked cross-currency payment")
      passed += 1
    } else {
      print("  ✗ Payment payload quoteId mismatch")
      failed += 1
    }

    // CHECK 24: POST /fx/quote sends source and target currencies on the shared session
    print("24. FX quote HTTP request...")
    let httpOk = runFxQuoteHttpCheck()
    if httpOk {
      print("  ✓ POST /fx/quote carries currencies, amount and session, and payment keeps quoteId")
      passed += 1
    } else {
      print("  ✗ FX quote HTTP request mismatch")
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
