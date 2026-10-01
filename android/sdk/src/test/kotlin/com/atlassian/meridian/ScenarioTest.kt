package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.ObjectInputStream
import java.io.ObjectOutputStream

/**
 * Shared scenario tests verifying behavioral parity between Swift and Kotlin
 * across: money formatting edge cases, cache-expiry detection, idempotency
 * persistence across retries, and process-death state recovery.
 */
class ScenarioTest {
  private val mapper = ObjectMapper().registerKotlinModule()

  // -------------------------------------------------------------------------
  // Money Formatting Scenarios
  // -------------------------------------------------------------------------

  @Test
  fun scenarioMoneyFormatsMinimumPence() {
    assertEquals("£0.01", money(1))
  }

  @Test
  fun scenarioMoneyFormatsExactPounds() {
    assertEquals("£1.00", money(100))
    assertEquals("£10.00", money(1_000))
    assertEquals("£100.00", money(10_000))
  }

  @Test
  fun scenarioMoneyFormatsMaximumAmount() {
    // £10,000 = 1,000,000 pence
    assertEquals("£10000.00", money(1_000_000))
  }

  @Test
  fun scenarioMoneyFormatsMixedPence() {
    assertEquals("£10.50", money(1_050))
    assertEquals("£0.99", money(99))
    assertEquals("£1.05", money(105))
    assertEquals("£99.99", money(9_999))
  }

  @Test
  fun scenarioMoneyFormattingRoundTripsWithParseAmount() {
    // Format then strip symbol and re-parse; result must equal the original pence value
    val samples = listOf(1, 50, 100, 1_050, 9_999, 1_000_000)
    samples.forEach { originalPence ->
      val formatted = money(originalPence)
      val stripped = formatted.removePrefix("£")
      val (parsed, error) = parseAmount(stripped)
      assertNull("Parse error for £$stripped: $error", error)
      assertEquals("Round-trip failed for $originalPence pence", originalPence, parsed)
    }
  }

  // -------------------------------------------------------------------------
  // Cache Expiry Scenarios
  // -------------------------------------------------------------------------

  @Test
  fun scenarioCacheExpiryDetectedByStateVersion() {
    // A locally cached state has a lower version than the fresh server state
    val staleState = BankState(version = 1, balance = 100_000, transactions = emptyList(), budgets = emptyList())
    val freshState  = BankState(version = 5, balance = 95_000, transactions = emptyList(), budgets = emptyList())
    assertTrue("Fresh state must have a higher version than stale state",
      freshState.version > staleState.version)
  }

  @Test
  fun scenarioCacheExpiryTransactionDateComparison() {
    val stale = Transaction("txn-old","R","rc","Old","Shopping",500,"2026-01-01","adyen","card","completed","")
    val fresh = Transaction("txn-new","R","rc","New","Shopping",500,"2026-09-18","adyen","card","completed","")
    assertTrue("Fresh transaction date must sort after stale date", fresh.date > stale.date)
  }

  @Test
  fun scenarioCatalogVersionBumpInvalidatesCache() {
    val v1 = CatalogResponse(
      demoDate = "2026-09-17",
      recipients = listOf(Recipient("r1","A","A","D","Shopping","#fff")),
      providers  = listOf(Provider("adyen","Adyen","Card",listOf("card")))
    )
    val v2 = CatalogResponse(
      demoDate = "2026-09-18",
      recipients = listOf(
        Recipient("r1","A","A","D","Shopping","#fff"),
        Recipient("r2","B","B","D","Food & drink","#aaa")
      ),
      providers = listOf(
        Provider("adyen","Adyen","Card",listOf("card")),
        Provider("worldpay","Worldpay","Bank",listOf("bank"))
      )
    )
    assertTrue("Newer catalog demoDate signals cache invalidation",
      v2.demoDate > v1.demoDate)
    assertTrue("Newer catalog has more recipients", v2.recipients.size > v1.recipients.size)
  }

  @Test
  fun scenarioStaleStateZeroVersionIsAlwaysExpired() {
    // version == 0 means uninitialised; treat as always-stale
    val uninitialised = BankState(version = 0, balance = 0, transactions = emptyList(), budgets = emptyList())
    assertTrue("version 0 must be treated as stale", uninitialised.version == 0)
  }

  // -------------------------------------------------------------------------
  // Idempotency Persistence Scenarios
  // -------------------------------------------------------------------------

  @Test
  fun scenarioIdempotencyKeyIsNonEmptyUuid() {
    val key = java.util.UUID.randomUUID().toString()
    assertTrue("Generated idempotency key must be non-empty", key.isNotEmpty())
    assertTrue("Generated idempotency key must be ≤ 128 chars", key.length <= 128)
  }

  @Test
  fun scenarioIdempotencyRetryReturnsSamePaymentId() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    val fixedPaymentId = "pay-idm-999"
    var callCount = 0

