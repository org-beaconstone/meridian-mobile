package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

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
  fun testLegacyAndDynamicCatalogDecoding() {
    val legacy = """
      {"demoDate":"2026-09-18","recipients":[],"providers":[
        {"id":"adyen","name":"Adyen","description":"Card processor","methods":["card"]},
        {"id":"worldpay","name":"Worldpay","description":"Bank payment","methods":["bank"]}
      ]}
    """.trimIndent()
    val legacyCatalog = CatalogDecoder.decode(legacy)
    assertNotNull(legacyCatalog)
    assertEquals("legacy", legacyCatalog!!.schema)
    assertEquals(listOf("adyen", "worldpay"), legacyCatalog.providers.map { it.id })
    assertEquals(listOf("GBP"), legacyCatalog.currencies)

    val dynamic = """
      {"schema":"dynamic","demoDate":"2026-09-18","currencies":[{"code":"EUR"},{"code":"USD"},"GBP"],
       "methods":[
         {"providerId":"adyen","label":"Adyen","method":"card"},
         {"providerId":"worldpay","name":"Worldpay","rail":"bank"},
         {"providerId":"extra","name":"Extra rail","method":"card"}
       ]}
    """.trimIndent()
    val dynamicCatalog = CatalogDecoder.decode(dynamic)
    assertNotNull(dynamicCatalog)
    assertEquals("dynamic", dynamicCatalog!!.schema)
    assertEquals(listOf("adyen", "worldpay"), dynamicCatalog.providers.map { it.id })
    assertEquals(listOf("EUR", "GBP"), dynamicCatalog.currencies)
    assertNull(CatalogDecoder.decode("not-json"))
  }

  @Test
  fun testFeatureFlagKillSwitchCacheAndTelemetry() {
    assertEquals(false to "legacy", FeatureFlagParser.parse("{}"))
    assertEquals(
      false to "legacy",
      FeatureFlagParser.parse("""{"flags":{"enable_mobile_eu_payments":{"enabled":true,"killSwitch":true}}}"""),
    )
    assertEquals(
      true to "dynamic",
      FeatureFlagParser.parse("""{"enable_mobile_eu_payments":{"enabled":true,"variant":"dynamic"}}"""),
    )
    assertNull(FeatureFlagParser.parse("[]"))

    val cache = InMemoryFeatureFlagCache()
    val stored = FeatureFlagEvaluation(enabled = true, variant = "dynamic", source = "remote")
    cache.write(FeatureFlags.cacheKey("room-a"), stored)
    assertEquals(stored, cache.read(FeatureFlags.cacheKey("room-a")))
    assertNull(cache.read(FeatureFlags.cacheKey("room-b")))

    val legacyEvent = PaymentTelemetry.event(FeatureFlagEvaluation.legacy("cache"), "key-1", "room-a", "EUR")
    assertEquals("legacy", legacyEvent.variant)
    assertEquals("GBP", legacyEvent.currency)
    assertEquals("enable_mobile_eu_payments=legacy", PaymentTelemetry.headerValue(legacyEvent))
    val dynamicEvent = PaymentTelemetry.event(stored, "key-1", "room-a", "EUR")
    assertEquals("dynamic", dynamicEvent.variant)
    assertEquals("EUR", dynamicEvent.currency)
    assertEquals("€10.50", formatMinor(1050, "EUR"))
  }

  @Test
  fun testRemoteFlagCacheAndPaymentHeader() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"
    val enabled = java.util.concurrent.atomic.AtomicBoolean(true)
    val seenFlags = mutableListOf<String>()

    server.createContext("/api/v1/flags") { exchange ->
      val session = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      assertEquals("flag-room", session)
      val body = if (enabled.get()) {
        """{"enable_mobile_eu_payments":{"enabled":true,"variant":"dynamic"}}"""
      } else {
        """{"enable_mobile_eu_payments":{"enabled":false,"variant":"dynamic","killSwitch":true}}"""
      }
      val bytes = body.toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.createContext("/api/v1/catalog") { exchange ->
      val body = """{"schema":"dynamic","demoDate":"2026-09-18","recipients":[],"currencies":["EUR","GBP"],"methods":[{"providerId":"adyen","name":"Adyen","method":"card"},{"providerId":"worldpay","name":"Worldpay","method":"bank"},{"providerId":"extra","name":"Extra rail","method":"card"}]}"""
      val bytes = body.toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.createContext("/api/v1/payments") { exchange ->
      seenFlags.add(exchange.requestHeaders.getFirst("X-Meridian-Flag"))
      val body = """{"ok":true,"paymentId":"tx-1"}"""
      val bytes = body.toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.start()
    try {
      val cache = InMemoryFeatureFlagCache()
      val client = MeridianClient(baseUrl, "flag-room", cache)
      val on = runBlocking { client.evaluateEuPaymentsFlag() }
      assertTrue(on.enabled)
      assertEquals("dynamic", on.variant)
      assertEquals("remote", on.source)
      val catalog = runBlocking { client.getCatalog() }
      assertEquals(listOf("adyen", "worldpay"), catalog.providers.map { it.id })
      runBlocking {
        client.submitPayment("northline-studio", 100, PaymentMethod.card, idempotencyKey = "same-key", displayCurrency = "EUR")
      }
      assertEquals(listOf("enable_mobile_eu_payments=dynamic"), seenFlags)
      assertEquals("EUR", client.paymentTelemetry().single().currency)

      enabled.set(false)
      val off = runBlocking { client.evaluateEuPaymentsFlag() }
      assertFalse(off.enabled)
      assertEquals("legacy", off.variant)
      assertEquals(off, cache.read(FeatureFlags.cacheKey("flag-room"))?.copy(source = off.source))
      runBlocking {
        client.submitPayment("northline-studio", 100, PaymentMethod.card, idempotencyKey = "same-key", displayCurrency = "EUR")
      }
      assertEquals("enable_mobile_eu_payments=legacy", seenFlags.last())
      assertEquals("GBP", client.paymentTelemetry().last().currency)
      assertEquals("same-key", client.paymentTelemetry().last().idempotencyKey)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testFlagReadFallsBackToCache() {
    val cache = InMemoryFeatureFlagCache()
    cache.write(
      FeatureFlags.cacheKey("flag-room"),
      FeatureFlagEvaluation(enabled = true, variant = "dynamic", source = "remote"),
    )
    val client = MeridianClient("http://127.0.0.1:9/api/v1", "flag-room", cache)
    val evaluation = runBlocking { client.evaluateEuPaymentsFlag() }
    assertTrue(evaluation.enabled)
    assertEquals("dynamic", evaluation.variant)
    assertEquals("cache", evaluation.source)
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
}
