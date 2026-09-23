package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import com.sun.net.httpserver.HttpExchange
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
import java.util.logging.Handler
import java.util.logging.Level
import java.util.logging.LogRecord
import java.util.logging.Logger

class ProviderConfigTest {
  private val mapper = ObjectMapper().registerKotlinModule()

  @Test
  fun testProviderIdDecodesKnownAndUnrecognizedIdentifiers() {
    val adyen = mapper.readValue("\"adyen\"", ProviderId::class.java)
    val worldpay = mapper.readValue("\"worldpay\"", ProviderId::class.java)
    val unrecognized = mapper.readValue("\"extra\"", ProviderId::class.java)

    assertEquals(ProviderId.adyen, adyen)
    assertEquals("adyen", adyen.rawValue)
    assertEquals(ProviderId.worldpay, worldpay)
    assertEquals("extra", unrecognized.rawValue)
    assertEquals("\"extra\"", mapper.writeValueAsString(unrecognized))
  }

  @Test
  fun testProviderIdRejectsBlank() {
    try {
      ProviderId("  ")
      throw AssertionError("blank provider id should be rejected")
    } catch (error: IllegalArgumentException) {
      assertTrue(error.message?.contains("Provider id") == true)
    }
  }

  @Test
  fun testShippedFlagDefaultsToRemoteAndParsesMilestone2Rollback() {
    assertEquals(ProviderPickerMode.REMOTE_CONFIG, ProviderPickerFlags.shippedDefault)
    assertEquals(ProviderPickerMode.REMOTE_CONFIG, ProviderPickerFlags.resolve(runtimeOverride = null, environment = null, systemProperty = null))
    assertEquals(
      ProviderPickerMode.MILESTONE_2_BASELINE,
      ProviderPickerFlags.resolve(runtimeOverride = null, environment = "milestone2", systemProperty = null),
    )
    assertEquals(
      ProviderPickerMode.REMOTE_CONFIG,
      ProviderPickerFlags.resolve(
        runtimeOverride = ProviderPickerMode.REMOTE_CONFIG,
        environment = "milestone2",
        systemProperty = "baseline",
      ),
    )
    assertNull(ProviderPickerFlags.parse("stripe"))
  }

  @Test
  fun testValidationDropsMalformedProvidersAndKeepsOpenIds() {
    val config = validatePaymentProviderConfig(
      PaymentProviderConfigResponse(
        configVersion = "v9",
        providers = listOf(
          PaymentProviderResponse("adyen", "Debit card", listOf("card"), listOf("UK")),
          PaymentProviderResponse("extra", "Configured method", listOf("bank", "wallet"), listOf("uk")),
          PaymentProviderResponse("", "Missing", listOf("card"), listOf("UK")),
          PaymentProviderResponse("broken", "Empty methods", emptyList(), listOf("UK")),
          PaymentProviderResponse("../nope", "Bad id", listOf("card"), listOf("UK")),
        ),
      ),
    )

    assertEquals("v9", config.configVersion)
    assertEquals(listOf("adyen", "extra"), config.providers.map { it.id.rawValue })
    assertEquals(listOf(PaymentMethod.bank), config.providers[1].methods)
    assertEquals(listOf("UK"), config.providers[1].corridors)
  }

  @Test
  fun testPickerRendersCorridorProvidersAndKeepsBaselineLabels() {
    val config = validatePaymentProviderConfig(
      PaymentProviderConfigResponse(
        configVersion = "v-baseline",
        providers = listOf(
          PaymentProviderResponse("adyen", "Debit card", listOf("card"), listOf("UK", "US")),
          PaymentProviderResponse("worldpay", "Bank payment", listOf("bank"), listOf("UK", "US")),
          PaymentProviderResponse("extra", "Configured method", listOf("bank"), listOf("UK")),
        ),
      ),
    )

    val uk = pickerOptions(config.providersForCorridor("UK"))
    val us = pickerOptions(config.providersForCorridor("us"))

    assertEquals(
      listOf("Debit card · Adyen", "Bank payment · Worldpay", "Configured method"),
      uk.map { it.label },
    )
    assertEquals(listOf(PaymentMethod.card, PaymentMethod.bank, PaymentMethod.bank), uk.map { it.method })
    assertEquals(listOf("adyen", "worldpay"), us.map { it.providerId.rawValue })
  }