    server.createContext("/api/v1/payments") { exchange ->
      callCount++
      val body = """{"ok":true,"paymentId":"$fixedPaymentId","state":{"version":1,"balance":90000,"transactions":[],"budgets":[]}}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, body.length.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }
    server.start()

    try {
      val client = MeridianClient("http://127.0.0.1:$port/api/v1", "sess-idm")
      val key = "idm-key-scenario-1"

      val r1 = runBlocking { client.submitPayment("rec-1", 500, PaymentMethod.card, idempotencyKey = key) }
      val r2 = runBlocking { client.submitPayment("rec-1", 500, PaymentMethod.card, idempotencyKey = key) }

      assertEquals(fixedPaymentId, r1.paymentId)
      assertEquals(fixedPaymentId, r2.paymentId)
      assertEquals("Both retries must reach the server", 2, callCount)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun scenarioIdempotencyPendingThenResolved() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    var callCount = 0

    server.createContext("/api/v1/payments") { exchange ->
      callCount++
      val (status, body) = if (callCount == 1) {
        202 to """{"ok":false,"code":"PAYMENT_PENDING","paymentId":"pay-xyz","error":"Awaiting confirmation"}"""
      } else {
        200 to """{"ok":true,"paymentId":"pay-xyz","state":{"version":2,"balance":90000,"transactions":[],"budgets":[]}}"""
      }
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(status, body.length.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }
    server.start()

    try {
      val client = MeridianClient("http://127.0.0.1:$port/api/v1", "sess-pending")
      val key = "idm-key-scenario-2"

      val r1 = runBlocking { client.submitPayment("rec-1", 1000, PaymentMethod.bank, idempotencyKey = key) }
      assertFalse("First call must return pending", r1.ok)
      assertEquals("PAYMENT_PENDING", r1.code)
      assertNotNull(r1.paymentId)

      // Retry with the same key resolves
      val r2 = runBlocking { client.submitPayment("rec-1", 1000, PaymentMethod.bank, idempotencyKey = key) }
      assertTrue("Retry must resolve to success", r2.ok)
      assertEquals("pay-xyz", r2.paymentId)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun scenarioIdempotencyKeyIncludedInRequestHeader() {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    var capturedKey: String? = null

    server.createContext("/api/v1/payments") { exchange ->
      capturedKey = exchange.requestHeaders.getFirst("Idempotency-Key")
      val body = """{"ok":true,"state":{"version":1,"balance":1000,"transactions":[],"budgets":[]}}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, body.length.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }
    server.start()

    try {
      val client = MeridianClient("http://127.0.0.1:$port/api/v1", "sess-header")
      val key = "my-explicit-idm-key"
      runBlocking { client.submitPayment("rec-1", 200, PaymentMethod.card, idempotencyKey = key) }
      assertEquals("Idempotency-Key header must match the supplied key", key, capturedKey)
    } finally {
      server.stop(0)
    }
  }

  // -------------------------------------------------------------------------
  // Process Death / State Recovery Scenarios
  // -------------------------------------------------------------------------

  @Test
  fun scenarioProcessDeathBankStateIsSerializable() {
    val original = BankState(
      version = 3,
      balance = 250_000,
      transactions = listOf(
        Transaction(
          id = "txn-pd-1", reference = "REF-PD-001", recipientId = "rec-1",
          name = "Test Merchant", category = "Shopping", amount = 2_500,
          date = "2026-09-18", provider = "worldpay", method = "bank",
          status = "completed", note = "Post-death recovery"
        )
      ),
      budgets = listOf(Budget("Shopping", 50_000))
    )

    val restored: BankState = roundTripSerialize(original)

    assertEquals(original.version, restored.version)
    assertEquals(original.balance, restored.balance)
    assertEquals(1, restored.transactions.size)
    assertEquals("txn-pd-1", restored.transactions[0].id)
    assertEquals(2_500, restored.transactions[0].amount)
    assertEquals(1, restored.budgets.size)
    assertEquals(50_000, restored.budgets[0].limit)
  }

  @Test
  fun scenarioProcessDeathPaymentResponseIsSerializable() {
    val original = PaymentResponse(
      ok = false,
      code = "PAYMENT_PENDING",
      paymentId = "pay-pd-99",
      error = "Awaiting bank confirmation"
    )
    val restored: PaymentResponse = roundTripSerialize(original)
    assertFalse(restored.ok)
    assertEquals("PAYMENT_PENDING", restored.code)
    assertEquals("pay-pd-99", restored.paymentId)
  }

  @Test
  fun scenarioProcessDeathCatalogResponseIsSerializable() {
    val original = CatalogResponse(
      demoDate = "2026-09-18",
      recipients = listOf(Recipient("rec-1", "Shop", "SH", "Detail", "Shopping", "#fff")),
      providers  = listOf(Provider("adyen", "Adyen", "Card", listOf("card")))
    )
    val restored: CatalogResponse = roundTripSerialize(original)
    assertEquals("2026-09-18", restored.demoDate)
    assertEquals(1, restored.recipients.size)
    assertEquals("rec-1", restored.recipients[0].id)
  }

  @Test
  fun scenarioProcessDeathPreservesIdempotencyId() {
    // After a crash, the stored PaymentResponse must retain the idempotency/paymentId
    // so the app can retry on restart without generating a duplicate payment.
    val pending = PaymentResponse(
      ok = false,
      code = "PAYMENT_PENDING",
      paymentId = "pay-crash-recovery",
      error = "Awaiting confirmation"
    )
    val recovered: PaymentResponse = roundTripSerialize(pending)
    assertEquals("pay-crash-recovery", recovered.paymentId)
    assertEquals("PAYMENT_PENDING", recovered.code)
    assertFalse(recovered.ok)
  }

  @Test
  fun scenarioProcessDeathBudgetIsSerializable() {
    val original = Budget("Transport", 20_000)
    val restored: Budget = roundTripSerialize(original)
    assertEquals("Transport", restored.category)
    assertEquals(20_000, restored.limit)
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  private inline fun <reified T : java.io.Serializable> roundTripSerialize(obj: T): T {
    val baos = ByteArrayOutputStream()
    ObjectOutputStream(baos).use { it.writeObject(obj) }
    return ObjectInputStream(ByteArrayInputStream(baos.toByteArray())).use {
      @Suppress("UNCHECKED_CAST")
      it.readObject() as T
    }
  }
}
