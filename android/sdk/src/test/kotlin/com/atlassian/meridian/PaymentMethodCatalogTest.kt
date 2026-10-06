package com.atlassian.meridian

import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.net.InetSocketAddress
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

class PaymentMethodCatalogTest {
  private val key = ByteArray(32) { index -> (index + 3).toByte() }

  @Test
  fun testOpenDescriptorIgnoresUnknownAttributes() {
    val catalog = parsePaymentMethodsCatalog(
      """
      {
        "accountScope": "everyday",
        "corridor": "GB",
        "currency": "GBP",
        "ttlSeconds": 300,
        "generatedBy": "catalog-service",
        "routingHint": {"lane": "future", "rank": 4},
        "methods": [
          {
            "id": "card-adyen",
            "method": "card",
            "provider": "adyen",
            "displayName": "Debit card",
            "currency": "GBP",
            "corridor": "GB",
            "requiresLiveEligibility": false,
            "capabilities": ["pay", {"kind": "future"}],
            "futureSettlementWindow": "T+2",
            "wallet": {"type": "later"}
          },
          {"futureOnly": true},
          {
            "id": "bank-worldpay",
            "method": "bank",
            "provider": "worldpay",
            "displayName": 12,
            "requiresLiveEligibility": true,
            "capabilities": ["pay", "live-eligibility"]
          }
        ]
      }
      """.trimIndent(),
    )

    assertEquals(listOf("generatedBy", "routingHint"), catalog.ignoredAttributeNames)
    assertEquals(2, catalog.methods.size)
    val card = catalog.methods[0]
    assertEquals("adyen", card.provider)
    assertEquals("card", card.method)
    assertEquals(listOf("pay"), card.capabilities)
    assertEquals(listOf("futureSettlementWindow", "wallet"), card.ignoredAttributeNames)
    val bank = catalog.methods[1]
    assertEquals("", bank.displayName)
    assertTrue(bank.requiresFreshEligibility)
    assertTrue(bank.isHardcodedBaseline)
    assertFalse(catalog.methods.any { it.provider == "unreleased" })
  }

  @Test
  fun testUnreleasedProviderIsNotPayableBaseline() {
    val catalog = sampleCatalog().copy(
      methods = sampleCatalog().methods + PaymentMethodDescriptor(
        id = "later",
        method = "card",
        provider = "unreleased",
        displayName = "Later",
        currency = "GBP",
        corridor = "GB",
      ),
    )
    val resolved = CatalogExpiryPolicy.resolve(catalog, storedAtEpochMs = 1_000, nowEpochMs = 1_000, fromCache = false)
    assertEquals(listOf("adyen", "worldpay"), resolved.payableBaseline.map { it.provider })
    assertTrue(resolved.available.any { it.provider == "unreleased" })
  }

  @Test
  fun testCapabilityExpiryFailsClosedWhenStale() {
    val catalog = sampleCatalog()
    val fresh = CatalogExpiryPolicy.resolve(catalog, 0, 299_999, fromCache = true)
    assertFalse(fresh.stale)
    assertEquals(listOf("adyen", "worldpay"), fresh.payableBaseline.map { it.provider })
    assertTrue(fresh.withheld.isEmpty())

    val stale = CatalogExpiryPolicy.resolve(catalog, 0, 300_000, fromCache = true)
    assertTrue(stale.stale)
    assertTrue(stale.failClosed)
    assertEquals(listOf("adyen"), stale.payableBaseline.map { it.provider })
    assertEquals(listOf("worldpay"), stale.withheld.map { it.provider })
  }

  @Test
  fun testMethodTtlCannotOutliveCatalogSnapshot() {
    val catalog = sampleCatalog().copy(
      ttlSeconds = 300,
      methods = listOf(
        baselineCard().copy(ttlSeconds = 10, requiresLiveEligibility = false, capabilities = listOf("pay")),
        baselineBank().copy(ttlSeconds = 86_400, capabilities = listOf("live-eligibility"), requiresLiveEligibility = false),
      ),
    )
    val atTenSeconds = CatalogExpiryPolicy.resolve(catalog, 0, 10_000, fromCache = true)
    assertTrue(atTenSeconds.stale)
    assertTrue(atTenSeconds.withheld.isEmpty())
    assertTrue(atTenSeconds.available.any { it.provider == "adyen" })
    assertTrue(atTenSeconds.available.any { it.provider == "worldpay" })

    val expired = CatalogExpiryPolicy.resolve(catalog, 0, 300_000, fromCache = true)
    assertEquals(listOf("adyen"), expired.available.map { it.provider })
    assertEquals(listOf("worldpay"), expired.withheld.map { it.provider })
  }

