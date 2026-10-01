package com.atlassian.meridian

import com.fasterxml.jackson.core.JsonGenerator
import com.fasterxml.jackson.core.JsonParser
import com.fasterxml.jackson.databind.DeserializationContext
import com.fasterxml.jackson.databind.JsonDeserializer
import com.fasterxml.jackson.databind.JsonMappingException
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.JsonSerializer
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.SerializerProvider
import com.fasterxml.jackson.databind.annotation.JsonDeserialize
import com.fasterxml.jackson.databind.annotation.JsonSerialize
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.io.Serializable
import java.math.BigInteger
import java.util.Locale

/**
 * ISO-4217 monetary amount stored as integer minor units.
 *
 * [minorUnitExponent] is the number of digits after the decimal separator
 * (2 for GBP and EUR). Arithmetic and JSON conversion never use binary
 * floating point. A bare JSON integer is the legacy GBP pence amount.
 */
@JsonSerialize(using = MoneySerializer::class)
@JsonDeserialize(using = MoneyDeserializer::class)
data class Money private constructor(
  val currencyCode: String,
  val minorUnits: Long,
  val minorUnitExponent: Int,
) : Serializable {
  fun legacyGbpPence(): Int {
    if (currencyCode != "GBP" || minorUnitExponent != 2) {
      throw MoneyException.notLegacyGbp()
    }
    if (minorUnits < Int.MIN_VALUE || minorUnits > Int.MAX_VALUE) {
      throw MoneyException.overflow()
    }
    return minorUnits.toInt()
  }

  fun adding(other: Money): Money {
    if (currencyCode != other.currencyCode || minorUnitExponent != other.minorUnitExponent) {
      throw MoneyException.currencyMismatch()
    }
    return of(currencyCode, addExact(minorUnits, other.minorUnits), minorUnitExponent)
  }

  /** Exact decimal spelling of the minor units. No grouping and no currency symbol. */
  fun plainDecimal(): String {
    val parts = splitMinorUnits()
    val body = if (minorUnitExponent == 0) parts.major else parts.major + "." + parts.fraction
    return if (parts.negative) "-$body" else body
  }

  /**
   * Format EUR or GBP (and any other stored code) for a user locale.
   * Grouping and separators follow the locale; the exponent comes from this value.
   */
  fun format(locale: Locale = Locale.UK): String {
    val style = localeStyle(locale.language.lowercase(Locale.ROOT))
    val symbol = symbol(currencyCode)
    val parts = splitMinorUnits()
    val grouped = groupDigits(parts.major, style.grouping)
    val number = if (minorUnitExponent == 0) {
      grouped
    } else {
      grouped + style.decimal + parts.fraction
    }
    val gap = if (symbol.length == 3 && style.gap.isEmpty()) " " else style.gap
    val body = if (style.symbolBefore) symbol + gap + number else number + gap + symbol
    return if (parts.negative) "-$body" else body
  }

  /** Canonical ISO-4217 JSON object. Digits are written from the integer, not a binary float. */
  fun toJSON(): String =
    "{\"currencyCode\":\"$currencyCode\",\"minorUnits\":$minorUnits,\"minorUnitExponent\":$minorUnitExponent}"

  private fun splitMinorUnits(): Split {
    var text = minorUnits.toString()
    val negative = text.startsWith("-")
    if (negative) text = text.substring(1)
    if (minorUnitExponent == 0) return Split(negative, text, "")
    if (text.length <= minorUnitExponent) {
      return Split(negative, "0", "0".repeat(minorUnitExponent - text.length) + text)
    }
    val split = text.length - minorUnitExponent
    return Split(negative, text.substring(0, split), text.substring(split))
  }

  private data class Split(val negative: Boolean, val major: String, val fraction: String)

  companion object {
    /** Exponents required by the currencies this client formats. */
    val isoExponents: Map<String, Int> = mapOf("GBP" to 2, "EUR" to 2)

    private val CURRENCY_CODE = Regex("^[A-Z]{3}$")
    private val INTEGER = Regex("-?\\d+")
    private val UNSIGNED = Regex("\\d+")
    private val LONG_MIN = BigInteger.valueOf(Long.MIN_VALUE)
    private val LONG_MAX = BigInteger.valueOf(Long.MAX_VALUE)

    fun of(currencyCode: String, minorUnits: Long, minorUnitExponent: Int): Money {
      if (!CURRENCY_CODE.matches(currencyCode)) {
        throw MoneyException.invalidCurrency(currencyCode)
      }
      if (minorUnitExponent !in 0..18) {
        throw MoneyException.invalidExponent(minorUnitExponent)
      }
      val expected = isoExponents[currencyCode]
      if (expected != null && expected != minorUnitExponent) {
        throw MoneyException.exponentMismatch(currencyCode, expected, minorUnitExponent)
      }
      return Money(currencyCode, minorUnits, minorUnitExponent)
    }

    /** Adapter from the existing British pound integer-pence fields. */
    fun fromLegacyGbpPence(pence: Int): Money = fromLegacyGbpPence(pence.toLong())

    fun fromLegacyGbpPence(pence: Long): Money = Money("GBP", pence, 2)

    /**
     * Parse a decimal amount into minor units without floating-point arithmetic.
     */
    fun parse(amount: String, currencyCode: String, minorUnitExponent: Int): Money {
      val trimmed = amount.trim()
      if (trimmed.isEmpty()) throw MoneyException.invalidAmount("Amount is required")
      if (trimmed.contains("+") || trimmed.lowercase().contains("e")) {
        throw MoneyException.invalidAmount("Amount cannot contain sign or exponent notation")
      }

      var sign = 1L
      var digits = trimmed
      if (digits.startsWith("-")) {
        sign = -1L
        digits = digits.substring(1)
        if (digits.isEmpty()) throw MoneyException.invalidAmount("Amount must be a valid number")
      }
      if (!Regex("^\\d+(\\.\\d*)?$").matches(digits)) {
        throw MoneyException.invalidAmount("Amount must be a valid number")
      }

      val parts = digits.split(".", limit = 2)
      val whole = parts[0]
      val fractionDigits = if (parts.size == 2) parts[1] else ""
      if (fractionDigits.length > minorUnitExponent) {
        throw MoneyException.invalidAmount(
          "Amount must have at most $minorUnitExponent decimal places",
        )
      }

      val major = exactLong(whole)
      val padded = fractionDigits.padEnd(minorUnitExponent, '0')
      val fraction = if (minorUnitExponent == 0) 0L else exactLong(padded)
      val scaled = multiplyExact(major, pow10(minorUnitExponent))
      val combined = addExact(scaled, fraction)
      val signed = multiplyExact(combined, sign)
      return of(currencyCode, signed, minorUnitExponent)
    }

    internal fun read(node: JsonNode): Money {
      if (node.isNumber) {
        val raw = node.asTokenText()
        if (!INTEGER.matches(raw)) {
          throw MoneyException.invalidAmount("Legacy amount must be an integer number of GBP pence")
        }
        return fromLegacyGbpPence(exactLong(node.bigIntegerValue()))
      }
      if (!node.isObject) {
        throw MoneyException.invalidAmount("Money JSON must be an integer or an ISO-4217 object")
      }
      val codeNode = node.get("currencyCode")
        ?: throw MoneyException.invalidAmount("currencyCode must be a string")
      val unitsNode = node.get("minorUnits")
        ?: throw MoneyException.invalidAmount("minorUnits must be an integer")
      val exponentNode = node.get("minorUnitExponent")
        ?: throw MoneyException.invalidAmount("minorUnitExponent must be an integer")
      if (!codeNode.isTextual) {
        throw MoneyException.invalidAmount("currencyCode must be a string")
      }
      if (!unitsNode.isNumber || !INTEGER.matches(unitsNode.asTokenText())) {
        throw MoneyException.invalidAmount("minorUnits must be an integer")
      }
      if (!exponentNode.isNumber || !UNSIGNED.matches(exponentNode.asTokenText())) {
        throw MoneyException.invalidAmount("minorUnitExponent must be an integer")
      }
      val exponentBig = exponentNode.bigIntegerValue()
      if (exponentBig < BigInteger.ZERO || exponentBig > BigInteger.valueOf(18)) {
        throw MoneyException.invalidExponent(-1)
      }
      return of(codeNode.asText(), exactLong(unitsNode.bigIntegerValue()), exponentBig.toInt())
    }

    private fun JsonNode.asTokenText(): String = toString()

    private fun exactLong(literal: String): Long {
      try {
        return literal.toLong()
      } catch (_: NumberFormatException) {
        throw MoneyException.overflow()
      }
    }

    private fun exactLong(value: BigInteger): Long {
      if (value < LONG_MIN || value > LONG_MAX) throw MoneyException.overflow()
      return value.toLong()
    }
  }
}

