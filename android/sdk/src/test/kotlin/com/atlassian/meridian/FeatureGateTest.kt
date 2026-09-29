package com.atlassian.meridian

import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.net.InetSocketAddress

class FeatureGateTest {
  private fun provider(
    id: String,
    name: String,
    methods: List<String>,
    currencies: List<String>? = null,
    regions: List<String>? = null,
  ) = Provider(id, name, "$name processor", methods, currencies, regions)

  @Test
  fun flagOffUsesCachedGbpAndHidesEur() {
    val cached = listOf(
      PaymentRail("adyen-card-gbp", ProviderId.adyen, PaymentMethod.card, CurrencyCode.GBP, "Debit card · Adyen Cards"),
      PaymentRail("worldpay-bank-gbp", ProviderId.worldpay, PaymentMethod.bank, CurrencyCode.GBP, "Bank payment · Worldpay"),
    )
    val resolved = resolvePaymentSurface(
      false,
      listOf(provider("adyen", "Adyen EU", listOf("card"), listOf("GBP", "EUR"))),
      cached,
    )
    assertFalse(resolved.surface.flagEnabled)
    assertFalse(resolved.surface.dynamicCatalogActive)
    assertTrue(resolved.surface.usingCachedGbp)
    assertEquals(listOf(CurrencyCode.GBP), resolved.surface.currencies)
    assertEquals(2, resolved.surface.rails.size)
    assertTrue(resolved.surface.rails.all { it.currency == CurrencyCode.GBP })
    assertEquals("Debit card · Adyen Cards", resolved.surface.rails[0].label)
    assertEquals(ProviderId.adyen, resolved.surface.rails[0].provider)
    assertEquals(PaymentMethod.card, resolved.surface.rails[0].method)
    assertEquals(ProviderId.worldpay, resolved.surface.rails[1].provider)
    assertEquals(PaymentMethod.bank, resolved.surface.rails[1].method)
    assertEquals(cached, resolved.cachedGbp)
  }

  @Test
  fun flagOnParsesCatalogAndUnlocksEur() {
    val resolved = resolvePaymentSurface(
      true,
      listOf(
        provider("adyen", "Adyen", listOf("card"), listOf("GBP", "EUR")),
        provider("worldpay", "Worldpay", listOf("bank"), listOf("GBP", "EUR"), listOf("EU")),
      ),
      gbpBaseline,
    )
    assertTrue(resolved.surface.dynamicCatalogActive)
    assertFalse(resolved.surface.usingCachedGbp)
    assertEquals(listOf(CurrencyCode.GBP, CurrencyCode.EUR), resolved.surface.currencies)
    assertEquals(4, resolved.surface.rails.size)
    assertEquals("adyen-card-eur", resolved.surface.rails[2].id)
    assertEquals("worldpay-bank-eur", resolved.surface.rails[3].id)
    assertTrue(resolved.surface.rails.all { it.provider == ProviderId.adyen || it.provider == ProviderId.worldpay })
  }

  @Test
  fun explicitGbpCatalogKeepsEurHiddenWhileFlagIsOn() {
    val resolved = resolvePaymentSurface(
      true,
      listOf(
        provider("adyen", "Adyen", listOf("card"), listOf("GBP")),
        provider("worldpay", "Worldpay", listOf("bank"), listOf("GBP")),
      ),
      gbpBaseline,
    )
    assertTrue(resolved.surface.dynamicCatalogActive)
    assertEquals(listOf(CurrencyCode.GBP), resolved.surface.currencies)
    assertEquals(2, resolved.surface.rails.size)
    assertTrue(resolved.surface.rails.none { it.currency == CurrencyCode.EUR })
  }

  @Test
  fun unknownProviderIsDroppedAndDoesNotEmptyTheList() {
    val resolved = resolvePaymentSurface(
      true,
      listOf(
        provider("pilot-rail", "Pilot Rail", listOf("card"), listOf("EUR")),
        provider("adyen", "Adyen", listOf("bank")),
        provider("worldpay", "Worldpay", listOf("bank"), regions = listOf("EU")),
      ),
      gbpBaseline,
    )
    val labels = resolved.surface.rails.joinToString(" ") { it.label }
    assertFalse(labels.contains("Pilot"))
    assertFalse(labels.contains("pilot-rail"))
    assertEquals(ProviderId.adyen, resolved.surface.rails[0].provider)
    assertEquals(PaymentMethod.card, resolved.surface.rails[0].method)
    assertTrue(resolved.surface.rails.any { it.id == "worldpay-bank-eur" })
    assertTrue(resolved.surface.rails.isNotEmpty())
  }

