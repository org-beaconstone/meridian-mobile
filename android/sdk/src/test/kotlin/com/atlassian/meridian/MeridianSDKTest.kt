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

  // MARK: - PaymentIntentStatus Tests

  @Test
  fun testPaymentIntentStatusTerminal() {
    assertFalse(PaymentIntentStatus.pending.isTerminal)
    assertTrue(PaymentIntentStatus.completed.isTerminal)
    assertTrue(PaymentIntentStatus.declined.isTerminal)
    assertTrue(PaymentIntentStatus.failed.isTerminal)
  }

  // MARK: - PaymentIntentSnapshot Tests

  @Test
  fun testSnapshotIsActivePending() {
    val snapshot = PaymentIntentSnapshot(
      paymentIntentId = "pi-001",
      idempotencyKey = "idem-001",
      businessPayloadHash = "abc123",
      status = PaymentIntentStatus.pending,
      createdAt = "2026-09-29T10:00:00Z",
    )
    assertTrue(snapshot.isActive)
    assertFalse(snapshot.isExpired)
  }

  @Test
  fun testSnapshotIsNotActiveWhenCompleted() {
    val snapshot = PaymentIntentSnapshot(
      paymentIntentId = "pi-002",
      idempotencyKey = "idem-002",
      businessPayloadHash = "abc123",
      status = PaymentIntentStatus.completed,
      createdAt = "2026-09-29T10:00:00Z",
      resolvedAt = "2026-09-29T10:01:00Z",
    )
    assertFalse(snapshot.isActive)
    assertFalse(snapshot.isExpired) // within retention window
  }

  @Test
  fun testSnapshotIsExpiredAfterRetentionWindow() {
    // resolvedAt is 25 hours ago (past 24-hour retention)
    val resolvedAt = java.time.Instant.now()
      .minusSeconds(PaymentIntentSnapshot.RETENTION_SECONDS + 3600)
      .toString()
    val snapshot = PaymentIntentSnapshot(
      paymentIntentId = "pi-003",
      idempotencyKey = "idem-003",
      businessPayloadHash = "abc123",
      status = PaymentIntentStatus.completed,
      createdAt = "2026-09-28T08:00:00Z",
      resolvedAt = resolvedAt,
    )
    assertFalse(snapshot.isActive)
    assertTrue(snapshot.isExpired)
  }

  @Test
  fun testSnapshotNotExpiredWithinRetentionWindow() {
    val resolvedAt = java.time.Instant.now().minusSeconds(3600).toString() // 1 hour ago
    val snapshot = PaymentIntentSnapshot(
      paymentIntentId = "pi-004",
      idempotencyKey = "idem-004",
      businessPayloadHash = "abc123",
      status = PaymentIntentStatus.declined,
      createdAt = "2026-09-29T09:00:00Z",
      resolvedAt = resolvedAt,
    )
    assertFalse(snapshot.isExpired)
  }

  @Test
  fun testSnapshotPendingNeverExpires() {
    // A pending snapshot has no resolvedAt, so isExpired must be false
    val snapshot = PaymentIntentSnapshot(
      paymentIntentId = "pi-005",
      idempotencyKey = "idem-005",
      businessPayloadHash = "abc123",
      status = PaymentIntentStatus.pending,
      createdAt = "2026-01-01T00:00:00Z",
    )
    assertFalse(snapshot.isExpired)
  }

  @Test
  fun testSnapshotIncludesReturnState() {
    val bankState = BankState(
      version = 2,
      balance = 950000,
      transactions = emptyList(),
      budgets = emptyList(),
    )
    val snapshot = PaymentIntentSnapshot(
      paymentIntentId = "pi-006",
      idempotencyKey = "idem-006",
      businessPayloadHash = "deadbeef",
      status = PaymentIntentStatus.completed,
      returnState = bankState,
      createdAt = "2026-09-29T12:00:00Z",
      resolvedAt = "2026-09-29T12:00:05Z",
    )
    assertNotNull(snapshot.returnState)
    assertEquals(950000, snapshot.returnState?.balance)
  }

  // MARK: - businessPayloadHash Tests

  @Test
  fun testBusinessPayloadHashDeterministic() {
    val h1 = businessPayloadHash("northline-studio", 2599, PaymentMethod.card, "test note", Scenario.success)
    val h2 = businessPayloadHash("northline-studio", 2599, PaymentMethod.card, "test note", Scenario.success)
    assertEquals(h1, h2)
  }

  @Test
  fun testBusinessPayloadHashDiffersOnAmountChange() {
    val h1 = businessPayloadHash("northline-studio", 2599, PaymentMethod.card, "note", Scenario.success)
    val h2 = businessPayloadHash("northline-studio", 2600, PaymentMethod.card, "note", Scenario.success)
    assertNotEquals(h1, h2)
  }

  @Test
  fun testBusinessPayloadHashDiffersOnRecipientChange() {
    val h1 = businessPayloadHash("recipient-a", 1000, PaymentMethod.bank, "", Scenario.success)
    val h2 = businessPayloadHash("recipient-b", 1000, PaymentMethod.bank, "", Scenario.success)
    assertNotEquals(h1, h2)
  }

  @Test
  fun testBusinessPayloadHashDiffersOnMethodChange() {
    val h1 = businessPayloadHash("rec", 500, PaymentMethod.card, "", Scenario.success)
    val h2 = businessPayloadHash("rec", 500, PaymentMethod.bank, "", Scenario.success)
    assertNotEquals(h1, h2)
  }

  @Test
  fun testBusinessPayloadHashIsHexString() {
    val hash = businessPayloadHash("rec", 100, PaymentMethod.card, "note", Scenario.success)
    assertTrue("Hash should be a 64-char hex string", hash.matches(Regex("[0-9a-f]{64}")))
  }

  // MARK: - InMemoryPaymentIntentStore Tests

  @Test
  fun testStoreSaveAndLoad() {
    val store = InMemoryPaymentIntentStore()
    val snapshot = PaymentIntentSnapshot(
      paymentIntentId = "pi-save-1",
      idempotencyKey = "idem-save-1",
      businessPayloadHash = "aabbcc",
      status = PaymentIntentStatus.pending,
      createdAt = "2026-09-29T10:00:00Z",
    )
    store.save(snapshot, "account-1")
    val all = store.loadAll("account-1")
    assertEquals(1, all.size)
    assertEquals("pi-save-1", all[0].paymentIntentId)
    assertEquals(PaymentIntentStatus.pending, all[0].status)
  }

  @Test
  fun testStoreUpdateExisting() {
    val store = InMemoryPaymentIntentStore()
    val initial = PaymentIntentSnapshot(
      paymentIntentId = "pi-upd-1",
      idempotencyKey = "idem-upd-1",
      businessPayloadHash = "hash",
      status = PaymentIntentStatus.pending,
      createdAt = "2026-09-29T10:00:00Z",
    )
    store.save(initial, "account-upd")

    val updated = initial.copy(
      status = PaymentIntentStatus.completed,
      resolvedAt = "2026-09-29T10:05:00Z",
    )
    store.save(updated, "account-upd")

    val all = store.loadAll("account-upd")
    assertEquals(1, all.size) // still one entry
    assertEquals(PaymentIntentStatus.completed, all[0].status)
    assertEquals("2026-09-29T10:05:00Z", all[0].resolvedAt)
  }

  @Test
  fun testStoreAccountIsolation() {
    val store = InMemoryPaymentIntentStore()
    val snap1 = PaymentIntentSnapshot(
      paymentIntentId = "pi-iso-1",
      idempotencyKey = "idem-iso-1",
      businessPayloadHash = "h1",
      status = PaymentIntentStatus.pending,
      createdAt = "2026-09-29T10:00:00Z",
    )
    val snap2 = PaymentIntentSnapshot(
      paymentIntentId = "pi-iso-2",
      idempotencyKey = "idem-iso-2",
      businessPayloadHash = "h2",
      status = PaymentIntentStatus.pending,
      createdAt = "2026-09-29T10:00:00Z",
    )
    store.save(snap1, "account-A")
    store.save(snap2, "account-B")

    assertEquals(1, store.loadAll("account-A").size)
    assertEquals("pi-iso-1", store.loadAll("account-A")[0].paymentIntentId)
    assertEquals(1, store.loadAll("account-B").size)
    assertEquals("pi-iso-2", store.loadAll("account-B")[0].paymentIntentId)
  }

  @Test
  fun testStoreLoadActiveIntent() {
    val store = InMemoryPaymentIntentStore()
    val pending = PaymentIntentSnapshot(
      paymentIntentId = "pi-active-1",
      idempotencyKey = "idem-active-1",
      businessPayloadHash = "h",
      status = PaymentIntentStatus.pending,
      createdAt = "2026-09-29T10:00:00Z",
    )
    store.save(pending, "account-active")
    val active = store.loadActiveIntent("account-active")
    assertNotNull(active)
    assertEquals("pi-active-1", active?.paymentIntentId)
  }

  @Test
  fun testStoreLoadActiveIntentSkipsCompleted() {
    val store = InMemoryPaymentIntentStore()
    val completed = PaymentIntentSnapshot(
      paymentIntentId = "pi-done-1",
      idempotencyKey = "idem-done-1",
      businessPayloadHash = "h",
      status = PaymentIntentStatus.completed,
      createdAt = "2026-09-29T10:00:00Z",
      resolvedAt = "2026-09-29T10:01:00Z",
    )
    store.save(completed, "account-done")
    val active = store.loadActiveIntent("account-done")
    assertNull(active)
  }

  @Test
  fun testStoreLoadActiveIntentSkipsExpired() {
    val store = InMemoryPaymentIntentStore()
    // Simulate a stale pending that was resolved long ago and is now expired
    val resolvedAt = java.time.Instant.now()
      .minusSeconds(PaymentIntentSnapshot.RETENTION_SECONDS + 7200)
      .toString()
    val expired = PaymentIntentSnapshot(
      paymentIntentId = "pi-exp-1",
      idempotencyKey = "idem-exp-1",
      businessPayloadHash = "h",
      status = PaymentIntentStatus.completed,
      createdAt = "2026-09-28T00:00:00Z",
      resolvedAt = resolvedAt,
    )
    store.save(expired, "account-exp")
    val active = store.loadActiveIntent("account-exp")
    assertNull(active)
  }

  @Test
  fun testStoreDelete() {
    val store = InMemoryPaymentIntentStore()
    val snap = PaymentIntentSnapshot(
      paymentIntentId = "pi-del-1",
      idempotencyKey = "idem-del-1",
      businessPayloadHash = "h",
      status = PaymentIntentStatus.pending,
      createdAt = "2026-09-29T10:00:00Z",
    )
    store.save(snap, "account-del")
    store.delete("pi-del-1", "account-del")
    assertEquals(0, store.loadAll("account-del").size)
  }

  @Test
  fun testStorePurgeExpired() {
    val store = InMemoryPaymentIntentStore()
    val resolvedAt = java.time.Instant.now()
      .minusSeconds(PaymentIntentSnapshot.RETENTION_SECONDS + 3600)
      .toString()
    val expired = PaymentIntentSnapshot(
      paymentIntentId = "pi-purge-expired",
      idempotencyKey = "idem-purge-expired",
      businessPayloadHash = "h",
      status = PaymentIntentStatus.failed,
      createdAt = "2026-09-28T00:00:00Z",
      resolvedAt = resolvedAt,
    )
    val active = PaymentIntentSnapshot(
      paymentIntentId = "pi-purge-active",
      idempotencyKey = "idem-purge-active",
      businessPayloadHash = "h",
      status = PaymentIntentStatus.pending,
      createdAt = "2026-09-29T10:00:00Z",
    )
    store.save(expired, "account-purge")
    store.save(active, "account-purge")
    assertEquals(2, store.loadAll("account-purge").size)

    store.purgeExpired("account-purge")
    val remaining = store.loadAll("account-purge")
    assertEquals(1, remaining.size)
    assertEquals("pi-purge-active", remaining[0].paymentIntentId)
  }

  @Test
  fun testStoreEmptyAccountReturnsEmpty() {
    val store = InMemoryPaymentIntentStore()
    assertEquals(0, store.loadAll("no-such-account").size)
    assertNull(store.loadActiveIntent("no-such-account"))
  }
}
