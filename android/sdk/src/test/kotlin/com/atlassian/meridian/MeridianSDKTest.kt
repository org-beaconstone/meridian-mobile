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

  // MARK: - SCA Challenge Tests

  @Test
  fun testSCAChallengeDefaultsBiometric() {
    val challenge = SCAChallenge(
      paymentId = "pay-001",
      amountMinor = 5000,
      recipientName = "Birch & Bloom",
    )
    assertEquals("pay-001", challenge.paymentId)
    assertEquals(5000, challenge.amountMinor)
    assertEquals("Birch & Bloom", challenge.recipientName)
    assertEquals(SCAType.biometric, challenge.type)
  }

  @Test
  fun testSCAChallengeExplicitPin() {
    val challenge = SCAChallenge(
      paymentId = "pay-002",
      amountMinor = 10000,
      recipientName = "Northline Studio",
      type = SCAType.pin,
    )
    assertEquals(SCAType.pin, challenge.type)
  }

  // MARK: - BankHandoff Allowlist Tests

  @Test
  fun testAllowedHostsContainsWorldpayDomains() {
    assertTrue(BankHandoff.allowedHosts.contains("payments.worldpay.com"))
    assertTrue(BankHandoff.allowedHosts.contains("secure.worldpay.com"))
    assertTrue(BankHandoff.allowedHosts.contains("bank.rehearsal.meridian.internal"))
  }

  @Test
  fun testBuildHandoffURLRejectsHttpScheme() {
    try {
      BankHandoff.buildHandoffURL(
        bankURL = "http://payments.worldpay.com/auth",
        paymentId = "pay-001",
        returnURLScheme = "meridian",
        signingKey = ByteArray(32) { it.toByte() },
      )
      fail("Expected DomainNotAllowed for non-HTTPS URL")
    } catch (e: BankHandoffError.DomainNotAllowed) {
      assertTrue(e.message?.contains("http") == true || e.message?.contains("worldpay") == true)
    }
  }

  @Test
  fun testBuildHandoffURLRejectsUnknownDomain() {
    try {
      BankHandoff.buildHandoffURL(
        bankURL = "https://evil.bank.example.com/auth",
        paymentId = "pay-001",
        returnURLScheme = "meridian",
        signingKey = ByteArray(32) { it.toByte() },
      )
      fail("Expected DomainNotAllowed for unknown domain")
    } catch (e: BankHandoffError.DomainNotAllowed) {
      assertTrue(e.message?.contains("evil.bank.example.com") == true)
    }
  }

  @Test
  fun testBuildHandoffURLProducesStateAndRedirectParams() {
    val url = BankHandoff.buildHandoffURL(
      bankURL = "https://payments.worldpay.com/auth",
      paymentId = "pay-123",
      returnURLScheme = "meridian",
      signingKey = ByteArray(32) { it.toByte() },
    )
    assertTrue("URL must contain state param", url.contains("state="))
    assertTrue("URL must contain redirect_uri param", url.contains("redirect_uri="))
    assertTrue("URL must target allowed host", url.startsWith("https://payments.worldpay.com"))
  }

  @Test
  fun testBuildHandoffURLAddsQuerySeparatorCorrectly() {
    // Base URL already has a query param
    val url = BankHandoff.buildHandoffURL(
      bankURL = "https://payments.worldpay.com/auth?sessionId=abc",
      paymentId = "pay-456",
      returnURLScheme = "meridian",
      signingKey = ByteArray(32) { it.toByte() },
    )
    assertTrue(url.contains("sessionId=abc"))
    assertTrue(url.contains("state="))
  }

  // MARK: - BankHandoff Token Round-Trip Tests

  @Test
  fun testValidateReturnURLSucceedsWithValidToken() {
    val key = ByteArray(32) { it.toByte() }
    val token = BankHandoff.makeStateToken("pay-789", key)
    val returnURL = "meridian://payment/return?state=${java.net.URLEncoder.encode(token, "UTF-8")}"
    val nonces = mutableSetOf<String>()
    val state = BankHandoff.validateReturnURL(returnURL, key, nonces)
    assertEquals("pay-789", state.paymentId)
    assertTrue(state.nonce.isNotEmpty())
    assertEquals(1, nonces.size)
  }

  @Test
  fun testValidateReturnURLFailsWithTamperedSignature() {
    val key = ByteArray(32) { it.toByte() }
    val token = BankHandoff.makeStateToken("pay-001", key)
    // Corrupt the signature part
    val parts = token.split(".")
    val tampered = "${parts[0]}.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    val returnURL = "meridian://payment/return?state=${java.net.URLEncoder.encode(tampered, "UTF-8")}"
    val nonces = mutableSetOf<String>()
    try {
      BankHandoff.validateReturnURL(returnURL, key, nonces)
      fail("Expected InvalidSignature")
    } catch (e: BankHandoffError.InvalidSignature) {
      assertTrue("Nonce set must be empty after failure", nonces.isEmpty())
    }
  }

  @Test
  fun testValidateReturnURLFailsWithWrongKey() {
    val key = ByteArray(32) { it.toByte() }
    val wrongKey = ByteArray(32) { (it + 1).toByte() }
    val token = BankHandoff.makeStateToken("pay-001", key)
    val returnURL = "meridian://payment/return?state=${java.net.URLEncoder.encode(token, "UTF-8")}"
    val nonces = mutableSetOf<String>()
    try {
      BankHandoff.validateReturnURL(returnURL, wrongKey, nonces)
      fail("Expected InvalidSignature with wrong key")
    } catch (e: BankHandoffError.InvalidSignature) {
      assertTrue(nonces.isEmpty())
    }
  }

  @Test
  fun testValidateReturnURLFailsWhenExpired() {
    val key = ByteArray(32) { it.toByte() }
    val token = BankHandoff.makeStateToken("pay-exp", key)
    val returnURL = "meridian://payment/return?state=${java.net.URLEncoder.encode(token, "UTF-8")}"
    val nonces = mutableSetOf<String>()
    // maxAgeMs = 0 forces immediate expiry
    try {
      BankHandoff.validateReturnURL(returnURL, key, nonces, maxAgeMs = 0L)
      fail("Expected TokenExpired")
    } catch (e: BankHandoffError.TokenExpired) {
      assertTrue(nonces.isEmpty())
    }
  }

  @Test
  fun testValidateReturnURLFailsOnReplay() {
    val key = ByteArray(32) { it.toByte() }
    val token = BankHandoff.makeStateToken("pay-rep", key)
    val returnURL = "meridian://payment/return?state=${java.net.URLEncoder.encode(token, "UTF-8")}"
    val nonces = mutableSetOf<String>()
    // First call succeeds
    val state = BankHandoff.validateReturnURL(returnURL, key, nonces)
    assertEquals("pay-rep", state.paymentId)
    // Second call with same token is a replay
    try {
      BankHandoff.validateReturnURL(returnURL, key, nonces)
      fail("Expected TokenReplayed on second call")
    } catch (e: BankHandoffError.TokenReplayed) {
      // Nonce is still in the set (from first call), replay correctly rejected
      assertTrue(nonces.contains(state.nonce))
    }
  }

  @Test
  fun testValidateReturnURLFailsWithMissingStateParam() {
    val key = ByteArray(32) { it.toByte() }
    val nonces = mutableSetOf<String>()
    try {
      BankHandoff.validateReturnURL("meridian://payment/return", key, nonces)
      fail("Expected MalformedToken when state param absent")
    } catch (e: BankHandoffError.MalformedToken) {
      assertTrue(nonces.isEmpty())
    }
  }

  @Test
  fun testReturnStateHasCorrectFields() {
    val key = ByteArray(32) { it.toByte() }
    val token = BankHandoff.makeStateToken("pay-fields", key)
    val nonces = mutableSetOf<String>()
    val state = BankHandoff.verifyStateToken(token, key, nonces, 600_000L)
    assertEquals("pay-fields", state.paymentId)
    assertTrue(state.issuedAt > 0)
    assertTrue(state.nonce.matches(Regex("[0-9a-f-]{36}")))
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
}
