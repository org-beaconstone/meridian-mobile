package com.atlassian.meridian

import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetSocketAddress
import java.nio.charset.StandardCharsets
import java.util.concurrent.CopyOnWriteArrayList

class TelemetryTest {
  private val traceparent = Regex("^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$")

  @Test
  fun testSanitizerStripsPanCardholderAndIban() {
    val dirty = "declined 4111-1111-1111-1111 iban GB29 NWBK 6016 1331 9268 19 cvv: 123 expiry: 12/29 cardholder: Ada Lovelace"
    val clean = TelemetrySanitizer.sanitize(dirty)
    assertFalse(clean.contains("4111"))
    assertFalse(clean.contains("NWBK"))
    assertFalse(clean.contains("Ada"))
    assertFalse(clean.contains("12/29"))
    assertFalse(clean.contains("cvv"))
    assertTrue(clean.contains("[REDACTED_PAN]"))
    assertTrue(clean.contains("[REDACTED_IBAN]"))
    assertTrue(clean.contains("[REDACTED_CARDHOLDER]"))

    val plain = "HTTP 422: Payment declined for Northline Studio"
    assertEquals(plain, TelemetrySanitizer.sanitize(plain))
    assertEquals("ref 4111111111111112", TelemetrySanitizer.sanitize("ref 4111111111111112"))
  }

  @Test
  fun testPagerDutySubmissionErrorRate() {
    val clock = MutableClock(10_000)
    val telemetry = TelemetryCenter(vendor = "sdk-android", language = "kotlin", now = clock::read)
    repeat(99) { telemetry.recordSubmission(true) }
    telemetry.recordSubmission(false)
    val exact = telemetry.evaluateAlerts()
    assertFalse(exact.shouldPage)
    assertTrue(exact.reasons.isEmpty())

    telemetry.recordSubmission(false)
    val over = telemetry.evaluateAlerts()
    assertTrue(over.shouldPage)
    assertTrue(over.reasons.any { it.contains("submission error rate") && it.contains("1.0%") && it.contains("5 minutes") })
  }

  @Test
  fun testPagerDutyScaDropOff() {
    val telemetry = TelemetryCenter(vendor = "sdk-android", language = "kotlin")
    repeat(95) { telemetry.recordSca(dropped = false) }
    repeat(5) { telemetry.recordSca(dropped = true) }
    assertFalse(telemetry.evaluateAlerts().shouldPage)

    telemetry.recordSca(dropped = true, detail = "card 4111111111111111")
    val decision = telemetry.evaluateAlerts()
    assertTrue(decision.shouldPage)
    assertTrue(decision.reasons.any { it.contains("SCA drop-offs") && it.contains("5%") })
    val crumbs = telemetry.snapshot().breadcrumbs.joinToString("\n")
    assertFalse(crumbs.contains("4111111111111111"))
    assertTrue(crumbs.contains("[REDACTED_PAN]"))
  }

  @Test
  fun testPagerDutyWindowExpires() {
    val clock = MutableClock(0)
    val telemetry = TelemetryCenter(vendor = "sdk-android", language = "kotlin", now = clock::read)
    repeat(10) { telemetry.recordSubmission(false) }
    assertTrue(telemetry.evaluateAlerts().shouldPage)
    clock.now = 5 * 60 * 1000
    assertTrue(telemetry.evaluateAlerts().shouldPage)
    clock.now = 5 * 60 * 1000 + 1
    telemetry.recordSubmission(true)
    val aged = telemetry.evaluateAlerts()
    assertFalse(aged.shouldPage)
    assertNull(aged.submissionErrorRate?.let { if (it == 0.0) null else it })
  }

  @Test
  fun testPagerDutyBothThresholds() {
    val telemetry = TelemetryCenter(vendor = "sdk-android", language = "kotlin")
    repeat(2) { telemetry.recordSubmission(false) }
    repeat(98) { telemetry.recordSubmission(true) }
    repeat(100) { index -> telemetry.recordSca(dropped = index < 6) }
    val decision = telemetry.evaluateAlerts()
    assertTrue(decision.shouldPage)
    assertEquals(2, decision.reasons.size)
  }

