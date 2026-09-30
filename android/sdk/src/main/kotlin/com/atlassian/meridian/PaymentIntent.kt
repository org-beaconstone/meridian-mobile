package com.atlassian.meridian

import com.fasterxml.jackson.annotation.JsonAlias
import com.fasterxml.jackson.annotation.JsonIgnoreProperties
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.security.MessageDigest
import java.text.Normalizer
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

const val paymentConsentSummary =
  "I authorise Meridian to submit this GBP payment to the named recipient. This rehearsal does not move real money or contact Adyen or Worldpay."

const val paymentQuoteTTLSeconds = 60

enum class IntentDisposition {
  succeeded,
  declined,
  actionRequired,
  retrySameIntent,
}

data class PaymentReview(
  val recipientName: String,
  val recipientDetail: String,
  val amountMinor: Int,
  val feeMinor: Int,
  val amountLabel: String,
  val feeLabel: String,
  val methodLabel: String,
  val bank: String,
  val quoteExpiresAt: String,
  val expiryLabel: String,
  val consentSummary: String,
  val localReference: String,
  val currency: String,
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class PaymentIntentResponse(
  val ok: Boolean = false,
  val status: String? = null,
  @JsonAlias("intent_id")
  val intentId: String? = null,
  val state: BankState? = null,
  val transaction: Transaction? = null,
  val error: String? = null,
  val code: String? = null,
)

data class PaymentIntentHttpResult(
  val statusCode: Int,
  val body: PaymentIntentResponse,
)

data class PaymentIntentSubmission(
  val disposition: IntentDisposition,
  val statusCode: Int,
  val intentId: String?,
  val ok: Boolean,
  val code: String?,
  val error: String?,
  val message: String,
  val idempotencyKey: String,
  val payloadHash: String,
  val state: BankState?,
) {
  val terminal: Boolean
    get() = disposition == IntentDisposition.succeeded ||
      disposition == IntentDisposition.declined ||
      disposition == IntentDisposition.actionRequired
}

fun resolvePaymentIntentsUrl(baseURL: String): String {
  var trimmed = baseURL
  while (trimmed.endsWith("/")) trimmed = trimmed.dropLast(1)
  val root = if (trimmed.endsWith("/api/v1")) trimmed.removeSuffix("/api/v1") else trimmed
  return root.trimEnd('/') + "/api/v2/payment-intents"
}

fun rehearsalFeeMinor(method: PaymentMethod, amountMinor: Int): Int = when (method) {
  PaymentMethod.bank -> 0
  PaymentMethod.card -> maxOf((amountMinor * 15 + 500) / 1000, 1)
}

fun baselineBank(method: PaymentMethod): String = when (method) {
  PaymentMethod.card -> "Adyen"
  PaymentMethod.bank -> "Worldpay"
}

fun baselineProviderId(method: PaymentMethod): String = when (method) {
  PaymentMethod.card -> "adyen"
  PaymentMethod.bank -> "worldpay"
}

fun baselineMethodLabel(method: PaymentMethod): String = when (method) {
  PaymentMethod.card -> "Debit card"
  PaymentMethod.bank -> "Bank payment"
}

fun localizedRecipientName(name: String): String =
  Normalizer.normalize(name.trim(), Normalizer.Form.NFC)

fun formatUTC(date: Date): String {
  val calendar = Calendar.getInstance(TimeZone.getTimeZone("UTC"), Locale.US)
  calendar.time = date
  return String.format(
    Locale.US,
    "%04d-%02d-%02dT%02d:%02d:%02dZ",
    calendar.get(Calendar.YEAR),
    calendar.get(Calendar.MONTH) + 1,
    calendar.get(Calendar.DAY_OF_MONTH),
    calendar.get(Calendar.HOUR_OF_DAY),
    calendar.get(Calendar.MINUTE),
    calendar.get(Calendar.SECOND),
  )
}

private val expiryMonths = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

fun localizedQuoteExpiry(iso: String): String {
  val match = Regex("""^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$""").matchEntire(iso) ?: return iso
  val month = match.groupValues[2].toIntOrNull() ?: return iso
  val day = match.groupValues[3].toIntOrNull() ?: return iso
  if (month !in 1..12) return iso
  return "$day ${expiryMonths[month - 1]} ${match.groupValues[1]}, ${match.groupValues[4]}:${match.groupValues[5]} UTC"
}

fun isQuoteExpired(quoteExpiresAt: String, now: Date): Boolean = formatUTC(now) >= quoteExpiresAt

fun normalizedLocalReference(input: String): Pair<String?, String?> {
  val trimmed = input.trim()
  if (trimmed.isEmpty()) return Pair(null, "Local reference is required")
  if (trimmed.length > 200) return Pair(null, "Local reference is too long")
  if (trimmed.any { it.code < 32 || it.code == 127 }) {
    return Pair(null, "Local reference contains invalid characters")
  }
  return Pair(trimmed, null)
}

fun jsonString(value: String): String {
  val out = StringBuilder("\"")
  value.forEach { ch ->
    when (ch) {
      '"' -> out.append("\\\"")
      '\\' -> out.append("\\\\")
      '\b' -> out.append("\\b")
      '\u000C' -> out.append("\\f")
      '\n' -> out.append("\\n")
      '\r' -> out.append("\\r")
      '\t' -> out.append("\\t")
      else -> if (ch.code < 32) out.append("\\u%04x".format(ch.code)) else out.append(ch)
    }
  }
  out.append('"')
  return out.toString()
}

fun canonicalPaymentIntentJSON(
  amountMinor: Int,
  bank: String,
  consentSummary: String,
  feeMinor: Int,
  localReference: String,
  method: String,
  provider: String,
  quoteExpiresAt: String,
  quoteId: String,
  recipientId: String,
  recipientName: String,
): String {
  val pairs = listOf(
    "amountMinor" to amountMinor.toString(),
    "bank" to jsonString(bank),
    "consentAccepted" to "true",
    "consentSummary" to jsonString(consentSummary),
    "currency" to jsonString("GBP"),
    "feeMinor" to feeMinor.toString(),
    "localReference" to jsonString(localReference),
    "method" to jsonString(method),
    "provider" to jsonString(provider),
    "quoteExpiresAt" to jsonString(quoteExpiresAt),
    "quoteId" to jsonString(quoteId),
    "recipientId" to jsonString(recipientId),
    "recipientName" to jsonString(recipientName),
  )
  return pairs.joinToString(prefix = "{", postfix = "}", separator = ",") { "${jsonString(it.first)}:${it.second}" }
}

fun sha256Hex(text: String): String {
  val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
  return digest.joinToString("") { "%02x".format(it) }
}

fun classifyPaymentIntent(statusCode: Int, body: PaymentIntentResponse): IntentDisposition {
  val normalized = body.status?.trim()?.lowercase(Locale.US)?.replace('-', '_')
  when (normalized) {
    "succeeded", "success", "completed" -> return IntentDisposition.succeeded
    "declined", "decline" -> return IntentDisposition.declined
    "action_required", "requires_action" -> return IntentDisposition.actionRequired
  }
  when (body.code?.trim()?.uppercase(Locale.US)) {
    "SUCCEEDED", "SUCCESS" -> return IntentDisposition.succeeded
    "DECLINED" -> return IntentDisposition.declined
    "ACTION_REQUIRED", "REQUIRES_ACTION" -> return IntentDisposition.actionRequired
  }
  if (statusCode == 422) return IntentDisposition.declined
  if (statusCode == 202) return IntentDisposition.actionRequired
  if (statusCode in 200..299 && body.ok) return IntentDisposition.succeeded
  return IntentDisposition.retrySameIntent
}

fun paymentIntentMessage(disposition: IntentDisposition, error: String?): String {
  val reason = error?.trim().orEmpty()
  return when (disposition) {
    IntentDisposition.succeeded -> "Payment intent succeeded. This intent was not submitted again."
    IntentDisposition.declined -> {
      val lead = if (reason.isEmpty()) "Payment declined" else reason.trim('.')
      "$lead. This intent stays closed."
    }
    IntentDisposition.actionRequired -> {
      val lead = if (reason.isEmpty()) "Action required" else reason.trim('.')
      "$lead. This intent was not recreated."
    }
    IntentDisposition.retrySameIntent -> {
      val lead = if (reason.isEmpty()) "Outcome may be unknown" else reason.trim('.')
      "$lead. Retry keeps the same idempotency key and payload hash."
    }
  }
}

private val safeToken = Regex("^[A-Za-z0-9_-]{1,100}$")

fun preparePaymentIntent(
  recipientId: String,
  recipientName: String,
  recipientDetail: String,
  amountInput: String,
  localReference: String,
  method: PaymentMethod,
  now: Date = Date(),
  ttlSeconds: Int = paymentQuoteTTLSeconds,
  idempotencyKey: String = UUID.randomUUID().toString(),
  quoteId: String = "quote-${UUID.randomUUID().toString().lowercase(Locale.US)}",
  quoteExpiresAt: String? = null,
): PaymentIntentAttempt {
  val recipient = recipientId.trim()
  val name = localizedRecipientName(recipientName)
  if (recipient.isEmpty() || name.isEmpty()) throw MeridianError.ValidationError("Recipient is required")
  val (amountMinor, amountError) = parseAmount(amountInput)
  if (amountMinor == null) throw MeridianError.ValidationError(amountError ?: "Amount is required")
  val (reference, referenceError) = normalizedLocalReference(localReference)
  if (reference == null) throw MeridianError.ValidationError(referenceError ?: "Local reference is required")
  if (!safeToken.matches(idempotencyKey)) throw MeridianError.ValidationError("Idempotency key is invalid")
  if (!safeToken.matches(quoteId)) throw MeridianError.ValidationError("Quote id is invalid")
  val expiry = quoteExpiresAt ?: formatUTC(Date(now.time + ttlSeconds * 1000L))
  if (!Regex("""^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$""").matches(expiry)) {
    throw MeridianError.ValidationError("Quote expiry is invalid")
  }
  val fee = rehearsalFeeMinor(method, amountMinor)
  val bank = baselineBank(method)
  val provider = baselineProviderId(method)
  val canonical = canonicalPaymentIntentJSON(
    amountMinor = amountMinor,
    bank = bank,
    consentSummary = paymentConsentSummary,
    feeMinor = fee,
    localReference = reference,
    method = method.name,
    provider = provider,
    quoteExpiresAt = expiry,
    quoteId = quoteId,
    recipientId = recipient,
    recipientName = name,
  )
  val review = PaymentReview(
    recipientName = name,
    recipientDetail = recipientDetail.trim(),
    amountMinor = amountMinor,
    feeMinor = fee,
    amountLabel = money(amountMinor),
    feeLabel = money(fee),
    methodLabel = baselineMethodLabel(method),
    bank = bank,
    quoteExpiresAt = expiry,
    expiryLabel = localizedQuoteExpiry(expiry),
    consentSummary = paymentConsentSummary,
    localReference = reference,
    currency = "GBP",
  )
  return PaymentIntentAttempt(
    idempotencyKey = idempotencyKey,
    payloadHash = sha256Hex(canonical),
    canonicalBody = canonical,
    quoteExpiresAt = expiry,
    review = review,
  )
}

class PaymentIntentAttempt(
  val idempotencyKey: String,
  val payloadHash: String,
  val canonicalBody: String,
  val quoteExpiresAt: String,
  val review: PaymentReview,
) {
  private val mutex = Mutex()
  private var inFlight = false
  @Volatile private var submitted = false
  private var settled: PaymentIntentSubmission? = null

  fun hasSubmitted(): Boolean = submitted || settled != null

  suspend fun submit(
    now: Date = Date(),
    consentAccepted: Boolean,
    transport: suspend (canonicalBody: String, idempotencyKey: String, payloadHash: String) -> PaymentIntentHttpResult,
  ): PaymentIntentSubmission {
    mutex.withLock {
      settled?.let { return it }
      if (inFlight) throw MeridianError.DuplicateSubmission()
      if (!submitted) {
        if (!consentAccepted) throw MeridianError.ValidationError("Consent is required")
        if (isQuoteExpired(quoteExpiresAt, now)) throw MeridianError.QuoteExpired()
      }
      inFlight = true
      submitted = true
    }
    try {
      val http = transport(canonicalBody, idempotencyKey, payloadHash)
      val disposition = classifyPaymentIntent(http.statusCode, http.body)
      val submission = PaymentIntentSubmission(
        disposition = disposition,
        statusCode = http.statusCode,
        intentId = http.body.intentId,
        ok = http.body.ok,
        code = http.body.code,
        error = http.body.error,
        message = paymentIntentMessage(disposition, http.body.error),
        idempotencyKey = idempotencyKey,
        payloadHash = payloadHash,
        state = http.body.state,
      )
      mutex.withLock {
        inFlight = false
        if (submission.terminal) settled = submission
      }
      return submission
    } catch (error: Throwable) {
      mutex.withLock { inFlight = false }
      throw error
    }
  }
}
