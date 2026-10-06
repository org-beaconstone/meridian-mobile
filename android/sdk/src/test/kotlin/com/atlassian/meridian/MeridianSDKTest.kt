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

  // MARK: - SCA Handler Tests

  @Test
  fun testSCAAlwaysSucceedStub() = runBlocking {
    val handler = AlwaysSucceedSCAHandler()
    val result = handler.authenticate(SCAChallenge.Any("Confirm payment"))
    assertTrue(result is SCAResult.Success)
  }

  @Test
  fun testSCAAlwaysFailStub() = runBlocking {
    val handler = AlwaysFailSCAHandler("Biometrics unavailable")
    val result = handler.authenticate(SCAChallenge.Biometric("Confirm payment"))
    assertTrue(result is SCAResult.Failed)
    assertEquals("Biometrics unavailable", (result as SCAResult.Failed).reason)
  }

  @Test
  fun testSCAAlwaysCancelStub() = runBlocking {
    val handler = AlwaysCancelSCAHandler()
    val result = handler.authenticate(SCAChallenge.Pin("Confirm payment"))
    assertTrue(result is SCAResult.Cancelled)
  }

  @Test
  fun testSCAChallengeReasonPropagated() = runBlocking {
    val challenges = listOf(
      SCAChallenge.Any("reason-any"),
      SCAChallenge.Biometric("reason-bio"),
      SCAChallenge.Pin("reason-pin"),
    )
    challenges.forEach { challenge ->
      assertTrue(challenge.reason.isNotEmpty())
    }
  }

  // MARK: - ReturnStateToken Tests

  @Test
  fun testReturnStateTokenRoundTrip() {
    val key = ReturnStateToken.deriveKey("test-session")
    val token = ReturnStateToken.generate("pay-001", key)
    val payload = ReturnStateToken.verify(token, key)
    assertEquals("pay-001", payload.paymentId)
    assertTrue(payload.issuedAt > 0)
    assertTrue(payload.nonce.isNotEmpty())
  }

  @Test
  fun testReturnStateTokenSignatureMismatch() {
    val key = ReturnStateToken.deriveKey("test-session")
    val wrongKey = ReturnStateToken.deriveKey("other-session")
    val token = ReturnStateToken.generate("pay-001", key)
    try {
      ReturnStateToken.verify(token, wrongKey)
      fail("Expected HandoffError.InvalidReturnState")
    } catch (e: HandoffError.InvalidReturnState) {
      assertTrue(e.message!!.contains("Signature mismatch"))
    }
  }

  @Test
  fun testReturnStateTokenTamperedPayload() {
    val key = ReturnStateToken.deriveKey("test-session")
    val token = ReturnStateToken.generate("pay-001", key)
    // Flip one char in the payload portion.
    val dotIndex = token.indexOf('.')
    val tampered = "X" + token.substring(1, dotIndex) + token.substring(dotIndex)
    try {
      ReturnStateToken.verify(tampered, key)
      fail("Expected HandoffError.InvalidReturnState")
    } catch (e: HandoffError.InvalidReturnState) {
      // Expected.
    }
  }

  @Test
  fun testReturnStateTokenMalformedNoDot() {
    val key = ReturnStateToken.deriveKey("test-session")
    try {
      ReturnStateToken.verify("nodothere", key)
      fail("Expected HandoffError.InvalidReturnState")
    } catch (e: HandoffError.InvalidReturnState) {
      assertTrue(e.message!!.contains("Malformed token"))
    }
  }

  // MARK: - ReturnStateValidator Tests

  @Test
  fun testValidatorAcceptsValidToken() {
    val key = ReturnStateToken.deriveKey("test-session")
    val token = ReturnStateToken.generate("pay-123", key)
    val validator = ReturnStateValidator(key, tokenTTL = 300L)
    val payload = validator.validate(token)
    assertEquals("pay-123", payload.paymentId)
  }

  @Test
  fun testValidatorRejectsExpiredToken() {
    val key = ReturnStateToken.deriveKey("test-session")
    // Create a payload with issuedAt set 10 minutes in the past.
    val oldPayload = ReturnStatePayload(
      paymentId = "pay-old",
      issuedAt = System.currentTimeMillis() / 1000L - 601L,
      nonce = "unique-nonce-expired",
    )
    val token = ReturnStateToken.sign(oldPayload, key)
    val validator = ReturnStateValidator(key, tokenTTL = 300L)
    try {
      validator.validate(token)
      fail("Expected HandoffError.ExpiredReturnState")
    } catch (e: HandoffError.ExpiredReturnState) {
      // Expected.
    }
  }

  @Test
  fun testValidatorRejectsReplayedToken() {
    val key = ReturnStateToken.deriveKey("test-session")
    val token = ReturnStateToken.generate("pay-replay", key)
    val validator = ReturnStateValidator(key, tokenTTL = 300L)
    // First validation succeeds.
    validator.validate(token)
    // Second validation with the same token must be rejected.
    try {
      validator.validate(token)
      fail("Expected HandoffError.ReplayedReturnState")
    } catch (e: HandoffError.ReplayedReturnState) {
      // Expected.
    }
  }

  @Test
  fun testValidatorAcceptsTwoDistinctTokens() {
    val key = ReturnStateToken.deriveKey("test-session")
    val token1 = ReturnStateToken.generate("pay-A", key)
    val token2 = ReturnStateToken.generate("pay-B", key)
    val validator = ReturnStateValidator(key, tokenTTL = 300L)
    val p1 = validator.validate(token1)
    val p2 = validator.validate(token2)
    assertEquals("pay-A", p1.paymentId)
    assertEquals("pay-B", p2.paymentId)
  }

  // MARK: - BankHandoffManager Tests

  @Test
  fun testBankHandoffManagerBuildsURL() {
    val manager = BankHandoffManager(sessionId = "room-abc")
    val url = manager.buildHandoffURL(
      bankURL = "https://secure.worldpay.com/checkout",
      paymentId = "pay-xyz",
      returnScheme = "meridian",
    )
    assertTrue(url.contains("returnState="))
    assertTrue(url.contains("returnScheme=meridian"))
    assertTrue(url.startsWith("https://secure.worldpay.com/checkout"))
  }

  @Test
  fun testBankHandoffManagerBuildsURLWithExistingParams() {
    val manager = BankHandoffManager(sessionId = "room-abc")
    val url = manager.buildHandoffURL(
      bankURL = "https://checkout.adyen.com/pay?merchantId=123",
      paymentId = "pay-xyz",
      returnScheme = "meridian",
    )
    assertTrue(url.contains("merchantId=123"))
    assertTrue(url.contains("returnState="))
  }

  @Test
  fun testBankHandoffManagerRejectsHttpURL() {
    val manager = BankHandoffManager(sessionId = "room-abc")
    try {
      manager.buildHandoffURL(
        bankURL = "http://secure.worldpay.com/checkout",
        paymentId = "pay-xyz",
        returnScheme = "meridian",
      )
      fail("Expected HandoffError.DisallowedURL")
    } catch (e: HandoffError.DisallowedURL) {
      assertTrue(e.message!!.contains("HTTPS"))
    }
  }

  @Test
  fun testBankHandoffManagerRejectsNonAllowlistedHost() {
    val manager = BankHandoffManager(sessionId = "room-abc")
    try {
      manager.buildHandoffURL(
        bankURL = "https://evil.example.com/steal",
        paymentId = "pay-xyz",
        returnScheme = "meridian",
      )
      fail("Expected HandoffError.DisallowedURL")
    } catch (e: HandoffError.DisallowedURL) {
      assertTrue(e.message!!.contains("evil.example.com"))
    }
  }

  @Test
  fun testBankHandoffManagerHandlesReturnURL() {
    val manager = BankHandoffManager(sessionId = "room-abc")
    val outbound = manager.buildHandoffURL(
      bankURL = "https://secure.worldpay.com/checkout",
      paymentId = "pay-return",
      returnScheme = "meridian",
    )
    // Extract the returnState value from the outbound URL.
    val returnState = outbound.split("&", "?")
      .first { it.startsWith("returnState=") }
      .removePrefix("returnState=")
    val returnURL = "meridian://payment/return?returnState=$returnState"
    val payload = manager.handleReturnURL(returnURL)
    assertEquals("pay-return", payload.paymentId)
  }

  @Test
  fun testBankHandoffManagerRejectsMissingReturnState() {
    val manager = BankHandoffManager(sessionId = "room-abc")
    try {
      manager.handleReturnURL("meridian://payment/return?status=ok")
      fail("Expected HandoffError.MissingReturnState")
    } catch (e: HandoffError.MissingReturnState) {
      // Expected.
    }
  }

  @Test
  fun testBankHandoffManagerRejectsReturnStateFromDifferentSession() {
    val managerA = BankHandoffManager(sessionId = "session-A")
    val managerB = BankHandoffManager(sessionId = "session-B")
    val outbound = managerA.buildHandoffURL(
      bankURL = "https://secure.worldpay.com/checkout",
      paymentId = "pay-xyz",
      returnScheme = "meridian",
    )
    val returnState = outbound.split("&", "?")
      .first { it.startsWith("returnState=") }
      .removePrefix("returnState=")
    val returnURL = "meridian://payment/return?returnState=$returnState"
    try {
      managerB.handleReturnURL(returnURL)
      fail("Expected HandoffError.InvalidReturnState")
    } catch (e: HandoffError.InvalidReturnState) {
      // Expected – session B cannot validate a token signed by session A.
    }
  }

  @Test
  fun testBankHandoffManagerRejectsReplayedReturnURL() {
    val manager = BankHandoffManager(sessionId = "room-abc")
    val outbound = manager.buildHandoffURL(
      bankURL = "https://secure.worldpay.com/checkout",
      paymentId = "pay-replay",
      returnScheme = "meridian",
    )
    val returnState = outbound.split("&", "?")
      .first { it.startsWith("returnState=") }
      .removePrefix("returnState=")
    val returnURL = "meridian://payment/return?returnState=$returnState"
    // First call succeeds.
    manager.handleReturnURL(returnURL)
    // Second call must be rejected.
    try {
      manager.handleReturnURL(returnURL)
      fail("Expected HandoffError.ReplayedReturnState")
    } catch (e: HandoffError.ReplayedReturnState) {
      // Expected.
    }
  }

  @Test
  fun testBankHandoffManagerRejectsExpiredReturnURL() {
    val key = ReturnStateToken.deriveKey("room-abc")
    val oldPayload = ReturnStatePayload(
      paymentId = "pay-expired",
      issuedAt = System.currentTimeMillis() / 1000L - 601L,
      nonce = "unique-nonce-for-expiry-test",
    )
    val token = ReturnStateToken.sign(oldPayload, key)
    val manager = BankHandoffManager(sessionId = "room-abc", tokenTTL = 300L)
    try {
      manager.handleReturnURL("meridian://payment/return?returnState=$token")
      fail("Expected HandoffError.ExpiredReturnState")
    } catch (e: HandoffError.ExpiredReturnState) {
      // Expected.
    }
  }
}
