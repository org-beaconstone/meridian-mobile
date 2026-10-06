package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonNode
import java.time.LocalDate
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max

data class ContractError(val code: String, val message: String)

sealed class Decoded<out T> {
  data class Ok<T>(val value: T) : Decoded<T>()
  data class Err(val error: ContractError) : Decoded<Nothing>()
}

data class Money(val currency: String, val minor: Int, val exponent: Int) {
  val gbpPence: Int? get() = if (currency == "GBP" && exponent == 2) minor else null
  val display: String get() = formatMoney(currency, minor, exponent)
}

fun formatMoney(currency: String, minor: Int, exponent: Int): String {
  val symbol = when (currency) {
    "GBP" -> "£"
    "EUR" -> "€"
    "USD" -> "$"
    "JPY" -> "¥"
    else -> "$currency "
  }
  val negative = minor < 0
  val absolute = abs(minor)
  val sign = if (negative) "-" else ""
  if (exponent <= 0) return sign + symbol + absolute.toString()
  var scale = 1
  repeat(exponent) { scale *= 10 }
  val whole = absolute / scale
  val fraction = (absolute % scale).toString().padStart(exponent, '0')
  return sign + symbol + whole + "." + fraction
}

fun isCalendarDate(value: String): Boolean {
  if (!Regex("^\\d{4}-\\d{2}-\\d{2}$").matches(value)) return false
  return try {
    LocalDate.parse(value)
    true
  } catch (_: Exception) {
    false
  }
}

fun decodeMoney(node: JsonNode): Decoded<Money> {
  if (node.isNumber) {
    if (!node.isIntegralNumber || !node.canConvertToInt()) {
      return Decoded.Err(ContractError("MALFORMED_AMOUNT", "Legacy amount must be an integer"))
    }
    return legacyPence(node.intValue())
  }
  if (node.isTextual) {
    return Decoded.Err(ContractError("MALFORMED_AMOUNT", "Amount must be an integer or money object"))
  }
  if (!node.isObject) {
    return Decoded.Err(ContractError("MALFORMED_AMOUNT", "Amount must be an integer or money object"))
  }
  val currencyNode = node.get("currency")
    ?: return Decoded.Err(ContractError("MALFORMED_AMOUNT", "Currency is required"))
  val minorNode = node.get("minor")
    ?: return Decoded.Err(ContractError("MALFORMED_AMOUNT", "Minor units are required"))
  val exponentNode = node.get("exponent")
    ?: return Decoded.Err(ContractError("MALFORMED_AMOUNT", "Exponent is required"))
  if (!currencyNode.isTextual || !minorNode.isIntegralNumber || !minorNode.canConvertToInt() || !exponentNode.isIntegralNumber || !exponentNode.canConvertToInt()) {
    return Decoded.Err(ContractError("MALFORMED_AMOUNT", "Money object fields are invalid"))
  }
  val currency = currencyNode.asText()
  if (!Regex("^[A-Z]{3}$").matches(currency)) {
    return Decoded.Err(ContractError("MALFORMED_AMOUNT", "Currency must be an ISO code"))
  }
  val minor = minorNode.intValue()
  val exponent = exponentNode.intValue()
  if (minor < 0) return Decoded.Err(ContractError("INVALID_AMOUNT", "Amount must be greater than zero"))
  if (exponent !in 0..4) return Decoded.Err(ContractError("MALFORMED_AMOUNT", "Exponent is out of range"))
  if (minor == 0) return Decoded.Err(ContractError("INVALID_AMOUNT", "Amount must be greater than zero"))
  if (minor > 100_000_000) return Decoded.Err(ContractError("INVALID_AMOUNT", "Amount is too large"))
  if (currency == "GBP" && exponent == 2 && minor > 1_000_000) {
    return Decoded.Err(ContractError("INVALID_AMOUNT", "Amount cannot exceed £10,000"))
  }
  return Decoded.Ok(Money(currency, minor, exponent))
}

private fun legacyPence(minor: Int): Decoded<Money> {
  if (minor <= 0) return Decoded.Err(ContractError("INVALID_AMOUNT", "Amount must be greater than zero"))
  if (minor > 1_000_000) return Decoded.Err(ContractError("INVALID_AMOUNT", "Amount cannot exceed £10,000"))
  return Decoded.Ok(Money("GBP", minor, 2))
}

fun buttonHeight(platform: String, fontScale: Double): Double {
  val minimum = if (platform == "android") 48.0 else 44.0
  return max(minimum, 20.0 * fontScale + 24.0)
}

fun wrappedLines(text: String, fontScale: Double, containerWidth: Double, baseSize: Double): Int {
  if (containerWidth <= 0.0) return 1
  val width = text.length.toDouble() * baseSize * 0.55 * fontScale
  return max(1, ceil(width / containerWidth).toInt())
}

fun horizontalEdges(direction: String): Pair<String, String> =
  if (direction == "rtl") "right" to "left" else "left" to "right"
