package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetSocketAddress
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors

/**
 * JUnit rehearsal suite for the Kotlin client used by the Android app.
 * The suite speaks the shared Spring Boot contract on a local HTTP mock: GBP pence,
 * Adyen card, Worldpay bank, catalog hydration, idempotency, HTTP 202 pending,
 * unavailable retry, and gateway timeout. It does not call a live provider.
 */
class RehearsalSuiteTest {
  private val json = ObjectMapper()

  @Test
  fun testGbpPenceRangeRejectsCurrencySwitch() {
    val (min, minError) = parseAmount("0.01")
    assertEquals(1, min)
    assertNull(minError)
    val (max, maxError) = parseAmount("10000.00")
    assertEquals(1_000_000, max)
    assertNull(maxError)
    val (zero, zeroError) = parseAmount("0.00")
    assertNull(zero)
    assertEquals("Amount must be greater than zero", zeroError)
    val (over, overError) = parseAmount("10000.01")
    assertNull(over)
    assertEquals("Amount cannot exceed £10,000", overError)

    val (euroMin, euroMinError) = parseAmount("0.01", "EUR")
    assertNull(euroMin)
    assertEquals("Only GBP integer pence are supported", euroMinError)
    val (euroMax, euroMaxError) = parseAmount("10000.00", "EUR")
    assertNull(euroMax)
    assertEquals("Only GBP integer pence are supported", euroMaxError)
    assertEquals("adyen", baselineProvider(PaymentMethod.card))
    assertEquals("worldpay", baselineProvider(PaymentMethod.bank))
  }

  @Test
  fun testDynamicCatalogHydrationAndLastKnownGood() = runBlocking {
    withMock { mock, session ->
      val first = session.hydrateCatalog()
      assertFalse(first.degraded)
      assertEquals(CatalogSource.LIVE, first.source)
      assertEquals("2026-09-18", first.catalog?.demoDate)
      assertEquals(listOf("adyen", "worldpay"), first.catalog?.providers?.map { it.id })
      assertEquals(listOf("card"), first.catalog?.providers?.get(0)?.methods)
      assertEquals(listOf("bank"), first.catalog?.providers?.get(1)?.methods)

      mock.demoDate = "2026-09-19"
      val refreshed = session.hydrateCatalog()
      assertEquals(CatalogSource.LIVE, refreshed.source)
      assertEquals("2026-09-19", refreshed.catalog?.demoDate)

      mock.catalogDown = true
      val fallback = session.hydrateCatalog()
      assertTrue(fallback.degraded)
      assertEquals(CatalogSource.LAST_KNOWN_GOOD, fallback.source)
      assertEquals("2026-09-19", fallback.catalog?.demoDate)
      assertEquals(listOf("adyen", "worldpay"), fallback.catalog?.providers?.map { it.id })
    }
  }

  @Test
  fun testCatalogMissWithoutCacheIsEmpty() = runBlocking {
    withMock { mock, session ->
      mock.catalogDown = true
      val missing = session.hydrateCatalog()
      assertTrue(missing.degraded)
      assertEquals(CatalogSource.EMPTY, missing.source)
      assertNull(missing.catalog)
    }
  }

  @Test
  fun testSettlementIdempotencyKeepsSessionAndKey() = runBlocking {
    withMock { mock, session ->
      val attempt = attempt(amount = 2_599, method = PaymentMethod.card, key = "settle-key-1")
      val first = session.submit(attempt)
      val settled = first as PaymentOutcome.Settled
      assertEquals(200, mock.lastStatus)
      assertEquals("txn-1", settled.response.transaction?.id)
      assertEquals("adyen", settled.response.transaction?.provider)
      assertEquals(1_248_050 - 2_599, settled.response.state?.balance)
      assertEquals("room-pay-120", session.sessionId)
      assertEquals(listOf("room-pay-120"), mock.sessions)
      assertEquals(listOf("card"), mock.methods)
      assertEquals(listOf("settle-key-1"), mock.keys)

      val replay = session.submit(attempt) as PaymentOutcome.Settled
      assertEquals("txn-1", replay.response.transaction?.id)
      assertEquals(1_248_050 - 2_599, replay.response.state?.balance)
      assertEquals(1, mock.debits)
      assertEquals("settle-key-1", replay.attempt.idempotencyKey)
      assertEquals(PaymentMethod.card, replay.attempt.method)
      assertEquals("adyen", replay.attempt.provider)
      assertEquals(listOf("room-pay-120", "room-pay-120"), mock.sessions)
    }
  }

