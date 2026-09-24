package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetSocketAddress
import java.util.concurrent.atomic.AtomicInteger
import java.util.logging.Handler
import java.util.logging.Level
import java.util.logging.LogRecord
import java.util.logging.Logger

/**
 * Catalog parsing, in-memory fallback, and the meridian-api GET /catalog shape.
 * The fixture matches meridian-api docs/fixture.json recipients and providers
 * plus the catalog demoDate from the connected rehearsal contract.
 */
class ProviderCatalogTest {
  private val mapper = ObjectMapper().registerKotlinModule()

  @Test
  fun testParseMeridianApiCatalogIntoMethodOptions() {
    val options = ProviderCatalog.parse(catalog())

    assertEquals(listOf(ProviderCatalog.ADYEN_CARD, ProviderCatalog.WORLDPAY_BANK), options.map { it.id })
    assertEquals("Debit card", options[0].displayLabel)
    assertEquals("Adyen", options[0].providerName)
    assertEquals("card", options[0].wireMethod)
    assertEquals("Debit card · Adyen", options[0].pickerLabel())
    assertEquals("Bank payment", options[1].displayLabel)
    assertEquals("Worldpay", options[1].providerName)
    assertEquals("bank", options[1].wireMethod)
    assertEquals("Bank payment · Worldpay", options[1].pickerLabel())
  }

  @Test
  fun testParseSkipsUnconfiguredProvidersAndDuplicateIds() {
    val catalog = CatalogResponse(
      demoDate = "2026-09-18",
      recipients = emptyList(),
      providers = listOf(
        Provider("adyen", "Adyen", "Card payment processor", listOf("card", "wallet")),
        Provider("unconfigured", "Unconfigured", "Not in the baseline", listOf("card")),
        Provider("adyen", "Adyen", "Card payment processor", listOf("card")),
        Provider("worldpay", "Worldpay", "Bank transfer processor", listOf("bank")),
      ),
    )

    val options = ProviderCatalog.parse(catalog)

    assertEquals(listOf(ProviderCatalog.ADYEN_CARD, ProviderCatalog.WORLDPAY_BANK), options.map { it.id })
  }

  @Test
  fun testParseBlankProviderNameUsesBaselineName() {
    val catalog = CatalogResponse(
      demoDate = "2026-09-18",
      recipients = emptyList(),
      providers = listOf(Provider("adyen", "  ", "Card payment processor", listOf("card"))),
    )

    val options = ProviderCatalog.parse(catalog)

    assertEquals(1, options.size)
    assertEquals("Adyen", options[0].providerName)
  }

  @Test
  fun testParseEmptyOrUnknownMethodsIsUnusable() {
    val empty = CatalogResponse(
      demoDate = "2026-09-18",
      recipients = emptyList(),
      providers = listOf(Provider("adyen", "Adyen", "Card payment processor", emptyList())),
    )
    assertTrue(ProviderCatalog.parse(empty).isEmpty())
  }

  @Test
  fun testMalformedCatalogJsonDoesNotDecode() {
    assertThrows(Exception::class.java) {
      mapper.readValue("{\"providers\":", CatalogResponse::class.java)
    }
  }

  @Test
  fun testExtraCatalogFieldsStillDecodeKnownMethods() {
    val json = """
      {
        "demoDate": "2026-09-18",
        "region": "GB",
        "recipients": [],
        "providers": [
          {
            "id": "adyen",
            "name": "Adyen",
            "description": "Card payment processor",
            "methods": ["card"],
            "corridor": "domestic"
          }
        ]
      }
    """.trimIndent()

    val options = ProviderCatalog.parse(mapper.readValue(json, CatalogResponse::class.java))

    assertEquals(ProviderCatalog.ADYEN_CARD, options.single().id)
    assertEquals("card", options.single().wireMethod)
  }

  @Test
  fun testFlagOffSkipsFetchAndKeepsHardcodedPicker() {
    var fetches = 0
    val metrics = CatalogFetchMetrics()
    val repository = ProviderCatalogRepository(configDriven = false, metrics = metrics)

    val options = runBlocking {
      repository.paymentMethods {
        fetches += 1
        error("catalog must not be fetched while the flag is off")
      }
    }

    assertEquals(0, fetches)
    assertEquals(ProviderCatalog.hardcodedPicker(), options)
    assertEquals(listOf("card", "bank"), options.map { it.id })
    assertEquals(listOf("Debit card · Adyen", "Bank payment · Worldpay"), options.map { it.pickerLabel() })
    assertEquals(0, metrics.successCount())
    assertEquals(0, metrics.failureCount())
    assertEquals(0, metrics.fallbackCount())
  }

