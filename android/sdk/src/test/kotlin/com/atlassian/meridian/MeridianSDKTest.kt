package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.net.InetSocketAddress
import java.time.Instant

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
  fun testScaVerificationTokenAndBudget() {
    assertEquals(300L, Sca.LATENCY_BUDGET_MS)
    val started = System.nanoTime()
    val token = scaVerificationToken("cht_european_1")
    assertEquals("sca_v1_7e0e3ab4c6566286", token)
    assertTrue((System.nanoTime() - started) / 1_000_000 < 300)
    assertEquals(token, scaVerificationToken("cht_european_1"))
  }

  @Test
  fun testScaExpiryBoundary() {
    val body = PaymentResponse(
      ok = false,
      code = Sca.CODE,
      challengeToken = "cht_european_1",
      challengeExpiresAt = "2026-10-04T09:30:00Z",
    )
    val ready = assessSca(202, body)
    assertTrue(ready is ScaAssessment.Ready)
    val challenge = (ready as ScaAssessment.Ready).challenge
    assertFalse(challenge.isExpired(Instant.parse("2026-10-04T09:29:59Z")))
    assertTrue(challenge.isExpired(Instant.parse("2026-10-04T09:30:00Z")))
    assertTrue(assessSca(202, PaymentResponse(ok = false, code = "PAYMENT_PENDING")) is ScaAssessment.NotRequired)
    assertTrue(
      assessSca(200, body) is ScaAssessment.NotRequired
    )
    assertTrue(assessSca(202, PaymentResponse(ok = false, code = Sca.CODE)) is ScaAssessment.Malformed)
  }

  @Test
  fun testScaResubmitsOriginalIdempotencyKey() {
    val prompts = mutableListOf<String>()
    val script = scaScript(
      listOf(
        202 to scaPayload("cht_european_1", "2099-01-01T00:00:00.000Z"),
        200 to """{"ok":true,"paymentId":"tx-sca"}""",
      )
    )
    withScaServer(script) { base ->
      val client = MeridianClient(base, "sca-room", ScaChallengeHandler {
        prompts.add(it)
        true
      })
      val paid = runBlocking {
        client.submitPayment("northline-studio", 2599, PaymentMethod.card, "European rehearsal", idempotencyKey = "idem-sca-1")
      }
      assertTrue(paid.ok)
      assertEquals(listOf(Sca.EUROPEAN_PAYMENT), prompts)
      assertEquals(2, script.calls.size)
      val proof = scaVerificationToken("cht_european_1")
      script.calls.forEach { call ->
        assertEquals("sca-room", call["session"])
        assertEquals("idem-sca-1", call["key"])
      }
      assertEquals("", script.calls[0]["verification"])
      assertEquals(proof, script.calls[1]["verification"])
      assertEquals(script.calls[0]["body"], script.calls[1]["body"])
      assertFalse(script.calls[1]["body"]!!.contains("challengeVerification"))
    }
  }

  @Test
  fun testScaExpiredDoesNotPromptOrResubmit() {
    val prompts = mutableListOf<String>()
    val script = scaScript(listOf(202 to scaPayload("cht_european_1", "2020-01-01T00:00:00Z")))
    withScaServer(script) { base ->
      val client = MeridianClient(base, "sca-room", ScaChallengeHandler {
        prompts.add(it)
        true
      })
      val error = assertThrows(MeridianError.ScaReinitiate::class.java) {
        runBlocking {
          client.submitPayment("northline-studio", 2599, PaymentMethod.card, idempotencyKey = "idem-sca-1")
        }
      }
      assertEquals(Sca.EXPIRED, error.message)
      assertTrue(prompts.isEmpty())
      assertEquals(1, script.calls.size)
    }
  }

  @Test
  fun testScaCancelKeepsSingleRequest() {
    val script = scaScript(listOf(202 to scaPayload("cht_european_1", "2099-01-01T00:00:00Z")))
    withScaServer(script) { base ->
      val client = MeridianClient(base, "sca-room", ScaChallengeHandler { false })
      val error = assertThrows(MeridianError.ScaCancelled::class.java) {
        runBlocking {
          client.submitPayment("northline-studio", 100, PaymentMethod.bank, idempotencyKey = "idem-sca-1")
        }
      }
      assertEquals(Sca.CANCELLED, error.message)
      assertEquals(1, script.calls.size)
      assertEquals("", script.calls[0]["verification"])
    }
  }

  @Test
  fun testScaExpiresDuringBiometric() {
    val times = ArrayDeque(
      listOf(Instant.parse("2026-10-04T09:00:00Z"), Instant.parse("2026-10-04T09:30:00Z"))
    )
    var prompts = 0
    val script = scaScript(listOf(202 to scaPayload("cht_european_1", "2026-10-04T09:30:00Z")))
    withScaServer(script) { base ->
      val client = MeridianClient(
        base,
        "sca-room",
        ScaChallengeHandler {
          prompts += 1
          true
        },
        clock = { times.removeFirst() },
      )
      val error = assertThrows(MeridianError.ScaReinitiate::class.java) {
        runBlocking {
          client.submitPayment("northline-studio", 100, PaymentMethod.card, idempotencyKey = "idem-sca-1")
        }
      }
      assertEquals(Sca.EXPIRED, error.message)
      assertEquals(1, prompts)
      assertEquals(1, script.calls.size)
    }
  }

  @Test
  fun testScaMalformedDoesNotPrompt() {
    var prompts = 0
    val script = scaScript(listOf(202 to """{"ok":false,"code":"SCA_STEP_UP_REQUIRED","error":"missing token"}"""))
    withScaServer(script) { base ->
      val client = MeridianClient(base, "sca-room", ScaChallengeHandler {
        prompts += 1
        true
      })
      assertThrows(MeridianError.ScaMalformed::class.java) {
        runBlocking {
          client.submitPayment("northline-studio", 100, PaymentMethod.card, idempotencyKey = "idem-sca-1")
        }
      }
      assertEquals(0, prompts)
      assertEquals(1, script.calls.size)
    }
  }

  @Test
  fun testRepeatedScaChallengeAsksToRestart() {
    var prompts = 0
    val script = scaScript(
      listOf(
        202 to scaPayload("cht_european_1", "2099-01-01T00:00:00Z"),
        202 to scaPayload("cht_european_1", "2099-01-01T00:00:00Z"),
      )
    )
    withScaServer(script) { base ->
      val client = MeridianClient(base, "sca-room", ScaChallengeHandler {
        prompts += 1
        true
      })
      val error = assertThrows(MeridianError.ScaReinitiate::class.java) {
        runBlocking {
          client.submitPayment("northline-studio", 100, PaymentMethod.card, idempotencyKey = "idem-sca-1")
        }
      }
      assertEquals(Sca.REJECTED, error.message)
      assertEquals(1, prompts)
      assertEquals(2, script.calls.size)
      assertEquals(scaVerificationToken("cht_european_1"), script.calls[1]["verification"])
    }
  }

  private class ScaScript(val responses: ArrayDeque<Pair<Int, String>>) {
    val calls = mutableListOf<Map<String, String>>()
  }

  private fun scaPayload(token: String, expiry: String) =
    """{"ok":false,"code":"SCA_STEP_UP_REQUIRED","error":"Strong customer authentication required","challengeToken":"$token","challengeExpiresAt":"$expiry"}"""

  private fun scaScript(responses: List<Pair<Int, String>>) = ScaScript(ArrayDeque(responses))

  private fun withScaServer(script: ScaScript, block: (String) -> Unit) {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.createContext("/api/v1/payments") { exchange ->
      val body = exchange.requestBody.readBytes().toString(Charsets.UTF_8)
      script.calls.add(
        mapOf(
          "session" to (exchange.requestHeaders.getFirst("X-Rehearsal-Session") ?: ""),
          "key" to (exchange.requestHeaders.getFirst("Idempotency-Key") ?: ""),
          "verification" to (exchange.requestHeaders.getFirst(Sca.HEADER) ?: ""),
          "body" to body,
        )
      )
      val (status, payload) = script.responses.removeFirst()
      val bytes = payload.toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(status, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.start()
    try {
      block("http://127.0.0.1:${server.address.port}/api/v1")
    } finally {
      server.stop(0)
    }
  }
}