  @Test
  fun testHttp202PendingDoesNotDebitOrRotateKey() = runBlocking {
    withMock { mock, session ->
      val attempt = attempt(amount = 100, method = PaymentMethod.card, key = "pending-key", scenario = Scenario.pending)
      val pending = session.submit(attempt) as PaymentOutcome.Pending
      assertEquals(202, mock.lastStatus)
      assertFalse(pending.response.ok)
      assertEquals("PAYMENT_PENDING", pending.response.code)
      assertEquals("pay-pending", pending.response.paymentId)
      assertEquals(1_248_050, mock.balance)
      assertEquals("pending-key", pending.attempt.idempotencyKey)
      assertEquals(PaymentMethod.card, pending.attempt.method)

      val again = session.submit(attempt) as PaymentOutcome.Pending
      assertEquals(202, mock.lastStatus)
      assertEquals(1_248_050, mock.balance)
      assertEquals(0, mock.debits)
      assertEquals("pending-key", again.attempt.idempotencyKey)
    }
  }

  @Test
  fun testUnavailableRetryStaysOnWorldpayBank() = runBlocking {
    withMock { mock, session ->
      val down = attempt(amount = 80, method = PaymentMethod.bank, key = "bank-key", scenario = Scenario.unavailable)
      val failed = session.submit(down) as PaymentOutcome.Retryable
      assertEquals(503, mock.lastStatus)
      assertEquals(1_248_050, mock.balance)
      assertEquals(PaymentMethod.bank, failed.attempt.method)
      assertEquals("worldpay", failed.attempt.provider)
      assertEquals("bank-key", failed.attempt.idempotencyKey)

      val recovered = attempt(amount = 80, method = failed.attempt.method, key = failed.attempt.idempotencyKey)
      val settled = session.submit(recovered) as PaymentOutcome.Settled
      assertEquals(1_248_050 - 80, settled.response.state?.balance)
      assertEquals("worldpay", settled.response.transaction?.provider)
      assertEquals("bank", settled.response.transaction?.method)
      assertEquals(listOf("bank", "bank"), mock.methods)
      assertEquals(listOf("bank-key", "bank-key"), mock.keys)
      assertEquals(1, mock.debits)
    }
  }

  @Test
  fun testGatewayTimeoutRetriesSameCardKeyOnce() = runBlocking {
    withMock { mock, session ->
      mock.hangNext = true
      val attempt = attempt(amount = 250, method = PaymentMethod.card, key = "timeout-key")
      val uncertain = session.submit(attempt) as PaymentOutcome.Retryable
      assertTrue(uncertain.message.contains("timeout") || uncertain.message.contains("Timeout"))
      assertEquals("timeout-key", uncertain.attempt.idempotencyKey)
      assertEquals(PaymentMethod.card, uncertain.attempt.method)
      assertEquals("adyen", uncertain.attempt.provider)
      assertEquals(1_248_050 - 250, mock.balance)
      assertEquals(1, mock.debits)

      val replay = session.submit(uncertain.attempt) as PaymentOutcome.Settled
      assertEquals("txn-1", replay.response.transaction?.id)
      assertEquals(1_248_050 - 250, replay.response.state?.balance)
      assertEquals(1, mock.debits)
      assertEquals(listOf("card", "card"), mock.methods)
      assertTrue(mock.methods.none { it != "card" })
    }
  }