  @Test
  fun testCacheTtlAndFallbackToLastKnownGood() {
    withCatalogLogs { lines ->
      var now = 5_000L
      var mode = "good"
      var fetches = 0
      val metrics = CatalogFetchMetrics()
      val repository = ProviderCatalogRepository(
        configDriven = true,
        ttlMillis = 30_000,
        clock = { now },
        metrics = metrics,
        correlationId = { if (mode == "down") "corr-77" else null },
      )
      val good = catalog()

      val first = runBlocking {
        repository.paymentMethods {
          fetches += 1
          when (mode) {
            "good" -> good
            "malformed" -> CatalogResponse("2026-09-18", emptyList(), emptyList())
            else -> throw MeridianError.NetworkError("catalog timeout")
          }
        }
      }
      assertEquals(1, fetches)
      assertEquals(listOf(ProviderCatalog.ADYEN_CARD, ProviderCatalog.WORLDPAY_BANK), first.map { it.id })

      now = 34_999
      val cached = runBlocking {
        repository.paymentMethods { error("fresh cache must not fetch") }
      }
      assertEquals(first, cached)
      assertEquals(1, fetches)

      now = 35_000
      mode = "down"
      val failed = runBlocking { repository.paymentMethods { fetches += 1; throw MeridianError.NetworkError("catalog timeout") } }
      assertEquals(first, failed)
      assertEquals(2, fetches)
      assertEquals(ProviderCatalog.WORLDPAY_BANK, ProviderCatalog.retainSelection(ProviderCatalog.WORLDPAY_BANK, failed))

      now = 80_000
      mode = "malformed"
      val malformed = runBlocking {
        repository.paymentMethods {
          fetches += 1
          CatalogResponse("2026-09-18", emptyList(), emptyList())
        }
      }
      assertEquals(first, malformed)
      assertEquals(1, metrics.successCount())
      assertEquals(2, metrics.failureCount())
      assertEquals(2, metrics.fallbackCount())
      assertTrue(lines.any { it.contains("result=success") && it.contains("successRate=1.000") })
      assertTrue(lines.any { it.contains("result=failure") && it.contains("correlationId=corr-77") && it.contains("catalog timeout") })
      assertTrue(lines.any { it.contains("result=fallback") && it.contains("fallbackRate=1.000") && it.contains("correlationId=corr-77") })
    }
  }

  @Test
  fun testFetchFailureWithoutCacheUsesSafeDefault() {
    withCatalogLogs { lines ->
      val metrics = CatalogFetchMetrics()
      val repository = ProviderCatalogRepository(
        configDriven = true,
        metrics = metrics,
        correlationId = { "corr-none" },
      )

      val options = runBlocking {
        repository.paymentMethods { throw MeridianError.DecodingError("Failed to parse response") }
      }

      assertEquals(ProviderCatalog.safeDefault(), options)
      assertEquals(0, metrics.successCount())
      assertEquals(1, metrics.failureCount())
      assertEquals(0, metrics.fallbackCount())
      assertTrue(lines.any { it.contains("result=baseline") && it.contains("correlationId=corr-none") && it.contains("no last-known-good") })
      assertTrue(lines.none { it.contains("result=fallback") })
    }
  }

  @Test
  fun testSuccessfulRefetchReplacesCachedMethods() {
    var now = 0L
    var worldpayOnly = false
    val repository = ProviderCatalogRepository(
      configDriven = true,
      ttlMillis = 1_000,
      clock = { now },
    )
    val both = runBlocking { repository.paymentMethods { catalog() } }
    assertEquals(2, both.size)

    now = 1_000
    worldpayOnly = true
    val replaced = runBlocking {
      repository.paymentMethods {
        if (!worldpayOnly) catalog() else CatalogResponse(
          demoDate = "2026-09-18",
          recipients = emptyList(),
          providers = listOf(Provider("worldpay", "Worldpay", "Bank transfer processor", listOf("bank"))),
        )
      }
    }

    assertEquals(listOf(ProviderCatalog.WORLDPAY_BANK), replaced.map { it.id })
    assertEquals(ProviderCatalog.WORLDPAY_BANK, ProviderCatalog.retainSelection(ProviderCatalog.ADYEN_CARD, replaced))
  }

