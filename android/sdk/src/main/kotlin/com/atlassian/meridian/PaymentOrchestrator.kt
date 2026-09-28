package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonNode
import kotlinx.coroutines.delay
import java.time.Instant
import java.util.UUID

const val QUOTE_EXPIRED_MESSAGE =
  "This conversion rate has expired. Refresh the conversion rate before confirming."
const val INVALID_IBAN_MESSAGE = "Enter a valid recipient IBAN before submitting."

object QuoteLock {
  /** Customers see this countdown on the review screen. The client never extends it. */
  const val DURATION_SECONDS = 60
  /** Initial attempt plus two gateway retries. The idempotency key stays the same. */
  const val MAX_PAYMENT_ATTEMPTS = 3
}

data class FxQuote(
  val quoteId: String,
  val sourceCurrency: String,
  val targetCurrency: String,
  val sourceAmountMinor: Int,
  val targetAmountMinor: Int,
  val rate: String,
  val expiresInSeconds: Int,
  val serverExpiresAtEpochMs: Long?,
)

data class FxQuoteLock(
  val quoteId: String,
  val sourceAmountMinor: Int,
  val targetAmountMinor: Int,
  val rate: String,
  val sourceCurrency: String,
  val targetCurrency: String,
  val lockedAtEpochMs: Long,
  val expiresAtEpochMs: Long,
) {
  fun remainingSeconds(nowEpochMs: Long): Int {
    val leftMs = expiresAtEpochMs - nowEpochMs
    if (leftMs <= 0) return 0
    val seconds = ((leftMs + 999) / 1000).toInt()
    return seconds.coerceAtMost(QuoteLock.DURATION_SECONDS)
  }

  fun isExpired(nowEpochMs: Long): Boolean = nowEpochMs >= expiresAtEpochMs
}

fun fxQuoteFromJson(node: JsonNode): FxQuote {
  val quoteId = node.path("quoteId").asText("").ifEmpty { node.path("id").asText("") }
  if (quoteId.isEmpty()) {
    throw MeridianError.DecodingError("FX quote id missing")
  }
  val sourceNode = when {
    node.hasNonNull("sourceAmountMinor") -> node.get("sourceAmountMinor")
    node.hasNonNull("amountMinor") -> node.get("amountMinor")
    else -> null
  }
  val targetNode = if (node.hasNonNull("targetAmountMinor")) node.get("targetAmountMinor") else null
  if (sourceNode == null || !sourceNode.canConvertToInt() || targetNode == null || !targetNode.canConvertToInt()) {
    throw MeridianError.DecodingError("FX quote amount missing")
  }
  val rateNode = node.get("rate")
  val rate = when {
    rateNode == null || rateNode.isNull -> ""
    else -> rateNode.asText()
  }
  val expiresAt = node.path("expiresAt").asText("").ifEmpty { null }?.let { raw ->
    runCatching { Instant.parse(raw).toEpochMilli() }.getOrNull()
  }
  return FxQuote(
    quoteId = quoteId,
    sourceCurrency = node.path("sourceCurrency").asText("GBP"),
    targetCurrency = node.path("targetCurrency").asText("EUR"),
    sourceAmountMinor = sourceNode.asInt(),
    targetAmountMinor = targetNode.asInt(),
    rate = rate,
    expiresInSeconds = if (node.hasNonNull("expiresInSeconds")) node.get("expiresInSeconds").asInt() else 60,
    serverExpiresAtEpochMs = expiresAt,
  )
}

fun lockQuote(quote: FxQuote, lockedAtEpochMs: Long): FxQuoteLock {
  val localExpiry = lockedAtEpochMs + QuoteLock.DURATION_SECONDS * 1000L
  val server = quote.serverExpiresAtEpochMs
  val expiry = if (server != null && server < localExpiry) server else localExpiry
  return FxQuoteLock(
    quoteId = quote.quoteId,
    sourceAmountMinor = quote.sourceAmountMinor,
    targetAmountMinor = quote.targetAmountMinor,
    rate = quote.rate,
    sourceCurrency = quote.sourceCurrency,
    targetCurrency = quote.targetCurrency,
    lockedAtEpochMs = lockedAtEpochMs,
    expiresAtEpochMs = expiry,
  )
}

