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

  // MARK: - PaymentIntentSnapshot Tests

  @Test
  fun testPaymentIntentStatusTerminalFlags() {
    assertTrue(PaymentIntentStatus.completed.isTerminal)
    assertTrue(PaymentIntentStatus.declined.isTerminal)
    assertTrue(PaymentIntentStatus.expired.isTerminal)
    assertFalse(PaymentIntentStatus.created.isTerminal)
    assertFalse(PaymentIntentStatus.pending.isTerminal)
  }

  @Test
  fun testPaymentPayloadHashDeterministic() {
    val h1 = paymentPayloadHash("r1", 1000, "card", "note")
    val h2 = paymentPayloadHash("r1", 1000, "card", "note")
    val h3 = paymentPayloadHash("r2", 1000, "card", "note")
    assertEquals(h1, h2)
    assertNotEquals(h1, h3)
    assertEquals(64, h1.length) // SHA-256 hex = 64 chars
  }

  @Test
  fun testBankStateHashDeterministic() {
    val bh1 = bankStateHash(1, 100_000)
    val bh2 = bankStateHash(1, 100_000)
    val bh3 = bankStateHash(2, 100_000)
    assertEquals(bh1, bh2)
    assertNotEquals(bh1, bh3)
    assertEquals(64, bh1.length)
  }

  @Test
  fun testPaymentIntentSnapshotFields() {
    val snap = PaymentIntentSnapshot(
      paymentIntentId = "pi-1",
      idempotencyKey = "ik-1",
      businessPayloadHash = "abc",
      status = PaymentIntentStatus.pending,
      returnStateHash = "def",
    )
    assertEquals("pi-1", snap.paymentIntentId)
    assertEquals("ik-1", snap.idempotencyKey)
    assertEquals("abc", snap.businessPayloadHash)
    assertEquals(PaymentIntentStatus.pending, snap.status)
    assertEquals("def", snap.returnStateHash)
    assertFalse(snap.isExpired)
  }

  @Test
  fun testSnapshotExpiryAfterRetentionWindow() {
    val pastWindow = System.currentTimeMillis() -
      (PaymentIntentSnapshot.TERMINAL_RETENTION_MS + 1000)
    val expired = PaymentIntentSnapshot(
      paymentIntentId = "pi-2",
      idempotencyKey = "ik-2",
      businessPayloadHash = "x",
      status = PaymentIntentStatus.completed,
      updatedAt = pastWindow,
    )
    assertTrue(expired.isExpired)
  }

  @Test
  fun testSnapshotNotExpiredWithinRetentionWindow() {
    val recent = PaymentIntentSnapshot(
      paymentIntentId = "pi-3",
      idempotencyKey = "ik-3",
      businessPayloadHash = "y",
      status = PaymentIntentStatus.completed,
    )
    assertFalse(recent.isExpired)
  }

  @Test
  fun testActiveSnapshotNeverExpires() {
    val active = PaymentIntentSnapshot(
      paymentIntentId = "pi-4",
      idempotencyKey = "ik-4",
      businessPayloadHash = "z",
      status = PaymentIntentStatus.pending,
    )
    assertFalse(active.isExpired)
  }

  @Test
  fun testInMemoryStoreSaveAndLoad() = runBlocking {
    val store = InMemoryPaymentIntentStore()
    val snap = PaymentIntentSnapshot(
      paymentIntentId = "pi-5",
      idempotencyKey = "ik-5",
      businessPayloadHash = "p",
      status = PaymentIntentStatus.created,
    )
    store.save(snap)
    val loaded = store.load("ik-5")
    val missing = store.load("ik-missing")
    assertNotNull(loaded)
    assertEquals("ik-5", loaded?.idempotencyKey)
    assertNull(missing)
  }

  @Test
  fun testInMemoryStoreDelete() = runBlocking {
    val store = InMemoryPaymentIntentStore()
    val snap = PaymentIntentSnapshot(
      paymentIntentId = "pi-6",
      idempotencyKey = "ik-6",
      businessPayloadHash = "q",
      status = PaymentIntentStatus.created,
    )
    store.save(snap)
    store.delete("ik-6")
    val afterDelete = store.load("ik-6")
    assertNull(afterDelete)
  }

  @Test
  fun testInMemoryStoreLoadActiveFiltering() = runBlocking {
    val store = InMemoryPaymentIntentStore()
    store.save(PaymentIntentSnapshot("pi-a", "ik-a", "1", PaymentIntentStatus.pending))
    store.save(PaymentIntentSnapshot("pi-b", "ik-b", "2", PaymentIntentStatus.created))
    store.save(PaymentIntentSnapshot("pi-c", "ik-c", "3", PaymentIntentStatus.completed))
    // Expired declined snapshot
    val oldTime = System.currentTimeMillis() -
      (PaymentIntentSnapshot.TERMINAL_RETENTION_MS + 60_000)
    store.save(
      PaymentIntentSnapshot(
        paymentIntentId = "pi-d",
        idempotencyKey = "ik-d",
        businessPayloadHash = "4",
        status = PaymentIntentStatus.declined,
        updatedAt = oldTime,
      )
    )

    val actives = store.loadActive()
    val ids = actives.map { it.idempotencyKey }.toSet()
    assertEquals(setOf("ik-a", "ik-b"), ids)
  }

  @Test
  fun testResumeActiveIntentsWithoutStore() = runBlocking {
    val client = MeridianClient(
      baseURL = "http://localhost:8080/api/v1",
      sessionId = "test-session",
    )
    val intents = client.resumeActiveIntents()
    assertTrue(intents.isEmpty())
  }

  @Test
  fun testResumeActiveIntentsWithStore() = runBlocking {
    val store = InMemoryPaymentIntentStore()
    store.save(PaymentIntentSnapshot("pi-x", "ik-x", "h", PaymentIntentStatus.pending))
    store.save(PaymentIntentSnapshot("pi-y", "ik-y", "h", PaymentIntentStatus.completed))

    val client = MeridianClient(
      baseURL = "http://localhost:8080/api/v1",
      sessionId = "test-session",
      snapshotStore = store,
    )
    val actives = client.resumeActiveIntents()
    assertEquals(1, actives.size)
    assertEquals("ik-x", actives[0].idempotencyKey)
  }

  @Test
  fun testSubmitPaymentPersistsSnapshotLifecycle() = runBlocking {
    // Stand up a local HTTP server to simulate the payment endpoint
    val server = com.sun.net.httpserver.HttpServer.create(
      java.net.InetSocketAddress("127.0.0.1", 0), 0
    )
    val port = server.address.port
    val baseUrl = "http://127.0.0.1:$port/api/v1"

    val callCount = java.util.concurrent.atomic.AtomicInteger(0)
    server.createContext("/api/v1/payments") { exchange ->
      val call = callCount.incrementAndGet()
      val responseBody = if (call == 1) {
        """{"ok":false,"code":"PAYMENT_PENDING","paymentId":"pay-server-001","error":"Awaiting confirmation"}"""
      } else {
        """{"ok":true,"paymentId":"pay-server-001","state":{"version":2,"balance":999000,"transactions":[],"budgets":[]}}"""
      }
      val status = if (call == 1) 202 else 200
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(status, responseBody.length.toLong())
      exchange.responseBody.write(responseBody.toByteArray())
      exchange.close()
    }
    server.start()

    val store = InMemoryPaymentIntentStore()
    val client = MeridianClient(baseUrl, "test-session", store)
    val key = "test-idempotency-key"

    try {
      // First call → pending
      val r1 = client.submitPayment("rec-1", 1000, PaymentMethod.card, idempotencyKey = key)
      assertFalse(r1.ok)
      assertEquals("PAYMENT_PENDING", r1.code)

      val snap1 = store.load(key)
      assertNotNull(snap1)
      assertEquals(PaymentIntentStatus.pending, snap1?.status)
      assertEquals("pay-server-001", snap1?.paymentIntentId)

      // Second call with same key → completed
      val r2 = client.submitPayment("rec-1", 1000, PaymentMethod.card, idempotencyKey = key)
      assertTrue(r2.ok)

      val snap2 = store.load(key)
      assertNotNull(snap2)
      assertEquals(PaymentIntentStatus.completed, snap2?.status)
      assertNotNull(snap2?.returnStateHash)
    } finally {
      server.stop(0)
    }
  }
}
