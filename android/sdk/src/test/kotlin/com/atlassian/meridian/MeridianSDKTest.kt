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

  // MARK: - Telemetry: TraceContext Tests

  @Test
  fun testTraceContextTraceIdFormat() {
    val ctx = TraceContext()
    // Must be 32 lowercase hex characters (128-bit)
    assertTrue(
      "traceId must be 32 lowercase hex chars",
      ctx.traceId.matches(Regex("[0-9a-f]{32}"))
    )
  }

  @Test
  fun testTraceContextUniqueness() {
    val id1 = TraceContext().traceId
    val id2 = TraceContext().traceId
    assertNotEquals(id1, id2)
  }

  @Test
  fun testNewSpanIdFormat() {
    val spanId = TraceContext.newSpanId()
    assertTrue(
      "spanId must be 16 lowercase hex chars",
      spanId.matches(Regex("[0-9a-f]{16}"))
    )
  }

  @Test
  fun testTraceparentFormat() {
    val ctx = TraceContext()
    val spanId = TraceContext.newSpanId()
    val header = ctx.traceparent(spanId)
    // Format: 00-{32hex}-{16hex}-01
    assertTrue(
      "traceparent must match W3C format",
      header.matches(Regex("00-[0-9a-f]{32}-[0-9a-f]{16}-01"))
    )
  }

  // MARK: - Telemetry: SHA-256 Tests

  @Test
  fun testSha256HexKnownValue() {
    // SHA-256("test") = 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
    assertEquals(
      "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
      sha256Hex("test")
    )
  }

  @Test
  fun testSha256HexEmptyString() {
    // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    assertEquals(
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      sha256Hex("")
    )
  }

  @Test
  fun testSha256HexReturnsSixtyFourLowercaseHexChars() {
    val hash = sha256Hex("idempotency-key-abc")
    assertTrue(
      "SHA-256 digest must be 64 lowercase hex chars",
      hash.matches(Regex("[0-9a-f]{64}"))
    )
  }

  @Test
  fun testSha256HexUniqueness() {
    assertNotEquals(sha256Hex("key-a"), sha256Hex("key-b"))
  }

  // MARK: - Telemetry: sanitizeForAudit Tests

  @Test
  fun testSanitizeHttpUrl() {
    assertEquals("[URL]", sanitizeForAudit("http://example.com/callback"))
  }

  @Test
  fun testSanitizeHttpsUrl() {
    assertEquals(
      "redirect to [URL]",
      sanitizeForAudit("redirect to https://pay.provider.com/auth?token=abc")
    )
  }

  @Test
  fun testSanitizeBearerToken() {
    val input = "Authorization: Bearer eyJhbGciOiJSUzI1NiJ9.payload.sig"
    val result = sanitizeForAudit(input)
    assertFalse("Raw token must not appear in output", result.contains("eyJhbGciOiJSUzI1NiJ9"))
    assertTrue(result.contains("Bearer [REDACTED]"))
  }

  @Test
  fun testSanitizeSortCode() {
    assertEquals("sort code [SORT-CODE]", sanitizeForAudit("sort code 20-00-01"))
  }

  @Test
  fun testSanitizeAccountNumber() {
    assertEquals("account [ACCOUNT]", sanitizeForAudit("account 12345678"))
  }

  @Test
  fun testSanitizeCleanTextUnchanged() {
    val clean = "PAYMENT_SUBMITTED"
    assertEquals(clean, sanitizeForAudit(clean))
  }

  @Test
  fun testSanitizeMultipleSensitiveValues() {
    val input = "url https://example.com sort 20-00-01 acc 12345678"
    val result = sanitizeForAudit(input)
    assertFalse(result.contains("https://"))
    assertFalse(result.contains("20-00-01"))
    assertFalse(result.contains("12345678"))
    assertTrue(result.contains("[URL]"))
    assertTrue(result.contains("[SORT-CODE]"))
    assertTrue(result.contains("[ACCOUNT]"))
  }

  // MARK: - Telemetry: TelemetryConfig Tests

  @Test
  fun testTelemetryConfigDefaultSamplingRate() {
    val config = TelemetryConfig()
    assertEquals(1.0, config.failedJourneySamplingRate, 0.0)
  }

  @Test
  fun testTelemetryConfigValidSamplingRates() {
    // Should not throw
    TelemetryConfig(failedJourneySamplingRate = 0.0)
    TelemetryConfig(failedJourneySamplingRate = 0.5)
    TelemetryConfig(failedJourneySamplingRate = 1.0)
  }

  @Test
  fun testTelemetryConfigInvalidSamplingRateAboveOne() {
    val exception = assertThrows(IllegalArgumentException::class.java) {
      TelemetryConfig(failedJourneySamplingRate = 1.1)
    }
    assertNotNull(exception)
  }

  @Test
  fun testTelemetryConfigInvalidSamplingRateNegative() {
    val exception = assertThrows(IllegalArgumentException::class.java) {
      TelemetryConfig(failedJourneySamplingRate = -0.1)
    }
    assertNotNull(exception)
  }

  // MARK: - Telemetry: Integration Tests (HTTP mock server)

  @Test
  fun testSubmitPaymentPropagatesTraceHeaders() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"

    var capturedTraceparent: String? = null
    var capturedTraceId: String? = null

    server.createContext("/api/v1/payments") { exchange ->
      capturedTraceparent = exchange.requestHeaders.getFirst("traceparent")
      capturedTraceId = exchange.requestHeaders.getFirst("X-Trace-Id")
      val body = """{"ok":true,"state":null}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, body.length.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }

    server.start()
    try {
      val client = MeridianClient(baseUrl, "test-session")
      runBlocking {
        client.submitPayment(
          recipientId = "rec-1",
          amountMinor = 1000,
          method = PaymentMethod.bank,
          idempotencyKey = "trace-test-key"
        )
      }
      assertNotNull("traceparent header must be set", capturedTraceparent)
      assertNotNull("X-Trace-Id header must be set", capturedTraceId)
      // traceparent must follow W3C format
      assertTrue(
        "traceparent must match W3C format",
        capturedTraceparent!!.matches(Regex("00-[0-9a-f]{32}-[0-9a-f]{16}-01"))
      )
      // X-Trace-Id must match the trace ID embedded in traceparent
      val traceIdFromHeader = capturedTraceparent!!.split("-")[1]
      assertEquals(traceIdFromHeader, capturedTraceId)
      // traceId must also match client.traceId
      assertEquals(client.traceId, capturedTraceId)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testSubmitPaymentEmitsTelemetryAndAudit() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"

    server.createContext("/api/v1/payments") { exchange ->
      val body = """{"ok":true,"state":null}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, body.length.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }

    server.start()
    try {
      val capturedEvents = mutableListOf<PaymentJourneyEvent>()
      val capturedAudit = mutableListOf<AuditLogEntry>()

      val config = TelemetryConfig(
        failedJourneySamplingRate = 1.0,
        onEvent = { capturedEvents.add(it) },
        onAudit = { capturedAudit.add(it) },
      )
      val client = MeridianClient(baseUrl, "test-session", config)
      val idempotencyKey = "audit-test-key-001"

      runBlocking {
        client.submitPayment(
          recipientId = "rec-1",
          amountMinor = 1000,
          method = PaymentMethod.card,
          idempotencyKey = idempotencyKey
        )
      }

      // Telemetry event assertions
      assertEquals(1, capturedEvents.size)
      val event = capturedEvents[0]
      assertEquals(client.traceId, event.traceId)
      assertTrue("scaInvoked must be true for card payment", event.scaInvoked)
      assertEquals(PaymentOutcome.SUCCESS, event.outcome)
      assertTrue("latency must be non-negative", event.latencyMs >= 0)

      // Audit entry assertions
      assertEquals(1, capturedAudit.size)
      val entry = capturedAudit[0]
      assertEquals(client.traceId, entry.traceId)
      assertEquals("PAYMENT_SUBMITTED", entry.action)
      assertEquals("card", entry.paymentMethod)
      assertEquals("success", entry.outcome)
      // Idempotency key must be hashed, not raw
      assertNotEquals(idempotencyKey, entry.hashedIdempotencyKey)
      assertEquals(sha256Hex(idempotencyKey), entry.hashedIdempotencyKey)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testSubmitPaymentBankPaymentScaNotInvoked() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"

    server.createContext("/api/v1/payments") { exchange ->
      val body = """{"ok":true,"state":null}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, body.length.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }

    server.start()
    try {
      val capturedEvents = mutableListOf<PaymentJourneyEvent>()
      val config = TelemetryConfig(onEvent = { capturedEvents.add(it) })
      val client = MeridianClient(baseUrl, "test-session", config)

      runBlocking {
        client.submitPayment(
          recipientId = "rec-1",
          amountMinor = 1000,
          method = PaymentMethod.bank,
          idempotencyKey = "bank-key-001"
        )
      }

      assertEquals(1, capturedEvents.size)
      assertFalse("scaInvoked must be false for bank payment", capturedEvents[0].scaInvoked)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testFailedJourneySamplingRateZeroSuppressesAudit() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"

    server.createContext("/api/v1/payments") { exchange ->
      // Return a declined response
      val body = """{"ok":false,"error":"Declined","code":"DECLINED"}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, body.length.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }

    server.start()
    try {
      val capturedAudit = mutableListOf<AuditLogEntry>()
      // Set sampling rate to 0: declined journeys must not be audited
      val config = TelemetryConfig(
        failedJourneySamplingRate = 0.0,
        onAudit = { capturedAudit.add(it) },
      )
      val client = MeridianClient(baseUrl, "test-session", config)

      runBlocking {
        client.submitPayment(
          recipientId = "rec-1",
          amountMinor = 1000,
          method = PaymentMethod.card,
          idempotencyKey = "declined-key-001"
        )
      }

      assertTrue("No audit entries expected when sampling rate is 0.0", capturedAudit.isEmpty())
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testAuditEntryIdempotencyKeyIsHashed() {
    val rawKey = "my-secret-idempotency-key"
    val expectedHash = sha256Hex(rawKey)
    assertNotEquals(rawKey, expectedHash)
    assertEquals(64, expectedHash.length)
    assertTrue(expectedHash.matches(Regex("[0-9a-f]{64}")))
  }
}
