package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class MoneyTest {
  private val mapper = ObjectMapper().registerKotlinModule()

  @Test
  fun testLegacyGbpAdapterRoundTrip() {
    val money = Money.fromLegacyGbpPence(1050)
    assertEquals("GBP", money.currencyCode)
    assertEquals(1050L, money.minorUnits)
    assertEquals(2, money.minorUnitExponent)
    assertEquals(1050, money.legacyGbpPence())
    assertEquals(Money.fromLegacyGbpPence(1_248_050), moneyFromBalance())
  }

  @Test
  fun testLegacyAdapterRejectsOtherCurrenciesAndOverflow() {
    assertThrows(MoneyException::class.java) {
      Money.of("EUR", 100, 2).legacyGbpPence()
    }
    val wide = Money.fromLegacyGbpPence(Int.MAX_VALUE.toLong() + 1)
    assertThrows(MoneyException::class.java) { wide.legacyGbpPence() }
  }

  @Test
  fun testEurExponentIsFixed() {
    assertThrows(MoneyException::class.java) { Money.of("EUR", 100, 0) }
    assertThrows(MoneyException::class.java) { Money.of("gbp", 100, 2) }
    assertThrows(MoneyException::class.java) { Money.of("GBP", 100, 3) }
  }

  @Test
  fun testDecimalConversionPrecision() {
    assertEquals(1050L, Money.parse("10.50", "EUR", 2).minorUnits)
    assertEquals(1050L, Money.parse("10.5", "EUR", 2).minorUnits)
    assertEquals(1L, Money.parse("0.01", "GBP", 2).minorUnits)
    assertEquals("10.50", Money.parse("10.5", "EUR", 2).plainDecimal())

    val exact = Money.parse("90071992547409.93", "EUR", 2)
    assertEquals(9007199254740993L, exact.minorUnits)
    assertEquals("90071992547409.93", exact.plainDecimal())
    val viaFloat = ("90071992547409.93".toDouble() * 100.0).toLong()
    assertNotEquals(exact.minorUnits, viaFloat)

    val sum = Money.parse("0.10", "EUR", 2).adding(Money.parse("0.20", "EUR", 2))
    assertEquals(30L, sum.minorUnits)
    assertEquals("0.30", sum.plainDecimal())
  }

  @Test
  fun testOverflowProtection() {
    assertThrows(MoneyException::class.java) {
      Money.parse("92233720368547759.00", "GBP", 2)
    }
    assertThrows(MoneyException::class.java) {
      Money.of("GBP", Long.MAX_VALUE, 2).adding(Money.of("GBP", 1, 2))
    }
    assertThrows(MoneyException::class.java) {
      Money.fromLegacyGbpPence(1).adding(Money.of("EUR", 1, 2))
    }
    val edge = Money.fromLegacyGbpPence(Long.MIN_VALUE)
    assertEquals("-92233720368547758.08", edge.plainDecimal())
  }

  @Test
  fun testLocaleFormatting() {
    assertEquals("£10.50", Money.fromLegacyGbpPence(1050).format(Locale.UK))
    assertEquals("£0.01", Money.fromLegacyGbpPence(1).format(Locale.UK))
    assertEquals("£10,000.00", Money.fromLegacyGbpPence(1_000_000).format(Locale.UK))
    assertEquals("£12,480.50", Money.fromLegacyGbpPence(1_248_050).format(Locale.UK))
    assertEquals("-£10.50", Money.fromLegacyGbpPence(-1050).format(Locale.UK))
    assertEquals("€10.50", Money.of("EUR", 1050, 2).format(Locale.UK))
    assertEquals("10,50 €", Money.of("EUR", 1050, 2).format(Locale.GERMANY))
    assertEquals("-10,50 €", Money.of("EUR", -1050, 2).format(Locale.GERMANY))
    assertEquals("10,50\u00A0€", Money.of("EUR", 1050, 2).format(Locale.FRANCE))
    assertEquals("1\u00A0234,56\u00A0€", Money.of("EUR", 123456, 2).format(Locale.FRANCE))
    assertEquals("XXX 1.234", Money.of("XXX", 1234, 3).format(Locale.UK))
  }

  @Test
  fun testJsonMigrationAndSerialization() {
    val legacy = MoneyMigration.decodeAmount("3500")
    assertEquals(Money.fromLegacyGbpPence(3500), legacy)

    val legacyField = """{"id":"txn-001","amount":3500,"note":"Breakfast"}"""
    assertEquals(3500, MoneyMigration.decodeAmountField(legacyField, "amount").legacyGbpPence())

    val eur = Money.of("EUR", 199, 2)
    val eurJson = """{"id":"txn-eu","amount":{"currencyCode":"EUR","minorUnits":199,"minorUnitExponent":2}}"""
    assertEquals(eur, MoneyMigration.decodeAmountField(eurJson, "amount"))

    val wideLiteral = "9007199254740993"
    val wide = MoneyMigration.decodeAmountField("""{"amount":$wideLiteral}""", "amount")
    assertEquals(9007199254740993L, wide.minorUnits)
    assertEquals("GBP", wide.currencyCode)
    assertEquals(2, wide.minorUnitExponent)
    assertEquals("90071992547409.93", wide.plainDecimal())

    val reordered = """{"minorUnitExponent":2,"minorUnits":1050,"currencyCode":"EUR"}"""
    val decoded = MoneyMigration.decodeAmount(reordered)
    assertEquals(Money.of("EUR", 1050, 2), decoded)
    assertEquals(decoded.toJSON(), mapper.writeValueAsString(decoded))
    assertEquals(decoded, mapper.readValue(decoded.toJSON(), Money::class.java))

    val precise = Money.of("EUR", 9007199254740993L, 2)
    assertEquals(
      """{"currencyCode":"EUR","minorUnits":9007199254740993,"minorUnitExponent":2}""",
      precise.toJSON(),
    )
    assertEquals(precise, mapper.readValue(precise.toJSON(), Money::class.java))
  }

  @Test
  fun testJsonRejectsFloatsAndMissingFields() {
    assertThrows(Exception::class.java) { MoneyMigration.decodeAmount("10.5") }
    assertThrows(Exception::class.java) { MoneyMigration.decodeAmount("1e3") }
    assertThrows(Exception::class.java) { MoneyMigration.decodeAmount("9223372036854775808") }
    assertThrows(Exception::class.java) {
      MoneyMigration.decodeAmount("""{"currencyCode":"EUR","minorUnits":10.5,"minorUnitExponent":2}""")
    }
    assertThrows(Exception::class.java) {
      MoneyMigration.decodeAmount("""{"currencyCode":"EUR","minorUnits":10,"minorUnitExponent":0}""")
    }
  }

  private fun moneyFromBalance(): Money = BankState(
    version = 1,
    balance = 1_248_050,
    transactions = emptyList(),
    budgets = emptyList(),
  ).balanceMoney
}
