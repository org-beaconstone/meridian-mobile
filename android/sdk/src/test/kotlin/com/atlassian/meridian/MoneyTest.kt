package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonMappingException
import org.junit.Assert.*
import org.junit.Test
import java.util.Locale

class MoneyTest {
  private val mapper = newMeridianMapper()

  @Test
  fun legacyIntegerIsGbpPence() {
    val money = mapper.readValue("3500", Money::class.java)
    assertEquals(Money.gbpPence(3500), money)
    assertEquals("GBP", money.currencyCode)
    assertEquals(2, money.minorUnitExponent)
  }

  @Test
  fun legacyAmountFieldAndIsoObject() {
    val eur = mapper.readValue(
      """{"currencyCode":"EUR","minorUnits":1999,"minorUnitExponent":2}""",
      Money::class.java,
    )
    val fromAmount = mapper.readValue(
      """{"amount":1999,"currencyCode":"EUR"}""",
      Money::class.java,
    )
    val fromMinor = mapper.readValue(
      """{"amountMinor":1999,"currencyCode":"GBP","minorUnitExponent":2}""",
      Money::class.java,
    )
    assertEquals(eur, fromAmount)
    assertEquals(Money.gbpPence(1999), fromMinor)
    assertEquals(1999L, eur.minorUnits)

    val node = mapper.readTree(mapper.writeValueAsString(eur))
    assertEquals("EUR", node.get("currencyCode").asText())
    assertEquals(1999L, node.get("minorUnits").asLong())
    assertEquals(2, node.get("minorUnitExponent").asInt())
    assertFalse(node.get("minorUnits").isFloatingPointNumber)
    assertEquals(eur, mapper.readValue(mapper.writeValueAsString(eur), Money::class.java))
  }

  @Test
  fun transactionLegacyIntegerAndEuroObject() {
    val legacy = mapper.readValue(
      """
      {
        "id": "txn-001",
        "reference": "REF",
        "recipientId": "birch-bloom",
        "name": "Birch & Bloom",
        "category": "Food & drink",
        "amount": 3500,
        "date": "2026-09-05",
        "provider": "worldpay",
        "method": "bank",
        "status": "completed",
        "note": "Breakfast"
      }
      """.trimIndent(),
      Transaction::class.java,
    )
    assertEquals(Money.gbpPence(3500), legacy.amount)

    val euro = mapper.readValue(
      """
      {
        "id": "txn-eur",
        "reference": "REF",
        "recipientId": "birch-bloom",
        "name": "Birch & Bloom",
        "category": "Food & drink",
        "amount": {"currencyCode":"EUR","minorUnits":1999,"minorUnitExponent":2},
        "date": "2026-09-05",
        "provider": "adyen",
        "method": "card",
        "status": "completed",
        "note": "Coffee"
      }
      """.trimIndent(),
      Transaction::class.java,
    )
    assertEquals("EUR", euro.amount.currencyCode)
    assertEquals(1999L, euro.amount.minorUnits)
  }

  @Test
  fun conversionPrecision() {
    assertEquals(10L, Money.parseMajor("0.10", "GBP").minorUnits)
    assertEquals(29L, Money.parseMajor("0.29", "EUR").minorUnits)
    assertEquals(1999L, Money.parseMajor("19.99", "EUR").minorUnits)
    assertEquals("19.99", Money.parseMajor("19.99", "EUR").majorDecimal())
    assertEquals(1050L, Money.parseMajor("10.5", "GBP").minorUnits)
    assertEquals(420L, Money.parseMajor("0004.20", "GBP").minorUnits)

    val wide = Money.parseMajor("90071992547409.91", "GBP")
    assertEquals(9_007_199_254_740_991L, wide.minorUnits)
    assertEquals("90071992547409.91", wide.majorDecimal())
    assertEquals(wide, Money.parseMajor(wide.majorDecimal(), "GBP"))

    assertEquals(2000L, Money.parseMajor("19.99", "EUR").plus(Money.parseMajor("0.01", "EUR")).minorUnits)
  }

  @Test
  fun overflowProtection() {
    assertThrows(MoneyException.Overflow::class.java) {
      Money.parseMajor("92233720368547758.08", "GBP")
    }
    val atLimit = Money.parseMajor("92233720368547758.07", "GBP")
    assertEquals(Long.MAX_VALUE, atLimit.minorUnits)
    assertThrows(MoneyException.Overflow::class.java) {
      atLimit + Money.gbpPence(1)
    }
    assertThrows(MoneyException.Overflow::class.java) {
      Money.gbpPence(Long.MAX_VALUE) + Money.gbpPence(1)
    }
    assertThrows(MoneyException.CurrencyMismatch::class.java) {
      Money.gbpPence(1) + Money("EUR", 1, 2)
    }
    assertThrows(MoneyException.ExponentMismatch::class.java) {
      Money("EUR", 1, 0)
    }
    assertThrows(MoneyException.NotLegacyGbp::class.java) {
      Money("EUR", 100, 2).requireLegacyGbpPence()
    }
    assertThrows(MoneyException.Overflow::class.java) {
      Money.gbpPence(Int.MAX_VALUE.toLong() + 1).requireLegacyGbpPence()
    }
    assertEquals(1050, Money.parseMajor("10.50", "GBP").requireLegacyGbpPence())
  }

  @Test
  fun rejectsNonIntegralAndInvalidCurrency() {
    assertThrows(JsonMappingException::class.java) {
      mapper.readValue("10.5", Money::class.java)
    }
    assertThrows(JsonMappingException::class.java) {
      mapper.readValue("9223372036854775808", Money::class.java)
    }
    assertThrows(MoneyException.InvalidCurrency::class.java) {
      Money.parseMajor("1.00", "gbp")
    }
    assertThrows(MoneyException.InvalidMajor::class.java) {
      Money.parseMajor("10.501", "EUR")
    }
    assertThrows(MoneyException.InvalidMajor::class.java) {
      Money.parseMajor("1e2", "GBP")
    }
  }

  @Test
  fun formatsEurAndGbpForLocale() {
    val pounds = Money.gbpPence(1_248_050)
    val euros = Money("EUR", 1_248_050, 2)
    assertEquals("£12,480.50", pounds.formatted(Locale.UK))
    assertEquals("€12,480.50", euros.formatted(Locale.UK))
    assertEquals("12.480,50\u00A0€", euros.formatted(Locale.GERMANY))
    assertEquals("12.480,50\u00A0£", pounds.formatted(Locale.GERMANY))
    assertEquals("€12,480.50", euros.formatted(Locale("en", "IE")))
    assertEquals("£0.01", Money.gbpPence(1).formatted(Locale.UK))
    assertEquals("£10.50", Money.gbpPence(1050).formatted(Locale.UK))
  }

  @Test
  fun paymentRequestStaysIntegerPence() {
    val request = PaymentRequest(
      recipientId = "northline-studio",
      amountMinor = Money.parseMajor("10.50", "GBP").requireLegacyGbpPence(),
      method = "card",
      note = "",
      scenario = "success",
    )
    val json = mapper.writeValueAsString(request)
    assertTrue(json.contains("\"amountMinor\":1050"))
    assertFalse(json.contains("."))
  }
}
