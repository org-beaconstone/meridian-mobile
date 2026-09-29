package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetSocketAddress

class PaymentOrchestratorTest {
  private val mapper = ObjectMapper().registerKotlinModule()

  @Test
  fun testNewKeyIsUuidV4() {
    val keys = List(20) { newPaymentIdempotencyKey() }
    assertEquals(20, keys.toSet().size)
    keys.forEach { assertTrue(isUuidV4(it)) }
  }

  @Test
  fun testBackoffGrowsThenCaps() {
    assertEquals(200L, GatewayRetry.backoffMillis(0, 0.0))
    assertEquals(400L, GatewayRetry.backoffMillis(1, 0.0))
    assertEquals(800L, GatewayRetry.backoffMillis(2, 0.0))
    assertEquals(1_600L, GatewayRetry.backoffMillis(4, 0.0))
    assertEquals(300L, GatewayRetry.backoffMillis(0, 1.0))
  }

  @Test
  fun testGatewayTimeoutRetriesKeepKeyMethodSessionAndAmount() {
    val observed = observePayments(listOf(502, 504, 200))
    val sleeps = mutableListOf<Long>()
    val key = newPaymentIdempotencyKey()
    val response = runBlocking {
      PaymentOrchestrator(
        client = observed.client,
        sleep = { sleeps.add(it) },
        randomUnit = { 0.0 },
      ).submit(
        recipientId = "northline-studio",
        amountMinor = 2599,
        method = PaymentMethod.bank,
        note = "Studio rent",
        scenario = Scenario.success,
        idempotencyKey = key,
      )
    }
    assertTrue(response.ok)
    assertEquals(listOf(key, key, key), observed.keys)
    assertEquals(listOf("room-keep", "room-keep", "room-keep"), observed.sessions)
    assertEquals(listOf("bank", "bank", "bank"), observed.methods)
    assertEquals(listOf(2599, 2599, 2599), observed.amounts)
    assertEquals(listOf(200L, 400L), sleeps)
    observed.stop()
  }

  @Test
  fun testExhaustedGatewayTimeoutKeepsTheOriginalKey() {
    val observed = observePayments(listOf(502, 502, 504))
    val sleeps = mutableListOf<Long>()
    val key = newPaymentIdempotencyKey()
    val error = runCatching {
      runBlocking {
        PaymentOrchestrator(
          client = observed.client,
          sleep = { sleeps.add(it) },
          randomUnit = { 0.0 },
        ).submit(
          recipientId = "northline-studio",
          amountMinor = 1000,
          method = PaymentMethod.card,
          idempotencyKey = key,
        )
      }
    }.exceptionOrNull()
    assertTrue(error is MeridianError.HttpError)
    val http = error as MeridianError.HttpError
    assertEquals(504, http.statusCode)
    assertTrue(http.message!!.contains("same key"))
    assertEquals(listOf(key, key, key), observed.keys)
    assertEquals(listOf("card", "card", "card"), observed.methods)
    assertEquals(listOf(200L, 400L), sleeps)
    observed.stop()
  }

  @Test
  fun testValidationAndBusinessErrorsDoNotRetry() {
    val observed = observePayments(listOf(400))
    val sleeps = mutableListOf<Long>()
    val key = newPaymentIdempotencyKey()
    val response = runBlocking {
      PaymentOrchestrator(
        client = observed.client,
        sleep = { sleeps.add(it) },
        randomUnit = { 0.0 },
      ).submit(
        recipientId = "northline-studio",
        amountMinor = 100,
        method = PaymentMethod.card,
        idempotencyKey = key,
      )
    }
    assertFalse(response.ok)
    assertEquals("BAD_REQUEST", response.code)
    assertEquals(1, observed.keys.size)
    assertTrue(sleeps.isEmpty())
    observed.stop()
  }

  @Test
  fun testInvalidKeyDoesNotReachTheNetwork() {
    val observed = observePayments(listOf(200))
    val error = runCatching {
      runBlocking {
        PaymentOrchestrator(observed.client, sleep = { }, randomUnit = { 0.0 }).submit(
          recipientId = "northline-studio",
          amountMinor = 100,
          method = PaymentMethod.card,
          idempotencyKey = "not-a-uuid",
        )
      }
    }.exceptionOrNull()
    assertTrue(error is MeridianError.ValidationError)
    assertTrue(observed.keys.isEmpty())
    observed.stop()
  }

  private fun observePayments(statusPlan: List<Int>): ObservedPayments {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val keys = mutableListOf<String>()
    val sessions = mutableListOf<String>()
    val methods = mutableListOf<String>()
    val amounts = mutableListOf<Int>()
    val statuses = ArrayDeque(statusPlan)
    server.createContext("/api/v1/payments") { exchange ->
      val body = exchange.requestBody.readBytes()
      val json = mapper.readTree(body)
      keys.add(exchange.requestHeaders.getFirst("Idempotency-Key"))
      sessions.add(exchange.requestHeaders.getFirst("X-Rehearsal-Session"))
      methods.add(json.get("method").asText())
      amounts.add(json.get("amountMinor").asInt())
      val status = if (statuses.isEmpty()) 200 else statuses.removeFirst()
      val response = if (status == 200) {
        """{"ok":true,"paymentId":"pay-1"}"""
      } else if (status == 400) {
        """{"ok":false,"error":"Invalid amount","code":"BAD_REQUEST"}"""
      } else {
        "bad gateway"
      }
      val bytes = response.toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(status, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.start()
    val client = MeridianClient(
      "http://127.0.0.1:${server.address.port}/api/v1",
      "room-keep",
    )
    return ObservedPayments(server, client, keys, sessions, methods, amounts)
  }

  private class ObservedPayments(
    private val server: HttpServer,
    val client: MeridianClient,
    val keys: List<String>,
    val sessions: List<String>,
    val methods: List<String>,
    val amounts: List<Int>,
  ) {
    fun stop() {
      server.stop(0)
    }
  }
}