  @Test
  fun testLockedSelectionDoesNotSwitchProvider() {
    val card = PickerOption(ProviderId.adyen, PaymentMethod.card, "Debit card · Adyen")
    val bank = PickerOption(ProviderId.worldpay, PaymentMethod.bank, "Bank payment · Worldpay")
    val retained = retainProviderSelection(card, listOf(bank), locked = true)
    val unlocked = retainProviderSelection(card, listOf(bank), locked = false)

    assertEquals(card, retained)
    assertEquals(bank, unlocked)
  }

  @Test
  fun testTwoProviderFlowUnchangedWhenConfigReturnsOnlyAdyenAndWorldpay() {
    val configHits = AtomicInteger()
    val failConfig = java.util.concurrent.atomic.AtomicBoolean(false)
    val paymentMethods = mutableListOf<String>()
    val paymentKeys = mutableListOf<String>()
    val server = httpServer()
    server.createContext("/api/v1/config/payment-providers") { exchange ->
      configHits.incrementAndGet()
      val session = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      assertEquals("two-provider-room", session)
      if (failConfig.get()) {
        sendJson(exchange, 503, """{"error":"config unavailable"}""")
      } else {
        sendJson(
          exchange,
          200,
          """
          {
            "configVersion": "v-baseline",
            "providers": [
              {"id": "adyen", "name": "Debit card", "methods": ["card"], "corridors": ["UK", "US"]},
              {"id": "worldpay", "name": "Bank payment", "methods": ["bank"], "corridors": ["UK", "US"]}
            ]
          }
          """.trimIndent(),
        )
      }
    }
    server.createContext("/api/v1/payments") { exchange ->
      assertEquals("two-provider-room", exchange.requestHeaders.getFirst("X-Rehearsal-Session"))
      val key = exchange.requestHeaders.getFirst("Idempotency-Key")
      val body = exchange.requestBody.readBytes().toString(StandardCharsets.UTF_8)
      val method = mapper.readTree(body).get("method").asText()
      synchronized(paymentMethods) {
        paymentKeys.add(key)
        paymentMethods.add(method)
      }
      val retry = synchronized(paymentKeys) { paymentKeys.count { it == key } > 1 }
      if (retry) {
        sendJson(exchange, 200, """{"ok":true,"paymentId":"tx-1","state":null}""")
      } else {
        sendJson(exchange, 202, """{"ok":false,"code":"PAYMENT_PENDING","paymentId":"tx-1","error":"Awaiting confirmation"}""")
      }
    }
    server.start()
    val health = ProviderConfigHealth()
    val messages = mutableListOf<String>()
    val logger = Logger.getLogger(ProviderPickerFlags.HEALTH_LOGGER)
    val handler = object : Handler() {
      override fun publish(record: LogRecord) {
        messages.add(record.message)
      }

      override fun flush() = Unit

      override fun close() = Unit
    }
    logger.addHandler(handler)
    logger.level = Level.INFO
    try {
      val client = MeridianClient(
        baseURL = "http://127.0.0.1:${server.address.port}/api/v1",
        sessionId = "two-provider-room",
        providerConfigStore = ProviderConfigStore(),
        providerConfigHealth = health,
        pickerMode = ProviderPickerMode.REMOTE_CONFIG,
      )
      val loaded = runBlocking { client.loadPaymentProviders("UK") }
      val options = pickerOptions(loaded.providers)
      assertEquals(ProviderConfigSource.REMOTE, loaded.source)
      assertEquals(listOf("Debit card · Adyen", "Bank payment · Worldpay"), options.map { it.label })
      assertEquals(listOf(ProviderId.adyen, ProviderId.worldpay), options.map { it.providerId })
      assertEquals(listOf(PaymentMethod.card, PaymentMethod.bank), options.map { it.method })

      val locked = retainProviderSelection(options.first(), options, locked = true)
      assertNotNull(locked)
      val key = "payment-key-adyen"
      val pending = runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 1050,
          method = locked!!.method,
          note = "GBP pence",
          idempotencyKey = key,
        )
      }
      assertFalse(pending.ok)
      assertEquals("PAYMENT_PENDING", pending.code)

