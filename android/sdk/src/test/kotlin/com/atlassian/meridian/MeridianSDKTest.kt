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

  // MARK: - Telemetry: hashIdempotencyKey Tests

  @Test
  fun testHashIdempotencyKeyLength() {
    val hash = hashIdempotencyKey("some-idempotency-key")
    assertEquals(64, hash.length)
  }

  @Test
  fun testHashIdempotencyKeyIsHex() {
    val hash = hashIdempotencyKey("some-idempotency-key")
    assertTrue("Hash should be lowercase hex", hash.all { it in '0'..'9' || it in 'a'..'f' })
  }

  @Test
  fun testHashIdempotencyKeyDeterministic() {
    val key = "idempotency-abc-123"
    assertEquals(hashIdempotencyKey(key), hashIdempotencyKey(key))
  }

  @Test
  fun testHashIdempotencyKeyUnique() {
    val hash1 = hashIdempotencyKey("key-one")
    val hash2 = hashIdempotencyKey("key-two")
    assertNotEquals(hash1, hash2)
  }

  @Test
  fun testHashIdempotencyKeyKnownValue() {
    // SHA-256("test") is a well-known value
    val expected = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
    assertEquals(expected, hashIdempotencyKey("test"))
  }

  // MARK: - Telemetry: sanitizeForLog Tests

  @Test
  fun testSanitizeForLogQueryParamsRedacted() {
    val input = "https://provider.example.com/callback?token=abc123&session=xyz"
    val result = sanitizeForLog(input)
    assertTrue("Query params should be redacted", result.contains("?[REDACTED]"))
    assertFalse("Raw token should not appear", result.contains("abc123"))
  }

  @Test
  fun testSanitizeForLogBearerTokenRedacted() {
    val input = "Authorization: bearer eyJhbGciOiJSUzI1NiJ9.payload.sig"
    val result = sanitizeForLog(input)
    assertTrue("Bearer should be retained as keyword", result.contains("bearer"))
    assertFalse("Raw token value should not appear", result.contains("eyJhbGciOiJSUzI1NiJ9"))
    assertTrue("Redaction marker should appear", result.contains("[REDACTED]"))
  }

  @Test
  fun testSanitizeForLogPasswordRedacted() {
    val input = "password=s3cr3tP@ss!"
    val result = sanitizeForLog(input)
    assertTrue(result.contains("password"))
    assertFalse(result.contains("s3cr3tP@ss!"))
    assertTrue(result.contains("[REDACTED]"))
  }

  @Test
  fun testSanitizeForLogApiKeyRedacted() {
    val input = "apikey=live_12345abcde"
    val result = sanitizeForLog(input)
    assertFalse(result.contains("live_12345abcde"))
    assertTrue(result.contains("[REDACTED]"))
  }

  @Test
  fun testSanitizeForLogPlainTextUnchanged() {
    val input = "payment completed for recipient northline-studio"
    assertEquals(input, sanitizeForLog(input))
  }

  // MARK: - Telemetry: TraceContext Tests

  @Test
  fun testTraceContextTraceIdIs32Chars() {
    val ctx = TraceContext.generate()
    assertEquals(32, ctx.traceId.length)
  }

  @Test
  fun testTraceContextSpanIdIs16Chars() {
    val ctx = TraceContext.generate()
    assertEquals(16, ctx.spanId.length)
  }

  @Test
  fun testTraceContextIdsAreLowercaseHex() {
    val ctx = TraceContext.generate()
    assertTrue(ctx.traceId.all { it in '0'..'9' || it in 'a'..'f' })
    assertTrue(ctx.spanId.all { it in '0'..'9' || it in 'a'..'f' })
  }

  @Test
  fun testTraceparentFormat() {
    val ctx = TraceContext.generate()
    val parts = ctx.traceparent.split("-")
    assertEquals(4, parts.size)
    assertEquals("00", parts[0])
    assertEquals(32, parts[1].length)
    assertEquals(16, parts[2].length)
    assertEquals("01", parts[3])
  }

  @Test
  fun testTraceContextUniqueness() {
    val ctx1 = TraceContext.generate()
    val ctx2 = TraceContext.generate()
    assertNotEquals(ctx1.traceId, ctx2.traceId)
    assertNotEquals(ctx1.spanId, ctx2.spanId)
  }

  // MARK: - Telemetry: TelemetryConfig Tests

  @Test
  fun testTelemetryConfigDefaultRate() {
    val config = TelemetryConfig()
    assertEquals(1.0, config.failedJourneySampleRate, 0.0)
  }

  @Test
  fun testTelemetryConfigZeroRateValid() {
    val config = TelemetryConfig(failedJourneySampleRate = 0.0)
    assertEquals(0.0, config.failedJourneySampleRate, 0.0)
  }

  @Test
  fun testTelemetryConfigHalfRateValid() {
    val config = TelemetryConfig(failedJourneySampleRate = 0.5)
    assertEquals(0.5, config.failedJourneySampleRate, 0.0)
  }

  @Test(expected = IllegalArgumentException::class)
  fun testTelemetryConfigRateTooHighThrows() {
    TelemetryConfig(failedJourneySampleRate = 1.1)
  }

  @Test(expected = IllegalArgumentException::class)
  fun testTelemetryConfigRateNegativeThrows() {
    TelemetryConfig(failedJourneySampleRate = -0.1)
  }

  // MARK: - Telemetry: AuditLogEntry Tests

  @Test
  fun testAuditLogEntryToLogLineContainsRequiredFields() {
    val entry = AuditLogEntry(
      traceId = "abc123def456abc1",
      timestamp = "2026-09-18T12:00:00Z",
      event = "payment.completed",
      outcome = "success",
      hashedIdempotencyKey = "deadbeef",
      latencyMs = 142,
      amountMinor = 1000,
      paymentMethod = "card",
    )
    val line = entry.toLogLine()
    assertTrue(line.contains("trace=abc123def456abc1"))
    assertTrue(line.contains("event=payment.completed"))
    assertTrue(line.contains("outcome=success"))
    assertTrue(line.contains("idem_hash=deadbeef"))
    assertTrue(line.contains("latency_ms=142"))
    assertTrue(line.contains("amount_pence=1000"))
    assertTrue(line.contains("method=card"))
  }

  @Test
  fun testAuditLogEntryToLogLineOmitsNullFields() {
    val entry = AuditLogEntry(
      traceId = "abc123",
      timestamp = "2026-09-18T12:00:00Z",
      event = "payment.completed",
    )
    val line = entry.toLogLine()
    assertFalse(line.contains("outcome="))
    assertFalse(line.contains("idem_hash="))
    assertFalse(line.contains("latency_ms="))
  }

  @Test
  fun testAuditLogEntryDoesNotContainRawIdempotencyKey() {
    val rawKey = "super-secret-idempotency-key-9876"
    val entry = AuditLogEntry(
      traceId = "abc",
      timestamp = "2026-09-18T12:00:00Z",
      event = "payment.completed",
      hashedIdempotencyKey = hashIdempotencyKey(rawKey),
    )
    val line = entry.toLogLine()
    assertFalse("Raw idempotency key must not appear in log line", line.contains(rawKey))
  }

  @Test
  fun testAuditLogEntryScaInvokedIncluded() {
    val entry = AuditLogEntry(
      traceId = "abc",
      timestamp = "2026-09-18T12:00:00Z",
      event = "payment.completed",
      scaInvoked = true,
      methodCount = 2,
      catalogAgeDays = 5L,
    )
    val line = entry.toLogLine()
    assertTrue(line.contains("sca=true"))
    assertTrue(line.contains("method_count=2"))
    assertTrue(line.contains("catalog_age_days=5"))
  }

  // MARK: - Telemetry: Integration Tests (mock HTTP server)

  @Test
  fun testTelemetryEmittedOnSuccessfulPayment() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"

    server.createContext("/api/v1/payments") { exchange ->
      val responseBody = """{"ok":true,"state":{"version":1,"balance":1000,"transactions":[],"budgets":[]}}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, responseBody.length.toLong())
      exchange.responseBody.write(responseBody.toByteArray())
      exchange.close()
    }
    server.start()

    val capturedEntries = mutableListOf<AuditLogEntry>()
    val config = TelemetryConfig(onEntry = { capturedEntries.add(it) })

    try {
      val client = MeridianClient(baseUrl, "test-session", config)
      runBlocking {
        client.submitPayment("rec-1", 500, PaymentMethod.card, idempotencyKey = "key-success")
      }
      assertEquals("Exactly one audit entry should be emitted", 1, capturedEntries.size)
      val entry = capturedEntries[0]
      assertEquals("payment.completed", entry.event)
      assertEquals("success", entry.outcome)
      assertEquals("card", entry.paymentMethod)
      assertEquals(500, entry.amountMinor)
      assertNotNull("Hashed idempotency key must be present", entry.hashedIdempotencyKey)
      assertEquals(64, entry.hashedIdempotencyKey?.length)
      assertFalse("Raw idempotency key must not appear", entry.toLogLine().contains("key-success"))
      assertNotNull(entry.latencyMs)
      assertTrue("Latency must be non-negative", entry.latencyMs!! >= 0)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testTelemetryEmittedOnDeclinedPayment() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"

    server.createContext("/api/v1/payments") { exchange ->
      val responseBody = """{"ok":false,"error":"Card declined","code":"DECLINED"}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, responseBody.length.toLong())
      exchange.responseBody.write(responseBody.toByteArray())
      exchange.close()
    }
    server.start()

    val capturedEntries = mutableListOf<AuditLogEntry>()
    val config = TelemetryConfig(onEntry = { capturedEntries.add(it) })

    try {
      val client = MeridianClient(baseUrl, "test-session", config)
      runBlocking {
        client.submitPayment("rec-1", 1000, PaymentMethod.card, idempotencyKey = "key-decline")
      }
      assertEquals(1, capturedEntries.size)
      assertEquals("declined", capturedEntries[0].outcome)
      assertFalse("Raw key must not appear", capturedEntries[0].toLogLine().contains("key-decline"))
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testTraceIdPropagatedAsHeader() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"

    var capturedTraceHeader: String? = null
    server.createContext("/api/v1/payments") { exchange ->
      capturedTraceHeader = exchange.requestHeaders.getFirst("X-Trace-ID")
      val responseBody = """{"ok":true,"state":{"version":1,"balance":1000,"transactions":[],"budgets":[]}}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, responseBody.length.toLong())
      exchange.responseBody.write(responseBody.toByteArray())
      exchange.close()
    }
    server.start()

    try {
      val client = MeridianClient(baseUrl, "test-session")
      runBlocking {
        client.submitPayment("rec-1", 100, PaymentMethod.bank, idempotencyKey = "key-trace")
      }
      assertNotNull("X-Trace-ID header must be sent", capturedTraceHeader)
      assertTrue(
        "X-Trace-ID must start with '00-'",
        capturedTraceHeader!!.startsWith("00-"),
      )
      val parts = capturedTraceHeader!!.split("-")
      assertEquals("traceparent must have 4 parts", 4, parts.size)
      assertEquals(32, parts[1].length)
      assertEquals(16, parts[2].length)
      assertEquals("01", parts[3])
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testTelemetrySuppressedWhenSamplingRateZero() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"

    server.createContext("/api/v1/payments") { exchange ->
      val responseBody = """{"ok":false,"error":"Declined","code":"DECLINED"}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, responseBody.length.toLong())
      exchange.responseBody.write(responseBody.toByteArray())
      exchange.close()
    }
    server.start()

    val capturedEntries = mutableListOf<AuditLogEntry>()
    // rate=0.0 means no failed journeys should be logged
    val config = TelemetryConfig(failedJourneySampleRate = 0.0, onEntry = { capturedEntries.add(it) })

    try {
      val client = MeridianClient(baseUrl, "test-session", config)
      runBlocking {
        client.submitPayment("rec-1", 100, PaymentMethod.card, idempotencyKey = "key-suppressed")
      }
      assertEquals("No entries should be emitted when sample rate is 0.0", 0, capturedEntries.size)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testSuccessAlwaysLoggedRegardlessOfSamplingRate() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"

    server.createContext("/api/v1/payments") { exchange ->
      val responseBody = """{"ok":true,"state":{"version":1,"balance":1000,"transactions":[],"budgets":[]}}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, responseBody.length.toLong())
      exchange.responseBody.write(responseBody.toByteArray())
      exchange.close()
    }
    server.start()

    val capturedEntries = mutableListOf<AuditLogEntry>()
    // rate=0.0 for failed journeys — but success must always log
    val config = TelemetryConfig(failedJourneySampleRate = 0.0, onEntry = { capturedEntries.add(it) })

    try {
      val client = MeridianClient(baseUrl, "test-session", config)
      runBlocking {
        client.submitPayment("rec-1", 100, PaymentMethod.card, idempotencyKey = "key-success")
      }
      assertEquals("Successful journeys must always be logged", 1, capturedEntries.size)
      assertEquals("success", capturedEntries[0].outcome)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testScaInvokedTrueForBankMethod() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"

    server.createContext("/api/v1/payments") { exchange ->
      val responseBody = """{"ok":true,"state":{"version":1,"balance":1000,"transactions":[],"budgets":[]}}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, responseBody.length.toLong())
      exchange.responseBody.write(responseBody.toByteArray())
      exchange.close()
    }
    server.start()

    val capturedEntries = mutableListOf<AuditLogEntry>()
    val config = TelemetryConfig(onEntry = { capturedEntries.add(it) })

    try {
      val client = MeridianClient(baseUrl, "test-session", config)
      runBlocking {
        client.submitPayment("rec-1", 100, PaymentMethod.bank, idempotencyKey = "key-sca")
      }
      assertEquals(1, capturedEntries.size)
      assertEquals(true, capturedEntries[0].scaInvoked)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testCatalogEnrichmentInTelemetry() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"

    server.createContext("/api/v1/catalog") { exchange ->
      val responseBody = """
        {
          "demoDate": "2026-09-01",
          "recipients": [],
          "providers": [
            {"id": "adyen", "name": "Adyen", "description": "Card", "methods": ["card"]},
            {"id": "worldpay", "name": "Worldpay", "description": "Bank", "methods": ["bank"]}
          ]
        }
      """.trimIndent()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, responseBody.length.toLong())
      exchange.responseBody.write(responseBody.toByteArray())
      exchange.close()
    }
    server.createContext("/api/v1/payments") { exchange ->
      val responseBody = """{"ok":true,"state":{"version":1,"balance":1000,"transactions":[],"budgets":[]}}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, responseBody.length.toLong())
      exchange.responseBody.write(responseBody.toByteArray())
      exchange.close()
    }
    server.start()

    val capturedEntries = mutableListOf<AuditLogEntry>()
    val config = TelemetryConfig(onEntry = { capturedEntries.add(it) })

    try {
      val client = MeridianClient(baseUrl, "test-session", config)
      runBlocking {
        client.getCatalog()
        client.submitPayment("rec-1", 100, PaymentMethod.card, idempotencyKey = "key-catalog")
      }
      assertEquals(1, capturedEntries.size)
      val entry = capturedEntries[0]
      assertEquals(2, entry.methodCount)
      assertNotNull("catalogAgeDays should be set after getCatalog", entry.catalogAgeDays)
      assertTrue("catalogAgeDays should be non-negative", entry.catalogAgeDays!! >= 0)
    } finally {
      server.stop(0)
    }
  }
}