class MoneyException(message: String) : IllegalArgumentException(message) {
  companion object {
    fun invalidCurrency(code: String) = MoneyException("Invalid ISO-4217 currency code: $code")
    fun invalidExponent(exponent: Int) = MoneyException("Minor unit exponent out of range: $exponent")
    fun exponentMismatch(currency: String, expected: Int, actual: Int) =
      MoneyException("$currency requires minor unit exponent $expected, got $actual")
    fun overflow() = MoneyException("Money amount overflow")
    fun invalidAmount(message: String) = MoneyException(message)
    fun notLegacyGbp() = MoneyException("Amount is not a legacy GBP pence value")
    fun currencyMismatch() = MoneyException("Currency and exponent must match")
  }
}

object MoneyMigration {
  private val mapper = ObjectMapper().registerKotlinModule()

  /** Decode a JSON amount that is either a legacy integer or an ISO-4217 money object. */
  fun decodeAmount(json: String): Money = mapper.readValue(json, Money::class.java)

  /** Read one amount field from a JSON object, leaving sibling fields untouched. */
  fun decodeAmountField(json: String, field: String): Money {
    val amount = mapper.readTree(json).get(field)
      ?: throw MoneyException.invalidAmount("Missing $field")
    return mapper.treeToValue(amount, Money::class.java)
  }
}

