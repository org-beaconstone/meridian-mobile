import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MeridianSDK

final class HeaderCaptureURLProtocol: URLProtocol, @unchecked Sendable {
  struct Record {
    let path: String
    let query: String
    let method: String
    let traceparent: String?
    let tracestate: String?
    let session: String?
    let idempotency: String?
  }

  static let gate = NSLock()
  static var records: [Record] = []
  static var statusCode = 200
  static var bodyOverride: Data?

  static func reset(status: Int, body: Data?) {
    gate.lock()
    records = []
    statusCode = status
    bodyOverride = body
    gate.unlock()
  }

  static func snapshot() -> [Record] {
    gate.lock()
    defer { gate.unlock() }
    return records
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let url = request.url ?? URL(string: "http://127.0.0.1/")!
    let record = Record(
      path: url.path,
      query: url.query ?? "",
      method: request.httpMethod ?? "",
      traceparent: request.value(forHTTPHeaderField: "traceparent"),
      tracestate: request.value(forHTTPHeaderField: "tracestate"),
      session: request.value(forHTTPHeaderField: "X-Rehearsal-Session"),
      idempotency: request.value(forHTTPHeaderField: "Idempotency-Key")
    )
    Self.gate.lock()
    let status = Self.statusCode
    let override = Self.bodyOverride
    Self.records.append(record)
    Self.gate.unlock()
    let body = override ?? Self.payload(for: url.path)
    let response = HTTPURLResponse(
      url: url,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func payload(for path: String) -> Data {
    let json: String
    if path.hasSuffix("/catalog") {
      json = #"{"demoDate":"2026-09-18","recipients":[],"providers":[]}"#
    } else if path.hasSuffix("/fx/quote") {
      json = #"{"base":"GBP","quote":"GBP","amountMinor":2500,"quoteAmountMinor":2500}"#
    } else if path.hasSuffix("/session/health") {
      json = #"{"status":"UP","session":"test-session"}"#
    } else if path.hasSuffix("/health") {
      json = #"{"status":"UP","service":"meridian-api","simulation":true}"#
    } else if path.hasSuffix("/state") {
      json = #"{"version":1,"balance":1248050,"transactions":[],"budgets":[]}"#
    } else if path.hasSuffix("/payments") {
      json = #"{"ok":true}"#
    } else if path.hasSuffix("/events") {
      json = #"{"events":[]}"#
    } else if path.hasSuffix("/reset") {
      json = #"{"ok":true}"#
    } else {
      json = #"{"ok":true}"#
    }
    return Data(json.utf8)
  }
}

private final class MutableClock: @unchecked Sendable {
  var now: Int64
  init(_ now: Int64) { self.now = now }
}

func runTelemetryChecks() async -> (passed: Int, failed: Int) {
  var passed = 0
  var failed = 0
  func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition {
      print("  ✓ \(name)")
      passed += 1
    } else {
      print("  ✗ \(name) \(detail)")
      failed += 1
    }
  }

  print("21. Telemetry sanitizer strips PAN, cardholder details, and IBAN...")
  let dirty = "declined 4111-1111-1111-1111 iban GB29 NWBK 6016 1331 9268 19 cvv: 123 expiry: 12/29 cardholder: Ada Lovelace"
  let clean = TelemetrySanitizer.sanitize(dirty)
  check("PAN removed", !clean.contains("4111") && clean.contains("[REDACTED_PAN]"), clean)
  check("IBAN removed", !clean.contains("NWBK") && clean.contains("[REDACTED_IBAN]"), clean)
  check("cardholder removed", !clean.contains("Ada") && !clean.contains("12/29") && !clean.contains("cvv") && clean.contains("[REDACTED_CARDHOLDER]"), clean)
  let plain = "HTTP 422: Payment declined for Northline Studio"
  check("ordinary error kept", TelemetrySanitizer.sanitize(plain) == plain)
  check("non-Luhn digits kept", TelemetrySanitizer.sanitize("ref 4111111111111112") == "ref 4111111111111112")

  print("22. PagerDuty thresholds page only when the rates are exceeded...")
  let submissionClock = MutableClock(10_000)
  let submission = TelemetryCenter(vendor: "sdk-ios", language: "swift", now: { submissionClock.now })
  for _ in 0 ..< 99 { submission.recordSubmission(success: true) }
  submission.recordSubmission(success: false)
  let exactPercent = submission.evaluateAlerts()
  check("1.0% does not page", !exactPercent.shouldPage && exactPercent.reasons.isEmpty)
  submission.recordSubmission(success: false)
  let overPercent = submission.evaluateAlerts()
  check(
    "above 1.0% pages",
    overPercent.shouldPage && overPercent.reasons.contains { $0.contains("submission error rate") && $0.contains("1.0%") && $0.contains("5 minutes") },
    overPercent.reasons.joined(separator: " | ")
  )

  let sca = TelemetryCenter(vendor: "sdk-ios", language: "swift")
  for _ in 0 ..< 95 { sca.recordSca(dropped: false) }
  for _ in 0 ..< 5 { sca.recordSca(dropped: true) }
  check("5% SCA drop-off does not page", !sca.evaluateAlerts().shouldPage)
  sca.recordSca(dropped: true, detail: "card 4111111111111111")
  let scaPage = sca.evaluateAlerts()
  check(
    "SCA drop-off above 5% pages",
    scaPage.shouldPage && scaPage.reasons.contains { $0.contains("SCA drop-offs") && $0.contains("5%") }
  )
  let scaCrumb = sca.snapshot().breadcrumbs.joined(separator: "\n")
  check("SCA breadcrumb is sanitized", !scaCrumb.contains("4111111111111111") && scaCrumb.contains("[REDACTED_PAN]"), scaCrumb)

  let windowClock = MutableClock(0)
  let window = TelemetryCenter(vendor: "sdk-ios", language: "swift", now: { windowClock.now })
  for _ in 0 ..< 10 { window.recordSubmission(success: false) }
  check("fresh failures page", window.evaluateAlerts().shouldPage)
  windowClock.now = 5 * 60 * 1000
  check("failure still inside the 5 minute window", window.evaluateAlerts().shouldPage)
  windowClock.now = 5 * 60 * 1000 + 1
  window.recordSubmission(success: true)
  check("aged failures leave the window", !window.evaluateAlerts().shouldPage)

  let both = TelemetryCenter(vendor: "sdk-ios", language: "swift")
  for _ in 0 ..< 2 { both.recordSubmission(success: false) }
  for _ in 0 ..< 98 { both.recordSubmission(success: true) }
  for index in 0 ..< 100 { both.recordSca(dropped: index < 6) }
  let bothDecision = both.evaluateAlerts()
  check("both thresholds page together", bothDecision.shouldPage && bothDecision.reasons.count == 2, bothDecision.reasons.joined(separator: " | "))

  print("23. Payment p95 and biometric prompt SLOs...")
  let within = TelemetryCenter(vendor: "sdk-ios", language: "swift")
  check("empty SLO is within target", within.paymentSlo().withinSlo && within.biometricSlo().withinSlo)
  for _ in 0 ..< 95 { within.endSpan(within.startSpan(name: "payment.submit"), status: "ok", durationMs: 100) }
  for _ in 0 ..< 5 { within.endSpan(within.startSpan(name: "payment.submit"), status: "ok", durationMs: 5_000) }
  check("p95 of 100 stays under 1200 ms", within.paymentSlo().observedMs == 100 && within.paymentSlo().withinSlo)
  let breach = TelemetryCenter(vendor: "sdk-ios", language: "swift")
  for _ in 0 ..< 94 { breach.endSpan(breach.startSpan(name: "payment.submit"), status: "ok", durationMs: 100) }
  for _ in 0 ..< 6 { breach.endSpan(breach.startSpan(name: "payment.submit"), status: "ok", durationMs: 5_000) }
  check("p95 over 1200 ms breaches", !breach.paymentSlo().withinSlo && breach.paymentSlo().observedMs == 5_000)
  let edge = TelemetryCenter(vendor: "sdk-ios", language: "swift")
  edge.endSpan(edge.startSpan(name: "payment.submit"), status: "ok", durationMs: 1_200)
  check("p95 of 1200 ms is outside the SLO", !edge.paymentSlo().withinSlo)
  let under = TelemetryCenter(vendor: "sdk-ios", language: "swift")
  under.endSpan(under.startSpan(name: "payment.submit"), status: "ok", durationMs: 1_199)
  check("p95 of 1199 ms is inside the SLO", under.paymentSlo().withinSlo)
  let biometric = TelemetryCenter(vendor: "sdk-ios", language: "swift")
  let fastPrompt = biometric.recordBiometricPrompt(durationMs: 299)
  check("299 ms biometric prompt is inside the SLO", fastPrompt.withinSlo && biometric.biometricSlo().withinSlo)
  let slowPrompt = biometric.recordBiometricPrompt(durationMs: 300)
  let slowSpan = biometric.snapshot().spans.last { $0.name == "biometric.prompt" }
  check(
    "300 ms biometric prompt breaches",
    !slowPrompt.withinSlo && !biometric.biometricSlo().withinSlo && slowSpan?.attributes["slo.breach"] == "true"
  )

  print("24. Upstream traceparent continues the gateway trace...")
  let continued = TelemetryCenter(
    upstreamTraceparent: "00-0AF7651916CD43DD8448EB211C80319C-B7AD6B7169203331-01",
    upstreamTracestate: "gateway=1",
    vendor: "sdk-ios",
    language: "swift"
  )
  let session = continued.snapshot().spans.first { $0.name == "meridian.session" }
  check(
    "session keeps the gateway trace id",
    continued.traceId == "0af7651916cd43dd8448eb211c80319c" && session?.parentSpanId == "b7ad6b7169203331"
  )
  let child = continued.startHttpSpan(method: "GET", path: "/catalog")
  check(
    "child span shares the trace and parents to the session",
    child.traceId == continued.traceId && child.parentSpanId == continued.sessionSpanId && child.traceparent.hasSuffix("-01")
  )
  check(
    "tracestate keeps the gateway entry",
    child.tracestate?.contains("meridian=sdk-ios") == true && child.tracestate?.contains("gateway=1") == true,
    child.tracestate ?? ""
  )
  let unsampled = TelemetryCenter(
    upstreamTraceparent: "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-00",
    vendor: "sdk-ios",
    language: "swift"
  )
  let quiet = unsampled.startSpan(name: "HTTP GET /health")
  check("unsampled flag is propagated", quiet.traceparent.hasSuffix("-00") && quiet.traceId == "0af7651916cd43dd8448eb211c80319c")
  let fresh = TelemetryCenter(upstreamTraceparent: "not-a-trace", vendor: "sdk-ios", language: "swift")
  let freshSession = fresh.snapshot().spans.first { $0.name == "meridian.session" }
  let tracePattern = #"^00-[0-9a-f]{32}-[0-9a-f]{16}-01$"#
  check(
    "invalid traceparent starts a new sampled trace",
    freshSession?.parentSpanId == nil && (freshSession?.traceparent.range(of: tracePattern, options: .regularExpression) != nil)
  )

  print("25. Outbound requests carry one traceparent across the payment routes...")
  HeaderCaptureURLProtocol.reset(status: 200, body: nil)
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [HeaderCaptureURLProtocol.self]
  config.timeoutIntervalForRequest = 5
  config.timeoutIntervalForResource = 5
  let urlSession = URLSession(configuration: config)
  let upstream = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
  do {
    let client = try MeridianClient(
      baseURL: "http://127.0.0.1:8080/api/v1",
      sessionId: "test-session",
      urlSession: urlSession,
      upstreamTraceparent: upstream,
      upstreamTracestate: "gateway=1"
    )
    _ = try await client.getHealth()
    _ = try await client.getCatalog()
    let quote = try await client.getFxQuote(amountMinor: 2500)
    _ = try await client.getSessionHealth()
    _ = try await client.getState()
    _ = try await client.submitPayment(recipientId: "northline-studio", amountMinor: 2500, method: .card, idempotencyKey: "pay-key-1")
    _ = try await client.submitPayment(recipientId: "northline-studio", amountMinor: 2500, method: .card, idempotencyKey: "pay-key-1")
    _ = try await client.getEvents()
    _ = try await client.reset()
    let prompt = await client.measureBiometricPrompt()
    await client.recordSca(dropped: false)
    check("fx quote stays in GBP pence", quote.base == "GBP" && quote.quote == "GBP" && quote.amountMinor == 2500)
    check("measured biometric prompt is inside the SLO", prompt.withinSlo)

    let records = HeaderCaptureURLProtocol.snapshot()
    let required = ["/catalog", "/fx/quote", "/payments", "/session/health"]
    check("captured the rehearsal routes", records.count == 9, "count \(records.count)")
    let headerOk = records.allSatisfy { record in
      record.session == "test-session" &&
        record.traceparent?.range(of: #"^00-0af7651916cd43dd8448eb211c80319c-[0-9a-f]{16}-01$"#, options: .regularExpression) != nil &&
        record.tracestate?.contains("meridian=sdk-ios") == true &&
        record.tracestate?.contains("gateway=1") == true
    }
    check("every request keeps the gateway traceparent", headerOk, records.map { "\($0.method) \($0.path) \($0.traceparent ?? "nil")" }.joined(separator: " | "))
    let spanIds = Set(records.compactMap { $0.traceparent?.split(separator: "-")[2] })
    check("each request has its own span id", spanIds.count == records.count)
    for suffix in required {
      check("traceparent on \(suffix)", records.contains { $0.path.hasSuffix(suffix) })
    }
    let payments = records.filter { $0.path.hasSuffix("/payments") }
    check(
      "retries keep the idempotency key",
      payments.count == 2 && payments.allSatisfy { $0.idempotency == "pay-key-1" && $0.method == "POST" }
    )
    let quoteCall = records.first { $0.path.hasSuffix("/fx/quote") }
    check(
      "fx quote query is GBP pence",
      quoteCall?.query.contains("base=GBP") == true && quoteCall?.query.contains("quote=GBP") == true && quoteCall?.query.contains("amountMinor=2500") == true,
      quoteCall?.query ?? ""
    )
    let otherIdempotency = records.filter { !$0.path.hasSuffix("/payments") }.allSatisfy { $0.idempotency == nil }
    check("idempotency stays on payments", otherIdempotency)

    let snap = await client.telemetrySnapshot()
    let sessionSpan = snap.spans.first { $0.name == "meridian.session" }
    let paymentSpans = snap.spans.filter { $0.name == "payment.submit" }
    let paymentHttp = snap.spans.filter { $0.name == "HTTP POST /payments" }
    check("session parents to the gateway span", sessionSpan?.parentSpanId == "b7ad6b7169203331" && sessionSpan?.traceId == snap.traceId)
    check("payment spans parent to the session", paymentSpans.count == 2 && paymentSpans.allSatisfy { $0.parentSpanId == sessionSpan?.spanId && $0.traceId == snap.traceId })
    check(
      "payment HTTP spans parent to payment.submit",
      paymentHttp.count == 2 && zip(paymentHttp, paymentSpans).allSatisfy { http, payment in
        http.parentSpanId == payment.spanId && http.traceId == payment.traceId && http.attributes["url.path"] == "/payments"
      }
    )
    let quoteSpan = snap.spans.first { $0.name == "HTTP GET /fx/quote" }
    check("fx span records the route", quoteSpan?.attributes["url.path"] == "/fx/quote" && quoteSpan?.parentSpanId == sessionSpan?.spanId)
    let headerSpanIds = Set(paymentHttp.map(\.spanId))
    let wireSpanIds = Set(payments.compactMap { record -> String? in
      guard let header = record.traceparent else { return nil }
      let parts = header.split(separator: "-")
      return parts.count == 4 ? String(parts[2]) : nil
    })
    check("wire traceparent span id is the HTTP span", headerSpanIds == wireSpanIds)
    check("successful rehearsal does not page", !snap.alerts.shouldPage && snap.paymentSlo.withinSlo && snap.biometricSlo.withinSlo)
  } catch {
    check("trace header rehearsal", false, String(describing: error))
  }

  print("26. Error logs and breadcrumbs are sanitized...")
  HeaderCaptureURLProtocol.reset(
    status: 500,
    body: Data("PAN 4111111111111111 IBAN GB29NWBK60161331926819 cardholder: Ada Lovelace".utf8)
  )
  let errorConfig = URLSessionConfiguration.ephemeral
  errorConfig.protocolClasses = [HeaderCaptureURLProtocol.self]
  let errorSession = URLSession(configuration: errorConfig)
  do {
    let client = try MeridianClient(
      baseURL: "http://127.0.0.1:9/api/v1",
      sessionId: "test-session",
      urlSession: errorSession
    )
    await client.addBreadcrumb("card 4111 1111 1111 1111")
    var thrown = ""
    do {
      _ = try await client.getCatalog()
      check("catalog failure is reported", false)
    } catch {
      thrown += (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
    do {
      _ = try await client.submitPayment(recipientId: "northline-studio", amountMinor: 100, method: .bank, idempotencyKey: "pay-key-err")
      check("payment failure is reported", false)
    } catch {
      thrown += (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
    let snap = await client.telemetrySnapshot()
    let leaked = (thrown + snap.errorLogs.joined() + snap.breadcrumbs.joined())
    check("thrown errors hide the PAN", !thrown.contains("4111111111111111") && !thrown.contains("4111 1111 1111 1111"), thrown)
    check("telemetry hides PAN, IBAN, and cardholder", !leaked.contains("4111111111111111") && !leaked.contains("GB29NWBK") && !leaked.contains("Ada Lovelace"), leaked)
    check("redaction tokens are present", leaked.contains("[REDACTED_PAN]") && leaked.contains("[REDACTED_IBAN]") && leaked.contains("[REDACTED_CARDHOLDER]"), leaked)
    check("failed submission pages above 1.0%", snap.alerts.shouldPage && snap.alerts.reasons.contains { $0.contains("submission error rate") })
    let wire = HeaderCaptureURLProtocol.snapshot()
    check("failed calls still send traceparent", wire.count == 2 && wire.allSatisfy { $0.traceparent?.range(of: tracePattern, options: .regularExpression) != nil })
  } catch {
    check("sanitized error rehearsal", false, String(describing: error))
  }

  return (passed, failed)
}
