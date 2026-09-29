package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.net.InetSocketAddress

class CatalogCacheTest {
  private val mapper = ObjectMapper().registerKotlinModule()

  @Test
  fun testLegacyCatalogDefaultsAvailabilityAndCorridors() {
    val json = """
      {
        "demoDate": "2026-09-18",
        "recipients": [],
        "providers": [
          {"id": "adyen", "name": "Adyen", "description": "Card payment processor", "methods": ["card"]},
          {"id": "worldpay", "name": "Worldpay", "description": "Bank payment processor", "methods": ["bank"]}
        ]
      }
    """.trimIndent()
    val catalog = mapper.readValue(json, CatalogResponse::class.java)
    assertEquals(2, catalog.providers.size)
    assertTrue(catalog.providers.all { it.available })
    assertTrue(catalog.corridors.isEmpty())
    assertEquals(listOf("adyen", "worldpay"), ProviderBaseline.active(catalog).map { it.id })
  }

  @Test
  fun testUnavailableProviderIsExcludedWithoutThrowing() {
    val catalog = mapper.readValue(
      sampleCatalog(adyenAvailable = false),
      CatalogResponse::class.java,
    )
    assertEquals(listOf("worldpay"), ProviderBaseline.active(catalog).map { it.id })
    assertEquals(catalog, ProviderBaseline.accept(catalog))
  }

  @Test
  fun testUnrecognizedProviderIsNotAccepted() {
    val catalog = mapper.readValue(
      sampleCatalog(extraProvider = true),
      CatalogResponse::class.java,
    )
    assertNull(ProviderBaseline.accept(catalog))
    assertTrue(ProviderBaseline.active(catalog).none { it.id != "adyen" && it.id != "worldpay" })
  }

  @Test
  fun testSwappedMethodIsRejected() {
    val catalog = CatalogResponse(
      demoDate = "2026-09-18",
      providers = listOf(Provider("adyen", "Adyen", "Card", listOf("bank"))),
    )
    assertNull(ProviderBaseline.accept(catalog))
    assertEquals(listOf("adyen", "worldpay"), ProviderBaseline.catalog().providers.map { it.id })
  }

  @Test
  fun testEncryptedStoreRoundTripHidesPlaintext() {
    val directory = File(System.getProperty("java.io.tmpdir"), "meridian-catalog-" + System.nanoTime())
    val store = EncryptedFileCatalogStore(directory)
    val catalog = mapper.readValue(sampleCatalog(), CatalogResponse::class.java)
    store.save(StoredCatalog(42, catalog))
    val blob = File(directory, "catalog.bin").readBytes()
    assertFalse(String(blob).contains("CACHE-TOKEN-XYZZY"))
    val restored = store.load()
    assertEquals(42L, restored?.fetchedAtEpochMillis)
    assertEquals("CACHE-TOKEN-XYZZY", restored?.catalog?.recipients?.first()?.name)
    directory.deleteRecursively()
  }

