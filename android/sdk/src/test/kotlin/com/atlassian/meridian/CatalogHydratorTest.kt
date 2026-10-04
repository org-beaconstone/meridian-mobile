package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetSocketAddress
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicInteger

class CatalogHydratorTest {
  private val mapper = ObjectMapper().registerKotlinModule()

  @Test
  fun testProviderBindingStaysAdyenAndWorldpay() {
    assertEquals(listOf("adyen", "worldpay"), ProviderId.entries.map { it.name })
    assertEquals(PaymentMethod.card, ProviderId.adyen.paymentMethod())
    assertEquals(PaymentMethod.bank, ProviderId.worldpay.paymentMethod())
    assertEquals("Debit card · Adyen", ProviderId.adyen.checkoutLabel())
    assertEquals("Bank payment · Worldpay", ProviderId.worldpay.checkoutLabel())
  }

  @Test
  fun testDynamicProviderDecodesWithoutProviderEnum() {
    val json = """
      {
        "id": "other",
        "name": "Other",
        "description": "Unbound",
        "methods": ["card"],
        "supportedCurrencies": ["GBP", "EUR"],
        "corridors": [{"id": "other-card", "method": "card", "currency": "GBP", "country": "GB"}]
      }
    """.trimIndent()

    val provider = mapper.readValue(json, DynamicProvider::class.java)
    assertEquals("other", provider.id)
    assertEquals(listOf("GBP", "EUR"), provider.currencies)
    assertEquals(1, provider.corridors.size)
  }

  @Test
  fun testBaselineProjectionDropsUnknownProvidersAndNonGbp() {
    val raw = CatalogResponse(
      demoDate = "2026-09-18",
      recipients = listOf(sampleRecipient()),
      providers = listOf(
        DynamicProvider("other", "Other", "Unbound", listOf("card"), listOf("GBP")),
        DynamicProvider("adyen", "Renamed", "Injected", listOf("card", "bank"), listOf("EUR", "GBP")),
        DynamicProvider("worldpay", "Worldpay", "Bank", listOf("bank_transfer"), emptyList()),
        DynamicProvider("adyen", "Adyen", "Duplicate", listOf("bank"), listOf("GBP")),
      ),
    )

    val projected = projectBaselineCatalog(raw)

    assertEquals(listOf("adyen", "worldpay"), projected.providers.map { it.id })
    assertEquals("Adyen", projected.providers[0].name)
    assertEquals(listOf("card"), projected.providers[0].methods)
    assertEquals(listOf("GBP"), projected.providers[0].currencies)
    assertEquals("card", projected.providers[0].corridors.single().method)
    assertEquals("GBP", projected.providers[0].corridors.single().currency)
    assertEquals("bank", projected.providers[1].corridors.single().method)
    assertEquals(listOf("GBP"), projected.providers[1].currencies)
    assertEquals("Northline Studio", projected.recipients.single().name)
    assertFalse(projected.providers.any { it.id == "other" || it.name == "Other" || it.name == "Renamed" })
  }

  @Test
  fun testEncryptedCacheRoundTripIsNotPlaintext() {
    val directory = java.io.File(System.getProperty("java.io.tmpdir"), "meridian-catalog-test-${System.nanoTime()}")
    val cache = FileEncryptedCatalogCache(directory)
    val catalog = projectBaselineCatalog(sampleCatalog())
    cache.save("room-a", catalog)

    val blob = cache.ciphertext("room-a")
    assertNotNull(blob)
    val stored = String(blob!!, StandardCharsets.UTF_8)
    assertFalse(stored.contains("Northline"))
    assertFalse(stored.contains("adyen"))
    assertFalse(stored.trim().startsWith("{"))

    val restored = FileEncryptedCatalogCache(directory).load("room-a")
    assertEquals(catalog, restored)
    assertNull(cache.load("room-b"))

    blob[0] = (blob[0] + 1).toByte()
    val file = directory.listFiles()?.first { it.name.endsWith(".bin") }
    assertNotNull(file)
    file!!.writeBytes(blob)
    assertNull(FileEncryptedCatalogCache(directory).load("room-a"))
    directory.deleteRecursively()
  }

