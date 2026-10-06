package com.atlassian.meridian

import com.fasterxml.jackson.core.JsonParser
import com.fasterxml.jackson.databind.DeserializationContext
import com.fasterxml.jackson.databind.JsonDeserializer
import com.fasterxml.jackson.databind.JsonMappingException
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.annotation.JsonDeserialize
import com.fasterxml.jackson.databind.module.SimpleModule
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.io.Serializable
import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import java.text.DecimalFormat
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

/**
 * ISO-4217 amount stored as integer minor units.
 *
 * A legacy JSON number is a British pound amount in pence (exponent 2).
 * Object payloads carry currencyCode, minorUnits, and minorUnitExponent.
 * Parsing, scaling, and overflow checks use integer arithmetic only.
 */
@JsonDeserialize(using = MoneyDeserializer::class)
data class Money(
  val currencyCode: String,
  val minorUnits: Long,
  val minorUnitExponent: Int,
) : Serializable {
  init {
    val expected = isoExponent(currencyCode)
    if (minorUnitExponent != expected) {
      throw MoneyException.ExponentMismatch(currencyCode, minorUnitExponent, expected)
    }
  }

  /** Integer pence for the current payment request. Refuses other currencies. */
  fun requireLegacyGbpPence(): Int {
    if (currencyCode != "GBP" || minorUnitExponent != 2) {
      throw MoneyException.NotLegacyGbp()
    }
    if (minorUnits > Int.MAX_VALUE || minorUnits < Int.MIN_VALUE) {
      throw MoneyException.Overflow()
    }
    return minorUnits.toInt()
  }

  operator fun plus(other: Money): Money {
    if (currencyCode != other.currencyCode || minorUnitExponent != other.minorUnitExponent) {
      throw MoneyException.CurrencyMismatch()
    }
    val sum = try {
      Math.addExact(minorUnits, other.minorUnits)
    } catch (_: ArithmeticException) {
      throw MoneyException.Overflow()
    }
    return Money(currencyCode, sum, minorUnitExponent)
  }

  /** Decimal major units with a dot separator and no currency symbol. */
  fun majorDecimal(): String = BigDecimal.valueOf(minorUnits, minorUnitExponent).toPlainString()

  /** Locale currency format. The amount is a base-10 decimal, not a binary float. */
  fun formatted(locale: Locale = Locale.getDefault()): String {
    val format = NumberFormat.getCurrencyInstance(locale) as DecimalFormat
    format.currency = Currency.getInstance(currencyCode)
    format.minimumFractionDigits = minorUnitExponent
    format.maximumFractionDigits = minorUnitExponent
    format.roundingMode = RoundingMode.UNNECESSARY
    return format.format(BigDecimal.valueOf(minorUnits, minorUnitExponent))
  }

  companion object {
    fun gbpPence(pence: Long): Money = Money("GBP", pence, 2)

    fun gbpPence(pence: Int): Money = gbpPence(pence.toLong())

    fun isoExponent(currencyCode: String): Int {
      if (!currencyCode.matches(Regex("^[A-Z]{3}$"))) {
        throw MoneyException.InvalidCurrency(currencyCode)
      }
      val currency = try {
        Currency.getInstance(currencyCode)
      } catch (_: IllegalArgumentException) {
        throw MoneyException.InvalidCurrency(currencyCode)
      }
      val exponent = currency.defaultFractionDigits
      if (exponent < 0) throw MoneyException.InvalidCurrency(currencyCode)
      return exponent
    }

    /** Parse a major-unit decimal string such as "10.50" into minor units. */
    fun parseMajor(input: String, currencyCode: String): Money {
      val exponent = isoExponent(currencyCode)
      val trimmed = input.trim()
      if (trimmed.isEmpty()) throw MoneyException.InvalidMajor("Amount is required")
      if (trimmed.contains('-') || trimmed.contains('+') || trimmed.lowercase().contains('e')) {
        throw MoneyException.InvalidMajor("Amount cannot contain sign or exponent notation")
      }
      if (!Regex("^\\d+(\\.\\d+)?$").matches(trimmed)) {
        throw MoneyException.InvalidMajor("Amount must be a valid number")
      }
      val parts = trimmed.split('.', limit = 2)
      val fraction = if (parts.size == 2) parts[1] else ""
      if (fraction.length > exponent) {
        throw MoneyException.InvalidMajor("Amount must have at most $exponent decimal places")
      }
      val padded = fraction.padEnd(exponent, '0')
      val total = BigInteger(parts[0])
        .multiply(BigInteger.TEN.pow(exponent))
        .add(if (padded.isEmpty()) BigInteger.ZERO else BigInteger(padded))
      if (total > BigInteger.valueOf(Long.MAX_VALUE)) throw MoneyException.Overflow()
      return Money(currencyCode, total.longValueExact(), exponent)
    }

    fun fromJson(node: JsonNode): Money {
      if (node.isNumber) {
        return gbpPence(longExact(node))
      }
      if (!node.isObject) throw MoneyException.MissingAmount()

      val codeNode = node.get("currencyCode")
      val currency = when {
        codeNode == null || codeNode.isNull -> "GBP"
        codeNode.isTextual -> codeNode.textValue()
        else -> throw MoneyException.InvalidCurrency(codeNode.toString())
      }

      val minorNode = node.get("minorUnits")
      val amountNode = node.get("amount") ?: node.get("amountMinor")
      val minor = if (minorNode != null && !minorNode.isNull) longExact(minorNode) else null
      val legacy = if (amountNode != null && !amountNode.isNull) longExact(amountNode) else null
      if (minor != null && legacy != null && minor != legacy) {
        throw MoneyException.ConflictingAmount()
      }
      val units = minor ?: legacy ?: throw MoneyException.MissingAmount()

      val exponentNode = node.get("minorUnitExponent")
      val exponent = if (exponentNode == null || exponentNode.isNull) {
        isoExponent(currency)
      } else {
        if (!exponentNode.isIntegralNumber || !exponentNode.canConvertToInt()) {
          throw MoneyException.NonIntegral()
        }
        exponentNode.intValue()
      }
      return Money(currency, units, exponent)
    }

    private fun longExact(node: JsonNode): Long {
      if (!node.isIntegralNumber) throw MoneyException.NonIntegral()
      val big = node.bigIntegerValue()
      if (big < BigInteger.valueOf(Long.MIN_VALUE) || big > BigInteger.valueOf(Long.MAX_VALUE)) {
        throw MoneyException.Overflow()
      }
      return big.longValueExact()
    }
  }
}