  @Test
  fun testIdempotencyMismatchDoesNotMintANewKey() = runBlocking {
    withMock { mock, session ->
      val original = attempt(amount = 100, method = PaymentMethod.card, key = "same-key")
      val settled = session.submit(original) as PaymentOutcome.Settled
      assertEquals(1_248_050 - 100, settled.response.state?.balance)

      val changed = attempt(amount = 200, method = PaymentMethod.card, key = "same-key")
      val rejected = session.submit(changed) as PaymentOutcome.Rejected
      assertEquals(409, mock.lastStatus)
      assertEquals("same-key", rejected.attempt.idempotencyKey)
      assertEquals(PaymentMethod.card, rejected.attempt.method)
      assertEquals(1_248_050 - 100, mock.balance)
      assertEquals(1, mock.debits)
    }
  }

  @Test
  fun testInvalidAmountDoesNotCallTheApi() = runBlocking {
    withMock { mock, session ->
      val outcome = session.submit(attempt(amount = 0, method = PaymentMethod.bank, key = "zero"))
      assertTrue(outcome is PaymentOutcome.Rejected)
      assertEquals("zero", (outcome as PaymentOutcome.Rejected).attempt.idempotencyKey)
      assertTrue(mock.methods.isEmpty())
      assertEquals(1_248_050, mock.balance)
    }
  }

  private fun attempt(
    amount: Int,
    method: PaymentMethod,
    key: String,
    scenario: Scenario = Scenario.success,
  ) = PaymentAttempt(
    recipientId = "northline-studio",
    amountMinor = amount,
    method = method,
    note = "rehearsal",
    scenario = scenario,
    idempotencyKey = key,
  )

  private suspend fun withMock(body: suspend (MockLedger, RehearsalSession) -> Unit) {
    val ledger = MockLedger()
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val pool = Executors.newCachedThreadPool()
    server.executor = pool
    server.createContext("/") { exchange ->
      try {
        val reply = ledger.handle(exchange, json)
        if (reply.delayMs > 0) Thread.sleep(reply.delayMs)
        val bytes = reply.body.toByteArray(StandardCharsets.UTF_8)
        exchange.responseHeaders.add("Content-Type", "application/json")
        exchange.sendResponseHeaders(reply.status, bytes.size.toLong())
        exchange.responseBody.write(bytes)
      } catch (_: Exception) {
        // The client may already have timed out.
      } finally {
        exchange.close()
      }
    }
    server.start()
    try {
      val client = MeridianClient(
        "http://127.0.0.1:${server.address.port}/api/v1",
        "room-pay-120",
        timeoutMillis = 300,
      )
      body(ledger, RehearsalSession(client))
    } finally {
      server.stop(0)
      pool.shutdownNow()
    }
  }
}

private data class Reply(val status: Int, val body: String, val delayMs: Long = 0)

private data class Stored(
  val payload: String,
  val phase: String,
  val id: String,
  val amount: Int,
  val method: String,
  val recipientId: String,
  val note: String,
)

private class MockLedger {
  val lock = Any()
  var balance = 1_248_050
  var catalogDown = false
  var demoDate = "2026-09-18"
  var hangNext = false
  var debits = 0
  var lastStatus = 0
  val methods = mutableListOf<String>()
  val keys = mutableListOf<String>()
  val sessions = mutableListOf<String>()
  private val stored = mutableMapOf<String, Stored>()
  private var sequence = 0

  fun handle(exchange: HttpExchange, json: ObjectMapper): Reply {
    val path = exchange.requestURI.path
    val session = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
    val key = exchange.requestHeaders.getFirst("Idempotency-Key")
    val text = exchange.requestBody.bufferedReader().readText()
    synchronized(lock) {
      return when {
        path.endsWith("/catalog") -> catalog()
        path.endsWith("/payments") -> payment(json, session, key, text)
        path.endsWith("/state") -> Reply(200, stateJson())
        else -> Reply(404, """{"ok":false,"error":"not found","code":"HTTP_404"}""")
      }
    }
  }

