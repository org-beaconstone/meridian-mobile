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
  fun testScaInterceptExtractsPayloadAndIgnoresPending() {
    val now = parseScaTimestamp("2026-09-29T00:00:00Z")!!
    val body = """
      {"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"payload":"ch_abc","expiresAt":"2099-01-01T00:00:00Z","token":"tok_1"}}
    """.trimIndent()
    val intercept = ScaInterpreter.intercept(202, body, now)
    val required = intercept as ScaIntercept.Required
    assertEquals("ch_abc", required.challenge.payload)
    assertEquals("tok_1", required.challenge.token)
    assertFalse(required.challenge.isExpired(now))

    val pending = """{"ok":false,"code":"PAYMENT_PENDING","paymentId":"pay-1"}"""
    assertTrue(ScaInterpreter.intercept(202, pending, now) is ScaIntercept.NotStepUp)
    val not202 = """{"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"payload":"ch","expiresAt":"2099-01-01T00:00:00Z"}}"""
    assertTrue(ScaInterpreter.intercept(400, not202, now) is ScaIntercept.NotStepUp)
    val missing = """{"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"expiresAt":"2099-01-01T00:00:00Z"}}"""
    assertTrue(ScaInterpreter.intercept(202, missing, now) is ScaIntercept.Invalid)
    val expired = """{"ok":false,"code":"SCA_STEP_UP_REQUIRED","challengePayload":"ch_old","expiresAt":"2000-01-01T00:00:00Z"}"""
    assertTrue(ScaInterpreter.intercept(202, expired, now) is ScaIntercept.Expired)

    val exact = parseScaTimestamp("2099-01-01T00:00:00Z")!!
    val boundary = """{"ok":false,"code":"SCA_STEP_UP_REQUIRED","expiresAt":"2099-01-01T00:00:00Z","challengePayload":"edge"}"""
    assertTrue(ScaInterpreter.intercept(202, boundary, exact - 1) is ScaIntercept.Required)
    assertTrue(ScaInterpreter.intercept(202, boundary, exact) is ScaIntercept.Expired)
    val shifted = parseScaTimestamp("2099-01-01T01:00:00+01:00")
    assertEquals(exact, shifted)
  }

  @Test
  fun testScaPasscodeKeepsDraftAndOmitsPasscodeFromBody() {
    val now = parseScaTimestamp("2026-09-29T00:00:00Z")!!
    val challenge = ScaChallenge("ch_live", parseScaTimestamp("2099-01-01T00:00:00Z")!!, "tok_live")
    val draft = PaymentDraft("northline-studio", 4000, PaymentMethod.card, "Studio", Scenario.success, "same-key")
    var session = ScaSession.start(draft, challenge, now)
    session = session.afterBiometric(BiometricStatus.UNAVAILABLE, now)
    assertEquals(ScaPhase.PASSCODE, session.phase)
    assertEquals(4000, session.draft.amountMinor)
    assertEquals(PaymentMethod.card, session.draft.method)
    assertEquals("same-key", session.draft.idempotencyKey)
    session = session.afterPasscode("000000", now)
    assertEquals(ScaCopy.FAILURE_MESSAGE, session.message)
    assertNull(session.resubmitToken)
    assertEquals("northline-studio", session.draft.recipientId)
    session = session.afterPasscode(ScaCopy.REHEARSAL_PASSCODE, now)
    assertEquals("tok_live", session.resubmitToken)
    assertFalse(RehearsalPasscode.matches("135791"))

    val plain = PaymentRequest("northline-studio", 4000, "card", "Studio", "success")
    val plainJson = mapper.writeValueAsString(plain)
    assertFalse(plainJson.contains("scaChallengeToken"))
    assertFalse(plainJson.contains(ScaCopy.REHEARSAL_PASSCODE))
    assertTrue(plainJson.contains("\"method\":\"card\""))
    val stepped = plain.copy(method = "bank", scaChallengeToken = "tok_live")
    val steppedJson = mapper.writeValueAsString(stepped)
    assertTrue(steppedJson.contains("\"method\":\"bank\""))
    assertTrue(steppedJson.contains("\"scaChallengeToken\":\"tok_live\""))
    assertFalse(steppedJson.contains(ScaCopy.REHEARSAL_PASSCODE))
  }

  @Test
  fun testScaResubmitKeepsSessionKeyAndCardMethod() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"
    val bodies = mutableListOf<String>()
    val keys = mutableListOf<String>()
    val sessions = mutableListOf<String>()
    server.createContext("/api/v1/payments") { exchange ->
      val body = exchange.requestBody.bufferedReader(Charsets.UTF_8).readText()
      bodies.add(body)
      keys.add(exchange.requestHeaders.getFirst("Idempotency-Key") ?: "")
      sessions.add(exchange.requestHeaders.getFirst("X-Rehearsal-Session") ?: "")
      val hasToken = body.contains("scaChallengeToken")
      val status = if (hasToken) 200 else 202
      val responseBody = if (hasToken) {
        """{"ok":true,"paymentId":"tx-sca"}"""
      } else {
        """{"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"payload":"ch_http","expiresAt":"2099-01-01T00:00:00Z"}}"""
      }
      val bytes = responseBody.toByteArray(Charsets.UTF_8)
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(status, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient(baseUrl, "sca-room")
      val key = "idem-sca-1"
      val draft = PaymentDraft("northline-studio", 4000, PaymentMethod.card, "Studio", Scenario.success, key)
      val first = runBlocking {
        client.submitPayment(draft.recipientId, draft.amountMinor, draft.method, draft.note, draft.scenario, draft.idempotencyKey)
      }
      assertEquals(202, first.statusCode)
      val required = ScaInterpreter.intercept(first.statusCode, first.bodyText) as ScaIntercept.Required
      var session = ScaSession.start(draft, required.challenge)
      session = session.afterBiometric(BiometricStatus.FAILED)
      session = session.afterPasscode("000000")
      assertEquals(ScaCopy.FAILURE_MESSAGE, session.message)
      assertNull(session.resubmitToken)
      assertEquals(4000, session.draft.amountMinor)
      session = session.afterPasscode(ScaCopy.REHEARSAL_PASSCODE)
      val token = session.resubmitToken
      assertEquals("ch_http", token)
      val second = runBlocking {
        client.submitPayment(
          recipientId = draft.recipientId,
          amountMinor = draft.amountMinor,
          method = draft.method,
          note = draft.note,
          scenario = draft.scenario,
          idempotencyKey = draft.idempotencyKey,
          scaChallengeToken = token,
        )
      }
      assertTrue(second.ok)
      assertEquals(listOf(key, key), keys)
      assertEquals(listOf("sca-room", "sca-room"), sessions)
      assertFalse(bodies[0].contains("scaChallengeToken"))
      assertTrue(bodies[1].contains("\"scaChallengeToken\":\"ch_http\""))
      assertTrue(bodies[0].contains("\"method\":\"card\""))
      assertTrue(bodies[1].contains("\"method\":\"card\""))
      assertFalse(bodies.joinToString("\n").contains(ScaCopy.REHEARSAL_PASSCODE))
    } finally {
      server.stop(0)
    }
  }
}
