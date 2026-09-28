package com.atlassian.meridian

import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

class TelemetryTest {
  private val pan = "4111111111111111"
  private val iban = "GB29NWBK60161331926819"
  private val noteIban = "DE89370400440532013000"
  private val spacedIban = "GB29 NWBK 6016 1331 9268 19"
  private val spacedPan = "4111-1111-1111-1111"

  @Test
  fun testTraceparentShapeAndRouteSelection() {
    val header = TraceContext.root().traceparent
    assertTrue(TraceContext.isValidTraceparent(header))
    assertFalse(TraceContext.isValidTraceparent("00-" + "0".repeat(32) + "-" + "1".repeat(16) + "-01"))
    assertFalse(TraceContext.isValidTraceparent("00-" + "a".repeat(32) + "-" + "0".repeat(16) + "-01"))
    assertTrue(shouldInjectTraceparent("/catalog"))
    assertTrue(shouldInjectTraceparent("/api/v1/payments"))
    assertTrue(shouldInjectTraceparent("/session/health"))
    assertFalse(shouldInjectTraceparent("/health"))
    assertFalse(shouldInjectTraceparent("/state"))
    assertFalse(shouldInjectTraceparent("/budgets"))
    assertFalse(shouldInjectTraceparent("/events"))
  }

  @Test
  fun testSanitizerRedactsPanAndIbanOnly() {
    assertEquals("[REDACTED_PAN]", TelemetrySanitizer.redact(pan))
    assertEquals("[REDACTED_PAN]", TelemetrySanitizer.redact(spacedPan))
    assertEquals("[REDACTED_IBAN]", TelemetrySanitizer.redact(iban))
    assertEquals("[REDACTED_IBAN]", TelemetrySanitizer.redact(noteIban))
    assertEquals("[REDACTED_IBAN]", TelemetrySanitizer.redact(spacedIban))
    val mixed = TelemetrySanitizer.redact("card $pan iban $iban ref rent")
    assertFalse(mixed.contains(pan))
    assertFalse(mixed.contains(iban))
    assertTrue(mixed.contains("rent"))
    assertEquals("balance 1248050", TelemetrySanitizer.redact("balance 1248050"))
    assertFalse(TelemetrySanitizer.containsSensitive("PAYMENT_PENDING"))
  }

  @Test
  fun testAttributePolicyDropsSecretsAndUnknownProviders() {
    val log = TelemetryLog()
    log.recordError(
      iban,
      "gateway_roundtrip",
      mapOf(
        "note" to noteIban,
        "detail" to pan,
        "error.message" to "declined $pan $spacedIban",
        "payment.provider" to "other",
        "payment.method" to "card",
        "outcome" to "DECLINED",
      ),
    )
    val rendered = log.rendered()
    assertFalse(rendered.contains(pan))
    assertFalse(rendered.contains(iban))
    assertFalse(rendered.contains(noteIban))
    assertFalse(rendered.contains(spacedIban))
    assertFalse(rendered.contains("other"))
    assertFalse(rendered.contains("note="))
    assertTrue(rendered.contains("REDACTED_CODE"))
    assertTrue(rendered.contains("payment.method=card"))
    assertTrue(rendered.contains("[REDACTED_PAN]"))
    assertTrue(rendered.contains("[REDACTED_IBAN]"))
    assertFalse(rendered.contains("payment.provider"))
  }

  @Test
  fun testBiometricSpansAndScaFallbackStayLocal() {
    val client = MeridianClient("http://127.0.0.1:9/api/v1", "telemetry-room")
    val accepted = client.resolveLocalBiometricPrompt(PaymentMethod.card)
    assertTrue(accepted.accepted)
    assertFalse(accepted.fallback)
    val prompt = client.telemetry.spans().single { it.name == "biometric.prompt" }
    assertTrue(prompt.durationMillis >= 0)
    assertEquals("ok", prompt.status)
    assertEquals("adyen", prompt.attributes["payment.provider"])
    assertEquals("card", prompt.attributes["payment.method"])

    val fallback = client.resolveLocalBiometricPrompt(PaymentMethod.bank, available = false)
    assertTrue(fallback.fallback)
    assertFalse(fallback.accepted)
    val event = client.telemetry.events().single { it.name == "sca.fallback" }
    assertEquals("SCA_CHALLENGE_FALLBACK", event.errorCode)
    assertEquals("biometric_prompt", event.failureStage)
    assertEquals("worldpay", event.attributes["payment.provider"])
    assertFalse(client.telemetry.rendered().contains(pan))

    val declined = client.resolveLocalBiometricPrompt(PaymentMethod.card, accepted = false)
    assertFalse(declined.accepted)
    assertTrue(client.telemetry.events().any { it.errorCode == "BIOMETRIC_DECLINED" && it.failureStage == "biometric_prompt" })
  }