  @Test
  fun testWireMethodKeepsPaymentContractValues() {
    assertEquals("card", ProviderCatalog.wireMethod("card"))
    assertEquals("card", ProviderCatalog.wireMethod(" adyen_card "))
    assertEquals("bank", ProviderCatalog.wireMethod("bank"))
    assertEquals("bank", ProviderCatalog.wireMethod(ProviderCatalog.WORLDPAY_BANK))
    assertThrows(MeridianError.ValidationError::class.java) {
      ProviderCatalog.wireMethod("unconfigured_method")
    }
  }

  @Test
  fun testFlagOffClientDoesNotFetchCatalogForMethods() {
    val hits = AtomicInteger()
    val server = catalogServer(hits, status = 500, body = "down")
    try {
      val client = MeridianClient(server.baseUrl, "test-session", configDrivenCatalog = false)
      val options = runBlocking { client.paymentMethods() }
      assertEquals(listOf("card", "bank"), options.map { it.id })
      assertEquals(0, hits.get())
      assertEquals(0, client.catalogMetrics.failureCount())
    } finally {
      server.server.stop(0)
    }
  }

  @Test
  fun testClientContractCacheFallbackAndIdempotentSubmit() {
    withCatalogLogs { lines ->
      val catalogHits = AtomicInteger()
      val paymentBodies = mutableListOf<String>()
      val paymentKeys = mutableListOf<String>()
      var catalogStatus = 200
      var catalogBody = MERIDIAN_API_CATALOG
      val server = com.sun.net.httpserver.HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
      val port = server.address.port
      val baseUrl = "http://127.0.0.1:$port/api/v1"

      server.createContext("/api/v1/catalog") { exchange ->
        catalogHits.incrementAndGet()
        val payload = catalogBody.toByteArray()
        exchange.responseHeaders.add("Content-Type", "application/json")
        exchange.responseHeaders.add("X-Correlation-Id", "corr-catalog")
        exchange.sendResponseHeaders(catalogStatus, payload.size.toLong())
        exchange.responseBody.write(payload)
        exchange.close()
      }
      server.createContext("/api/v1/payments") { exchange ->
        val key = exchange.requestHeaders.getFirst("Idempotency-Key")
        val session = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
        assertEquals("room-1", session)
        paymentKeys.add(key)
        val body = exchange.requestBody.bufferedReader().readText()
        paymentBodies.add(body)
        val retry = paymentKeys.size > 1
        val responseBody = if (retry) {
          """{"ok":true,"paymentId":"tx-1"}"""
        } else {
          """{"ok":false,"code":"PAYMENT_PENDING","paymentId":"tx-1","error":"Awaiting confirmation"}"""
        }
        val status = if (retry) 200 else 202
        exchange.responseHeaders.add("Content-Type", "application/json")
        exchange.sendResponseHeaders(status, responseBody.length.toLong())
        exchange.responseBody.write(responseBody.toByteArray())
        exchange.close()
      }
      server.start()
      try {
        var now = 0L
        val client = MeridianClient(
          baseURL = baseUrl,
          sessionId = "room-1",
          configDrivenCatalog = true,
          catalogTtlMillis = 30_000,
          clock = { now },
        )
        val first = runBlocking { client.paymentMethods() }
        assertEquals(listOf(ProviderCatalog.ADYEN_CARD, ProviderCatalog.WORLDPAY_BANK), first.map { it.id })
        assertEquals("2026-09-18", catalog().demoDate)
        assertEquals(5, catalog().recipients.size)
        assertEquals(1, catalogHits.get())

        val again = runBlocking { client.paymentMethods() }
        assertEquals(first, again)
        assertEquals(1, catalogHits.get())

        now = 30_000
        catalogStatus = 503
        catalogBody = """{"ok":false,"error":"unavailable","code":"HTTP_503"}"""
        val fallback = runBlocking { client.paymentMethods() }
        assertEquals(first, fallback)
        assertEquals(2, catalogHits.get())
        assertEquals(1, client.catalogMetrics.successCount())
        assertEquals(1, client.catalogMetrics.failureCount())
        assertEquals(1, client.catalogMetrics.fallbackCount())
        assertTrue(lines.any { it.contains("result=failure") && it.contains("correlationId=corr-catalog") })
        assertTrue(lines.any { it.contains("result=fallback") && it.contains("fallbackRate=1.000") })

        val key = "idem-catalog-1"
        val pending = runBlocking {
          client.submitPayment(
            recipientId = "northline-studio",
            amountMinor = 1000,
            methodId = ProviderCatalog.ADYEN_CARD,
            note = "Catalog",
            idempotencyKey = key,
          )
        }
        val completed = runBlocking {
          client.submitPayment(
            recipientId = "northline-studio",
            amountMinor = 1000,
            methodId = ProviderCatalog.ADYEN_CARD,
            note = "Catalog",
            idempotencyKey = key,
          )
        }
        assertFalse(pending.ok)
        assertEquals("PAYMENT_PENDING", pending.code)
        assertTrue(completed.ok)
        assertEquals(listOf(key, key), paymentKeys)
        assertEquals(2, paymentBodies.size)
        assertEquals(paymentBodies[0], paymentBodies[1])
        paymentBodies.forEach { body ->
          assertTrue(body.contains("\"method\":\"card\""))
          assertFalse(body.contains("adyen_card"))
        }

        catalogStatus = 500
        catalogBody = "timeout"
        now = 90_000
        val stillCached = runBlocking { client.paymentMethods() }
        assertEquals(first.map { it.id }, stillCached.map { it.id })
        runBlocking {
          client.submitPayment(
            recipientId = "northline-studio",
            amountMinor = 1000,
            methodId = ProviderCatalog.WORLDPAY_BANK,
            idempotencyKey = "idem-bank-1",
          )
        }
        assertEquals("idem-bank-1", paymentKeys.last())
        assertTrue(paymentBodies.last().contains("\"method\":\"bank\""))
        assertFalse(paymentBodies.last().contains("worldpay_bank"))
      } finally {
        server.stop(0)
      }
    }
  }