  private fun catalog(): Reply {
    if (catalogDown) {
      return Reply(503, """{"ok":false,"error":"catalog unavailable","code":"PROVIDER_UNAVAILABLE"}""")
    }
    return Reply(
      200,
      """
      {
        "demoDate":"$demoDate",
        "recipients":[{
          "id":"northline-studio","name":"Northline Studio","initials":"NS",
          "detail":"Design tools & materials","category":"Shopping","color":"#FF6B6B"
        }],
        "providers":[
          {"id":"adyen","name":"Adyen","description":"Card payment processor","methods":["card"]},
          {"id":"worldpay","name":"Worldpay","description":"Bank transfer processor","methods":["bank"]}
        ]
      }
      """.trimIndent(),
    )
  }

  private fun payment(json: ObjectMapper, session: String?, key: String?, text: String): Reply {
    if (session.isNullOrBlank() || key.isNullOrBlank()) {
      return replied(400, """{"ok":false,"error":"Session and idempotency key are required","code":"HTTP_400"}""")
    }
    sessions += session
    keys += key
    val tree = json.readTree(text)
    val recipient = tree.get("recipientId").asText()
    val amount = tree.get("amountMinor").asInt()
    val method = tree.get("method").asText()
    val note = tree.get("note").asText()
    val scenario = tree.get("scenario").asText()
    methods += method
    val payload = "$recipient|$amount|$method|$note"
    val existing = stored[key]
    if (existing != null && existing.payload != payload) {
      return replied(409, """{"ok":false,"error":"Idempotency key belongs to a different payment","code":"HTTP_409"}""")
    }
    if (existing?.phase == "settled") {
      return replied(200, settledJson(existing))
    }
    if (existing?.phase == "pending") {
      return replied(202, pendingJson(existing.id))
    }
    if (scenario == "pending") {
      sequence += 1
      val id = "pay-pending"
      stored[key] = Stored(payload, "pending", id, amount, method, recipient, note)
      return replied(202, pendingJson(id))
    }
    if (scenario == "unavailable") {
      return replied(
        503,
        """{"ok":false,"code":"PROVIDER_UNAVAILABLE","error":"Provider unavailable before authorization. No debit was made."}""",
      )
    }
    if (scenario == "declined") {
      return replied(422, """{"ok":false,"code":"PAYMENT_DECLINED","error":"Payment declined. No debit was made."}""")
    }
    sequence += 1
    val id = "txn-$sequence"
    balance -= amount
    debits += 1
    val record = Stored(payload, "settled", id, amount, method, recipient, note)
    stored[key] = record
    val delay = if (hangNext) {
      hangNext = false
      1_000L
    } else {
      0L
    }
    return Reply(200, settledJson(record), delay).also { lastStatus = 200 }
  }

  private fun replied(status: Int, body: String): Reply {
    lastStatus = status
    return Reply(status, body)
  }

  private fun pendingJson(id: String) =
    """{"ok":false,"error":"Payment pending confirmation. Do not create another payment.","code":"PAYMENT_PENDING","paymentId":"$id"}"""

  private fun provider(method: String) = if (method == "card") "adyen" else "worldpay"

  private fun settledJson(record: Stored): String {
    val transaction = """
      {"id":"${record.id}","reference":"MER-${record.id}","recipientId":"${record.recipientId}",
      "name":"Northline Studio","category":"Shopping","amount":${record.amount},"date":"2026-09-18",
      "provider":"${provider(record.method)}","method":"${record.method}","status":"completed","note":"${record.note}"}
    """.trimIndent().replace("\n", "")
    return """{"ok":true,"state":${stateJson(transaction)},"transaction":$transaction}"""
  }

  private fun stateJson(transaction: String? = null): String {
    val transactions = if (transaction == null) "[]" else "[$transaction]"
    return """{"version":1,"balance":$balance,"transactions":$transactions,"budgets":[]}"""
  }
}