  @Test
  fun testTracedRoutesSpansAndSanitizedGatewayErrors() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val executor = Executors.newCachedThreadPool()
    server.executor = executor
    val healthCalls = AtomicInteger()
    val paymentCalls = AtomicInteger()
    var paymentBody = ""
    server.createContext("/api/v1/catalog") { exchange ->
      val header = checkNotNull(exchange.requestHeaders.getFirst("traceparent"))
      assertTrue(TraceContext.isValidTraceparent(header))
      val body = """
        {"demoDate":"2026-09-18","recipients":[{"id":"northline-studio","name":"Northline","initials":"NS","detail":"$iban","category":"Shopping","color":"#111111"}],"providers":[{"id":"adyen","name":"Adyen","description":"Card","methods":["card"]}]}
      """.trimIndent()
      respond(exchange, 200, body)
    }
    server.createContext("/api/v1/payments") { exchange ->
      paymentCalls.incrementAndGet()
      val header = checkNotNull(exchange.requestHeaders.getFirst("traceparent"))
      assertTrue(TraceContext.isValidTraceparent(header))
      assertEquals("room-telemetry", exchange.requestHeaders.getFirst("X-Rehearsal-Session"))
      assertEquals("same-key", exchange.requestHeaders.getFirst("Idempotency-Key"))
      paymentBody = exchange.requestBody.readBytes().toString(StandardCharsets.UTF_8)
      val code = if (paymentBody.contains("\"scenario\":\"unavailable\"")) "SCA_REQUIRED" else "DECLINED"
      respond(exchange, 422, """{"ok":false,"code":"$code","error":"card $pan iban $iban"}""")
    }
    server.createContext("/api/v1/session/health") { exchange ->
      assertTrue(TraceContext.isValidTraceparent(checkNotNull(exchange.requestHeaders.getFirst("traceparent"))))
      val body = when (healthCalls.getAndIncrement()) {
        0 -> """{"status":"UP","service":"meridian-api","simulation":true}"""
        1 -> """{"status":"UP","service":"meridian-api","simulation":true}"""
        else -> """{"status":"degraded","corridors":[{"id":"adyen-card","provider":"adyen","method":"card","state":"degraded"},{"id":"other-wallet","provider":"other","method":"card","state":"degraded"}]}"""
      }
      respond(exchange, 200, body)
    }
    server.createContext("/api/v1/state") { exchange ->
      assertNull(exchange.requestHeaders.getFirst("traceparent"))
      respond(exchange, 200, """{"version":1,"balance":1248050,"transactions":[],"budgets":[]}""")
    }
    server.createContext("/api/v1/health") { exchange ->
      assertNull(exchange.requestHeaders.getFirst("traceparent"))
      respond(exchange, 200, """{"status":"UP","service":"meridian-api","simulation":true}""")
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:${server.address.port}/api/v1", "room-telemetry")
      val catalog = runBlocking { client.getCatalog() }
      assertEquals(iban, catalog.recipients[0].detail)
      val parse = client.telemetry.spans().single { it.name == "catalog.parse" }
      assertTrue(parse.durationMillis >= 0)
      assertEquals("1", parse.attributes["recipient.count"])
      assertNotNull(parse.parentSpanId)
      assertFalse(client.telemetry.rendered().contains(iban))

      runBlocking { client.getState() }
      runBlocking { client.getHealth() }

      val declined = runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 2500,
          method = PaymentMethod.card,
          note = noteIban,
          scenario = Scenario.declined,
          idempotencyKey = "same-key",
        )
      }
      assertFalse(declined.ok)
      assertTrue(paymentBody.contains(noteIban))
      val gateway = client.telemetry.spans().single { it.name == "payment.gateway" }
      assertEquals("error", gateway.status)
      assertTrue(gateway.durationMillis >= 0)
      assertNull(gateway.parentSpanId)
      assertEquals("adyen", gateway.attributes["payment.provider"])
      val gatewayError = client.telemetry.events().single { it.failureStage == "gateway_roundtrip" && it.name == "client.error" }
      assertEquals("DECLINED", gatewayError.errorCode)
      val rendered = client.telemetry.rendered()
      assertFalse(rendered.contains(pan))
      assertFalse(rendered.contains(iban))
      assertFalse(rendered.contains(noteIban))
      assertFalse(rendered.contains("other"))

      val challenged = runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 2500,
          method = PaymentMethod.card,
          note = "rent",
          scenario = Scenario.unavailable,
          idempotencyKey = "same-key",
        )
      }
      assertEquals("SCA_REQUIRED", challenged.code)
      assertEquals(2, paymentCalls.get())
      assertTrue(client.telemetry.events().any { it.name == "sca.fallback" && it.errorCode == "SCA_REQUIRED" && it.failureStage == "sca_challenge" })

      val first = runBlocking { client.checkSessionHealth() }
      assertEquals("healthy", first.connectionState)
      val afterFirst = client.telemetry.events().count { it.name == "session.connection_changed" }
      val second = runBlocking { client.checkSessionHealth() }
      assertEquals("healthy", second.connectionState)
      assertEquals(afterFirst, client.telemetry.events().count { it.name == "session.connection_changed" })
      assertFalse(client.telemetry.events().any { it.name == "corridor.degraded" })
      val third = runBlocking { client.checkSessionHealth() }
      assertEquals("degraded", third.connectionState)
      val degraded = client.telemetry.events().filter { it.name == "corridor.degraded" }
      val adyen = degraded.single { it.attributes["corridor.id"] == "adyen-card" }
      assertEquals("adyen", adyen.attributes["payment.provider"])
      assertEquals("card", adyen.attributes["payment.method"])
      assertTrue(degraded.any { it.attributes["corridor.id"] == "session" })
      assertFalse(client.telemetry.rendered().contains("other"))
      assertTrue(client.telemetry.spans().any { it.name == "session.health" && it.attributes["http.route"] == "/api/v1/session/health" })
    } finally {
      server.stop(0)
      executor.shutdownNow()
    }
  }

  @Test
  fun testNetworkFailureRecordsStageWithoutSecrets() {
    val port = ServerSocket().use { socket ->
      socket.bind(InetSocketAddress("127.0.0.1", 0))
      socket.localPort
    }
    val client = MeridianClient("http://127.0.0.1:$port/api/v1", "room-telemetry")
    val thrown = runCatching {
      runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 100,
          method = PaymentMethod.bank,
          note = noteIban,
          idempotencyKey = "kept-key",
        )
      }
    }.exceptionOrNull()
    assertNotNull(thrown)
    val rendered = client.telemetry.rendered()
    assertTrue(rendered.contains("NETWORK_ERROR"))
    assertTrue(rendered.contains("gateway_roundtrip"))
    assertTrue(client.telemetry.spans().any { it.name == "payment.gateway" && it.status == "error" })
    assertFalse(rendered.contains(noteIban))
    assertFalse(rendered.contains(pan))
    assertEquals("worldpay", client.telemetry.spans().single { it.name == "payment.gateway" }.attributes["payment.provider"])
  }

  private fun respond(exchange: com.sun.net.httpserver.HttpExchange, status: Int, body: String) {
    val bytes = body.toByteArray(StandardCharsets.UTF_8)
    exchange.responseHeaders.add("Content-Type", "application/json")
    exchange.sendResponseHeaders(status, bytes.size.toLong())
    exchange.responseBody.use { it.write(bytes) }
  }
}
