package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class MeridianSDKTest {
  private val mapper = ObjectMapper().registerKotlinModule()

  // MARK: - Amount Parsing Tests

  @Test
  fun testParseAmountValidInteger() {
    val (pence, error) = parseAmount("10")
    assertEquals(1000, pence)
    assertNull(error)
  }

  @Test
  fun testParseAmountValidDecimal() {
    val (pence, error) = parseAmount("10.50")
    assertEquals(1050, pence)
    assertNull(error)
  }

  @Test
  fun testParseAmountSingleDecimal() {
    val (pence, error) = parseAmount("10.5")
    assertEquals(1050, pence)
    assertNull(error)
  }

  @Test
  fun testParseAmountZero() {
    val (pence, error) = parseAmount("0")
    assertNull(pence)
    assertEquals("Amount must be greater than zero", error)
  }

  @Test
  fun testParseAmountNegative() {
    val (pence, error) = parseAmount("-10.50")
    assertNull(pence)
    assertNotNull(error)
  }

  @Test
  fun testParseAmountExponent() {
    val (pence, error) = parseAmount("1e3")
    assertNull(pence)
    assertNotNull(error)
  }

  @Test
  fun testParseAmountTooManyDecimals() {
    val (pence, error) = parseAmount("10.501")
    assertNull(pence)
    assertEquals("Amount must have at most 2 decimal places", error)
  }

  @Test
  fun testParseAmountTooLarge() {
    val (pence, error) = parseAmount("10001")
    assertNull(pence)
    assertEquals("Amount cannot exceed £10,000", error)
  }

  @Test
  fun testParseAmountEmpty() {
    val (pence, error) = parseAmount("")
    assertNull(pence)
    assertEquals("Amount is required", error)
  }

  @Test
  fun testParseAmountWhitespace() {
    val (pence, error) = parseAmount("   ")
    assertNull(pence)
    assertEquals("Amount is required", error)
  }

  @Test
  fun testParseAmountMaxValid() {
    val (pence, error) = parseAmount("10000")
    assertEquals(1_000_000, pence)
    assertNull(error)
  }

  // MARK: - Formatting Tests

  @Test
  fun testMoneyFormatting() {
    assertEquals("£10.50", money(1050))
    assertEquals("£1.00", money(100))
    assertEquals("£0.01", money(1))
    assertEquals("£10000.00", money(1_000_000))
  }

  // MARK: - Model Deserialization

  @Test
  fun testBankStateDeserialization() {
    val json = """
      {
        "version": 1,
        "balance": 1248050,
        "transactions": [
          {
            "id": "txn-001",
            "reference": "REF-20260905-001",
            "recipientId": "birch-bloom",
            "name": "Birch & Bloom",
            "category": "Food & drink",
            "amount": 3500,
            "date": "2026-09-05",
            "provider": "worldpay",
            "method": "bank",
            "status": "completed",
            "note": "Breakfast"
          }
        ],
        "budgets": [
          {
            "category": "Shopping",
            "limit": 100000
          }
        ]
      }
    """.trimIndent()

    val state = mapper.readValue(json, BankState::class.java)

    assertEquals(1, state.version)
    assertEquals(1_248_050, state.balance)
    assertEquals(1, state.transactions.size)
    assertEquals("txn-001", state.transactions[0].id)
    assertEquals(3500, state.transactions[0].amount)
    assertEquals(1, state.budgets.size)
    assertEquals(100_000, state.budgets[0].limit)
  }

  @Test
  fun testPaymentResponseDeserialization() {
    val json = """
      {
        "ok": true,
        "state": {
          "version": 1,
          "balance": 1000000,
          "transactions": [],
          "budgets": []
        },
        "transaction": {
          "id": "txn-new",
          "reference": "REF-20260919-new",
          "recipientId": "birch-bloom",
          "name": "Birch & Bloom",
          "category": "Food & drink",
          "amount": 5000,
          "date": "2026-09-19",
          "provider": "adyen",
          "method": "card",
          "status": "completed",
          "note": "Coffee"
        }
      }
    """.trimIndent()

    val response = mapper.readValue(json, PaymentResponse::class.java)

    assertTrue(response.ok)
    assertNotNull(response.state)
    assertNotNull(response.transaction)
    assertEquals(5000, response.transaction?.amount)
  }

  @Test
  fun testPaymentResponseErrorDeserialization() {
    val json = """
      {
        "ok": false,
        "error": "Insufficient balance",
        "code": "INSUFFICIENT_BALANCE"
      }
    """.trimIndent()

    val response = mapper.readValue(json, PaymentResponse::class.java)

    assertFalse(response.ok)
    assertEquals("Insufficient balance", response.error)
    assertEquals("INSUFFICIENT_BALANCE", response.code)
  }

  @Test
  fun testPaymentResponsePendingDeserialization() {
    val json = """
      {
        "ok": false,
        "error": "Payment pending confirmation",
        "code": "PAYMENT_PENDING",
        "paymentId": "pay-12345"
      }
    """.trimIndent()

    val response = mapper.readValue(json, PaymentResponse::class.java)

    assertFalse(response.ok)
    assertEquals("PAYMENT_PENDING", response.code)
    assertEquals("pay-12345", response.paymentId)
  }

  @Test
  fun testRecipientDeserialization() {
    val json = """
      {
        "id": "northline-studio",
        "name": "Northline Studio",
        "initials": "NS",
        "detail": "Design tools & materials",
        "category": "Shopping",
        "color": "#FF6B6B"
      }
    """.trimIndent()

    val recipient = mapper.readValue(json, Recipient::class.java)

    assertEquals("northline-studio", recipient.id)
    assertEquals("Shopping", recipient.category)
    assertEquals("#FF6B6B", recipient.color)
  }

  @Test
  fun testCatalogResponseDeserialization() {
    val json = """
      {
        "demoDate": "2026-09-18",
        "recipients": [
          {
            "id": "birch-bloom",
            "name": "Birch & Bloom",
            "initials": "BB",
            "detail": "Organic café & bistro",
            "category": "Food & drink",
            "color": "#FFD93D"
          }
        ],
        "providers": [
          {
            "id": "adyen",
            "name": "Adyen",
            "description": "Card payment processor",
            "methods": ["card"]
          }
        ]
      }
    """.trimIndent()

    val response = mapper.readValue(json, CatalogResponse::class.java)

    assertEquals("2026-09-18", response.demoDate)
    assertEquals(1, response.recipients.size)
    assertEquals(1, response.providers.size)
    assertEquals("adyen", response.providers[0].id)
  }

  @Test
  fun testClientInitialization() {
    val client = MeridianClient(
      baseURL = "http://localhost:8080/api/v1",
      sessionId = "test-session-123",
    )
    assertNotNull(client)
  }

  @Test
  fun testClientInitializationMissingSession() {
    val exception = assertThrows(IllegalArgumentException::class.java) {
      MeridianClient(
        baseURL = "http://localhost:8080/api/v1",
        sessionId = "",
      )
    }
    assertTrue(exception.message?.contains("Session ID") ?: false)
  }

  @Test
  fun testClientInitializationInvalidURL() {
    val exception = assertThrows(IllegalArgumentException::class.java) {
      MeridianClient(
        baseURL = "not a valid url",
        sessionId = "test-session",
      )
    }
    assertTrue(exception.message?.contains("Invalid URL") ?: false)
  }

  @Test
  fun testHttpTransportWithIdempotency() {
    // Start a simple HTTP server on localhost:0 (random port)
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"

    // Track idempotency keys
    val seenKeys = mutableSetOf<String>()
    var statusCode = 202

    // Handler that validates headers and returns 202 first time, 200 on retry
    server.createContext("/api/v1/payments") { exchange ->
      val method = exchange.requestMethod
      assertEquals("POST", method)

      // Validate session header
      val sessionHeader = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      assertNotNull(sessionHeader)
      assertEquals("test-session", sessionHeader)

      // Validate idempotency header
      val idempotencyKey = exchange.requestHeaders.getFirst("Idempotency-Key")
      assertNotNull(idempotencyKey)
      assertTrue(idempotencyKey.isNotEmpty())

      // Track idempotency key
      val isRetry = idempotencyKey in seenKeys
      seenKeys.add(idempotencyKey)

      // Return appropriate status
      val status = if (isRetry) 200 else 202
      val responseBody = if (isRetry) {
        """{"ok":true,"paymentId":"tx-123","state":null}"""
      } else {
        """{"ok":false,"code":"PAYMENT_PENDING","paymentId":"tx-123","error":"Awaiting confirmation"}"""
      }

      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(status, responseBody.length.toLong())
      exchange.responseBody.write(responseBody.toByteArray())
      exchange.close()
    }

    server.start()
    try {
      val client = MeridianClient(baseUrl, "test-session")
      
      // First call returns 202 (pending)
      val response1 = runBlocking {
        client.submitPayment(
          recipientId = "rec-1",
          amountMinor = 10000,
          method = PaymentMethod.card,
          idempotencyKey = "idempotency-key-1"
        )
      }
      assertFalse(response1.ok)
      assertEquals("PAYMENT_PENDING", response1.code)
      assertEquals("tx-123", response1.paymentId)

      // Second call with same key returns 200 (success)
      val response2 = runBlocking {
        client.submitPayment(
          recipientId = "rec-1",
          amountMinor = 10000,
          method = PaymentMethod.card,
          idempotencyKey = "idempotency-key-1"
        )
      }
      assertTrue(response2.ok)

      // Verify only one idempotency key was used
      assertEquals(1, seenKeys.size)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testBackoffScheduleRetriesOnlyGatewayTimeouts() {
    val policy = RetryPolicy(jitter = { 0 })
    assertEquals(3, policy.maxAttempts)
    assertEquals(200L, policy.delayMillis(beforeAttempt = 2))
    assertEquals(400L, policy.delayMillis(beforeAttempt = 3))
    assertEquals(800L, policy.delayMillis(beforeAttempt = 4))
    assertEquals(1600L, policy.delayMillis(beforeAttempt = 5))
    assertEquals(1600L, policy.delayMillis(beforeAttempt = 8))
    assertTrue(policy.retries(502))
    assertTrue(policy.retries(504))
    assertFalse(policy.retries(500))
    assertFalse(policy.retries(503))
    assertFalse(policy.retries(409))
    assertFalse(policy.retries(400))
  }

  @Test
  fun testDegradedCardPromptsWorldpayBankOnly() {
    val health = SessionHealth(
      status = "DEGRADED",
      simulation = true,
      corridors = listOf(
        CorridorHealth(
          id = "EU",
          currency = "EUR",
          status = "outage",
          rails = listOf(RailHealth("card", "adyen", "outage")),
        ),
        CorridorHealth(
          id = "GB",
          currency = "GBP",
          status = "degraded",
          rails = listOf(
            RailHealth("card", "adyen", "degraded"),
            RailHealth("bank", "unlisted", "healthy"),
            RailHealth("bank", "worldpay", "healthy"),
          ),
        ),
      ),
    )
    val notice = corridorNotice(health, PaymentMethod.card)
    assertTrue(notice is CorridorNotice.SwitchRail)
    val prompt = (notice as CorridorNotice.SwitchRail).prompt
    assertEquals("GB", prompt.corridorId)
    assertEquals(PaymentMethod.card, prompt.selectedMethod)
    assertEquals(PaymentMethod.bank, prompt.alternateMethod)
    assertEquals("worldpay", baselineProvider(prompt.alternateMethod))
    assertNull(corridorNotice(health, PaymentMethod.bank))
  }

  @Test
  fun testOutageWithoutHealthyBaselineRailDoesNotInventAProvider() {
    val health = SessionHealth(
      status = "DOWN",
      corridors = listOf(
        CorridorHealth(
          id = "GB",
          currency = "GBP",
          status = "outage",
          rails = listOf(
            RailHealth("card", "adyen", "outage"),
            RailHealth("bank", "worldpay", "degraded"),
            RailHealth("card", "unlisted", "healthy"),
          ),
        ),
      ),
    )
    val notice = corridorNotice(health, PaymentMethod.card)
    assertTrue(notice is CorridorNotice.Unavailable)
    assertFalse((notice as CorridorNotice.Unavailable).message.contains("unlisted"))
  }

  @Test
  fun testSessionHealthJsonIgnoresUnknownFields() {
    val json = """
      {
        "status": "DEGRADED",
        "simulation": true,
        "region": "uk",
        "corridors": [
          {
            "id": "GB",
            "currency": "GBP",
            "status": "degraded",
            "rails": [
              {"method": "card", "provider": "adyen", "status": "outage", "latencyMs": 900}
            ]
          }
        ]
      }
    """.trimIndent()
    val health = mapper.readValue(json, SessionHealth::class.java)
    assertEquals("DEGRADED", health.status)
    assertEquals(true, health.simulation)
    assertEquals("outage", health.corridors[0].rails[0].status)
    assertTrue(corridorNotice(health, PaymentMethod.card) is CorridorNotice.Unavailable)
  }

  @Test
  fun testGatewayRetryKeepsIdempotencyKeyAndPaymentBody() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val baseUrl = "http://127.0.0.1:${server.address.port}/api/v1"
    val keys = mutableListOf<String>()
    val bodies = mutableListOf<String>()
    val sessions = mutableListOf<String>()
    val delays = mutableListOf<Long>()
    server.createContext("/api/v1/payments") { exchange ->
      sessions.add(exchange.requestHeaders.getFirst("X-Rehearsal-Session"))
      keys.add(exchange.requestHeaders.getFirst("Idempotency-Key"))
      bodies.add(String(exchange.requestBody.readBytes(), Charsets.UTF_8))
      val status = when (keys.size) {
        1 -> 502
        2 -> 504
        else -> 200
      }
      val responseBody = if (status == 200) """{"ok":true,"paymentId":"pay-keep"}""" else ""
      val bytes = responseBody.toByteArray()
      exchange.sendResponseHeaders(status, bytes.size.toLong())
      if (bytes.isNotEmpty()) exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient(
        baseURL = baseUrl,
        sessionId = "room-keep",
        retryPolicy = RetryPolicy(jitter = { 0 }),
        sleeper = { delays.add(it) },
      )
      val response = runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 2500,
          method = PaymentMethod.card,
          note = "Studio materials",
          idempotencyKey = "pay-key-keep",
        )
      }
      assertTrue(response.ok)
      assertEquals("pay-keep", response.paymentId)
      assertEquals(listOf("pay-key-keep", "pay-key-keep", "pay-key-keep"), keys)
      assertEquals(listOf("room-keep", "room-keep", "room-keep"), sessions)
      assertEquals(1, bodies.toSet().size)
      assertTrue(bodies[0].contains("\"method\":\"card\""))
      assertTrue(bodies[0].contains("\"amountMinor\":2500"))
      assertFalse(bodies[0].contains("worldpay"))
      assertEquals(listOf(200L, 400L), delays)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testGatewayRetriesExhaustWithoutChangingTheKey() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val baseUrl = "http://127.0.0.1:${server.address.port}/api/v1"
    val hits = AtomicInteger()
    val keys = mutableListOf<String>()
    server.createContext("/api/v1/payments") { exchange ->
      hits.incrementAndGet()
      keys.add(exchange.requestHeaders.getFirst("Idempotency-Key"))
      exchange.requestBody.readBytes()
      exchange.sendResponseHeaders(502, -1)
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient(
        baseURL = baseUrl,
        sessionId = "room-exhaust",
        retryPolicy = RetryPolicy(jitter = { 0 }),
        sleeper = { },
      )
      val error = assertThrows(MeridianError.RetriesExhausted::class.java) {
        runBlocking {
          client.submitPayment(
            recipientId = "northline-studio",
            amountMinor = 100,
            method = PaymentMethod.bank,
            idempotencyKey = "same-bank-key",
          )
        }
      }
      assertEquals(502, error.statusCode)
      assertEquals(3, error.attempts)
      assertEquals(3, hits.get())
      assertEquals(listOf("same-bank-key", "same-bank-key", "same-bank-key"), keys)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testBusiness503IsNotRetried() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val baseUrl = "http://127.0.0.1:${server.address.port}/api/v1"
    val hits = AtomicInteger()
    server.createContext("/api/v1/payments") { exchange ->
      hits.incrementAndGet()
      exchange.requestBody.readBytes()
      val body = """{"ok":false,"error":"Provider unavailable","code":"PROVIDER_UNAVAILABLE"}"""
      val bytes = body.toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(503, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient(baseUrl, "room-503", sleeper = { throw AssertionError("503 must not sleep") })
      val response = runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 100,
          method = PaymentMethod.card,
          idempotencyKey = "once",
        )
      }
      assertFalse(response.ok)
      assertEquals("PROVIDER_UNAVAILABLE", response.code)
      assertEquals(1, hits.get())
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testSessionHealthPollingAndMissingEndpoint() = runBlocking {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val baseUrl = "http://127.0.0.1:${server.address.port}/api/v1"
    val hits = AtomicInteger()
    server.createContext("/api/v1/session/health") { exchange ->
      hits.incrementAndGet()
      assertEquals("GET", exchange.requestMethod)
      assertEquals("health-room", exchange.requestHeaders.getFirst("X-Rehearsal-Session"))
      val body = """
        {"status":"DEGRADED","simulation":true,"corridors":[{"id":"GB","currency":"GBP","status":"degraded","rails":[{"method":"card","provider":"adyen","status":"outage"},{"method":"bank","provider":"worldpay","status":"healthy"}]}]}
      """.trimIndent()
      val bytes = body.toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient(baseUrl, "health-room")
      val job = client.startSessionHealthPolling(this, 30)
      val deadline = System.currentTimeMillis() + 3_000
      while (hits.get() < 2 && System.currentTimeMillis() < deadline) delay(15)
      client.stopSessionHealthPolling()
      job.cancel()
      assertTrue("expected repeated /session/health polls, saw ${hits.get()}", hits.get() >= 2)
      val notice = corridorNotice(client.sessionHealth().value.health!!, PaymentMethod.card)
      assertTrue(notice is CorridorNotice.SwitchRail)
      assertEquals(PaymentMethod.bank, (notice as CorridorNotice.SwitchRail).prompt.alternateMethod)
    } finally {
      server.stop(0)
    }

    val missing = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    missing.createContext("/api/v1/session/health") { exchange ->
      exchange.sendResponseHeaders(404, -1)
      exchange.close()
    }
    missing.start()
    try {
      val client = MeridianClient("http://127.0.0.1:${missing.address.port}/api/v1", "health-room")
      val snapshot = client.loadSessionHealth()
      assertFalse(snapshot.reachable)
      assertNull(snapshot.health)
      assertEquals("Session health is not available", snapshot.detail)
    } finally {
      missing.stop(0)
    }
  }
}