  @Test
  fun testUnknownMethodIdDoesNotSubmit() {
    val hits = AtomicInteger()
    val server = com.sun.net.httpserver.HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.createContext("/api/v1/payments") {
      hits.incrementAndGet()
      it.close()
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:${server.address.port}/api/v1", "room-1")
      assertThrows(MeridianError.ValidationError::class.java) {
        runBlocking {
          client.submitPayment(
            recipientId = "northline-studio",
            amountMinor = 100,
            methodId = "unconfigured_method",
            idempotencyKey = "idem-unknown",
          )
        }
      }
      assertEquals(0, hits.get())
    } finally {
      server.stop(0)
    }
  }

  private fun catalog(): CatalogResponse = mapper.readValue(MERIDIAN_API_CATALOG, CatalogResponse::class.java)

  private fun catalogServer(hits: AtomicInteger, status: Int, body: String): TestServer {
    val server = com.sun.net.httpserver.HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.createContext("/api/v1/catalog") { exchange ->
      hits.incrementAndGet()
      val payload = body.toByteArray()
      exchange.sendResponseHeaders(status, payload.size.toLong())
      exchange.responseBody.write(payload)
      exchange.close()
    }
    server.start()
    return TestServer(server, "http://127.0.0.1:${server.address.port}/api/v1")
  }

  private fun withCatalogLogs(block: (List<String>) -> Unit) {
    val lines = java.util.Collections.synchronizedList(mutableListOf<String>())
    val handler = object : Handler() {
      override fun publish(record: LogRecord?) {
        if (record != null) lines.add(record.message)
      }
      override fun flush() {}
      override fun close() {}
    }
    handler.level = Level.ALL
    val logger = Logger.getLogger(CatalogFetchMetrics.LOGGER_NAME)
    logger.addHandler(handler)
    try {
      block(lines)
    } finally {
      logger.removeHandler(handler)
    }
  }

  private data class TestServer(val server: com.sun.net.httpserver.HttpServer, val baseUrl: String)

  companion object {
    /**
     * GET /catalog body from meridian-api: demoDate plus fixture recipients and providers.
     * Providers are only Adyen/card and Worldpay/bank.
     */
    private val MERIDIAN_API_CATALOG = """
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
          },
          {
            "id": "octavia-energy",
            "name": "Octavia Energy",
            "initials": "OE",
            "detail": "Electricity & gas supplier",
            "category": "Bills",
            "color": "#4ECDC4"
          },
          {
            "id": "maya-chen",
            "name": "Maya Chen",
            "initials": "MC",
            "detail": "Yoga & wellness classes",
            "category": "Lifestyle",
            "color": "#95E1D3"
          },
          {
            "id": "birch-bloom",
            "name": "Birch & Bloom",
            "initials": "BB",
            "detail": "Organic café & bistro",
            "category": "Food & drink",
            "color": "#FFD93D"
          },
          {
            "id": "london-transit",
            "name": "London Transit",
            "initials": "LT",
            "detail": "Public transport & taxis",
            "category": "Transport",
            "color": "#6BCB77"
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
  }
}