  @Test
  fun missingCatalogStillUnlocksEurFromCache() {
    val resolved = resolvePaymentSurface(true, null, emptyList())
    assertFalse(resolved.surface.dynamicCatalogActive)
    assertTrue(resolved.surface.usingCachedGbp)
    assertEquals(4, resolved.surface.rails.size)
    assertEquals(gbpBaseline, resolved.cachedGbp)
    assertTrue(resolved.surface.rails.any { it.currency == CurrencyCode.EUR })
  }

  @Test
  fun killSwitchRestoresCachedGbpWithoutEmptyRails() {
    val enabled = resolvePaymentSurface(
      true,
      listOf(
        provider("adyen", "Adyen", listOf("card")),
        provider("worldpay", "Worldpay", listOf("bank")),
      ),
      gbpBaseline,
    )
    val reviewing = reconcileSelection(enabled.surface, CurrencyCode.EUR, "adyen-card-eur", true)
    assertEquals(CurrencyCode.EUR, reviewing.currency)
    assertTrue(reviewing.reviewing)

    val disabled = resolvePaymentSurface(false, null, enabled.cachedGbp)
    val settled = reconcileSelection(disabled.surface, reviewing.currency, reviewing.railId, reviewing.reviewing)
    assertFalse(disabled.surface.flagEnabled)
    assertTrue(disabled.surface.usingCachedGbp)
    assertEquals(2, disabled.surface.rails.size)
    assertTrue(disabled.surface.rails.none { it.currency == CurrencyCode.EUR })
    assertEquals(CurrencyCode.GBP, settled.currency)
    assertEquals("adyen-card-gbp", settled.railId)
    assertFalse(settled.reviewing)
  }

  @Test
  fun gbpReviewSurvivesARefreshThatKeepsTheSameRail() {
    val surface = resolvePaymentSurface(false, null, gbpBaseline).surface
    val selection = reconcileSelection(surface, CurrencyCode.GBP, "worldpay-bank-gbp", true)
    assertTrue(selection.reviewing)
    assertEquals("worldpay-bank-gbp", selection.railId)
    assertEquals(PaymentMethod.bank, surface.rails.first { it.id == selection.railId }.method)
  }

  @Test
  fun flagPayloads() {
    assertTrue(evaluateMobileEuPaymentsFlag("""{"enable_mobile_eu_payments":true}"""))
    assertFalse(evaluateMobileEuPaymentsFlag("""{"enable_mobile_eu_payments":false}"""))
    assertTrue(evaluateMobileEuPaymentsFlag("""{"flags":{"enable_mobile_eu_payments":true}}"""))
    assertFalse(evaluateMobileEuPaymentsFlag("""{"enable_mobile_eu_payments":"false"}"""))
    assertTrue(evaluateMobileEuPaymentsFlag("""{"enable_mobile_eu_payments":"true"}"""))
    assertFalse(evaluateMobileEuPaymentsFlag("""{"enable_mobile_eu_payments":1}"""))
    assertFalse(evaluateMobileEuPaymentsFlag("not-json"))
    assertFalse(evaluateMobileEuPaymentsFlag("{}"))
  }

  @Test
  fun eurAmountLimitUsesEuroSymbol() {
    val (pence, error) = parseAmount("10001", CurrencyCode.EUR)
    assertNull(pence)
    assertEquals("Amount cannot exceed €10,000", error)
    assertEquals("€10.50", money(1050, CurrencyCode.EUR))
    assertEquals("£10.50", money(1050))
  }

  @Test
  fun remoteFlagHonoursSessionAndFailsClosed() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    var body = """{"enable_mobile_eu_payments":true}"""
    var status = 200
    server.createContext("/api/v1/config") { exchange ->
      assertEquals("GET", exchange.requestMethod)
      assertEquals("room-eu", exchange.requestHeaders.getFirst("X-Rehearsal-Session"))
      val bytes = body.toByteArray()
      exchange.sendResponseHeaders(status, bytes.size.toLong())
      exchange.responseBody.write(bytes)
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:$port/api/v1", "room-eu")
      assertTrue(runBlocking { client.mobileEuPaymentsEnabled() })
      body = """{"flags":{"enable_mobile_eu_payments":false}}"""
      assertFalse(runBlocking { client.mobileEuPaymentsEnabled() })
      status = 500
      body = """{"enable_mobile_eu_payments":true}"""
      assertFalse(runBlocking { client.mobileEuPaymentsEnabled() })
      status = 200
      body = "<html>nope</html>"
      assertFalse(runBlocking { client.mobileEuPaymentsEnabled() })
    } finally {
      server.stop(0)
    }
  }
}