  @Test
  fun testCatalogSuccessProjectsAndCachesOneRequest() {
    val hits = AtomicInteger()
    val server = catalogServer { exchange ->
      hits.incrementAndGet()
      assertEquals("GET", exchange.requestMethod)
      assertEquals("room-1", exchange.requestHeaders.getFirst("X-Rehearsal-Session"))
      val body = """
        {
          "demoDate": "2026-09-18",
          "recipients": [{"id": "northline-studio", "name": "Northline Studio", "initials": "NS", "detail": "Design", "category": "Shopping", "color": "#fff"}],
          "providers": [
            {"id": "other", "name": "Other", "description": "Unbound", "methods": ["card"], "currencies": ["GBP"]},
            {"id": "worldpay", "name": "Worldpay", "description": "Bank", "methods": ["bank"], "supportedCurrencies": ["GBP"]},
            {"id": "adyen", "name": "Adyen", "description": "Card", "methods": ["card"], "currencies": ["GBP"], "corridors": [{"id": "gb-card", "method": "card", "currency": "GBP", "country": "gb"}]}
          ]
        }
      """.trimIndent()
      writeJson(exchange, 200, body)
    }
    try {
      val cache = MemoryEncryptedCatalogCache()
      val client = MeridianClient(base(server), "room-1", timeoutMillis = 1_000)
      val loaded = runBlocking { client.loadCatalog(cache) }
      assertEquals(CatalogOrigin.network, loaded.origin)
      assertEquals(listOf("adyen", "worldpay"), loaded.catalog?.providers?.map { it.id })
      assertEquals("gb-card", loaded.catalog?.providers?.first()?.corridors?.single()?.id)
      assertEquals("GB", loaded.catalog?.providers?.first()?.corridors?.single()?.country)
      assertEquals(loaded.catalog, cache.load("room-1"))
      assertEquals(1, hits.get())
      val stored = String(cache.ciphertext("room-1")!!, StandardCharsets.UTF_8)
      assertFalse(stored.contains("Other"))
      assertFalse(stored.contains("Northline"))
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testServerErrorAndTimeoutUseCacheWithoutAnotherHost() {
    val catalogHits = AtomicInteger()
    val evilHits = AtomicInteger()
    val evil = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    evil.createContext("/") { exchange ->
      evilHits.incrementAndGet()
      writeJson(exchange, 200, "{}")
    }
    evil.start()
    val server = catalogServer { exchange ->
      catalogHits.incrementAndGet()
      exchange.responseHeaders.add("Location", "http://127.0.0.1:${evil.address.port}/collect")
      writeJson(exchange, 500, """{"error":"unavailable"}""")
    }
    try {
      val cache = MemoryEncryptedCatalogCache()
      val saved = projectBaselineCatalog(sampleCatalog())
      cache.save("room-1", saved)
      val client = MeridianClient(base(server), "room-1", timeoutMillis = 1_000)
      val loaded = runBlocking { client.loadCatalog(cache) }
      assertEquals(CatalogOrigin.cache, loaded.origin)
      assertEquals(saved, loaded.catalog)
      assertEquals(1, catalogHits.get())
      assertEquals(0, evilHits.get())
    } finally {
      server.stop(0)
      evil.stop(0)
    }
  }

  @Test
  fun testTimeoutUsesSavedCatalogAndDoesNotRedirect() {
    val hits = AtomicInteger()
    val server = catalogServer { exchange ->
      hits.incrementAndGet()
      Thread.sleep(2_000)
      writeJson(exchange, 200, "{}")
    }
    try {
      val cache = MemoryEncryptedCatalogCache()
      val saved = projectBaselineCatalog(sampleCatalog())
      cache.save("room-1", saved)
      val client = MeridianClient(base(server), "room-1", timeoutMillis = 300)
      val loaded = runBlocking { client.loadCatalog(cache) }
      assertEquals(CatalogOrigin.cache, loaded.origin)
      assertEquals("Northline Studio", loaded.catalog?.recipients?.single()?.name)
      assertEquals(1, hits.get())
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testOfflineUsesSavedCatalog() {
    val server = catalogServer { exchange -> writeJson(exchange, 200, "{}") }
    val port = server.address.port
    server.stop(0)
    val cache = MemoryEncryptedCatalogCache()
    val saved = projectBaselineCatalog(sampleCatalog())
    cache.save("room-1", saved)
    val client = MeridianClient("http://127.0.0.1:$port/api/v1", "room-1", timeoutMillis = 500)
    val loaded = runBlocking { client.loadCatalog(cache) }
    assertEquals(CatalogOrigin.cache, loaded.origin)
    assertEquals(saved.providers.map { it.id }, loaded.catalog?.providers?.map { it.id })
  }

  @Test
  fun testClientErrorDoesNotUseCacheOrThrow() {
    val server = catalogServer { exchange -> writeJson(exchange, 400, """{"error":"bad room"}""") }
    try {
      val cache = MemoryEncryptedCatalogCache()
      cache.save("room-1", projectBaselineCatalog(sampleCatalog()))
      val client = MeridianClient(base(server), "room-1", timeoutMillis = 1_000)
      val loaded = runBlocking { client.loadCatalog(cache) }
      assertNull(loaded.catalog)
      assertNull(loaded.origin)
      assertNotNull(cache.load("room-1"))
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testServerErrorWithoutCacheDoesNotThrow() {
    val server = catalogServer { exchange -> writeJson(exchange, 503, """{"error":"down"}""") }
    try {
      val client = MeridianClient(base(server), "room-1", timeoutMillis = 1_000)
      val loaded = runBlocking { client.loadCatalog(MemoryEncryptedCatalogCache()) }
      assertNull(loaded.catalog)
      assertNull(loaded.origin)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testRedirectIsNotFollowed() {
    val evilHits = AtomicInteger()
    val evil = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    evil.createContext("/") { exchange ->
      evilHits.incrementAndGet()
      writeJson(exchange, 200, """{"demoDate":"2026-09-18","recipients":[],"providers":[]}""")
    }
    evil.start()
    val server = catalogServer { exchange ->
      exchange.responseHeaders.add("Location", "http://127.0.0.1:${evil.address.port}/collect")
      writeJson(exchange, 302, "")
    }
    try {
      val client = MeridianClient(base(server), "room-1", timeoutMillis = 1_000)
      val loaded = runBlocking { client.loadCatalog(MemoryEncryptedCatalogCache()) }
      assertNull(loaded.catalog)
      assertEquals(0, evilHits.get())
    } finally {
      server.stop(0)
      evil.stop(0)
    }
  }

  private fun sampleRecipient() = Recipient(
    id = "northline-studio",
    name = "Northline Studio",
    initials = "NS",
    detail = "Design",
    category = "Shopping",
    color = "#fff",
  )

  private fun sampleCatalog() = CatalogResponse(
    demoDate = "2026-09-18",
    recipients = listOf(sampleRecipient()),
    providers = listOf(
      DynamicProvider(
        id = "adyen",
        name = "Adyen",
        description = "Card processor",
        methods = listOf("card"),
        currencies = listOf("GBP"),
      ),
      DynamicProvider(
        id = "worldpay",
        name = "Worldpay",
        description = "Bank payment processor",
        methods = listOf("bank"),
        currencies = listOf("GBP"),
      ),
    ),
  )

  private fun base(server: HttpServer) = "http://127.0.0.1:${server.address.port}/api/v1"

  private fun catalogServer(
    handler: com.sun.net.httpserver.HttpHandler,
  ): HttpServer {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.createContext("/api/v1/catalog", handler)
    server.start()
    return server
  }

  private fun writeJson(exchange: com.sun.net.httpserver.HttpExchange, status: Int, body: String) {
    val bytes = body.toByteArray(StandardCharsets.UTF_8)
    exchange.responseHeaders.add("Content-Type", "application/json")
    exchange.sendResponseHeaders(status, bytes.size.toLong())
    exchange.responseBody.use { it.write(bytes) }
  }
}
