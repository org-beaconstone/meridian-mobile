package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.net.InetSocketAddress
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList

class RehearsalSuiteTest {
  @Test
  fun testJourneyAgainstContractDouble() = runBlocking {
    val double = ContractDouble()
    try {
      val api = MeridianClient(double.baseUrl, "rehearsal-room-1", timeoutMillis = 3_000)
      RehearsalJourney.run(api)
      assertTrue(double.requests.isNotEmpty())
      assertTrue(double.requests.all { it.session == "rehearsal-room-1" })
      val payments = double.requests.filter { it.path == "/api/v1/payments" }
      assertTrue(payments.isNotEmpty())
      assertTrue(payments.all { it.paymentMethod == "card" || it.paymentMethod == "bank" })
      payments.groupBy { it.idempotencyKey }.values.forEach { group ->
        assertEquals(1, group.map { it.paymentMethod }.toSet().size)
      }
      assertTrue(payments.all { it.idempotencyKey != null && it.idempotencyKey.isNotEmpty() })
    } finally {
      double.close()
    }
  }

  @Test
  fun testTimeoutRetriesSameKeyAndMethod() = runBlocking {
    val double = ContractDouble()
    try {
      double.holdNextPayment = true
      val api = MeridianClient(double.baseUrl, "timeout-room-1", timeoutMillis = 250)
      val rehearsal = RehearsalClient(api)
      val key = UUID.randomUUID().toString()
      val result = rehearsal.submit(
        recipientId = "northline-studio",
        amountMinor = 1000,
        method = PaymentMethod.bank,
        note = "timeout",
        idempotencyKey = key,
      )
      val settled = result as? Submission.Settled ?: error("expected settled after retry, got $result")
      assertEquals(key, settled.idempotencyKey)
      assertEquals(PaymentMethod.bank, settled.method)
      assertEquals("worldpay", settled.response.transaction?.provider)
      assertEquals("bank", settled.response.transaction?.method)
      assertEquals(RehearsalJourney.OPENING_BALANCE - 1000, settled.response.state?.balance)
      val calls = double.requests.filter { it.path == "/api/v1/payments" && it.idempotencyKey == key }
      assertTrue(calls.size >= 2)
      assertTrue(calls.all { it.paymentMethod == "bank" })
      assertEquals(1, double.debitCount("timeout-room-1"))
    } finally {
      double.close()
    }
  }

  @Test
  fun testCatalogFallbackKeepsBaselineProviders() = runBlocking {
    val double = ContractDouble()
    try {
      val rehearsal = RehearsalClient(MeridianClient(double.baseUrl, "catalog-room-1"))
      val first = rehearsal.hydrateCatalog()
      assertEquals(setOf("adyen", "worldpay"), first.providers.map { it.id }.toSet())
      double.failCatalog = true
      val second = rehearsal.hydrateCatalog()
      assertTrue(rehearsal.usingCatalogFallback)
      assertEquals(first.recipients.map { it.id }, second.recipients.map { it.id })
      assertEquals(listOf("card"), second.providers.first { it.id == "adyen" }.methods)
      assertEquals(listOf("bank"), second.providers.first { it.id == "worldpay" }.methods)
    } finally {
      double.close()
    }
  }

  @Test
  fun testUnknownProviderIsNotAdopted() = runBlocking {
    val double = ContractDouble()
    try {
      val rehearsal = RehearsalClient(MeridianClient(double.baseUrl, "provider-room-1"))
      rehearsal.hydrateCatalog()
      double.unknownProvider = true
      try {
        rehearsal.hydrateCatalog()
        fail("A catalogue outside the Adyen and Worldpay baseline must be rejected")
      } catch (error: MeridianError.ValidationError) {
        assertTrue(rehearsal.hasCatalog())
        assertFalse(rehearsal.usingCatalogFallback)
      }
    } finally {
      double.close()
    }
  }

  @Test
  fun testLiveContainerWhenConfigured() = runBlocking {
    val base = System.getenv("MERIDIAN_TEST_API")
    assumeTrue("MERIDIAN_TEST_API is not set", !base.isNullOrBlank())
    val api = MeridianClient(base!!, "kotlin-live-" + UUID.randomUUID().toString().take(8))
    RehearsalJourney.run(api)
  }
}

private data class Recorded(
  val path: String,
  val session: String?,
  val idempotencyKey: String?,
  val paymentMethod: String?,
)

private class ContractDouble : AutoCloseable {
  private val mapper = ObjectMapper().registerKotlinModule()
  private val server: HttpServer = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
  private val lock = Any()
  private val balances = mutableMapOf<String, Int>()
  private val transactions = mutableMapOf<String, MutableList<Map<String, Any>>>()
  private val payments = mutableMapOf<String, Stored>()
  val requests = CopyOnWriteArrayList<Recorded>()
  val baseUrl = "http://127.0.0.1:${server.address.port}/api/v1"

