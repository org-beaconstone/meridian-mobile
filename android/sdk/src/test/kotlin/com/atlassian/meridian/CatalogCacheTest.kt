package com.atlassian.meridian

import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetSocketAddress
import java.nio.file.Files
import java.nio.file.attribute.PosixFilePermission

class CatalogCacheTest {
  private val now = 1_700_000_000_000L

  private val fixture = """
    {
      "accountScope": "everyday",
      "corridor": "gb",
      "currency": "gbp",
      "ttlSeconds": 120,
      "generatedBy": "rehearsal",
      "methods": [
        {
          "id": "card-adyen",
          "method": "card",
          "provider": "adyen",
          "displayName": "Debit card",
          "capabilities": ["charge", "live_eligibility", "future_capability"],
          "requiresLiveEligibility": false,
          "ttlSeconds": 30,
          "enabled": true,
          "routingWeight": 10,
          "metadata": {"region": "uk"}
        },
        {
          "id": "bank-worldpay",
          "method": "bank",
          "provider": "worldpay",
          "displayName": "Bank payment",
          "capabilities": ["charge"],
          "requiresLiveEligibility": false,
          "ttlSeconds": 600,
          "enabled": true,
          "settlementHint": "batch"
        },
        {
          "id": "card-adyen-off",
          "method": "card",
          "provider": "adyen",
          "displayName": "Debit card offline",
          "enabled": false
        },
        {
          "id": "eur-skip",
          "method": "card",
          "provider": "adyen",
          "displayName": "Other currency",
          "currency": "EUR"
        },
        {"displayName": "missing id"},
        {
          "id": "bad-flag",
          "method": "card",
          "provider": "adyen",
          "displayName": "Bad flag",
          "enabled": 1
        },
        "not-an-object"
      ]
    }
  """.trimIndent()

  @Test
  fun testOpenDescriptorIgnoresUnknownAttributes() {
    val scope = CatalogScope.parse(" everyday ", "gb", "gbp")
    val catalog = parsePaymentMethodsCatalog(fixture, scope)

    assertEquals("everyday", catalog.accountScope)
    assertEquals("GB", catalog.corridor)
    assertEquals("GBP", catalog.currency)
    assertEquals(listOf("card-adyen", "bank-worldpay", "card-adyen-off"), catalog.methods.map { it.id })

    val card = catalog.methods[0]
    assertEquals("adyen", card.provider)
    assertEquals("card", card.method)
    assertEquals("Debit card", card.displayName)
    assertEquals(listOf("charge", "live_eligibility", "future_capability"), card.capabilities)
    assertTrue(card.requiresLiveEligibility)
    assertTrue(catalog.methods.all { it.provider == "adyen" || it.provider == "worldpay" })
  }

  @Test
  fun testNonGbpRejectedWithoutNetwork() {
    val client = MeridianClient("http://127.0.0.1:9/api/v1", "everyday-room")
    val error = assertThrows(MeridianError.ValidationError::class.java) {
      runBlocking { client.getPaymentMethods("everyday", "GB", "EUR") }
    }
    assertTrue(error.message!!.contains("GBP"))
  }

  @Test
  fun testPaymentMethodsUrlUsesV2OnSameOrigin() {
    val scope = CatalogScope.parse("everyday", "gb", "gbp")
    val url = paymentMethodsUrl("http://127.0.0.1:8080/api/v1/", scope)
    assertEquals("/api/v2/payment-methods", url.path)
    assertEquals("accountScope=everyday&corridor=GB&currency=GBP", url.query)

    val scoped = CatalogScope.parse("acct:everyday", "eea", "GBP")
    val encoded = paymentMethodsUrl("http://127.0.0.1:8080/api/v1", scoped)
    assertTrue(encoded.query.contains("accountScope=acct%3Aeveryday"))
    assertTrue(encoded.query.contains("corridor=EEA"))
    assertTrue(encoded.query.contains("currency=GBP"))
  }

  @Test
  fun testEncryptedRoundTripAndScopeIsolation() {
    val store = MemoryCatalogBlobStore()
    val cache = CatalogCache(store, MemoryCatalogKeyProvider())
    val gb = CatalogScope.parse("everyday", "GB", "GBP")
    val eea = CatalogScope.parse("everyday", "EEA", "GBP")

    cache.store(gb, fixture, now)
    val fresh = cache.read(gb, now)
    assertEquals(listOf("card-adyen", "bank-worldpay"), fresh!!.methods.map { it.id })
    assertTrue(fresh.fromCache)
    assertFalse(fresh.stale)
    assertEquals(0, fresh.withheldLiveEligibility)

    val ciphertext = store.peek(gb.storageKey)!!
    val leaked = String(ciphertext, Charsets.ISO_8859_1)
    assertFalse(leaked.contains("card-adyen"))
    assertFalse(leaked.contains("Debit card"))

    assertNull(cache.read(eea, now))
    store.copy(gb.storageKey, eea.storageKey)
    assertThrows(MeridianError.CatalogUnavailable::class.java) {
      cache.read(eea, now)
    }

    val tampered = ciphertext.copyOf()
    tampered[tampered.lastIndex] = tampered[tampered.lastIndex].inc()
    store.write(gb.storageKey, tampered)
    assertThrows(MeridianError.CatalogUnavailable::class.java) {
      cache.read(gb, now)
    }
  }

