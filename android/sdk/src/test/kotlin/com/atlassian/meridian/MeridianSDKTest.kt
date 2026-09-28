package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.nio.charset.StandardCharsets

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
  fun testIbanMod97() {
    assertTrue(isValidIban("GB82WEST12345698765432"))
    assertTrue(isValidIban("GB82 WEST 1234 5698 7654 32"))
    assertTrue(isValidIban("de89 3704 0044 0532 0130 00"))
    assertTrue(isValidIban("FR1420041010050500013M02606"))
    assertFalse(isValidIban("GB82WEST12345698765433"))
    assertFalse(isValidIban("DE89370400440532013001"))
    assertFalse(isValidIban(""))
    assertFalse(isValidIban("GB82"))
  }

  @Test
  fun testUuidV4IdempotencyKey() {
    val key = makeIdempotencyKey()
    assertTrue(isUuidV4(key))
    assertFalse(isUuidV4("not-a-uuid"))
    assertFalse(isUuidV4("aaaaaaaa-bbbb-1ccc-8ddd-eeeeeeeeeeee"))
    assertEquals(key, nextIdempotencyKey(key, retain = true))
    assertNotEquals(key, nextIdempotencyKey(key, retain = false))
  }

  @Test
  fun testQuoteLockCountdown() {
    val lockedAt = 1_700_000_000_000L
    val quote = FxQuote("q-1", "GBP", "EUR", 1000, 1170, "1.1700", 60, null)
    val lock = lockQuote(quote, lockedAt)
    assertEquals(60, lock.remainingSeconds(lockedAt))
    assertFalse(lock.isExpired(lockedAt))
    assertEquals(0, lock.remainingSeconds(lockedAt + 60_000))
    assertTrue(lock.isExpired(lockedAt + 60_000))
    val shorter = lockQuote(quote.copy(serverExpiresAtEpochMs = lockedAt + 15_000), lockedAt)
    assertEquals(lockedAt + 15_000, shorter.expiresAtEpochMs)
    assertEquals(15, shorter.remainingSeconds(lockedAt))
  }

  @Test
  fun testSubmissionGate() {
    val lockedAt = 1_700_000_000_000L
    val lock = lockQuote(FxQuote("q-1", "GBP", "EUR", 1000, 1170, "1.1700", 60, null), lockedAt)
    assertNull(
      submissionBlockReason(PayCurrency.EUR, PaymentMethod.bank, "GB82WEST12345698765432", lock, 1000, lockedAt)
    )
    assertEquals(
      QUOTE_EXPIRED_MESSAGE,
      submissionBlockReason(PayCurrency.EUR, PaymentMethod.bank, "GB82WEST12345698765432", lock, 1000, lockedAt + 60_000)
    )
    assertEquals(
      INVALID_IBAN_MESSAGE,
      submissionBlockReason(PayCurrency.GBP, PaymentMethod.bank, "GB82WEST12345698765433", null, 1000, lockedAt)
    )
    assertNull(submissionBlockReason(PayCurrency.GBP, PaymentMethod.card, "", null, 1000, lockedAt))
    assertEquals(
      QUOTE_EXPIRED_MESSAGE,
      submissionBlockReason(PayCurrency.EUR, PaymentMethod.card, "GB82WEST12345698765432", lock, 999, lockedAt)
    )
  }

  @Test
  fun testFxQuoteJson() {
    val node = mapper.readTree(
      """{"quoteId":"q-9","amountMinor":2500,"targetAmountMinor":2925,"rate":1.17,"expiresInSeconds":60,"expiresAt":"2026-09-28T12:00:00Z"}"""
    )
    val quote = fxQuoteFromJson(node)
    assertEquals("q-9", quote.quoteId)
    assertEquals(2500, quote.sourceAmountMinor)
    assertEquals(2925, quote.targetAmountMinor)
    assertEquals("1.17", quote.rate)
    assertNotNull(quote.serverExpiresAtEpochMs)
  }

  @Test
  fun testGatewayRetryKeepsKeyAndMethod() = runBlocking {
    val keys = mutableListOf<String>()
    val methods = mutableListOf<PaymentMethod>()
    val delays = mutableListOf<Long>()
    var calls = 0
    val key = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    val result = submitPaymentWithRetry(key, PaymentMethod.bank, sleep = { delays += it }) { attemptKey, attemptMethod ->
      calls += 1
      keys += attemptKey
      methods += attemptMethod
      if (calls < 3) throw MeridianError.HttpError(if (calls == 1) 502 else 504, "gateway")
      PaymentResponse(ok = true, paymentId = "pay-1")
    }
    assertTrue(result.ok)
    assertEquals(listOf(key, key, key), keys)
    assertEquals(listOf(PaymentMethod.bank, PaymentMethod.bank, PaymentMethod.bank), methods)
    assertEquals(listOf(200L, 400L), delays)
  }

  @Test
  fun testNonGatewayStatusesDoNotRetry() = runBlocking {
    for (status in listOf(400, 409, 422, 503)) {
      var calls = 0
      val delays = mutableListOf<Long>()
      try {
        submitPaymentWithRetry("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", PaymentMethod.card, sleep = { delays += it }) { _, _ ->
          calls += 1
          throw MeridianError.HttpError(status, "stop")
        }
        fail("expected HTTP $status")
      } catch (error: MeridianError.HttpError) {
        assertEquals(status, error.statusCode)
        assertEquals(1, calls)
        assertTrue(delays.isEmpty())
      }
    }
  }

  @Test
  fun testGatewayRetriesStopAfterThreeAttempts() = runBlocking {
    var calls = 0
    val delays = mutableListOf<Long>()
    try {
      submitPaymentWithRetry("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", PaymentMethod.bank, sleep = { delays += it }) { _, method ->
        calls += 1
        check(method == PaymentMethod.bank)
        throw MeridianError.HttpError(502, "gateway")
      }
      fail("expected exhausted gateway")
    } catch (error: MeridianError.HttpError) {
      assertEquals(502, error.statusCode)
      assertEquals(3, calls)
      assertEquals(listOf(200L, 400L), delays)
    }
    assertEquals(200L, gatewayBackoffMilliseconds(1))
    assertEquals(400L, gatewayBackoffMilliseconds(2))
    assertEquals(800L, gatewayBackoffMilliseconds(3))
  }

  @Test
  fun testOrchestratorRetriesSameKeyOverHttp() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"
    val keys = mutableListOf<String>()
    val sessions = mutableListOf<String>()
    val methods = mutableListOf<String>()
    var hits = 0
    server.createContext("/api/v1/payments") { exchange ->
      hits += 1
      keys += exchange.requestHeaders.getFirst("Idempotency-Key")
      sessions += exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      val body = String(exchange.requestBody.readBytes(), StandardCharsets.UTF_8)
      methods += Regex("\"method\"\\s*:\\s*\"([^\"]+)\"").find(body)?.groupValues?.get(1) ?: ""
      val status = if (hits < 3) 502 else 200
      val responseBody = if (hits < 3) "bad gateway" else """{"ok":true,"paymentId":"tx-9"}"""
      exchange.sendResponseHeaders(status, responseBody.toByteArray(StandardCharsets.UTF_8).size.toLong())
      exchange.responseBody.write(responseBody.toByteArray(StandardCharsets.UTF_8))
      exchange.close()
    }
    server.createContext("/api/v1/fx/quote") { exchange ->
      assertEquals("POST", exchange.requestMethod)
      assertEquals("quote-room", exchange.requestHeaders.getFirst("X-Rehearsal-Session"))
      val responseBody = """{"quoteId":"q1","amountMinor":1000,"targetAmountMinor":1170,"rate":"1.1700","sourceCurrency":"GBP","targetCurrency":"EUR","expiresInSeconds":60}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, responseBody.toByteArray(StandardCharsets.UTF_8).size.toLong())
      exchange.responseBody.write(responseBody.toByteArray(StandardCharsets.UTF_8))
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient(baseUrl, "quote-room")
      val key = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
      val response = runBlocking {
        submitPaymentWithRetry(key, PaymentMethod.bank, sleep = {}) { attemptKey, attemptMethod ->
          client.submitPayment(
            recipientId = "rec-1",
            amountMinor = 1000,
            method = attemptMethod,
            idempotencyKey = attemptKey,
          )
        }
      }
      assertTrue(response.ok)
      assertEquals(3, hits)
      assertEquals(listOf(key, key, key), keys)
      assertEquals(listOf("quote-room", "quote-room", "quote-room"), sessions)
      assertEquals(listOf("bank", "bank", "bank"), methods)
      val quote = runBlocking { client.requestFxQuote(1000) }
      assertEquals("q1", quote.quoteId)
      assertEquals(1170, quote.targetAmountMinor)
      assertEquals("1.1700", quote.rate)
    } finally {
      server.stop(0)
    }
  }
}