  @Test
  fun testLoadCatalogCachesAndFallsBack() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    var hits = 0
    var status = 200
    var body = sampleCatalog()
    server.createContext("/api/v1/catalog") { exchange ->
      hits += 1
      val payload = body.toByteArray()
      exchange.sendResponseHeaders(status, payload.size.toLong())
      exchange.responseBody.write(payload)
      exchange.close()
    }
    server.start()
    try {
      val clock = ClockBox(1_700_000_000_000)
      val store = InMemoryCatalogStore()
      val client = MeridianClient(
        baseURL = "http://127.0.0.1:${server.address.port}/api/v1",
        sessionId = "catalog-check",
        catalogTtlMillis = 300_000,
        catalogStore = store,
        clock = { clock.millis },
      )
      val first = runBlocking { client.loadCatalog() }
      assertEquals(CatalogOrigin.NETWORK, first.origin)
      assertEquals(2, ProviderBaseline.active(first.catalog).size)
      assertEquals(1, hits)

      status = 500
      val fresh = runBlocking { client.loadCatalog() }
      assertEquals(CatalogOrigin.CACHE, fresh.origin)
      assertEquals(1, hits)

      clock.millis += 301_000
      val after500 = runBlocking { client.loadCatalog() }
      status = 502
      val after502 = runBlocking { client.loadCatalog() }
      status = 504
      val after504 = runBlocking { client.loadCatalog() }
      assertEquals(CatalogOrigin.FALLBACK, after500.origin)
      assertEquals(CatalogOrigin.FALLBACK, after502.origin)
      assertEquals(CatalogOrigin.FALLBACK, after504.origin)
      assertEquals(listOf("adyen", "worldpay"), after504.catalog.providers.map { it.id })

      status = 200
      body = sampleCatalog(extraProvider = true)
      val rejected = runBlocking { client.loadCatalog() }
      assertEquals(CatalogOrigin.FALLBACK, rejected.origin)
      assertEquals(listOf("adyen", "worldpay"), rejected.catalog.providers.map { it.id })

      body = sampleCatalog(adyenAvailable = false)
      val flagged = runBlocking { client.loadCatalog() }
      assertEquals(CatalogOrigin.NETWORK, flagged.origin)
      assertEquals(listOf("worldpay"), ProviderBaseline.active(flagged.catalog).map { it.id })
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testGatewayWithoutCacheUsesCompiledBaseline() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.createContext("/api/v1/catalog") { exchange ->
      val payload = "nope".toByteArray()
      exchange.sendResponseHeaders(500, payload.size.toLong())
      exchange.responseBody.write(payload)
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient(
        baseURL = "http://127.0.0.1:${server.address.port}/api/v1",
        sessionId = "catalog-empty",
        catalogStore = InMemoryCatalogStore(),
      )
      val loaded = runBlocking { client.loadCatalog() }
      assertEquals(CatalogOrigin.BASELINE, loaded.origin)
      assertEquals(listOf("adyen", "worldpay"), loaded.catalog.providers.map { it.id })
      assertTrue(isCatalogGateway(500) && isCatalogGateway(502) && isCatalogGateway(504))
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testOfflineUsesLastCatalog() {
    val store = InMemoryCatalogStore()
    val saved = mapper.readValue(sampleCatalog(), CatalogResponse::class.java)
    store.save(StoredCatalog(1, saved))
    val client = MeridianClient(
      baseURL = "http://127.0.0.1:9/api/v1",
      sessionId = "catalog-offline",
      catalogTtlMillis = 1,
      catalogStore = store,
      clock = { 10_000 },
    )
    val loaded = runBlocking { client.loadCatalog() }
    assertEquals(CatalogOrigin.FALLBACK, loaded.origin)
    assertEquals("CACHE-TOKEN-XYZZY", loaded.catalog.recipients.first().name)
  }

  private class ClockBox(var millis: Long)

  private fun sampleCatalog(adyenAvailable: Boolean = true, extraProvider: Boolean = false): String {
    val extra = if (extraProvider) {
      """,{"id":"unrecognized","name":"X","description":"Y","methods":["card"]}"""
    } else {
      ""
    }
    return """
      {
        "demoDate": "2026-09-18",
        "recipients": [
          {
            "id": "northline-studio",
            "name": "CACHE-TOKEN-XYZZY",
            "initials": "NS",
            "detail": "Design",
            "category": "Shopping",
            "color": "#112233"
          }
        ],
        "providers": [
          {
            "id": "adyen",
            "name": "Adyen",
            "description": "Card payment processor",
            "methods": ["card"],
            "available": $adyenAvailable
          },
          {
            "id": "worldpay",
            "name": "Worldpay",
            "description": "Bank payment processor",
            "methods": ["bank"]
          }
          $extra
        ],
        "corridors": [
          {"id": "gb-card", "provider": "adyen", "method": "card", "currency": "GBP"},
          {"id": "gb-bank", "provider": "worldpay", "method": "bank", "currency": "GBP"}
        ]
      }
    """.trimIndent()
  }
}