  @Test
  fun testPaymentSubmissionP95Slo() {
    val empty = TelemetryCenter(vendor = "sdk-android", language = "kotlin")
    assertTrue(empty.paymentSlo().withinSlo)
    assertTrue(empty.biometricSlo().withinSlo)

    val within = TelemetryCenter(vendor = "sdk-android", language = "kotlin")
    repeat(95) { within.endSpan(within.startSpan("payment.submit"), "ok", 100) }
    repeat(5) { within.endSpan(within.startSpan("payment.submit"), "ok", 5_000) }
    assertEquals(100L, within.paymentSlo().observedMs)
    assertTrue(within.paymentSlo().withinSlo)

    val breach = TelemetryCenter(vendor = "sdk-android", language = "kotlin")
    repeat(94) { breach.endSpan(breach.startSpan("payment.submit"), "ok", 100) }
    repeat(6) { breach.endSpan(breach.startSpan("payment.submit"), "ok", 5_000) }
    assertEquals(5_000L, breach.paymentSlo().observedMs)
    assertFalse(breach.paymentSlo().withinSlo)

    val edge = TelemetryCenter(vendor = "sdk-android", language = "kotlin")
    edge.endSpan(edge.startSpan("payment.submit"), "ok", 1_200)
    assertFalse(edge.paymentSlo().withinSlo)

    val under = TelemetryCenter(vendor = "sdk-android", language = "kotlin")
    under.endSpan(under.startSpan("payment.submit"), "ok", 1_199)
    assertTrue(under.paymentSlo().withinSlo)
  }

  @Test
  fun testBiometricPromptSlo() {
    val telemetry = TelemetryCenter(vendor = "sdk-android", language = "kotlin")
    val fast = telemetry.recordBiometricPrompt(299)
    assertTrue(fast.withinSlo)
    assertTrue(telemetry.biometricSlo().withinSlo)
    val slow = telemetry.recordBiometricPrompt(300)
    assertFalse(slow.withinSlo)
    assertFalse(telemetry.biometricSlo().withinSlo)
    val span = telemetry.snapshot().spans.last { it.name == "biometric.prompt" }
    assertEquals("true", span.attributes["slo.breach"])
    assertEquals("300", span.attributes["slo.threshold_ms"])
  }

  @Test
  fun testUpstreamTraceCorrelation() {
    val telemetry = TelemetryCenter(
      upstreamTraceparent = "00-0AF7651916CD43DD8448EB211C80319C-B7AD6B7169203331-01",
      upstreamTracestate = "gateway=1",
      vendor = "sdk-android",
      language = "kotlin",
    )
    val session = telemetry.snapshot().spans.first { it.name == "meridian.session" }
    assertEquals("0af7651916cd43dd8448eb211c80319c", telemetry.traceId)
    assertEquals("b7ad6b7169203331", session.parentSpanId)
    val child = telemetry.startHttpSpan("GET", "/catalog")
    assertEquals(telemetry.traceId, child.traceId)
    assertEquals(telemetry.sessionSpanId, child.parentSpanId)
    assertTrue(child.traceparent.endsWith("-01"))
    assertTrue(child.tracestate!!.contains("meridian=sdk-android"))
    assertTrue(child.tracestate!!.contains("gateway=1"))

    val unsampled = TelemetryCenter(
      upstreamTraceparent = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-00",
      vendor = "sdk-android",
      language = "kotlin",
    )
    val quiet = unsampled.startSpan("HTTP GET /health")
    assertTrue(quiet.traceparent.endsWith("-00"))
    assertEquals("0af7651916cd43dd8448eb211c80319c", quiet.traceId)

    val fresh = TelemetryCenter(upstreamTraceparent = "not-a-trace", vendor = "sdk-android", language = "kotlin")
    val freshSession = fresh.snapshot().spans.first { it.name == "meridian.session" }
    assertNull(freshSession.parentSpanId)
    assertTrue(traceparent.matches(freshSession.traceparent))
  }

