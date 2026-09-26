package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.net.InetSocketAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class ProviderConfigTest {
  private val mapper = ObjectMapper().registerKotlinModule()

  private val agreedCatalog = """
    {
      "demoDate": "2026-09-18",
      "recipients": [
        {
          "id": "northline-studio",
          "name": "Northline Studio",
          "initials": "NS",
          "detail": "Design tools & materials",
          "category": "Shopping",
          "color": "#FF6B6B"
        }
      ],
      "providers": [
        {
          "id": "adyen",
          "name": "Adyen",
          "description": "Card payment processor",
          "methods": ["card"]
        },
        {
          "id": "worldpay",
          "name": "Worldpay",
          "description": "Bank transfer processor",
          "methods": ["bank"]
        }
      ]
    }
  """.trimIndent()

  @Test
  fun testFlagDefaultsToHardcodedProviders() {
    val config = MeridianClientConfig()
    assertFalse(config.configDrivenProviders)
    val options = ProviderCatalog.baseline()
    assertEquals(listOf("adyen_card", "worldpay_bank"), options.map { it.id })
    assertEquals(listOf("Debit card", "Bank payment"), options.map { it.displayLabel })
    assertEquals(listOf("Adyen", "Worldpay"), options.map { it.providerName })
  }

  @Test
  fun testAgreedCatalogContractParsesLiveProviders() {
    val catalog = mapper.readValue(agreedCatalog, CatalogResponse::class.java)
    assertEquals("2026-09-18", catalog.demoDate)
    assertEquals(2, catalog.providers.size)
    assertEquals("adyen", catalog.providers[0].id)
    assertEquals(listOf("card"), catalog.providers[0].methods)
    assertEquals("worldpay", catalog.providers[1].id)
    assertEquals(listOf("bank"), catalog.providers[1].methods)

    val options = ProviderCatalog.optionsFromCatalog(catalog)
    assertEquals("adyen_card", options[0].id)
    assertEquals("Debit card", options[0].displayLabel)
    assertEquals("Adyen", options[0].providerName)
    assertEquals("worldpay_bank", options[1].id)
    assertEquals("Bank payment", options[1].displayLabel)
    assertEquals("Worldpay", options[1].providerName)
  }

  @Test
  fun testCatalogIgnoresExtraFieldsAndUnlistedProviders() {
    val json = """
      {
        "demoDate": "2026-09-18",
        "corridor": "UK",
        "recipients": [],
        "providers": [
          {
            "id": "adyen",
            "name": "adyen",
            "description": "Card payment processor",
            "methods": ["card", "bank"],
            "displayLabel": "Ignored"
          },
          {
            "id": "unlisted",
            "name": "Unlisted",
            "description": "Not a live provider",
            "methods": ["card"]
          },
          {
            "id": "worldpay",
            "name": "Worldpay",
            "description": "Bank transfer processor",
            "methods": ["bank"]
          }
        ]
      }
    """.trimIndent()

    val options = ProviderCatalog.optionsFromCatalog(mapper.readValue(json, CatalogResponse::class.java))
    assertEquals(listOf("adyen_card", "worldpay_bank"), options.map { it.id })
    assertEquals("Adyen", options[0].providerName)
    assertEquals("Debit card", options[0].displayLabel)
  }

  @Test
  fun testSwappedPairingsAreNotOffered() {
    val json = """
      {
        "demoDate": "2026-09-18",
        "recipients": [],
        "providers": [
          {"id": "adyen", "name": "Adyen", "description": "Card payment processor", "methods": ["bank"]},
          {"id": "worldpay", "name": "Worldpay", "description": "Bank transfer processor", "methods": ["card"]}
        ]
      }
    """.trimIndent()
    assertTrue(ProviderCatalog.optionsFromCatalog(mapper.readValue(json, CatalogResponse::class.java)).isEmpty())
  }

  @Test
  fun testNonCanonicalCatalogNameStaysOnLiveBrand() {
    val json = """
      {
        "demoDate": "2026-09-18",
        "recipients": [],
        "providers": [
          {"id": "adyen", "name": "Renamed", "description": "Card payment processor", "methods": ["card"]}
        ]
      }
    """.trimIndent()
    val options = ProviderCatalog.optionsFromCatalog(mapper.readValue(json, CatalogResponse::class.java))
    assertEquals(1, options.size)
    assertEquals("adyen_card", options[0].id)
    assertEquals("Adyen", options[0].providerName)
  }

  @Test
  fun testCacheServesFreshCopyThenKeepsLastKnownGood() {
    var now = 5_000L
    val cache = ProviderConfigCache(ttlMillis = 1_000, clock = { now })
    val options = ProviderCatalog.baseline()
    assertNull(cache.fresh())
    assertNull(cache.lastKnown())
    cache.store(options)
    assertEquals(options, cache.fresh())
    now = 5_999
    assertEquals(listOf("adyen_card", "worldpay_bank"), cache.fresh()!!.map { it.id })
    now = 6_000
    assertNull(cache.fresh())
    assertEquals(options, cache.lastKnown())
  }

  @Test
  fun testCorrelationIdPrefersHeaderThenErrorBody() {
    val fromHeader = ProviderCatalog.correlationId(
      headers = mapOf("X-Correlation-Id" to listOf("corr-header"), "X-Request-Id" to listOf("req-1")),
      body = """{"correlationId":"corr-body"}""",
      mapper = mapper,
    )
    assertEquals("corr-header", fromHeader)

    val fromRequestHeader = ProviderCatalog.correlationId(
      headers = mapOf("x-request-id" to listOf("req-9")),
      body = "",
      mapper = mapper,
    )
    assertEquals("req-9", fromRequestHeader)

    val fromBody = ProviderCatalog.correlationId(
      headers = emptyMap(),
      body = """{"ok":false,"error":"unavailable","code":"HTTP_500","correlationId":"corr-body"}""",
      mapper = mapper,
    )
    assertEquals("corr-body", fromBody)
  }

  @Test
  fun testConfigTransportAllowsHttpsAndLocalRehearsalOnly() {
    assertTrue(ProviderCatalog.configTransportAllowed("https://payments.example/api/v1"))
    assertTrue(ProviderCatalog.configTransportAllowed("http://127.0.0.1:8080/api/v1"))
    assertTrue(ProviderCatalog.configTransportAllowed("http://10.0.2.2:8080/api/v1"))
    assertTrue(ProviderCatalog.configTransportAllowed("http://localhost:8080/api/v1"))
    assertFalse(ProviderCatalog.configTransportAllowed("http://payments.example/api/v1"))
  }

  @Test
  fun testFlagOffDoesNotFetchCatalog() {
    val hits = AtomicInteger()
    val server = catalogServer { exchange ->
      hits.incrementAndGet()
      val body = agreedCatalog.toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, body.size.toLong())
      exchange.responseBody.write(body)
      exchange.close()
    }
    try {
      val client = MeridianClient(server.baseUrl, "room-flag-off")
      val options = runBlocking { client.paymentMethodOptions() }
      assertEquals(listOf("adyen_card", "worldpay_bank"), options.map { it.id })
      assertEquals(0, hits.get())
      assertEquals(0, client.providerConfigMetrics.fetchSuccessCount)
      assertEquals(0, client.providerConfigMetrics.fetchFailureCount)
    } finally {
      server.stop()
    }
  }

  @Test
  fun testFlagOnFetchesCatalogAndCachesWithinTtl() {
    val hits = AtomicInteger()
    var session: String? = null
    val server = catalogServer { exchange ->
      hits.incrementAndGet()
      session = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      val body = agreedCatalog.toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, body.size.toLong())
      exchange.responseBody.write(body)
      exchange.close()
    }
    var now = 1_000L
    try {
      val client = configuredClient(server.baseUrl, "room-catalog", clock = { now }, ttlMillis = 500)
      val first = runBlocking { client.paymentMethodOptions() }
      val second = runBlocking { client.paymentMethodOptions() }
      now = 1_499
      val third = runBlocking { client.paymentMethodOptions() }
      assertEquals(listOf("adyen_card", "worldpay_bank"), first.map { it.id })
      assertEquals(first, second)
      assertEquals(first, third)
      assertEquals(1, hits.get())
      assertEquals("room-catalog", session)
      assertEquals(1, client.providerConfigMetrics.fetchSuccessCount)
      assertEquals(0, client.providerConfigMetrics.fetchFailureCount)
      assertEquals(0, client.providerConfigMetrics.fallbackToCacheCount)
    } finally {
      server.stop()
    }
  }

  @Test
  fun testFetchFailureFallsBackToCacheWithCorrelationId() {
    var mode = "ok"
    val server = catalogServer { exchange ->
      if (mode == "ok") {
        val body = agreedCatalog.toByteArray()
        exchange.responseHeaders.add("Content-Type", "application/json")
        exchange.sendResponseHeaders(200, body.size.toLong())
        exchange.responseBody.write(body)
      } else {
        val body = """{"ok":false,"error":"catalog unavailable","code":"HTTP_500","correlationId":"from-body"}"""
          .toByteArray()
        exchange.responseHeaders.add("Content-Type", "application/json")
        exchange.responseHeaders.add("X-Correlation-Id", "corr-catalog-7")
        exchange.sendResponseHeaders(500, body.size.toLong())
        exchange.responseBody.write(body)
      }
      exchange.close()
    }
    var now = 10_000L
    try {
      val client = configuredClient(server.baseUrl, "room-fallback", clock = { now }, ttlMillis = 1_000)
      val cached = runBlocking { client.paymentMethodOptions() }
      mode = "fail"
      now = 11_000
      val fallback = runBlocking { client.paymentMethodOptions() }
      assertEquals(cached.map { it.id }, fallback.map { it.id })
      assertEquals(listOf("Adyen", "Worldpay"), fallback.map { it.providerName })
      assertEquals(1, client.providerConfigMetrics.fetchSuccessCount)
      assertEquals(1, client.providerConfigMetrics.fetchFailureCount)
      assertEquals(1, client.providerConfigMetrics.fallbackToCacheCount)
      val failure = client.providerConfigMetrics.recentFailures().single()
      assertEquals("corr-catalog-7", failure.correlationId)
      assertEquals("room-fallback", failure.sessionId)
      assertEquals("HTTP 500", failure.reason)
    } finally {
      server.stop()
    }
  }

  @Test
  fun testMalformedCatalogAndMissingCacheUseBaseline() {
    val server = catalogServer { exchange ->
      val body = "{".toByteArray()
      exchange.responseHeaders.add("X-Request-Id", "req-malformed")
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, body.size.toLong())
      exchange.responseBody.write(body)
      exchange.close()
    }
    try {
      val client = configuredClient(server.baseUrl, "room-malformed")
      val options = runBlocking { client.paymentMethodOptions() }
      assertEquals(listOf("adyen_card", "worldpay_bank"), options.map { it.id })
      assertEquals(0, client.providerConfigMetrics.fetchSuccessCount)
      assertEquals(1, client.providerConfigMetrics.fetchFailureCount)
      assertEquals(0, client.providerConfigMetrics.fallbackToCacheCount)
      assertEquals("req-malformed", client.providerConfigMetrics.recentFailures().single().correlationId)
    } finally {
      server.stop()
    }
  }

  @Test
  fun testEmptyProviderListDoesNotCrash() {
    val server = catalogServer { exchange ->
      val body = """{"demoDate":"2026-09-18","recipients":[],"providers":[]}""".toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, body.size.toLong())
      exchange.responseBody.write(body)
      exchange.close()
    }
    try {
      val client = configuredClient(server.baseUrl, "room-empty")
      val options = runBlocking { client.paymentMethodOptions() }
      assertEquals(ProviderCatalog.baseline(), options)
      assertEquals(1, client.providerConfigMetrics.fetchFailureCount)
      assertEquals(0, client.providerConfigMetrics.fallbackToCacheCount)
    } finally {
      server.stop()
    }
  }

  @Test
  fun testTimeoutFallsBackToCachedProviders() {
    val release = CountDownLatch(1)
    var hang = false
    val server = catalogServer { exchange ->
      if (hang) {
        release.await(5, TimeUnit.SECONDS)
      }
      val body = agreedCatalog.toByteArray()
      try {
        exchange.responseHeaders.add("Content-Type", "application/json")
        exchange.sendResponseHeaders(200, body.size.toLong())
        exchange.responseBody.write(body)
      } catch (_: Exception) {
        // The client may already have timed out and closed the socket.
      } finally {
        exchange.close()
      }
    }
    var now = 2_000L
    try {
      val client = configuredClient(
        server.baseUrl,
        "room-timeout",
        clock = { now },
        ttlMillis = 100,
        timeoutMillis = 800,
      )
      val cached = runBlocking { client.paymentMethodOptions() }
      hang = true
      now = 3_000
      val started = System.nanoTime()
      val fallback = runBlocking { client.paymentMethodOptions() }
      val elapsedMs = (System.nanoTime() - started) / 1_000_000
      assertTrue("timeout took ${elapsedMs}ms", elapsedMs < 2_500)
      assertEquals(listOf("adyen_card", "worldpay_bank"), fallback.map { it.id })
      assertEquals(cached, fallback)
      assertEquals(1, client.providerConfigMetrics.fetchFailureCount)
      assertEquals(1, client.providerConfigMetrics.fallbackToCacheCount)
      assertNull(client.providerConfigMetrics.recentFailures().single().correlationId)
    } finally {
      release.countDown()
      server.stop()
    }
  }

  @Test
  fun testCleartextRemoteCatalogDoesNotFetch() {
    val client = MeridianClient(
      baseURL = "http://payments.example/api/v1",
      sessionId = "room-remote",
      clientConfig = MeridianClientConfig(configDrivenProviders = true, providerConfigTimeoutMillis = 200),
    )
    val options = runBlocking { client.paymentMethodOptions() }
    assertEquals(ProviderCatalog.baseline(), options)
    assertEquals(1, client.providerConfigMetrics.fetchFailureCount)
    assertEquals(0, client.providerConfigMetrics.fallbackToCacheCount)
    assertEquals("Provider configuration requires HTTPS", client.providerConfigMetrics.recentFailures().single().reason)
  }

  @Test
  fun testSubmitPaymentMethodIdKeepsIdempotencyAndWireMethod() {
    val bodies = mutableListOf<String>()
    val keys = mutableListOf<String>()
    val server = catalogServer { exchange ->
      assertEquals("POST", exchange.requestMethod)
      keys += exchange.requestHeaders.getFirst("Idempotency-Key")
      assertEquals("pay-room", exchange.requestHeaders.getFirst("X-Rehearsal-Session"))
      val requestBody = exchange.requestBody.bufferedReader().readText()
      bodies += requestBody
      val retry = keys.size > 1
      val responseBody = if (retry) {
        """{"ok":true,"paymentId":"tx-123","transaction":{"id":"tx-123","reference":"REF","recipientId":"northline-studio","name":"Northline Studio","category":"Shopping","amount":1000,"date":"2026-09-18","provider":"adyen","method":"card","status":"completed","note":""}}"""
      } else {
        """{"ok":false,"code":"PAYMENT_PENDING","paymentId":"tx-123","error":"Awaiting confirmation"}"""
      }
      val bytes = responseBody.toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(if (retry) 200 else 202, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    try {
      val client = MeridianClient(server.baseUrl, "pay-room")
      val pending = runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 1000,
          methodId = "adyen_card",
          idempotencyKey = "idem-1",
        )
      }
      val completed = runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 1000,
          methodId = "adyen_card",
          idempotencyKey = "idem-1",
        )
      }
      assertEquals("PAYMENT_PENDING", pending.code)
      assertTrue(completed.ok)
      assertEquals(listOf("idem-1", "idem-1"), keys)
      assertEquals(2, bodies.size)
      bodies.forEach { body ->
        assertTrue(body.contains("\"method\":\"card\""))
        assertFalse(body.contains("adyen_card"))
      }
      val events = client.paymentEventLog.snapshot()
      assertEquals(2, events.size)
      assertEquals("payment.method_selected", events[0].action)
      assertEquals("adyen_card", events[0].methodId)
      assertEquals("Adyen", events[0].providerName)
      assertEquals("card", events[0].wireMethod)
      assertEquals("idem-1", events[0].idempotencyKey)
      assertEquals("tx-123", events[0].transactionId)
      assertEquals("tx-123", events[1].transactionId)
      assertEquals(mapOf("Adyen" to 2L), client.paymentEventLog.selectionCounts())
    } finally {
      server.stop()
    }
  }

  @Test
  fun testWorldpayMethodIdUsesBankWireValue() {
    var method: String? = null
    val server = catalogServer { exchange ->
      val payload = mapper.readTree(exchange.requestBody.bufferedReader().readText())
      method = payload.get("method").asText()
      val body = """{"ok":true,"paymentId":"tx-bank"}""".toByteArray()
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, body.size.toLong())
      exchange.responseBody.write(body)
      exchange.close()
    }
    try {
      val client = MeridianClient(server.baseUrl, "pay-room")
      val response = runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 1000,
          methodId = "worldpay_bank",
          idempotencyKey = "idem-bank",
        )
      }
      assertTrue(response.ok)
      assertEquals("bank", method)
      val event = client.paymentEventLog.snapshot().single()
      assertEquals("worldpay_bank", event.methodId)
      assertEquals("Worldpay", event.providerName)
      assertEquals("bank", event.wireMethod)
      assertEquals("tx-bank", event.transactionId)
    } finally {
      server.stop()
    }
  }

  @Test
  fun testUnknownMethodIdDoesNotCallTheApi() {
    val hits = AtomicInteger()
    val server = catalogServer { exchange ->
      hits.incrementAndGet()
      exchange.sendResponseHeaders(500, -1)
      exchange.close()
    }
    try {
      val client = MeridianClient(server.baseUrl, "pay-room")
      val error = assertThrows(MeridianError.ValidationError::class.java) {
        runBlocking {
          client.submitPayment(
            recipientId = "northline-studio",
            amountMinor = 1000,
            methodId = "unlisted_method",
            idempotencyKey = "idem-unknown",
          )
        }
      }
      assertTrue(error.message!!.contains("Unknown payment method"))
      assertEquals(0, hits.get())
      assertTrue(client.paymentEventLog.snapshot().isEmpty())
    } finally {
      server.stop()
    }
  }

  private fun configuredClient(
    baseUrl: String,
    sessionId: String,
    clock: () -> Long = System::currentTimeMillis,
    ttlMillis: Long = 30_000,
    timeoutMillis: Int = 3_000,
  ): MeridianClient = MeridianClient(
    baseURL = baseUrl,
    sessionId = sessionId,
    clientConfig = MeridianClientConfig(
      configDrivenProviders = true,
      providerConfigTtlMillis = ttlMillis,
      providerConfigTimeoutMillis = timeoutMillis,
    ),
    clock = clock,
  )

  private class CatalogServer(
    val baseUrl: String,
    private val server: HttpServer,
  ) {
    fun stop() {
      server.stop(0)
    }
  }

  private fun catalogServer(
    handler: com.sun.net.httpserver.HttpHandler,
  ): CatalogServer {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.createContext("/api/v1/catalog", handler)
    server.createContext("/api/v1/payments", handler)
    server.start()
    val port = server.address.port
    return CatalogServer("http://127.0.0.1:$port/api/v1", server)
  }
}