  @Test
  fun testEncryptedCacheRoundTripIsScopedAndFailsClosedOnTamper() {
    val store = MemoryProtectedBlobStore()
    val cache = CatalogCache(store, AesGcmCatalogSealer(key))
    val catalog = sampleCatalog().forRequest("everyday", "GB", "GBP")
    cache.write(catalog, 5_000)
    val storageKey = cache.storageKey("everyday", "GB", "GBP")
    assertEquals("everyday\u001fGB\u001fGBP", storageKey)
    val blob = store.read(storageKey)
    assertNotNull(blob)
    val encoded = blob!!.toString(StandardCharsets.UTF_8)
    assertTrue(blob.copyOfRange(0, 4).contentEquals(CatalogBlob.MAGIC))
    assertFalse(encoded.contains("adyen"))
    assertFalse(encoded.contains("everyday"))

    val resolved = cache.read("everyday", "GB", "GBP", 5_000)
    assertNotNull(resolved)
    assertEquals(listOf("adyen", "worldpay"), resolved!!.payableBaseline.map { it.provider })
    assertTrue(resolved.available.all { it.ignoredAttributeNames.isEmpty() })

    cache.write(catalog.copy(accountScope = "savings"), 5_000)
    assertEquals(2, store.keys.size)

    blob[blob.lastIndex] = (blob[blob.lastIndex] + 1).toByte()
    store.write(storageKey, blob)
    assertNull(cache.read("everyday", "GB", "GBP", 5_000))
    assertNull(store.read(storageKey))
  }

  @Test
  fun testUnknownSchemaAndMismatchedScopeFailClosed() {
    val store = MemoryProtectedBlobStore()
    val sealer = AesGcmCatalogSealer(key)
    val cache = CatalogCache(store, sealer)
    val keyName = catalogStorageKey("everyday", "GB", "GBP")
    store.write(keyName, sealer.seal("""{"schema":2,"accountScope":"everyday","corridor":"GB","currency":"GBP","storedAtEpochMs":1,"ttlSeconds":300,"methods":[]}""".toByteArray()))
    assertNull(cache.read("everyday", "GB", "GBP", 1))
    assertTrue(store.keys.isEmpty())

    store.write(
      keyName,
      sealer.seal("""{"schema":1,"accountScope":"savings","corridor":"GB","currency":"GBP","storedAtEpochMs":1,"ttlSeconds":300,"methods":[]}""".toByteArray()),
    )
    assertNull(cache.read("everyday", "GB", "GBP", 1))
    assertTrue(store.keys.isEmpty())
  }

  @Test
  fun testFileStoreRoundTripKeepsCiphertext() {
    val directory = Files.createTempDirectory("meridian-catalog").toFile()
    val cache = CatalogCache(FileProtectedBlobStore(directory), AesGcmCatalogSealer(key))
    cache.write(sampleCatalog().forRequest("everyday", "GB", "GBP"), 20)
    val resolved = cache.read("everyday", "GB", "GBP", 20)
    assertEquals(listOf("card", "bank"), resolved!!.payableBaseline.map { it.method })
    val files = directory.listFiles { file -> file.extension == "bin" }!!.toList()
    assertEquals(1, files.size)
    assertFalse(String(files[0].readBytes(), StandardCharsets.ISO_8859_1).contains("worldpay"))
  }

  @Test
  fun testSessionDirectoriesDiffer() {
    assertTrue(catalogSessionDirectoryName("room-a") != catalogSessionDirectoryName("room-b"))
    assertTrue(catalogSessionDirectoryName("room-a").matches(Regex("[0-9a-f]{64}")))
  }

  @Test
  fun testCurrencyAndUrlStayOnGbpCatalog() {
    val client = MeridianClient("http://10.0.2.2:8080/api/v1/", "room-kept")
    assertEquals(
      "http://10.0.2.2:8080/api/v2/payment-methods?accountScope=everyday&corridor=GB&currency=GBP",
      client.paymentMethodsUrl("everyday", "GB"),
    )
    try {
      client.paymentMethodsUrl("everyday", "GB", "EUR")
      fail("Expected GBP validation")
    } catch (error: MeridianError.ValidationError) {
      assertTrue(error.message!!.contains("GBP"))
    }
  }