  @Test
  fun testTraceparentOnCatalogFxPaymentsAndSessionHealth() {
    val captured = CopyOnWriteArrayList<Captured>()
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.createContext("/api/v1") { exchange ->
      val path = exchange.requestURI.path
      val query = exchange.requestURI.query ?: ""
      captured += Captured(
        path = path,
        query = query,
        method = exchange.requestMethod,
        traceparent = exchange.requestHeaders.getFirst("traceparent"),
        tracestate = exchange.requestHeaders.getFirst("tracestate"),
        session = exchange.requestHeaders.getFirst("X-Rehearsal-Session"),
        idempotency = exchange.requestHeaders.getFirst("Idempotency-Key"),
      )
      val body = payload(path)
      val bytes = body.toByteArray(StandardCharsets.UTF_8)
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.start()
    try {
      val base = "http://127.0.0.1:${server.address.port}/api/v1"
      val upstream = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
      val client = MeridianClient(base, "test-session", upstream, "gateway=1")
      runBlocking {
        client.getHealth()
        client.getCatalog()
        val quote = client.getFxQuote(2500)
        assertEquals("GBP", quote.base)
        assertEquals("GBP", quote.quote)
        assertEquals(2500, quote.amountMinor)
        client.getSessionHealth()
        client.getState()
        client.submitPayment("northline-studio", 2500, PaymentMethod.card, idempotencyKey = "pay-key-1")
        client.submitPayment("northline-studio", 2500, PaymentMethod.card, idempotencyKey = "pay-key-1")
        client.getEvents()
        client.reset()
        val prompt = client.measureBiometricPrompt()
        assertTrue(prompt.withinSlo)
        client.recordSca(dropped = false)
      }

      assertEquals(9, captured.size)
      val gateway = Regex("^00-0af7651916cd43dd8448eb211c80319c-[0-9a-f]{16}-01$")
      captured.forEach { call ->
        assertEquals("test-session", call.session)
        assertTrue(call.traceparent ?: "", gateway.matches(call.traceparent ?: ""))
        assertTrue(call.tracestate!!.contains("meridian=sdk-android"))
        assertTrue(call.tracestate.contains("gateway=1"))
      }
      assertEquals(captured.size, captured.mapNotNull { it.traceparent?.split("-")?.getOrNull(2) }.toSet().size)
      listOf("/catalog", "/fx/quote", "/payments", "/session/health").forEach { suffix ->
        assertTrue(captured.any { it.path.endsWith(suffix) })
      }
      val payments = captured.filter { it.path.endsWith("/payments") }
      assertEquals(2, payments.size)
      assertTrue(payments.all { it.method == "POST" && it.idempotency == "pay-key-1" })
      assertTrue(captured.filter { !it.path.endsWith("/payments") }.all { it.idempotency == null })
      val quote = captured.first { it.path.endsWith("/fx/quote") }
      assertTrue(quote.query.contains("base=GBP"))
      assertTrue(quote.query.contains("quote=GBP"))
      assertTrue(quote.query.contains("amountMinor=2500"))

      val snap = client.telemetrySnapshot()
      val session = snap.spans.first { it.name == "meridian.session" }
      val paymentSpans = snap.spans.filter { it.name == "payment.submit" }
      val paymentHttp = snap.spans.filter { it.name == "HTTP POST /payments" }
      assertEquals("b7ad6b7169203331", session.parentSpanId)
      assertEquals(snap.traceId, session.traceId)
      assertEquals(2, paymentSpans.size)
      assertTrue(paymentSpans.all { it.parentSpanId == session.spanId && it.traceId == snap.traceId })
      assertEquals(2, paymentHttp.size)
      paymentHttp.zip(paymentSpans).forEach { (http, payment) ->
        assertEquals(payment.spanId, http.parentSpanId)
        assertEquals(payment.traceId, http.traceId)
        assertEquals("/payments", http.attributes["url.path"])
      }
      val quoteSpan = snap.spans.first { it.name == "HTTP GET /fx/quote" }
      assertEquals("/fx/quote", quoteSpan.attributes["url.path"])
      assertEquals(session.spanId, quoteSpan.parentSpanId)
      val wireSpanIds = payments.map { it.traceparent!!.split("-")[2] }.toSet()
      assertEquals(wireSpanIds, paymentHttp.map { it.spanId }.toSet())
      assertFalse(snap.alerts.shouldPage)
      assertTrue(snap.paymentSlo.withinSlo)
      assertTrue(snap.biometricSlo.withinSlo)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testErrorTelemetryIsSanitized() {
    val captured = CopyOnWriteArrayList<String?>()
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.createContext("/api/v1") { exchange ->
      captured += exchange.requestHeaders.getFirst("traceparent")
      val body = "PAN 4111111111111111 IBAN GB29NWBK60161331926819 cardholder: Ada Lovelace"
      val bytes = body.toByteArray(StandardCharsets.UTF_8)
      exchange.sendResponseHeaders(500, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:${server.address.port}/api/v1", "test-session")
      client.addBreadcrumb("card 4111 1111 1111 1111")
      val thrown = StringBuilder()
      runBlocking {
        try {
          client.getCatalog()
          throw AssertionError("catalog should fail")
        } catch (error: MeridianError) {
          thrown.append(error.message)
        }
        try {
          client.submitPayment("northline-studio", 100, PaymentMethod.bank, idempotencyKey = "pay-key-err")
          throw AssertionError("payment should fail")
        } catch (error: MeridianError) {
          thrown.append(error.message)
        }
      }
      val snap = client.telemetrySnapshot()
      val leaked = thrown.toString() + snap.errorLogs.joinToString() + snap.breadcrumbs.joinToString()
      assertFalse(thrown.toString().contains("4111111111111111"))
      assertFalse(leaked.contains("4111111111111111"))
      assertFalse(leaked.contains("GB29NWBK"))
      assertFalse(leaked.contains("Ada Lovelace"))
      assertTrue(leaked.contains("[REDACTED_PAN]"))
      assertTrue(leaked.contains("[REDACTED_IBAN]"))
      assertTrue(leaked.contains("[REDACTED_CARDHOLDER]"))
      assertTrue(snap.alerts.shouldPage)
      assertTrue(snap.alerts.reasons.any { it.contains("submission error rate") })
      assertEquals(2, captured.size)
      assertTrue(captured.all { header -> header?.let(traceparent::matches) == true })
    } finally {
      server.stop(0)
    }
  }

  private fun payload(path: String): String = when {
    path.endsWith("/catalog") -> """{"demoDate":"2026-09-18","recipients":[],"providers":[]}"""
    path.endsWith("/fx/quote") -> """{"base":"GBP","quote":"GBP","amountMinor":2500,"quoteAmountMinor":2500}"""
    path.endsWith("/session/health") -> """{"status":"UP","session":"test-session"}"""
    path.endsWith("/health") -> """{"status":"UP","service":"meridian-api","simulation":true}"""
    path.endsWith("/state") -> """{"version":1,"balance":1248050,"transactions":[],"budgets":[]}"""
    path.endsWith("/payments") -> """{"ok":true}"""
    path.endsWith("/events") -> """{"events":[]}"""
    path.endsWith("/reset") -> """{"ok":true}"""
    else -> """{"ok":true}"""
  }

  private data class Captured(
    val path: String,
    val query: String,
    val method: String,
    val traceparent: String?,
    val tracestate: String?,
    val session: String?,
    val idempotency: String?,
  )

  private class MutableClock(var now: Long) {
    fun read(): Long = now
  }
}