class MoneySerializer : JsonSerializer<Money>() {
  override fun serialize(value: Money, gen: JsonGenerator, serializers: SerializerProvider) {
    gen.writeStartObject()
    gen.writeStringField("currencyCode", value.currencyCode)
    gen.writeNumberField("minorUnits", value.minorUnits)
    gen.writeNumberField("minorUnitExponent", value.minorUnitExponent)
    gen.writeEndObject()
  }
}

class MoneyDeserializer : JsonDeserializer<Money>() {
  override fun deserialize(parser: JsonParser, ctxt: DeserializationContext): Money {
    val node = parser.codec.readTree<JsonNode>(parser)
    try {
      return Money.read(node)
    } catch (error: MoneyException) {
      throw JsonMappingException(parser, error.message, error)
    }
  }
}

val Transaction.amountMoney: Money
  get() = Money.fromLegacyGbpPence(amount)

val Budget.limitMoney: Money
  get() = Money.fromLegacyGbpPence(limit)

val BankState.balanceMoney: Money
  get() = Money.fromLegacyGbpPence(balance)

private data class LocaleMoneyStyle(
  val decimal: Char,
  val grouping: Char,
  val symbolBefore: Boolean,
  val gap: String,
)

private fun localeStyle(language: String): LocaleMoneyStyle = when (language) {
  "de", "nl", "es", "it", "pt" -> LocaleMoneyStyle(',', '.', false, " ")
  "fr" -> LocaleMoneyStyle(',', '\u00A0', false, "\u00A0")
  else -> LocaleMoneyStyle('.', ',', true, "")
}

private fun symbol(currencyCode: String): String = when (currencyCode) {
  "GBP" -> "£"
  "EUR" -> "€"
  else -> currencyCode
}

private fun groupDigits(digits: String, separator: Char): String {
  if (digits.length <= 3) return digits
  val groups = ArrayList<String>()
  var end = digits.length
  while (end > 0) {
    val start = maxOf(0, end - 3)
    groups.add(digits.substring(start, end))
    end = start
  }
  return groups.reversed().joinToString(separator.toString())
}

private fun pow10(exponent: Int): Long {
  var result = 1L
  repeat(exponent) {
    result = multiplyExact(result, 10L)
  }
  return result
}

private fun multiplyExact(lhs: Long, rhs: Long): Long = try {
  Math.multiplyExact(lhs, rhs)
} catch (_: ArithmeticException) {
  throw MoneyException.overflow()
}

private fun addExact(lhs: Long, rhs: Long): Long = try {
  Math.addExact(lhs, rhs)
} catch (_: ArithmeticException) {
  throw MoneyException.overflow()
}
