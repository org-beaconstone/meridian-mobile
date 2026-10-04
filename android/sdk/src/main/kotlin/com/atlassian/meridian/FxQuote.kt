package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonNode
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import kotlin.math.min

const val ACCOUNT_CURRENCY = "GBP"
const val QUOTE_LOCK_SECONDS = 60

object FxCopy {
  const val unavailable = "We couldn't lock an exchange rate. Try again."
  const val expired =
    "This rate lock has expired. Refresh the rate to continue. Your payment details are unchanged."
  const val retry = "Try again"
  const val refresh = "Refresh rate"
  const val locked = "Rate locked"
}

fun isCrossCurrency(source: String, target: String): Boolean =
  !source.equals(target, ignoreCase = true)

data class FxQuoteRequest(
  val sourceCurrency: String,
  val targetCurrency: String,
  val amountMinor: Int,
)

data class FxQuote(
  val quoteId: String,
  val sourceCurrency: String,
  val targetCurrency: String,
  val sourceAmountMinor: Int?,
  val targetAmountMinor: Int?,
  val rate: String,
  val expiresInSeconds: Int,
  val serverExpiresAtEpochMs: Long?,
)

data class FxQuoteLock(
  val quoteId: String,
  val sourceCurrency: String,
  val targetCurrency: String,
  val sourceAmountMinor: Int,
  val targetAmountMinor: Int?,
  val rate: String,
  val expiresAtEpochMs: Long,
) {
  fun remainingSeconds(nowEpochMs: Long): Int {
    val left = expiresAtEpochMs - nowEpochMs
    if (left <= 0) return 0
    val seconds = ((left + 999) / 1000).toInt()
    return min(QUOTE_LOCK_SECONDS, seconds)
  }

  fun isExpired(nowEpochMs: Long): Boolean = nowEpochMs >= expiresAtEpochMs
}

fun parseFxQuote(node: JsonNode): FxQuote {
  val quoteId = node.path("quoteId").asText("").ifEmpty { node.path("id").asText("") }
  if (quoteId.isEmpty()) throw MeridianError.DecodingError("FX quote id missing")
  val rateNode = node.get("rate")
  val rate = when {
    rateNode == null || rateNode.isNull -> ""
    rateNode.isNumber -> trimRate(rateNode.asDouble())
    else -> rateNode.asText("")
  }
  if (rate.isEmpty()) throw MeridianError.DecodingError("FX rate missing")
  val sourceAmount = intOrNull(node, "sourceAmountMinor") ?: intOrNull(node, "amountMinor")
  val targetAmount = intOrNull(node, "targetAmountMinor")
  val expiresIn = intOrNull(node, "expiresInSeconds") ?: QUOTE_LOCK_SECONDS
  return FxQuote(
    quoteId = quoteId,
    sourceCurrency = node.path("sourceCurrency").asText(""),
    targetCurrency = node.path("targetCurrency").asText(""),
    sourceAmountMinor = sourceAmount,
    targetAmountMinor = targetAmount,
    rate = rate,
    expiresInSeconds = expiresIn,
    serverExpiresAtEpochMs = parseExpiry(node.get("expiresAt")),
  )
}

private fun intOrNull(node: JsonNode, field: String): Int? {
  val value = node.get(field) ?: return null
  if (value.isNull || !value.isNumber || !value.canConvertToInt()) return null
  return value.asInt()
}

private fun trimRate(number: Double): String {
  var text = "%.6f".format(number)
  while (text.contains('.') && (text.endsWith('0') || text.endsWith('.'))) {
    text = text.dropLast(1)
  }
  return text
}

private fun parseExpiry(node: JsonNode?): Long? {
  if (node == null || node.isNull) return null
  if (node.isNumber) {
    val raw = node.asLong()
    return if (raw < 10_000_000_000L) raw * 1000 else raw
  }
  val text = node.asText("")
  if (text.isEmpty()) return null
  val patterns = arrayOf(
    "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
    "yyyy-MM-dd'T'HH:mm:ssXXX",
    "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
    "yyyy-MM-dd'T'HH:mm:ss'Z'",
  )
  for (pattern in patterns) {
    try {
      val format = SimpleDateFormat(pattern, Locale.US)
      format.timeZone = TimeZone.getTimeZone("UTC")
      val parsed = format.parse(text) ?: continue
      return parsed.time
    } catch (_: Exception) {
      continue
    }
  }
  return null
}

fun lockQuote(
  quote: FxQuote,
  sourceCurrency: String,
  targetCurrency: String,
  amountMinor: Int,
  lockedAtEpochMs: Long,
): FxQuoteLock {
  val windowSeconds = min(QUOTE_LOCK_SECONDS, maxOf(0, quote.expiresInSeconds))
  var expiry = lockedAtEpochMs + windowSeconds * 1000L
  quote.serverExpiresAtEpochMs?.let { server ->
    if (server < expiry) expiry = server
  }
  val cap = lockedAtEpochMs + QUOTE_LOCK_SECONDS * 1000L
  if (expiry > cap) expiry = cap
  return FxQuoteLock(
    quoteId = quote.quoteId,
    sourceCurrency = quote.sourceCurrency.ifEmpty { sourceCurrency },
    targetCurrency = quote.targetCurrency.ifEmpty { targetCurrency },
    sourceAmountMinor = quote.sourceAmountMinor ?: amountMinor,
    targetAmountMinor = quote.targetAmountMinor,
    rate = quote.rate,
    expiresAtEpochMs = expiry,
  )
}

fun rateLockBlockReason(
  sourceCurrency: String,
  targetCurrency: String,
  amountMinor: Int,
  quote: FxQuoteLock?,
  nowEpochMs: Long,
): String? {
  if (!isCrossCurrency(sourceCurrency, targetCurrency)) return null
  val active = quote ?: return FxCopy.unavailable
  val samePair =
    active.sourceCurrency.equals(sourceCurrency, ignoreCase = true) &&
      active.targetCurrency.equals(targetCurrency, ignoreCase = true) &&
      active.sourceAmountMinor == amountMinor &&
      active.quoteId.isNotEmpty() &&
      !active.isExpired(nowEpochMs)
  return if (samePair) null else FxCopy.expired
}

fun formatMinor(amountMinor: Int, currency: String): String {
  if (currency.equals("EUR", ignoreCase = true)) {
    return "€%.2f".format(amountMinor / 100.0)
  }
  return money(amountMinor)
}