  @Volatile var failCatalog: Boolean = false
  @Volatile var unknownProvider: Boolean = false
  @Volatile var holdNextPayment: Boolean = false

  private data class Stored(
    val id: String,
    val recipientId: String,
    val amount: Int,
    val method: String,
    val note: String,
    var phase: String,
    val provider: String,
  )

  init {
    server.createContext("/api/v1/health") { exchange ->
      record(exchange, null)
      write(exchange, 200, """{"status":"UP","service":"meridian-api","simulation":true}""")
    }
    server.createContext("/api/v1/catalog") { exchange ->
      record(exchange, null)
      if (failCatalog) {
        write(exchange, 503, """{"ok":false,"error":"catalogue down","code":"PROVIDER_UNAVAILABLE"}""")
      } else {
        write(exchange, 200, catalogJson())
      }
    }
    server.createContext("/api/v1/state") { exchange ->
      record(exchange, null)
      val session = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      if (!validRoom(session)) {
        write(exchange, 400, """{"ok":false,"error":"Invalid rehearsal session","code":"HTTP_400"}""")
      } else {
        val body = synchronized(lock) { mapper.writeValueAsString(stateMap(session!!)) }
        write(exchange, 200, body)
      }
    }
    server.createContext("/api/v1/reset") { exchange ->
      record(exchange, null)
      val session = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      if (!validRoom(session)) {
        write(exchange, 400, """{"ok":false,"error":"Invalid rehearsal session","code":"HTTP_400"}""")
      } else {
        val body = synchronized(lock) {
          balances.remove(session)
          transactions.remove(session)
          payments.keys.filter { it.startsWith("$session|") }.toList().forEach { payments.remove(it) }
          mapper.writeValueAsString(mapOf("ok" to true, "state" to stateMap(session!!)))
        }
        write(exchange, 200, body)
      }
    }
    server.createContext("/api/v1/payments") { exchange ->
      val raw = exchange.requestBody.use { it.readBytes() }.toString(StandardCharsets.UTF_8)
      val node = mapper.readTree(raw)
      val method = node.path("method").asText("")
      record(exchange, method)
      val session = exchange.requestHeaders.getFirst("X-Rehearsal-Session") ?: ""
      val key = exchange.requestHeaders.getFirst("Idempotency-Key") ?: ""
      val outcome = synchronized(lock) { applyPayment(session, key, node) }
      if (outcome.hold) {
        try {
          exchange.close()
        } catch (_: Exception) {
        }
        return@createContext
      }
      write(exchange, outcome.status, outcome.body)
    }
    server.start()
  }

  fun debitCount(room: String): Int = synchronized(lock) {
    transactions[room].orEmpty().size
  }

  private fun record(exchange: HttpExchange, paymentMethod: String?) {
    requests.add(
      Recorded(
        path = exchange.requestURI.path,
        session = exchange.requestHeaders.getFirst("X-Rehearsal-Session"),
        idempotencyKey = exchange.requestHeaders.getFirst("Idempotency-Key"),
        paymentMethod = paymentMethod,
      )
    )
  }

  private fun validRoom(session: String?): Boolean =
    session != null && Regex("[A-Za-z0-9_-]{3,64}").matches(session)

  private fun people(id: String): Pair<String, String>? = when (id) {
    "northline-studio" -> "Northline Studio" to "Shopping"
    "octavia-energy" -> "Octavia Energy" to "Bills"
    "maya-chen" -> "Maya Chen" to "Lifestyle"
    "birch-bloom" -> "Birch & Bloom" to "Food & drink"
    "london-transit" -> "London Transit" to "Transport"
    else -> null
  }

  private fun stateMap(room: String): Map<String, Any> {
    val balance = balances.getOrPut(room) { RehearsalJourney.OPENING_BALANCE }
    return mapOf(
      "version" to 1,
      "balance" to balance,
      "transactions" to transactions.getOrPut(room) { mutableListOf() }.toList(),
      "budgets" to emptyList<Any>(),
    )
  }

  private data class Outcome(val status: Int, val body: String, val hold: Boolean = false)

