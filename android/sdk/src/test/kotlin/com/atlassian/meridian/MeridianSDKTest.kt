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

      val traceparent = exchange.requestHeaders.getFirst("traceparent")
      assertNotNull(traceparent)
      assertTrue(TraceIds.isTraceparent(traceparent!!))

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
  fun testSanitizerRedactsPanAndIbanOnly() {
    val pan = "4111111111111111"
    val spacedPan = "4111 1111 1111 1111"
    val dashedPan = "4111-1111-1111-1111"
    val iban = "GB82WEST12345698765432"
    val spacedIban = "GB82 WEST 1234 5698 7654 32"
    val raw = "declined $iban $spacedIban card $pan / $spacedPan / $dashedPan"
    val cleaned = Sanitizer.sanitize(raw)
    assertFalse(cleaned.contains(pan))
    assertFalse(cleaned.contains("4111 1111"))
    assertFalse(cleaned.contains("4111-1111"))
    assertFalse(cleaned.contains(iban))
    assertFalse(cleaned.contains("WEST 1234"))
    assertTrue(cleaned.contains("[REDACTED_PAN]"))
    assertTrue(cleaned.contains("[REDACTED_IBAN]"))
    assertEquals("Insufficient balance", Sanitizer.sanitize("Insufficient balance"))
    assertEquals("4111111111111112", Sanitizer.sanitize("4111111111111112"))
    val attributes = Sanitizer.cleanAttributes(mapOf("pan" to pan, "note" to iban, "http.path" to "/payments"))
    assertFalse(attributes.containsKey("pan"))
    assertFalse(attributes.containsKey("note"))
    assertEquals("/payments", attributes["http.path"])
  }

  @Test
  fun testTraceparentSpansRedactionAndCorridorDegradation() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val captured = java.util.concurrent.ConcurrentHashMap<String, String>()
    val healthCalls = java.util.concurrent.atomic.AtomicInteger()

    fun write(exchange: com.sun.net.httpserver.HttpExchange, status: Int, body: String) {
      val traceparent = exchange.requestHeaders.getFirst("traceparent")
      assertNotNull(traceparent)
      assertTrue(TraceIds.isTraceparent(traceparent!!))
      assertEquals("trace-room", exchange.requestHeaders.getFirst("X-Rehearsal-Session"))
      captured[exchange.requestURI.path] = traceparent
      val bytes = body.toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(status, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }

    server.createContext("/api/v1/catalog") { exchange ->
      write(
        exchange,
        200,
        """{"demoDate":"2026-09-18","recipients":[{"id":"northline-studio","name":"Northline Studio","initials":"NS","detail":"Design tools","category":"Shopping","color":"#111111"}],"providers":[{"id":"adyen","name":"Adyen","description":"Card","methods":["card"]},{"id":"worldpay","name":"Worldpay","description":"Bank","methods":["bank"]}]}"""
      )
    }
    server.createContext("/api/v1/payments") { exchange ->
      val requestBody = exchange.requestBody.bufferedReader().readText()
      assertTrue(requestBody.contains("GB82WEST12345698765432"))
      assertEquals("idem-trace-1", exchange.requestHeaders.getFirst("Idempotency-Key"))
      write(
        exchange,
        422,
        """{"ok":false,"code":"DECLINED","error":"declined 4111 1111 1111 1111 for GB82 WEST 1234 5698 7654 32"}"""
      )
    }
    server.createContext("/api/v1/session/health") { exchange ->
      val attempt = healthCalls.incrementAndGet()
      val body = if (attempt == 1) {
        """{"status":"UP","connection":"connected","corridors":[{"id":"adyen-card","state":"healthy"},{"id":"worldpay-bank","state":"healthy"},{"id":"unlisted","state":"healthy"}]}"""
      } else {
        """{"status":"UP","connection":"connected","corridors":[{"id":"adyen-card","state":"degraded"},{"id":"worldpay-bank","state":"healthy"},{"id":"unlisted","provider":"unlisted","state":"down"}]}"""
      }
      write(exchange, 200, body)
    }
    server.createContext("/api/v1/state") { exchange ->
      write(exchange, 200, """{"version":1,"balance":1248050,"transactions":[],"budgets":[]}""")
    }
    server.start()

    try {
      val client = MeridianClient("http://127.0.0.1:${server.address.port}/api/v1", "trace-room")
      val catalog = runBlocking { client.getCatalog() }
      assertEquals(1, catalog.recipients.size)
      val parse = client.telemetry.spans().single { it.name == "catalog.parse" }
      assertTrue(parse.durationMillis >= 0)
      assertEquals("ok", parse.status)
      assertEquals("1", parse.attributes["recipientCount"])

      val biometric = runBlocking { client.resolveBiometricPrompt(sensorAvailable = false) }
      assertEquals("SCA_FALLBACK", biometric.code)
      val biometricSpan = client.telemetry.spans().single { it.name == "biometric.prompt" }
      assertEquals("error", biometricSpan.status)
      assertTrue(biometricSpan.durationMillis >= 0)

      val payment = runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 1000,
          method = PaymentMethod.card,
          note = "Rent GB82WEST12345698765432",
          idempotencyKey = "idem-trace-1",
        )
      }
      assertFalse(payment.ok)
      assertEquals("DECLINED", payment.code)
      assertFalse(payment.error.orEmpty().contains("4111"))
      assertFalse(payment.error.orEmpty().contains("WEST"))
      val gateway = client.telemetry.spans().single { it.name == "payment.gateway" }
      assertTrue(gateway.durationMillis >= 0)
      assertEquals("error", gateway.status)
      val paymentHeader = captured.getValue("/api/v1/payments")
      assertTrue(paymentHeader.contains(gateway.traceId))
      assertTrue(paymentHeader.contains(gateway.spanId))

      runBlocking { client.getState() }
      val first = runBlocking { client.checkSessionHealth() }
      assertEquals("connected", first.connection)
      assertTrue(first.corridors.any { it.id == "adyen-card" && it.state == "healthy" })
      assertTrue(first.corridors.any { it.id == "corridor" && it.state == "healthy" })
      val second = runBlocking { client.checkSessionHealth() }
      assertEquals("degraded", second.connection)
      assertTrue(second.corridors.any { it.id == "adyen-card" && it.state == "degraded" })

      val required = listOf("/api/v1/catalog", "/api/v1/payments", "/api/v1/session/health", "/api/v1/state")
      required.forEach { path -> assertTrue(TraceIds.isTraceparent(captured.getValue(path))) }
      assertEquals(captured.getValue("/api/v1/catalog").split("-")[1], parse.traceId)

      val dump = (client.telemetry.events() + client.telemetry.spans().map {
        TelemetryEvent(it.name, it.status, it.name, it.attributes.values.joinToString(" "), it.traceId, it.spanId, it.attributes)
      }).joinToString(" ") { "${it.code} ${it.stage} ${it.message} ${it.attributes}" }
      assertTrue(dump.contains("SCA_FALLBACK"))
      assertTrue(dump.contains("biometric"))
      assertTrue(dump.contains("DECLINED"))
      assertTrue(dump.contains("gateway"))
      assertTrue(dump.contains("corridor.degraded") || dump.contains("CORRIDOR_DEGRADED"))
      assertTrue(dump.contains("adyen-card"))
      assertFalse(dump.contains("4111111111111111"))
      assertFalse(dump.contains("4111 1111 1111 1111"))
      assertFalse(dump.contains("GB82WEST12345698765432"))
      assertFalse(dump.contains("GB82 WEST"))
      assertFalse(dump.contains("GB82WEST12345698765432"))
      assertFalse(dump.contains("unlisted"))
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testPeriodicSessionHealthRecordsDegradationOnce() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val calls = java.util.concurrent.atomic.AtomicInteger()
    server.createContext("/api/v1/session/health") { exchange ->
      val attempt = calls.incrementAndGet()
      val body = if (attempt == 1) {
        """{"status":"UP","connection":"connected","corridors":[{"id":"worldpay-bank","state":"healthy"}]}"""
      } else {
        """{"status":"UP","corridors":[{"id":"bank","state":"degraded"}]}"""
      }
      val bytes = body.toByteArray()
      exchange.sendResponseHeaders(200, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:${server.address.port}/api/v1", "trace-room")
      val updates = java.util.concurrent.atomic.AtomicInteger()
      val scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Default)
      val job = client.startSessionHealthChecks(scope, intervalMillis = 40) { updates.incrementAndGet() }
      val deadline = System.currentTimeMillis() + 2000
      while (updates.get() < 2 && System.currentTimeMillis() < deadline) {
        Thread.sleep(20)
      }
      job.cancel()
      assertTrue(updates.get() >= 2)
      val degraded = client.telemetry.events().filter { it.name == "corridor.degraded" }
      assertEquals(1, degraded.size)
      assertEquals("worldpay-bank", degraded.single().attributes["corridorId"])
      assertEquals("health", degraded.single().stage)
      assertTrue(client.telemetry.events().any { it.name == "connection.state" && it.attributes["connection"] == "degraded" })
    } finally {
      server.stop(0)
    }
  }
}