class MoneyDeserializer : JsonDeserializer<Money>() {
  override fun deserialize(parser: JsonParser, ctxt: DeserializationContext): Money {
    val node = parser.codec.readTree(parser) as JsonNode
    try {
      return Money.fromJson(node)
    } catch (ex: MoneyException) {
      throw JsonMappingException.from(parser, ex.message, ex)
    }
  }
}

fun newMeridianMapper(): ObjectMapper =
  ObjectMapper().apply {
    registerKotlinModule()
    registerModule(SimpleModule().addDeserializer(Money::class.java, MoneyDeserializer()))
  }

sealed class MoneyException(message: String) : IllegalArgumentException(message) {
  class InvalidCurrency(code: String) : MoneyException("Invalid ISO-4217 currency code: $code")
  class ExponentMismatch(code: String, exponent: Int, expected: Int) :
    MoneyException("Exponent $exponent does not match $code ($expected)")
  class NonIntegral : MoneyException("Amount must be an integer number of minor units")
  class Overflow : MoneyException("Amount overflows the integer minor-unit range")
  class MissingAmount : MoneyException("Amount is missing")
  class ConflictingAmount : MoneyException("minorUnits and amount disagree")
  class InvalidMajor(detail: String) : MoneyException(detail)
  class NotLegacyGbp : MoneyException("Only GBP amounts with a minor-unit exponent of 2 convert to legacy pence")
  class CurrencyMismatch : MoneyException("Currency and exponent must match")
}