fun normalizeIban(raw: String): String = raw.uppercase().filter { !it.isWhitespace() }

/** ISO 13616 MOD-97. Letters expand to A=10 … Z=35. A valid IBAN has remainder 1. */
fun isValidIban(raw: String): Boolean {
  val iban = normalizeIban(raw)
  if (iban.length !in 15..34) return false
  if (!Regex("^[A-Z]{2}[0-9]{2}[A-Z0-9]+$").matches(iban)) return false
  val rearranged = iban.drop(4) + iban.take(4)
  var remainder = 0
  for (character in rearranged) {
    val digits = when {
      character.isDigit() -> character.toString()
      character in 'A'..'Z' -> (character.code - 55).toString()
      else -> return false
    }
    for (digit in digits) {
      remainder = (remainder * 10 + (digit.code - '0'.code)) % 97
    }
  }
  return remainder == 1
}

private val UUID_V4 = Regex(
  "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
)

fun isUuidV4(value: String): Boolean = UUID_V4.matches(value)

fun makeIdempotencyKey(): String {
  val key = UUID.randomUUID().toString()
  check(isUuidV4(key)) { "Platform UUID must be version 4" }
  return key
}

fun nextIdempotencyKey(current: String, retain: Boolean): String =
  if (retain) current else makeIdempotencyKey()

fun ibanRequired(currency: PayCurrency, method: PaymentMethod): Boolean =
  currency == PayCurrency.EUR || method == PaymentMethod.bank

fun ibanBlockReason(currency: PayCurrency, method: PaymentMethod, iban: String): String? {
  if (ibanRequired(currency, method) || normalizeIban(iban).isNotEmpty()) {
    if (!isValidIban(iban)) return INVALID_IBAN_MESSAGE
  }
  return null
}

fun submissionBlockReason(
  currency: PayCurrency,
  method: PaymentMethod,
  iban: String,
  quote: FxQuoteLock?,
  amountMinor: Int,
  nowEpochMs: Long,
): String? {
  ibanBlockReason(currency, method, iban)?.let { return it }
  if (currency == PayCurrency.EUR) {
    if (quote == null || quote.sourceAmountMinor != amountMinor || quote.isExpired(nowEpochMs)) {
      return QUOTE_EXPIRED_MESSAGE
    }
  }
  return null
}

fun isGatewayTimeout(statusCode: Int): Boolean = statusCode == 502 || statusCode == 504

/** Delay before the next attempt. `failedAttempt` is the 1-based count of gateway failures so far. */
fun gatewayBackoffMilliseconds(failedAttempt: Int): Long {
  require(failedAttempt >= 1)
  val shift = (failedAttempt - 1).coerceAtMost(8)
  return 200L shl shift
}

/**
 * Replays POST /payments on HTTP 502/504. The key and method never change, so a timeout cannot hop providers.
 */
suspend fun submitPaymentWithRetry(
  idempotencyKey: String,
  method: PaymentMethod,
  maxAttempts: Int = QuoteLock.MAX_PAYMENT_ATTEMPTS,
  delayMilliseconds: (Int) -> Long = ::gatewayBackoffMilliseconds,
  sleep: suspend (Long) -> Unit = { wait -> delay(wait) },
  send: suspend (idempotencyKey: String, method: PaymentMethod) -> PaymentResponse,
): PaymentResponse {
  var attempt = 1
  while (true) {
    try {
      return send(idempotencyKey, method)
    } catch (error: MeridianError.HttpError) {
      if (!isGatewayTimeout(error.statusCode) || attempt >= maxAttempts) throw error
      val wait = delayMilliseconds(attempt)
      attempt += 1
      sleep(wait)
    }
  }
}
