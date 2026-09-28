package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentRailsTest {
  @Test
  fun testResolveBaselineRailsInCatalogOrder() {
    val rails = resolvePaymentRails(
      listOf(
        Provider("worldpay", "Worldpay", "Bank payment processor", listOf("bank")),
        Provider("adyen", "Adyen", "Card payment processor", listOf("card")),
      ),
    )

    assertEquals(2, rails.size)
    assertEquals(PaymentMethod.bank, rails[0].method)
    assertEquals(ProviderId.worldpay, rails[0].provider)
    assertEquals(worldpayBankTitle, rails[0].title)
    assertEquals(worldpayBankBadge, rails[0].badge)
    assertTrue(rails[0].selectable)
    assertNull(rails[0].warning)
    assertEquals("Select Bank payment, radio button, 1 of 2", rails[0].announcement)
    assertEquals(PaymentMethod.card, rails[1].method)
    assertEquals(adyenCardBadge, rails[1].badge)
    assertEquals("Select Debit card, radio button, 2 of 2", rails[1].announcement)
    assertEquals(paymentOptionAnnouncement(adyenCardTitle, 2, 2), rails[1].announcement)
  }

  @Test
  fun testUnavailableAndDegradedRailsAreDisabled() {
    val rails = resolvePaymentRails(
      listOf(
        Provider("adyen", "Adyen", "Card", listOf("card"), "degraded"),
        Provider("worldpay", "Worldpay", "Bank", listOf("bank"), "OFFLINE"),
      ),
    )

    assertEquals(RailAvailability.degraded, rails[0].availability)
    assertFalse(rails[0].selectable)
    assertEquals(regionalUnavailabilityWarning, rails[0].warning)
    assertEquals(RailAvailability.unavailable, rails[1].availability)
    assertFalse(rails[1].selectable)
    assertEquals(regionalUnavailabilityWarning, rails[1].warning)
    assertEquals("Select Debit card, radio button, 1 of 2", rails[0].announcement)
  }

  @Test
  fun testUnknownProvidersAndWrongPairingsAreIgnored() {
    val rails = resolvePaymentRails(
      listOf(
        Provider("adyen", "Adyen", "Card", listOf("bank", "card")),
        Provider("adyen", "Adyen duplicate", "Card", listOf("card")),
        Provider("not-baseline", "Not Shown", "Skip", listOf("card"), "available"),
        Provider("worldpay", "Worldpay", "Bank", listOf("card")),
      ),
    )
    val rendered = rails.joinToString(" ") { "${it.title} ${it.badge} ${it.announcement}" }

    assertEquals(1, rails.size)
    assertEquals(PaymentMethod.card, rails[0].method)
    assertEquals(ProviderId.adyen, rails[0].provider)
    assertEquals("Select Debit card, radio button, 1 of 1", rails[0].announcement)
    assertFalse(rendered.contains("Not Shown"))
    assertEquals(emptyList<PaymentRail>(), resolvePaymentRails(emptyList()))
  }

  @Test
  fun testCatalogStatusDecodesAndMissingStatusStaysAvailable() {
    val mapper = ObjectMapper().registerKotlinModule()
    val json = """
      {
        "demoDate": "2026-09-18",
        "recipients": [],
        "providers": [
          {"id": "adyen", "name": "Adyen", "description": "Card processor", "methods": ["card"], "status": "available"},
          {"id": "worldpay", "name": "Worldpay", "description": "Bank", "methods": ["bank"]},
          {"id": "other", "name": "Other", "description": "Skip", "methods": ["card"], "status": "unavailable"}
        ]
      }
    """.trimIndent()

    val response = mapper.readValue(json, CatalogResponse::class.java)
    val rails = resolvePaymentRails(response.providers)

    assertNull(response.providers[1].status)
    assertEquals(2, rails.size)
    assertTrue(rails.all { it.selectable })
    assertEquals(listOf(PaymentMethod.card, PaymentMethod.bank), rails.map { it.method })
  }
}
