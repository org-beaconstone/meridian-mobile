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
    assertTrue(response.providers[0].available)
    assertTrue(response.corridors.isEmpty())
    assertEquals(setOf(PaymentMethod.card), response.activeBaselineMethods())
  }

  @Test
  fun testCatalogIgnoresUnknownFieldsAndFiltersAvailability() {
    val json = """
      {
        "demoDate": "2026-09-28",
        "recipients": [],
        "providers": [
          {"id": "adyen", "name": "Adyen", "description": "Card payment processor", "methods": ["card", "bank"], "available": false},
          {"id": "worldpay", "name": "Worldpay", "description": "Bank payment processor", "methods": ["bank"]}
        ],
        "corridors": [
          {"id": "gb-domestic", "source": "GB", "destination": "GB", "currency": "GBP", "available": true},
          {"id": "closed", "source": "GB", "destination": "GB", "currency": "GBP", "available": false}
        ],
        "region": "GB"
      }
    """.trimIndent()

    val response = mapper.readValue(json, CatalogResponse::class.java)
    assertEquals(2, response.providers.size)
    assertFalse(response.providers[0].available)
    assertTrue(response.providers[1].available)
    assertEquals(setOf(PaymentMethod.bank), response.activeBaselineMethods())
    assertEquals(2, response.corridors.size)
    assertEquals("GBP", response.corridors[0].currency)

    val unknown = response.copy(
      providers = listOf(Provider("unknown", "Unknown", "Unrecognized", listOf("card"))),
    )
    assertTrue(unknown.activeBaselineMethods().isEmpty())
    assertNull(acceptCatalog(unknown))
    val presented = presentCatalog(response)
    assertEquals(listOf("worldpay"), presented.providers.map { it.id })
    assertEquals(listOf("gb-domestic"), presented.corridors.map { it.id })
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
  fun testCatalogCacheFallbackAndSessionIsolation() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"
    val clock = object { var now: Long = 10_000L }
    var status = 200
    var body = catalogBody()
    var hits = 0
    server.createContext("/api/v1/catalog") { exchange ->
      hits += 1
      val session = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      check(session == "room-a" || session == "room-b")
      val payload = body.toByteArray(Charsets.UTF_8)
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(status, payload.size.toLong())
      exchange.responseBody.write(payload)
      exchange.close()
    }
    server.start()
    val store = MemoryCatalogStore()
    val clientA = MeridianClient(
      baseURL = baseUrl,
      sessionId = "room-a",
      catalogStore = store,
      catalogTtlMillis = 1_000,
      clock = { clock.now },
    )
    try {
      val first = runBlocking { clientA.getCatalog() }
      assertEquals(listOf("adyen", "worldpay"), first.providers.map { it.id })
      assertEquals(listOf("northline-studio"), first.recipients.map { it.id })
      assertEquals(listOf("gb-domestic"), first.corridors.map { it.id })
      assertFalse(clientA.catalogUsingFallback)
      assertEquals(1, hits)

      val cached = runBlocking { clientA.getCatalog() }
      assertEquals(first, cached)
      assertEquals(1, hits)

      clock.now += 5_000
      status = 502
      body = """{"error":"bad gateway"}"""
      val gateway = runBlocking { clientA.getCatalog() }
      assertEquals(listOf("adyen", "worldpay"), gateway.providers.map { it.id })
      assertTrue(clientA.catalogUsingFallback)
      assertEquals("saved", store.read("$baseUrl\nroom-a")?.catalog?.demoDate)

      status = 500
      val internalError = runBlocking { clientA.getCatalog() }
      assertEquals("northline-studio", internalError.recipients[0].id)
      assertTrue(clientA.catalogUsingFallback)

      status = 504
      val timeout = runBlocking { clientA.getCatalog() }
      assertEquals(setOf(PaymentMethod.card, PaymentMethod.bank), timeout.activeBaselineMethods())

      status = 200
      body = catalogBody(
        providers = """[
          {"id":"adyen","name":"Adyen","description":"Card payment processor","methods":["card"],"available":false},
          {"id":"worldpay","name":"Worldpay","description":"Bank payment processor","methods":["bank"],"available":true}
        ]""",
      )
      val hidden = runBlocking { clientA.getCatalog() }
      assertEquals(listOf("worldpay"), hidden.providers.map { it.id })
      assertEquals(setOf(PaymentMethod.bank), hidden.activeBaselineMethods())
      assertFalse(clientA.catalogUsingFallback)

      clock.now += 5_000
      body = catalogBody(
        providers = """[
          {"id":"adyen","name":"Adyen","description":"Card payment processor","methods":["card"]},
          {"id":"unknown","name":"Unknown","description":"Unrecognized","methods":["card"]}
        ]""",
      )
      val rejected = runBlocking { clientA.getCatalog() }
      assertEquals(listOf("worldpay"), rejected.providers.map { it.id })
      assertTrue(clientA.catalogUsingFallback)
      assertFalse(store.read("$baseUrl\nroom-a")!!.catalog.providers.any { it.id == "unknown" })

      status = 400
      body = """{"error":"bad request"}"""
      clock.now += 5_000
      val httpError = assertThrows(MeridianError.HttpError::class.java) {
        runBlocking { clientA.getCatalog() }
      }
      assertEquals(400, httpError.statusCode)

      val clientB = MeridianClient(
        baseURL = baseUrl,
        sessionId = "room-b",
        catalogStore = store,
        catalogTtlMillis = 1_000,
        clock = { clock.now },
      )
      status = 504
      body = """{"error":"timeout"}"""
      val isolated = runBlocking { clientB.getCatalog() }
      assertTrue(isolated.recipients.isEmpty())
      assertEquals(listOf("adyen", "worldpay"), isolated.providers.map { it.id })
      assertTrue(clientB.catalogUsingFallback)

      server.stop(0)
      clock.now += 5_000
      val offline = runBlocking { clientA.getCatalog() }
      assertEquals("northline-studio", offline.recipients.single().id)
      assertTrue(clientA.catalogUsingFallback)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testEncryptedCatalogStoreRoundTrip() {
    val directory = java.nio.file.Files.createTempDirectory("meridian-catalog").toFile()
    val store = EncryptedFileCatalogStore(directory)
    val entry = CachedCatalog(baselineCatalog().copy(demoDate = "baseline"), 42L)
    store.write("room\nsecret", entry)
    val blob = directory.listFiles { file -> file.name.endsWith(".catalog") }!!.single().readBytes()
    val text = String(blob, Charsets.ISO_8859_1)
    assertFalse(text.contains("worldpay"))
    assertFalse(text.contains("adyen"))
    assertFalse(blob.first().toInt().toChar() == '{')

    val reopened = EncryptedFileCatalogStore(directory)
    val loaded = reopened.read("room\nsecret")
    assertEquals("baseline", loaded?.catalog?.demoDate)
    assertEquals(listOf("adyen", "worldpay"), loaded?.catalog?.providers?.map { it.id })
    assertEquals(42L, loaded?.fetchedAtEpochMs)
    assertNull(reopened.read("other-room"))
  }

  private fun catalogBody(
    providers: String = """[
      {"id":"adyen","name":"Adyen","description":"Card payment processor","methods":["card"]},
      {"id":"worldpay","name":"Worldpay","description":"Bank payment processor","methods":["bank"]}
    ]""",
    corridors: String = """[
      {"id":"gb-domestic","source":"GB","destination":"GB","currency":"GBP","available":true},
      {"id":"closed","source":"GB","destination":"GB","currency":"GBP","available":false}
    ]""",
  ) = """
    {
      "demoDate": "saved",
      "recipients": [
        {"id":"northline-studio","name":"Northline Studio","initials":"NS","detail":"Design","category":"Shopping","color":"#111111"}
      ],
      "providers": $providers,
      "corridors": $corridors
    }
  """.trimIndent()
}