  @Test
  fun testStaleLiveEligibilityFailsClosed() {
    val cache = CatalogCache(MemoryCatalogBlobStore(), MemoryCatalogKeyProvider())
    val scope = CatalogScope.parse("everyday", "GB", "GBP")
    cache.store(scope, fixture, now)

    val atMethodTtl = cache.read(scope, now + 30_000)!!
    assertEquals(listOf("bank-worldpay"), atMethodTtl.methods.map { it.id })
    assertEquals(1, atMethodTtl.withheldLiveEligibility)
    assertFalse(atMethodTtl.stale)

    val atCatalogTtl = cache.read(scope, now + 120_000)!!
    assertEquals(listOf("bank-worldpay"), atCatalogTtl.methods.map { it.id })
    assertEquals(1, atCatalogTtl.withheldLiveEligibility)
    assertTrue(atCatalogTtl.stale)
    assertEquals("worldpay", atCatalogTtl.methods.single().provider)
  }

  @Test
  fun testMismatchedScopeIsNotCached() {
    val store = MemoryCatalogBlobStore()
    val cache = CatalogCache(store, MemoryCatalogKeyProvider())
    val scope = CatalogScope.parse("everyday", "GB", "GBP")
    val other = fixture.replace(""""accountScope": "everyday"""", """"accountScope": "other"""")
    assertThrows(MeridianError.ValidationError::class.java) {
      cache.store(scope, other, now)
    }
    assertNull(store.peek(scope.storageKey))
  }

  @Test
  fun testFetchCachesSameKeyAndFailsClosedWhenStale() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val seen = mutableListOf<String>()
    var calls = 0
    server.createContext("/api/v2/payment-methods") { exchange ->
      calls += 1
      val session = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      val idempotency = exchange.requestHeaders.getFirst("Idempotency-Key")
      seen.add("${exchange.requestURI.rawPath}?${exchange.requestURI.rawQuery}|$session|$idempotency")
      val body = if (calls == 1) fixture.toByteArray() else """{"ok":false}""".toByteArray()
      val status = if (calls == 1) 200 else 503
      exchange.sendResponseHeaders(status, body.size.toLong())
      exchange.responseBody.write(body)
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:${server.address.port}/api/v1", "everyday-room")
      val cache = CatalogCache(MemoryCatalogBlobStore(), MemoryCatalogKeyProvider())
      val fresh = runBlocking {
        cache.resolve(client, "everyday", "gb", "GBP", now)
      }
      assertFalse(fresh.fromCache)
      assertEquals(listOf("card-adyen", "bank-worldpay"), fresh.methods.map { it.id })

      val stale = runBlocking {
        cache.resolve(client, "everyday", "GB", "gbp", now + 30_000)
      }
      assertTrue(stale.fromCache)
      assertEquals(listOf("bank-worldpay"), stale.methods.map { it.id })
      assertEquals(1, stale.withheldLiveEligibility)
      assertEquals(2, seen.size)
      assertEquals(seen[0], seen[1])
      assertTrue(seen[0].startsWith("/api/v2/payment-methods?"))
      assertTrue(seen[0].contains("accountScope=everyday"))
      assertTrue(seen[0].contains("corridor=GB"))
      assertTrue(seen[0].contains("currency=GBP"))
      assertTrue(seen[0].endsWith("|everyday-room|null"))
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testHttpFailureWithoutCacheDoesNotInventProviders() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    server.createContext("/api/v2/payment-methods") { exchange ->
      val body = """{"ok":false}""".toByteArray()
      exchange.sendResponseHeaders(503, body.size.toLong())
      exchange.responseBody.write(body)
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:${server.address.port}/api/v1", "everyday-room")
      val cache = CatalogCache(MemoryCatalogBlobStore(), MemoryCatalogKeyProvider())
      val error = assertThrows(MeridianError.HttpError::class.java) {
        runBlocking { cache.resolve(client, "everyday", "GB", "GBP", now) }
      }
      assertEquals(503, error.statusCode)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testPlatformProtectedFileIsOwnerOnly() {
    assertFalse(AndroidKeystoreKeyProtector.isAvailable())
    val dir = Files.createTempDirectory("meridian-catalog").toFile()
    try {
      val scope = CatalogScope.parse("everyday", "GB", "GBP")
      val cache = CatalogCache.platformProtected(dir)
      cache.store(scope, fixture, now)
      val read = cache.read(scope, now)!!
      assertEquals("card-adyen", read.methods.first().id)

      val key = java.io.File(dir, "catalog.key")
      val permissions = Files.getPosixFilePermissions(key.toPath())
      assertTrue(permissions.contains(PosixFilePermission.OWNER_READ))
      assertFalse(permissions.contains(PosixFilePermission.GROUP_READ))
      assertFalse(permissions.contains(PosixFilePermission.OTHERS_READ))

      val blobs = java.io.File(dir, "blobs").listFiles { file -> file.name.endsWith(".bin") }!!
      assertEquals(1, blobs.size)
      val stored = String(blobs[0].readBytes(), Charsets.ISO_8859_1)
      assertFalse(stored.contains("Debit card"))
    } finally {
      dir.deleteRecursively()
    }
  }
}