  @Test
  fun testFetchUsesSessionAndCachePolicyWithoutAnotherProvider() = runBlocking {
    val requests = mutableListOf<String>()
    val hits = AtomicInteger()
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.createContext("/api/v2/payment-methods") { exchange ->
      hits.incrementAndGet()
      requests.add(exchange.requestURI.toString())
      assertEquals("GET", exchange.requestMethod)
      assertEquals("room-kept", exchange.requestHeaders.getFirst("X-Rehearsal-Session"))
      assertNull(exchange.requestHeaders.getFirst("Idempotency-Key"))
      val body = catalogJson()
      val status = if (hits.get() == 1) 200 else 503
      val payload = if (status == 200) body else """{"ok":false,"error":"unavailable","code":"UNAVAILABLE"}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(status, payload.toByteArray().size.toLong())
      exchange.responseBody.write(payload.toByteArray())
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:${server.address.port}/api/v1", "room-kept")
      val store = MemoryProtectedBlobStore()
      val cache = CatalogCache(store, AesGcmCatalogSealer(key))
      val clock = AtomicLong(1_000)
      val service = PaymentMethodCatalogService(client, cache) { clock.get() }

      val fresh = service.load("everyday", "GB")
      assertFalse(fresh.fromCache)
      assertFalse(fresh.stale)
      assertEquals(listOf("adyen", "worldpay"), fresh.payableBaseline.map { it.provider })
      assertTrue(fresh.available.none { it.id == "elsewhere" })
      assertEquals(1, requests.size)
      assertTrue(requests[0].startsWith("/api/v2/payment-methods?"))
      assertTrue(requests[0].contains("accountScope=everyday"))
      assertTrue(requests[0].contains("currency=GBP"))

      val cached = service.load("everyday", "GB")
      assertTrue(cached.fromCache)
      assertEquals(1, hits.get())

      clock.set(1_000 + 300_000)
      val fallback = service.load("everyday", "GB")
      assertTrue(fallback.fromCache)
      assertTrue(fallback.failClosed)
      assertEquals(listOf("adyen"), fallback.payableBaseline.map { it.provider })
      assertEquals(listOf("worldpay"), fallback.withheld.map { it.provider })
      assertEquals(2, hits.get())
      assertTrue(requests.all { it.startsWith("/api/v2/payment-methods?") })
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testHttpFailureWithoutCacheDoesNotInventBaseline() = runBlocking {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val paths = mutableListOf<String>()
    server.createContext("/") { exchange ->
      paths.add(exchange.requestURI.path)
      val payload = """{"error":"no"}"""
      exchange.sendResponseHeaders(503, payload.length.toLong())
      exchange.responseBody.write(payload.toByteArray())
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:${server.address.port}/api/v1", "room-kept")
      val cache = CatalogCache(MemoryProtectedBlobStore(), AesGcmCatalogSealer(key))
      try {
        PaymentMethodCatalogService(client, cache).load("everyday", "GB")
        fail("Expected HTTP failure")
      } catch (error: MeridianError.HttpError) {
        assertEquals(503, error.statusCode)
      }
      assertEquals(listOf("/api/v2/payment-methods"), paths)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testNonGbpResponseIsRejectedAndNotCached() = runBlocking {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.createContext("/api/v2/payment-methods") { exchange ->
      val payload = catalogJson().replace(""""currency": "GBP"""", """"currency": "EUR"""")
      exchange.sendResponseHeaders(200, payload.toByteArray().size.toLong())
      exchange.responseBody.write(payload.toByteArray())
      exchange.close()
    }
    server.start()
    try {
      val store = MemoryProtectedBlobStore()
      val client = MeridianClient("http://127.0.0.1:${server.address.port}/api/v1", "room-kept")
      try {
        client.fetchPaymentMethods("everyday", "GB")
        fail("Expected GBP rejection")
      } catch (error: MeridianError.ValidationError) {
        assertTrue(error.message!!.contains("GBP"))
      }
      assertTrue(store.keys.isEmpty())
    } finally {
      server.stop(0)
    }
  }

  private fun baselineCard() = PaymentMethodDescriptor(
    id = "card-adyen",
    method = "card",
    provider = "adyen",
    displayName = "Debit card",
    currency = "GBP",
    corridor = "GB",
    requiresLiveEligibility = false,
    capabilities = listOf("pay"),
  )

  private fun baselineBank() = PaymentMethodDescriptor(
    id = "bank-worldpay",
    method = "bank",
    provider = "worldpay",
    displayName = "Bank payment",
    currency = "GBP",
    corridor = "GB",
    requiresLiveEligibility = true,
    capabilities = listOf("pay", "live-eligibility"),
  )

  private fun sampleCatalog() = PaymentMethodsCatalog(
    accountScope = "everyday",
    corridor = "GB",
    currency = "GBP",
    ttlSeconds = 300,
    methods = listOf(baselineCard(), baselineBank()),
  )

  private fun catalogJson() = """
    {
      "accountScope": "everyday",
      "corridor": "GB",
      "currency": "GBP",
      "ttlSeconds": 300,
      "futureSettlementWindow": "T+2",
      "methods": [
        {
          "id": "card-adyen",
          "method": "card",
          "provider": "adyen",
          "displayName": "Debit card",
          "currency": "GBP",
          "corridor": "GB",
          "requiresLiveEligibility": false,
          "capabilities": ["pay"],
          "wallet": {"type": "later"}
        },
        {
          "id": "bank-worldpay",
          "method": "bank",
          "provider": "worldpay",
          "displayName": "Bank payment",
          "requiresLiveEligibility": true,
          "capabilities": ["pay", "live-eligibility"]
        },
        {
          "id": "elsewhere",
          "method": "card",
          "provider": "adyen",
          "currency": "GBP",
          "corridor": "EU"
        }
      ]
    }
  """.trimIndent()
}
