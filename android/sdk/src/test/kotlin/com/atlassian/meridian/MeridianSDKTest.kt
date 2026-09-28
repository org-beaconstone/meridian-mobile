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
      assertEquals(202, response1.statusCode)
      assertFalse(response1.body.ok)
      assertEquals("PAYMENT_PENDING", response1.body.code)
      assertEquals("tx-123", response1.body.paymentId)

      // Second call with same key returns 200 (success)
      val response2 = runBlocking {
        client.submitPayment(
          recipientId = "rec-1",
          amountMinor = 10000,
          method = PaymentMethod.card,
          idempotencyKey = "idempotency-key-1"
        )
      }
      assertEquals(200, response2.statusCode)
      assertTrue(response2.body.ok)

      // Verify only one idempotency key was used
      assertEquals(1, seenKeys.size)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testScaPromptAndFailureCopy() {
    assertEquals(
      "Confirm with Face ID / Fingerprint to authorize European payment",
      ScaStepUp.BIOMETRIC_PROMPT,
    )
    assertEquals(
      "Authentication challenge failed. Please verify with your passcode.",
      ScaStepUp.FAILURE_MESSAGE,
    )
  }

  @Test
  fun testScaTimestampParsesZuluAndOffset() {
    val zulu = parseScaTimestamp("2026-09-28T21:45:00Z")
    val offset = parseScaTimestamp("2026-09-28T22:45:00+01:00")
    val fractional = parseScaTimestamp("2026-09-28T21:45:00.123Z")
    assertNotNull(zulu)
    assertEquals(zulu, offset)
    assertEquals(zulu!! + 123L, fractional)
  }

  @Test
  fun testScaStepUpExtractsChallengeAndFallsBackWithoutReleasingToken() {
    val body = paymentResponse(
      """
      {
        "ok": false,
        "code": "SCA_STEP_UP_REQUIRED",
        "challenge": {
          "payload": "challenge-payload",
          "expiresAt": "2099-01-01T00:00:00Z",
          "scaChallengeToken": "token-123"
        }
      }
      """.trimIndent(),
    )
    val payment = samplePayment()
    val now = 1_700_000_000_000L
    val handler = ScaChallengeHandler.begin(202, body, payment, now)
    assertNotNull(handler)
    assertTrue(handler!!.phase is ScaPhase.Biometric)
    assertEquals("challenge-payload", (handler.phase as ScaPhase.Biometric).challenge.payload)
    assertNull(handler.resubmission())

    val passcode = handler.biometricUnavailableOrFailed(now)
    assertTrue(passcode.phase is ScaPhase.Passcode)
    assertEquals(payment, passcode.payment)
    assertNull(passcode.resubmission())

    val rejected = passcode.passcodeRejected(now)
    assertTrue(rejected.phase is ScaPhase.Passcode)
    assertEquals(ScaStepUp.FAILURE_MESSAGE, (rejected.phase as ScaPhase.Passcode).message)
    assertEquals("northline-studio", rejected.payment.recipientId)
    assertEquals(4500, rejected.payment.amountMinor)
    assertEquals(payment.idempotencyKey, rejected.payment.idempotencyKey)
    assertNull(rejected.resubmission())
  }

  @Test
  fun testScaPasscodeSuccessResubmitsOriginalKeyAndMethod() {
    val body = paymentResponse(
      """
      {
        "ok": false,
        "code": "SCA_STEP_UP_REQUIRED",
        "challengePayload": "opaque-payload",
        "expirationTimestamp": "2099-06-01T12:00:00Z",
        "scaChallengeToken": "token-from-gateway"
      }
      """.trimIndent(),
    )
    val payment = samplePayment()
    val now = 1_700_000_000_000L
    val ready = ScaChallengeHandler.begin(202, body, payment, now)!!
      .biometricUnavailableOrFailed(now)
      .passcodeVerified(now)
    val retry = ready.resubmission()
    assertNotNull(retry)
    assertEquals(payment.idempotencyKey, retry!!.idempotencyKey)
    assertEquals(PaymentMethod.card, retry.method)
    assertEquals(4500, retry.amountMinor)
    assertEquals("northline-studio", retry.recipientId)
    assertEquals("token-from-gateway", retry.scaChallengeToken)
    assertTrue(RehearsalPasscode.matches("135790", "135790"))
    assertFalse(RehearsalPasscode.matches("000000", "135790"))
    assertFalse(RehearsalPasscode.matches("13579", "135790"))
  }

  @Test
  fun testExpiredScaChallengeKeepsPaymentAndDoesNotResubmit() {
    val body = paymentResponse(
      """
      {
        "ok": false,
        "code": "SCA_STEP_UP_REQUIRED",
        "challenge": "stale-payload",
        "expiresAt": "2000-01-01T00:00:00Z",
        "scaChallengeToken": "stale-token"
      }
      """.trimIndent(),
    )
    val payment = samplePayment()
    val handler = ScaChallengeHandler.begin(202, body, payment, System.currentTimeMillis())
    assertNotNull(handler)
    assertTrue(handler!!.phase is ScaPhase.Failed)
    assertEquals(ScaStepUp.FAILURE_MESSAGE, (handler.phase as ScaPhase.Failed).message)
    assertEquals(payment, handler.payment)
    assertNull(handler.resubmission())
    assertNull(ScaChallengeHandler.begin(202, paymentResponse("""{"ok":false,"code":"PAYMENT_PENDING"}"""), payment, 0))
    assertNull(ScaChallengeHandler.begin(400, body, payment, 0))
  }

  @Test
  fun testPaymentRequestOmitsTokenUntilPresent() {
    val without = mapper.writeValueAsString(
      PaymentRequest("northline-studio", 4500, "card", "Lunch", "success"),
    )
    assertFalse(without.contains("scaChallengeToken"))
    val withToken = mapper.readTree(
      mapper.writeValueAsString(
        PaymentRequest("northline-studio", 4500, "card", "Lunch", "success", "token-123"),
      ),
    )
    assertEquals("token-123", withToken.get("scaChallengeToken").asText())
    assertEquals("card", withToken.get("method").asText())
    assertEquals(4500, withToken.get("amountMinor").asInt())
  }

  @Test
  fun testScaStepUpResubmitsOriginalIdempotencyKey() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"
    val bodies = mutableListOf<String>()
    val keys = mutableListOf<String>()

    server.createContext("/api/v1/payments") { exchange ->
      val sessionHeader = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      assertEquals("sca-room", sessionHeader)
      val idempotencyKey = exchange.requestHeaders.getFirst("Idempotency-Key")
      keys.add(idempotencyKey)
      val requestBody = exchange.requestBody.bufferedReader().use { it.readText() }
      bodies.add(requestBody)
      val responseBody = if (bodies.size == 1) {
        """{"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"payload":"challenge-payload","expiresAt":"2099-01-01T00:00:00Z","scaChallengeToken":"token-123"}}"""
      } else {
        """{"ok":true,"paymentId":"pay-sca"}"""
      }
      val status = if (bodies.size == 1) 202 else 200
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(status, responseBody.toByteArray().size.toLong())
      exchange.responseBody.write(responseBody.toByteArray())
      exchange.close()
    }

    server.start()
    try {
      val client = MeridianClient(baseUrl, "sca-room")
      val key = "idem-sca-1"
      val first = runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 4500,
          method = PaymentMethod.card,
          note = "European rehearsal",
          idempotencyKey = key,
        )
      }
      val payment = InFlightPayment(
        "northline-studio",
        4500,
        PaymentMethod.card,
        "European rehearsal",
        Scenario.success,
        key,
      )
      val now = System.currentTimeMillis()
      val ready = ScaChallengeHandler.begin(first.statusCode, first.body, payment, now)!!
        .biometricSucceeded(now)
      val retry = ready.resubmission()!!
      assertEquals(PaymentMethod.card, retry.method)
      val second = runBlocking {
        client.submitPayment(
          recipientId = retry.recipientId,
          amountMinor = retry.amountMinor,
          method = retry.method,
          note = retry.note,
          scenario = retry.scenario,
          idempotencyKey = retry.idempotencyKey,
          scaChallengeToken = retry.scaChallengeToken,
        )
      }
      assertEquals(200, second.statusCode)
      assertTrue(second.body.ok)
      assertEquals(listOf(key, key), keys)
      val firstJson = mapper.readTree(bodies[0])
      val secondJson = mapper.readTree(bodies[1])
      assertFalse(firstJson.has("scaChallengeToken"))
      assertEquals("token-123", secondJson.get("scaChallengeToken").asText())
      assertEquals("card", secondJson.get("method").asText())
      assertEquals(4500, secondJson.get("amountMinor").asInt())
    } finally {
      server.stop(0)
    }
  }

  private fun paymentResponse(json: String): PaymentResponse =
    mapper.readValue(json, PaymentResponse::class.java)

  private fun samplePayment() = InFlightPayment(
    recipientId = "northline-studio",
    amountMinor = 4500,
    method = PaymentMethod.card,
    note = "Studio supplies",
    scenario = Scenario.success,
    idempotencyKey = "idem-original",
  )
}
