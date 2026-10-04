package com.atlassian.meridian

import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetSocketAddress
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

class FaultInjectionTest {
  @Test
  fun responseDropDedupesAndKeepsProvider() {
    val fault = FaultServer()
    fault.dropAfterCommit = 2
    fault.use { server ->
      val client = MeridianClient(server.baseUrl, "fault-session", connectTimeoutMs = 1000, readTimeoutMs = 1000)
      client.maxTransportRetries = 2
      val response = runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 1,
          method = PaymentMethod.card,
          note = "drop",
          idempotencyKey = "drop-key-1",
        )
      }
      assertTrue(response.ok)
      assertEquals("adyen", response.transaction?.provider)
      assertEquals("card", response.transaction?.method)
      assertEquals(1, server.debits.get())
      assertEquals(listOf("drop-key-1", "drop-key-1", "drop-key-1"), server.keys)
      assertEquals(listOf("card", "card", "card"), server.methods)
      assertEquals(listOf("adyen", "adyen", "adyen"), server.providers)
      assertEquals(listOf("fault-session", "fault-session", "fault-session"), server.sessions)
    }
  }

  @Test
  fun requestDropRecoversWithTheSameKey() {
    val fault = FaultServer()
    fault.dropBeforeCommit = 2
    fault.use { server ->
      val client = MeridianClient(server.baseUrl, "fault-session-2", connectTimeoutMs = 1000, readTimeoutMs = 1000)
      val response = runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 2500,
          method = PaymentMethod.bank,
          note = "lost-request",
          idempotencyKey = "drop-key-2",
        )
      }
      assertTrue(response.ok)
      assertEquals("worldpay", response.transaction?.provider)
      assertEquals("bank", response.transaction?.method)
      assertEquals(1, server.debits.get())
      assertEquals(3, server.keys.size)
      assertTrue(server.keys.all { it == "drop-key-2" })
      assertTrue(server.methods.all { it == "bank" })
      assertTrue(server.providers.all { it == "worldpay" })
      assertTrue(server.sessions.all { it == "fault-session-2" })
    }
  }

  @Test
  fun definiteDeclineIsNotRetriedOrRerouted() {
    val fault = FaultServer()
    fault.mode = "decline"
    fault.use { server ->
      val client = MeridianClient(server.baseUrl, "fault-session-3", connectTimeoutMs = 1000, readTimeoutMs = 1000)
      val response = runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 50,
          method = PaymentMethod.card,
          note = "declined",
          idempotencyKey = "decline-key",
        )
      }
      assertFalse(response.ok)
      assertEquals("PAYMENT_DECLINED", response.code)
      assertEquals(0, server.debits.get())
      assertEquals(listOf("decline-key"), server.keys)
      assertEquals(listOf("card"), server.methods)
      assertEquals(listOf("adyen"), server.providers)
    }
  }

  private class FaultServer : AutoCloseable {
    val debits = AtomicInteger()
    val keys = mutableListOf<String>()
    val methods = mutableListOf<String>()
    val sessions = mutableListOf<String>()
    val providers = mutableListOf<String>()
    var dropAfterCommit = 0
    var dropBeforeCommit = 0
    var mode = "success"
    private val committed = mutableMapOf<String, String>()
    private val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val baseUrl: String

    init {
      baseUrl = "http://127.0.0.1:${server.address.port}/api/v1"
      server.createContext("/api/v1/payments") { exchange ->
        val body = exchange.requestBody.readBytes().toString(StandardCharsets.UTF_8)
        val key = exchange.requestHeaders.getFirst("Idempotency-Key").orEmpty()
        val session = exchange.requestHeaders.getFirst("X-Rehearsal-Session").orEmpty()
        val method = Regex("\"method\"\\s*:\\s*\"(card|bank)\"").find(body)?.groupValues?.get(1).orEmpty()
        val provider = when (method) {
          "card" -> "adyen"
          "bank" -> "worldpay"
          else -> "unknown"
        }
        synchronized(this) {
          keys += key
          methods += method
          sessions += session
          providers += provider
          if (mode == "decline") {
            val payload = """{"ok":false,"code":"PAYMENT_DECLINED","error":"Payment declined. No debit was made."}"""
            write(exchange, 422, payload)
            return@createContext
          }
          if (dropBeforeCommit > 0) {
            dropBeforeCommit -= 1
            exchange.close()
            return@createContext
          }
          val existing = committed[key]
          val payload = if (existing != null) {
            existing
          } else {
            debits.incrementAndGet()
            val created = """{"ok":true,"paymentId":"pay-1","transaction":{"id":"pay-1","reference":"MER-PAY","recipientId":"northline-studio","name":"Northline Studio","category":"Shopping","amount":1,"date":"2026-09-18","provider":"$provider","method":"$method","status":"completed","note":"drop"},"state":{"version":1,"balance":1,"transactions":[],"budgets":[]}}"""
            committed[key] = created
            created
          }
          if (dropAfterCommit > 0) {
            dropAfterCommit -= 1
            exchange.close()
            return@createContext
          }
          write(exchange, 200, payload)
        }
      }
      server.executor = Executors.newCachedThreadPool()
      server.start()
    }

    private fun write(exchange: com.sun.net.httpserver.HttpExchange, status: Int, payload: String) {
      val bytes = payload.toByteArray(StandardCharsets.UTF_8)
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(status, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }

    override fun close() {
      server.stop(0)
    }
  }

  private fun <T> FaultServer.use(block: (FaultServer) -> T): T = try {
    block(this)
  } finally {
    close()
  }
}
