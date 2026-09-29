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

  // MARK: - SCA Challenge Handler Tests

  private val mapper2 = ObjectMapper().registerKotlinModule()

  /** Starts a stub HTTP server that returns [body] with [statusCode] for every /payments call. */
  private fun makeScaServer(body: String, statusCode: Int = 200):
    Pair<com.sun.net.httpserver.HttpServer, String> {
    val server =
      com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"
    server.createContext("/api/v1/payments") { exchange ->
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(statusCode, body.length.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }
    server.start()
    return Pair(server, baseUrl)
  }

  private fun mockBiometric(available: Boolean, succeeds: Boolean): ScaBiometricAuthenticator =
    object : ScaBiometricAuthenticator {
      override fun canAuthenticate() = available
      override suspend fun authenticate(prompt: String) = succeeds
    }

  private fun mockPasscode(succeeds: Boolean): ScaPasscodeVerifier =
    object : ScaPasscodeVerifier {
      override suspend fun verifyPasscode() = succeeds
    }

  @Test
  fun testScaPaymentResponseDecoding() {
    val json =
      """
      {
        "ok": false,
        "error": "SCA authentication required",
        "code": "SCA_STEP_UP_REQUIRED",
        "scaChallengeToken": "sca-tok-abc123",
        "challengeExpiresAt": "2099-12-31T23:59:59Z"
      }
    """.trimIndent()

    val response = mapper2.readValue(json, PaymentResponse::class.java)

    assertFalse(response.ok)
    assertEquals("SCA_STEP_UP_REQUIRED", response.code)
    assertEquals("sca-tok-abc123", response.scaChallengeToken)
    assertEquals("2099-12-31T23:59:59Z", response.challengeExpiresAt)
  }

  @Test
  fun testScaPaymentRequestSerialization() {
    val req = ScaPaymentRequest(
      recipientId = "rec-1",
      amountMinor = 15000,
      method = "card",
      note = "test",
      scenario = "success",
      scaChallengeToken = "tok-xyz",
    )
    val json = mapper2.writeValueAsString(req)

    assertTrue("JSON should contain scaChallengeToken key", json.contains("scaChallengeToken"))
    assertTrue("JSON should contain the token value", json.contains("tok-xyz"))
  }

  @Test
  fun testScaChallengeHandlerBiometricSuccess() {
    val successBody =
      """{"ok":true,"state":{"version":1,"balance":990000,"transactions":[],"budgets":[]},"transaction":null}"""
    val (server, baseUrl) = makeScaServer(successBody)
    try {
      val client = MeridianClient(baseUrl, "test-session")
      val handler = ScaChallengeHandler(
        client = client,
        biometricAuthenticator = mockBiometric(available = true, succeeds = true),
        passcodeVerifier = mockPasscode(succeeds = false),
      )

      val outcome = runBlocking {
        handler.handle(
          scaChallengeToken = "tok-bio",
          challengeExpiresAt = "2099-12-31T23:59:59Z",
          recipientId = "rec-1",
          amountMinor = 15000,
          method = PaymentMethod.card,
          note = "test",
          scenario = Scenario.success,
          idempotencyKey = "key-1",
        )
      }

      assertTrue("Expected Success outcome", outcome is ScaOutcome.Success)
      assertTrue("Payment should be ok", (outcome as ScaOutcome.Success).response.ok)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testScaChallengeHandlerBiometricUnavailablePasscodeSuccess() {
    val successBody =
      """{"ok":true,"state":{"version":1,"balance":990000,"transactions":[],"budgets":[]},"transaction":null}"""
    val (server, baseUrl) = makeScaServer(successBody)
    try {
      val client = MeridianClient(baseUrl, "test-session")
      val handler = ScaChallengeHandler(
        client = client,
        biometricAuthenticator = mockBiometric(available = false, succeeds = false),
        passcodeVerifier = mockPasscode(succeeds = true),
      )

      val outcome = runBlocking {
        handler.handle(
          scaChallengeToken = "tok-pc",
          challengeExpiresAt = "2099-12-31T23:59:59Z",
          recipientId = "rec-1",
          amountMinor = 15000,
          method = PaymentMethod.card,
          note = "test",
          scenario = Scenario.success,
          idempotencyKey = "key-2",
        )
      }

      assertTrue("Expected Success outcome via passcode", outcome is ScaOutcome.Success)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testScaChallengeHandlerBiometricFailPasscodeSuccess() {
    val successBody =
      """{"ok":true,"state":{"version":1,"balance":990000,"transactions":[],"budgets":[]},"transaction":null}"""
    val (server, baseUrl) = makeScaServer(successBody)
    try {
      val client = MeridianClient(baseUrl, "test-session")
      val handler = ScaChallengeHandler(
        client = client,
        biometricAuthenticator = mockBiometric(available = true, succeeds = false),
        passcodeVerifier = mockPasscode(succeeds = true),
      )

      val outcome = runBlocking {
        handler.handle(
          scaChallengeToken = "tok-fallback",
          challengeExpiresAt = "2099-12-31T23:59:59Z",
          recipientId = "rec-1",
          amountMinor = 15000,
          method = PaymentMethod.card,
          note = "test",
          scenario = Scenario.success,
          idempotencyKey = "key-3",
        )
      }

      assertTrue("Expected Success via passcode fallback", outcome is ScaOutcome.Success)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testScaChallengeHandlerBothFail() {
    val (server, baseUrl) = makeScaServer("{}", 200)
    try {
      val client = MeridianClient(baseUrl, "test-session")
      val handler = ScaChallengeHandler(
        client = client,
        biometricAuthenticator = mockBiometric(available = true, succeeds = false),
        passcodeVerifier = mockPasscode(succeeds = false),
      )

      val outcome = runBlocking {
        handler.handle(
          scaChallengeToken = "tok-fail",
          challengeExpiresAt = "2099-12-31T23:59:59Z",
          recipientId = "rec-1",
          amountMinor = 15000,
          method = PaymentMethod.card,
          note = "test",
          scenario = Scenario.success,
          idempotencyKey = "key-4",
        )
      }

      assertTrue("Expected AuthenticationFailed", outcome is ScaOutcome.AuthenticationFailed)
      assertEquals(
        ScaChallengeHandler.FAILURE_MESSAGE,
        (outcome as ScaOutcome.AuthenticationFailed).message,
      )
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testScaChallengeHandlerExpiredChallenge() {
    val (server, baseUrl) = makeScaServer("{}", 200)
    try {
      val client = MeridianClient(baseUrl, "test-session")
      val handler = ScaChallengeHandler(
        client = client,
        biometricAuthenticator = mockBiometric(available = true, succeeds = true),
        passcodeVerifier = mockPasscode(succeeds = true),
      )

      val outcome = runBlocking {
        handler.handle(
          scaChallengeToken = "tok-expired",
          challengeExpiresAt = "2000-01-01T00:00:00Z", // already expired
          recipientId = "rec-1",
          amountMinor = 15000,
          method = PaymentMethod.card,
          note = "test",
          scenario = Scenario.success,
          idempotencyKey = "key-5",
        )
      }

      assertTrue("Expected ChallengeExpired", outcome is ScaOutcome.ChallengeExpired)
      assertEquals(
        ScaChallengeHandler.FAILURE_MESSAGE,
        (outcome as ScaOutcome.ChallengeExpired).message,
      )
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testHttpTransportWithScaStepUp() {
    val server =
      com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"

    var requestCount = 0

    server.createContext("/api/v1/payments") { exchange ->
      requestCount++
      assertEquals("POST", exchange.requestMethod)

      val bodyStr = String(exchange.requestBody.readBytes())
      val (statusCode, body) =
        if (requestCount == 1) {
          // Initial payment – gateway requires SCA step-up
          202 to
            """{"ok":false,"code":"SCA_STEP_UP_REQUIRED","scaChallengeToken":"tok-sca-xyz","challengeExpiresAt":"2099-12-31T23:59:59Z","error":"SCA required"}"""
        } else {
          // Re-dispatch with scaChallengeToken
          assertTrue(
            "Re-dispatch must include scaChallengeToken",
            bodyStr.contains("scaChallengeToken"),
          )
          assertTrue("Re-dispatch must include token value", bodyStr.contains("tok-sca-xyz"))
          val sessionHeader = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
          assertEquals("test-session", sessionHeader)
          val idempotencyKey = exchange.requestHeaders.getFirst("Idempotency-Key")
          assertEquals("sca-idempotency-key", idempotencyKey)
          200 to
            """{"ok":true,"state":{"version":1,"balance":990000,"transactions":[],"budgets":[]},"transaction":null}"""
        }

      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(statusCode, body.length.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }

    server.start()
    try {
      val client = MeridianClient(baseUrl, "test-session")

      // Initial payment returns SCA_STEP_UP_REQUIRED
      val initial = runBlocking {
        client.submitPayment(
          recipientId = "rec-1",
          amountMinor = 15000,
          method = PaymentMethod.card,
          idempotencyKey = "sca-idempotency-key",
        )
      }
      assertFalse(initial.ok)
      assertEquals("SCA_STEP_UP_REQUIRED", initial.code)
      assertEquals("tok-sca-xyz", initial.scaChallengeToken)
      assertNotNull(initial.challengeExpiresAt)

      // Re-dispatch with scaChallengeToken under the original idempotency key
      val resubmit = runBlocking {
        client.submitScaPayment(
          recipientId = "rec-1",
          amountMinor = 15000,
          method = PaymentMethod.card,
          idempotencyKey = "sca-idempotency-key",
          scaChallengeToken = initial.scaChallengeToken!!,
        )
      }
      assertTrue(resubmit.ok)
      assertEquals(2, requestCount)
    } finally {
      server.stop(0)
    }
  }
}