      failConfig.set(true)
      val fallback = runBlocking { client.loadPaymentProviders("UK") }
      assertEquals(ProviderConfigSource.CACHE, fallback.source)
      assertEquals("v-baseline", fallback.configVersion)
      val stillLocked = retainProviderSelection(locked, pickerOptions(fallback.providers), locked = true)
      assertEquals(PaymentMethod.card, stillLocked?.method)
      assertEquals(ProviderId.adyen, stillLocked?.providerId)

      val repeated = runBlocking {
        client.submitPayment(
          recipientId = "northline-studio",
          amountMinor = 1050,
          method = stillLocked!!.method,
          note = "GBP pence",
          idempotencyKey = key,
        )
      }
      assertTrue(repeated.ok)
      assertEquals(listOf("card", "card"), paymentMethods)
      assertEquals(listOf(key, key), paymentKeys)
      assertEquals(2, configHits.get())

      val snapshot = health.snapshot()
      assertEquals(2, snapshot.fetchAttempts)
      assertEquals(1, snapshot.fetchSuccesses)
      assertEquals(1, snapshot.fallbacks)
      assertEquals(0.5, snapshot.successRate, 0.0001)
      assertEquals(0.5, snapshot.fallbackRate, 0.0001)
      assertTrue(messages.any { it.contains("event=fetch_success") && it.contains("successRate=1.0000") && it.contains("fallbackToCacheRate=0.0000") })
      assertTrue(messages.any { it.contains("event=fallback_to_cache") && it.contains("successRate=0.5000") && it.contains("fallbackToCacheRate=0.5000") })
    } finally {
      logger.removeHandler(handler)
      server.stop(0)
    }
  }

  @Test
  fun testConfigFailureWithEmptyCacheUsesMilestone2Seed() {
    val server = httpServer()
    server.createContext("/api/v1/config/payment-providers") { exchange ->
      sendJson(exchange, 500, """{"error":"down"}""")
    }
    server.start()
    try {
      val health = ProviderConfigHealth()
      val client = MeridianClient(
        baseURL = "http://127.0.0.1:${server.address.port}/api/v1",
        sessionId = "empty-cache-room",
        providerConfigStore = ProviderConfigStore(),
        providerConfigHealth = health,
      )
      val result = runBlocking { client.loadPaymentProviders("UK", ProviderPickerMode.REMOTE_CONFIG) }
      assertEquals(ProviderConfigSource.CACHE, result.source)
      assertEquals("milestone-2", result.configVersion)
      assertEquals(listOf("adyen", "worldpay"), pickerOptions(result.providers).map { it.providerId.rawValue })
      assertEquals(1.0, health.snapshot().fallbackRate, 0.0001)
      assertEquals(0.0, health.snapshot().successRate, 0.0001)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testMalformedConfigDoesNotReplaceCachedProviders() {
    var calls = 0
    val server = httpServer()
    server.createContext("/api/v1/config/payment-providers") { exchange ->
      calls += 1
      if (calls == 1) {
        sendJson(
          exchange,
          200,
          """
          {"configVersion":"good","providers":[
            {"id":"adyen","name":"Debit card","methods":["card"],"corridors":["UK"]},
            {"id":"worldpay","name":"Bank payment","methods":["bank"],"corridors":["UK"]}
          ]}
          """.trimIndent(),
        )
      } else {
        sendJson(exchange, 200, """{"configVersion":"","providers":[]}""")
      }
    }
    server.start()
    try {
      val client = MeridianClient(
        baseURL = "http://127.0.0.1:${server.address.port}/api/v1",
        sessionId = "malformed-room",
        providerConfigStore = ProviderConfigStore(),
        providerConfigHealth = ProviderConfigHealth(),
      )
      val first = runBlocking { client.loadPaymentProviders("UK") }
      val second = runBlocking { client.loadPaymentProviders("UK") }
      assertEquals("good", first.configVersion)
      assertEquals(ProviderConfigSource.CACHE, second.source)
      assertEquals("good", second.configVersion)
      assertEquals(listOf("adyen", "worldpay"), second.providers.map { it.id.rawValue })
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testMilestone2FlagSkipsRemoteConfig() {
    val hits = AtomicInteger()
    val server = httpServer()
    server.createContext("/api/v1/config/payment-providers") { exchange ->
      hits.incrementAndGet()
      sendJson(
        exchange,
        200,
        """
        {"configVersion":"other","providers":[
          {"id":"extra","name":"Configured method","methods":["card"],"corridors":["UK"]}
        ]}
        """.trimIndent(),
      )
    }
    server.start()
    try {
      val health = ProviderConfigHealth()
      val client = MeridianClient(
        baseURL = "http://127.0.0.1:${server.address.port}/api/v1",
        sessionId = "rollback-room",
        providerConfigStore = ProviderConfigStore(),
        providerConfigHealth = health,
        pickerMode = ProviderPickerMode.MILESTONE_2_BASELINE,
      )
      val result = runBlocking { client.loadPaymentProviders("UK") }
      assertEquals(0, hits.get())
      assertEquals(ProviderConfigSource.MILESTONE_2_BASELINE, result.source)
      assertEquals(listOf("Debit card · Adyen", "Bank payment · Worldpay"), pickerOptions(result.providers).map { it.label })
      assertEquals(0, health.snapshot().fetchAttempts)
    } finally {
      server.stop(0)
    }
  }

  @Test
  fun testCachedConfigStaysOnTheSelectedSession() {
    val store = ProviderConfigStore()
    val server = httpServer()
    server.createContext("/api/v1/config/payment-providers") { exchange ->
      val session = exchange.requestHeaders.getFirst("X-Rehearsal-Session")
      if (session == "room-a") {
        sendJson(
          exchange,
          200,
          """
          {"configVersion":"a","providers":[
            {"id":"adyen","name":"Debit card","methods":["card"],"corridors":["UK"]}
          ]}
          """.trimIndent(),
        )
      } else {
        sendJson(exchange, 500, """{"error":"down"}""")
      }
    }
    server.start()
    try {
      val base = "http://127.0.0.1:${server.address.port}/api/v1"
      val roomA = MeridianClient(base, "room-a", store, ProviderConfigHealth())
      val roomB = MeridianClient(base, "room-b", store, ProviderConfigHealth())
      val cachedA = runBlocking { roomA.loadPaymentProviders("UK") }
      val fallbackB = runBlocking { roomB.loadPaymentProviders("UK") }
      assertEquals("a", cachedA.configVersion)
      assertEquals(listOf("adyen"), cachedA.providers.map { it.id.rawValue })
      assertEquals("milestone-2", fallbackB.configVersion)
      assertEquals(listOf("adyen", "worldpay"), fallbackB.providers.map { it.id.rawValue })
    } finally {
      server.stop(0)
    }
  }

  private fun httpServer(): HttpServer {
    return HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
  }

  private fun sendJson(exchange: HttpExchange, status: Int, body: String) {
    val bytes = body.toByteArray(StandardCharsets.UTF_8)
    exchange.responseHeaders.add("Content-Type", "application/json")
    exchange.sendResponseHeaders(status, bytes.size.toLong())
    exchange.responseBody.use { it.write(bytes) }
  }
}