  private fun applyPayment(session: String, key: String, node: com.fasterxml.jackson.databind.JsonNode): Outcome {
    if (!validRoom(session) || !Regex("[A-Za-z0-9_-]{1,100}").matches(key)) {
      return Outcome(400, """{"ok":false,"error":"Invalid rehearsal session","code":"HTTP_400"}""")
    }
    val recipientId = node.path("recipientId").asText("")
    val amount = node.path("amountMinor").asInt(-1)
    val method = node.path("method").asText("")
    val note = node.path("note").asText("")
    val scenario = node.path("scenario").asText("success")
    val person = people(recipientId)
    if (person == null || amount !in 1..1_000_000 || (method != "card" && method != "bank") || note.length > 200) {
      return Outcome(400, """{"ok":false,"error":"Invalid payment","code":"HTTP_400"}""")
    }
    if (scenario !in setOf("success", "declined", "unavailable", "pending")) {
      return Outcome(400, """{"ok":false,"error":"Unknown scenario","code":"HTTP_400"}""")
    }
    val payload = "$recipientId|$amount|$method|$note"
    val provider = if (method == "card") "adyen" else "worldpay"
    val existing = payments["$session|$key"]
    if (existing != null) {
      val previous = "${existing.recipientId}|${existing.amount}|${existing.method}|${existing.note}"
      if (previous != payload) {
        return Outcome(409, """{"ok":false,"error":"Idempotency key belongs to a different payment","code":"HTTP_409"}""")
      }
      if (existing.phase == "completed") {
        val txn = transactions[session].orEmpty().first { it["id"] == existing.id }
        return Outcome(200, mapper.writeValueAsString(mapOf("ok" to true, "state" to stateMap(session), "transaction" to txn)))
      }
      if (existing.phase == "pending") {
        return Outcome(202, pendingBody(existing.id))
      }
    }
    val balance = balances.getOrPut(session) { RehearsalJourney.OPENING_BALANCE }
    if (balance < amount) {
      return Outcome(400, """{"ok":false,"error":"Insufficient available balance","code":"HTTP_400"}""")
    }
    val stored = existing ?: Stored(
      id = UUID.randomUUID().toString(),
      recipientId = recipientId,
      amount = amount,
      method = method,
      note = note,
      phase = "prepared",
      provider = provider,
    ).also { payments["$session|$key"] = it }
    return when (scenario) {
      "pending" -> {
        stored.phase = "pending"
        Outcome(202, pendingBody(stored.id))
      }
      "declined" -> {
        stored.phase = "declined"
        Outcome(422, """{"ok":false,"error":"Payment declined. No debit was made.","code":"PAYMENT_DECLINED"}""")
      }
      "unavailable" -> {
        stored.phase = "unavailable"
        Outcome(503, """{"ok":false,"error":"Provider unavailable before authorization. No debit was made.","code":"PROVIDER_UNAVAILABLE"}""")
      }
      else -> {
        stored.phase = "completed"
        balances[session] = balance - amount
        val txn = mapOf(
          "id" to stored.id,
          "reference" to "MER-TEST",
          "recipientId" to recipientId,
          "name" to person.first,
          "category" to person.second,
          "amount" to amount,
          "date" to "2026-09-18",
          "provider" to stored.provider,
          "method" to method,
          "status" to "completed",
          "note" to note,
        )
        transactions.getOrPut(session) { mutableListOf() }.add(txn)
        val hold = holdNextPayment
        holdNextPayment = false
        Outcome(
          200,
          mapper.writeValueAsString(mapOf("ok" to true, "state" to stateMap(session), "transaction" to txn)),
          hold,
        )
      }
    }
  }

  private fun pendingBody(id: String) =
    """{"ok":false,"error":"Payment pending confirmation. Do not create another payment.","code":"PAYMENT_PENDING","paymentId":"$id"}"""

  private fun catalogJson(): String {
    val providers = if (unknownProvider) {
      """[{"id":"adyen","name":"Adyen","description":"Card payment processor","methods":["card"]},{"id":"worldpay","name":"Worldpay","description":"Bank transfer processor","methods":["bank"]},{"id":"other","name":"Other","description":"Not in the baseline","methods":["card"]}]"""
    } else {
      """[{"id":"adyen","name":"Adyen","description":"Card payment processor","methods":["card"]},{"id":"worldpay","name":"Worldpay","description":"Bank transfer processor","methods":["bank"]}]"""
    }
    return """{"demoDate":"2026-09-18","recipients":[{"id":"northline-studio","name":"Northline Studio","initials":"NS","detail":"Design tools & materials","category":"Shopping","color":"#FF6B6B"},{"id":"octavia-energy","name":"Octavia Energy","initials":"OE","detail":"Electricity & gas supplier","category":"Bills","color":"#4ECDC4"},{"id":"maya-chen","name":"Maya Chen","initials":"MC","detail":"Yoga & wellness classes","category":"Lifestyle","color":"#95E1D3"},{"id":"birch-bloom","name":"Birch & Bloom","initials":"BB","detail":"Organic café & bistro","category":"Food & drink","color":"#FFD93D"},{"id":"london-transit","name":"London Transit","initials":"LT","detail":"Public transport & taxis","category":"Transport","color":"#6BCB77"}],"providers":$providers}"""
  }

  private fun write(exchange: HttpExchange, status: Int, body: String) {
    val bytes = body.toByteArray(StandardCharsets.UTF_8)
    exchange.responseHeaders.add("Content-Type", "application/json")
    exchange.sendResponseHeaders(status, bytes.size.toLong())
    exchange.responseBody.use { it.write(bytes) }
  }

  override fun close() {
    server.stop(0)
  }
}
