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

  @Test
  fun testPaymentRequestOmitsChallengeTokenUntilVerified() {
    val first = PaymentRequest(
      recipientId = "northline-studio",
      amountMinor = 4500,
      method = "card",
      note = "Studio materials",
      scenario = "success",
    )
    val encoded = mapper.writeValueAsString(first)
    assertFalse(encoded.contains("scaChallengeToken"))
    assertFalse(encoded.contains(ScaCopy.REHEARSAL_PASSCODE))
    assertTrue(encoded.contains("\"method\":\"card\""))

    val second = first.copy(scaChallengeToken = "token-eu")
    val retry = mapper.writeValueAsString(second)
    assertTrue(retry.contains("\"scaChallengeToken\":\"token-eu\""))
    assertTrue(retry.contains("\"method\":\"card\""))
    assertFalse(retry.contains("worldpay"))
    assertFalse(retry.contains(ScaCopy.REHEARSAL_PASSCODE))
  }

  @Test
  fun testScaInterceptsStepUpAndKeepsPendingSeparate() {
    val now = 1_700_000_000_000L
    val required = ScaInterpreter.interpret(
      202,
      """
      {"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"payload":"payload-eu","expiresAt":"2099-06-01T12:00:00Z","scaChallengeToken":"token-eu"}}
      """.trimIndent(),
      now,
    )
    assertTrue(required is ScaIntercept.Required)
    val challenge = (required as ScaIntercept.Required).challenge
    assertEquals("payload-eu", challenge.payload)
    assertEquals("token-eu", challenge.token)
    assertTrue(challenge.expiresAtMs > now)

    val pending = ScaInterpreter.interpret(
      202,
      """{"ok":false,"code":"PAYMENT_PENDING","paymentId":"pay-1","error":"Payment pending confirmation"}""",
      now,
    )
    assertTrue(pending is ScaIntercept.NotStepUp)
    assertTrue(
      ScaInterpreter.interpret(200, """{"ok":false,"code":"SCA_STEP_UP_REQUIRED"}""", now)
        is ScaIntercept.NotStepUp
    )
    assertTrue(
      ScaInterpreter.interpret(
        202,
        """{"ok":false,"code":"SCA_STEP_UP_REQUIRED","challenge":{"payload":"only"}}""",
        now,
      ) is ScaIntercept.Invalid
    )

    val expired = ScaInterpreter.interpret(
      202,
      """{"code":"SCA_STEP_UP_REQUIRED","challengePayload":"payload-eu","expirationTimestamp":"2000-01-01T00:00:00Z","scaChallengeToken":"token-eu"}""",
      now,
    )
    assertTrue(expired is ScaIntercept.Expired)
  }

  @Test
  fun testPasscodeFallbackKeepsDraftAndOriginalKey() {
    val draft = PaymentDraft(
      recipientId = "northline-studio",
      amountMinor = 4500,
      method = PaymentMethod.card,
      note = "Studio materials",
      scenario = Scenario.success,
      idempotencyKey = "idem-sca-1",
    )
    val challenge = ScaChallenge("payload-eu", 4_102_444_800_000L, "token-eu")
    val started = ScaSession.start(draft, challenge, nowMs = 0L)
    assertEquals(ScaPhase.BIOMETRIC, started.phase)
    assertEquals(ScaCopy.BIOMETRIC_PROMPT, "Confirm with Face ID / Fingerprint to authorize European payment")

    for (status in listOf(BiometricStatus.FAILED, BiometricStatus.UNAVAILABLE, BiometricStatus.CANCELLED)) {
      val fallback = started.afterBiometric(status, nowMs = 0L)
      assertEquals(ScaPhase.PASSCODE, fallback.phase)
      assertEquals(draft, fallback.draft)
      assertNull(fallback.resubmit())
    }

    val passcode = started.afterBiometric(BiometricStatus.UNAVAILABLE, nowMs = 0L)
    val wrong = passcode.afterPasscode("111111", nowMs = 0L)
    assertEquals(ScaPhase.FAILED, wrong.phase)
    assertEquals(ScaCopy.FAILURE_MESSAGE, wrong.message)
    assertEquals("northline-studio", wrong.draft.recipientId)
    assertEquals(4500, wrong.draft.amountMinor)
    assertEquals("idem-sca-1", wrong.draft.idempotencyKey)
    assertEquals(PaymentMethod.card, wrong.draft.method)
    assertNull(wrong.resubmit())

    val verified = wrong.afterPasscode(ScaCopy.REHEARSAL_PASSCODE, nowMs = 0L)
    val body = verified.resubmit()
    assertNotNull(body)
    assertEquals("token-eu", body!!.scaChallengeToken)
    assertEquals("idem-sca-1", body.idempotencyKey)
    assertEquals(PaymentMethod.card, body.method)
    assertFalse(body.toString().contains(ScaCopy.REHEARSAL_PASSCODE))

    val expired = passcode.afterPasscode(ScaCopy.REHEARSAL_PASSCODE, nowMs = challenge.expiresAtMs)
    assertEquals(ScaCopy.FAILURE_MESSAGE, expired.message)
    assertEquals(4500, expired.draft.amountMinor)
    assertNull(expired.resubmit())
  }

  @Test
  fun testScaResubmitUsesOriginalIdempotencyKeyAndToken() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val seen = mutableListOf<String>()
    server.createContext("/api/v1/payments") { exchange ->
      val session = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      val key = exchange.requestHeaders.getFirst("Idempotency-Key")
      val body = exchange.requestBody.bufferedReader().readText()
      seen.add("$session|$key|$body")
      val steppedUp = body.contains("\"scaChallengeToken\"")
      val responseBody = if (steppedUp) {
        """{"ok":true,"paymentId":"pay-sca"}"""
      } else {
        """{"code":"SCA_STEP_UP_REQUIRED","challenge":{"payload":"payload-eu","expiresAt":"2099-06-01T12:00:00Z","scaChallengeToken":"token-eu"}}"""
      }
      val status = if (steppedUp) 200 else 202
      val bytes = responseBody.toByteArray(java.nio.charset.StandardCharsets.UTF_8)
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(status, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:$port/api/v1", "sca-room")
      val key = "idem-sca-1"
      val first = runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 4500,
          method = PaymentMethod.card,
          note = "Studio materials",
          idempotencyKey = key,
        )
      }
      assertEquals(202, first.statusCode)
      assertEquals(ScaCopy.STEP_UP_CODE, first.code)
      val intercept = ScaInterpreter.interpret(first.statusCode, first.body, nowMs = 0L)
      assertTrue(intercept is ScaIntercept.Required)
      val draft = PaymentDraft(
        "northline-studio",
        4500,
        PaymentMethod.card,
        "Studio materials",
        Scenario.success,
        key,
      )
      var session = ScaSession.start(draft, (intercept as ScaIntercept.Required).challenge, nowMs = 0L)
      session = session.afterBiometric(BiometricStatus.FAILED, nowMs = 0L)
      session = session.afterPasscode(ScaCopy.REHEARSAL_PASSCODE, nowMs = 0L)
      val retry = session.resubmit()
      assertNotNull(retry)
      assertEquals(PaymentMethod.card, retry!!.method)
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
      assertTrue(second.ok)
      assertEquals(2, seen.size)
      assertTrue(seen.all { it.startsWith("sca-room|$key|") })
      assertFalse(seen[0].contains("scaChallengeToken"))
      assertFalse(seen[0].contains(ScaCopy.REHEARSAL_PASSCODE))
      assertTrue(seen[1].contains("\"scaChallengeToken\":\"token-eu\""))
      assertTrue(seen[0].contains("\"method\":\"card\""))
      assertTrue(seen[1].contains("\"method\":\"card\""))
      assertFalse(seen[1].contains(ScaCopy.REHEARSAL_PASSCODE))
    } finally {
      server.stop(0)
    }
  }
}
