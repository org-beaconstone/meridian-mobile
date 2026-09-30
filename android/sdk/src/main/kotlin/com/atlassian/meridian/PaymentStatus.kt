package com.atlassian.meridian

import com.fasterxml.jackson.annotation.JsonIgnoreProperties
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.delay
import java.io.File
import java.time.Instant
import java.util.Locale

/** Authoritative payment-intent phase from GET /api/v2/payment-intents/{id}. */
enum class IntentPhase {
  processing,
  pending,
  unknown,
  succeeded,
  declined;

  val needsStatusCheck: Boolean
    get() = this == processing || this == pending || this == unknown

  companion object {
    fun classify(raw: String?): IntentPhase {
      val value = raw?.trim()?.lowercase(Locale.ROOT)?.replace('_', '-') ?: ""
      return when (value) {
        "processing", "submitting", "prepared", "created", "in-progress", "authorizing" -> processing
        "pending", "payment-pending", "requires-action" -> pending
        "succeeded", "success", "completed", "complete" -> succeeded
        "declined", "declined-final", "payment-declined", "hard-decline" -> declined
        else -> unknown
      }
    }
  }
}

/** Restart behaviour. Status checks are GET lookups. Declined never submits again. */
sealed class RecoveryAction {
  data class Poll(val intentId: String) : RecoveryAction()
  data object ShowReceipt : RecoveryAction()
  data object ShowDecline : RecoveryAction()
  data object HoldUnknown : RecoveryAction()
}

fun recoveryAction(snapshot: IntentSnapshot): RecoveryAction {
  return when (snapshot.phase) {
    IntentPhase.succeeded -> RecoveryAction.ShowReceipt
    IntentPhase.declined -> RecoveryAction.ShowDecline
    IntentPhase.processing, IntentPhase.pending, IntentPhase.unknown -> {
      val intentId = snapshot.intentId
      if (!intentId.isNullOrEmpty()) RecoveryAction.Poll(intentId) else RecoveryAction.HoldUnknown
    }
  }
}

fun phaseFor(response: PaymentResponse): IntentPhase {
  if (response.ok) return IntentPhase.succeeded
  return when (response.code) {
    "PAYMENT_DECLINED" -> IntentPhase.declined
    "PAYMENT_PENDING" -> IntentPhase.pending
    "PAYMENT_PROCESSING" -> IntentPhase.processing
    else -> IntentPhase.unknown
  }
}

fun recoveryFeedback(phase: IntentPhase): String {
  return when (phase) {
    IntentPhase.succeeded -> "Payment complete."
    IntentPhase.declined ->
      "This payment was declined. No money was taken. It will not be submitted again automatically."
    IntentPhase.pending ->
      "This payment is pending confirmation. Status checks continue without submitting it again."
    IntentPhase.processing ->
      "Checking payment status. This does not start a new payment."
    IntentPhase.unknown ->
      "The payment status is still unknown. Status checks resume after a restart. A new payment was not created."
  }
}

fun providerLabel(provider: String?): String {
  return when (provider) {
    "adyen" -> "Adyen"
    "worldpay" -> "Worldpay"
    else -> "Simulated provider"
  }
}

fun baselineProvider(method: String): String = if (method == "bank") "worldpay" else "adyen"

/** Equal-jitter backoff capped at [maxMs]. The delay stays inside half the step and the cap. */
object StatusBackoff {
  const val INITIAL_MS = 500L
  const val MAX_MS = 4_000L
  const val MAX_ATTEMPTS = 5
  const val MAX_ELAPSED_MS = 15_000L

  fun backoffMillis(
    attemptIndex: Int,
    randomUnit: Double,
    initialMs: Long = INITIAL_MS,
    maxMs: Long = MAX_MS,
  ): Long {
    require(attemptIndex >= 0) { "attemptIndex must be >= 0" }
    var delayMs = initialMs
    var steps = attemptIndex
    while (steps > 0) {
      if (delayMs >= maxMs / 2) {
        delayMs = maxMs
        break
      }
      delayMs *= 2
      steps -= 1
    }
    if (delayMs > maxMs) delayMs = maxMs
    val unit = randomUnit.coerceIn(0.0, 1.0)
    val half = delayMs / 2
    val jitter = (unit * (delayMs - half)).toLong()
    return half + jitter
  }
}

@JsonIgnoreProperties(ignoreUnknown = true)
data class PaymentIntent(
  val id: String = "",
  val status: String? = null,
  val phase: String? = null,
  val amountMinor: Int? = null,
  val currency: String? = null,
  val recipientId: String? = null,
  val recipientName: String? = null,
  val method: String? = null,
  val provider: String? = null,
  val note: String? = null,
  val supportReference: String? = null,
  val transaction: Transaction? = null,
  val error: String? = null,
  val code: String? = null,
) {
  fun rawStatus(): String = status ?: phase ?: "unknown"
}

/** GBP-only view of an intent. A non-GBP currency is not treated as success. */
fun presentationPhase(intent: PaymentIntent): IntentPhase {
  val currency = intent.currency?.trim()
  val classified = IntentPhase.classify(intent.rawStatus())
  if (!currency.isNullOrEmpty() && !currency.equals("GBP", ignoreCase = true) && classified != IntentPhase.declined) {
    return IntentPhase.unknown
  }
  return classified
}

@JsonIgnoreProperties(ignoreUnknown = true)
data class IntentSnapshot(
  val intentId: String? = null,
  val sessionId: String,
  val baseURL: String,
  val idempotencyKey: String,
  val recipientId: String,
  val recipientName: String,
  val amountMinor: Int,
  val method: String,
  val note: String,
  val phase: IntentPhase,
  val supportReference: String? = null,
  val transaction: Transaction? = null,
  val provider: String? = null,
  val detail: String? = null,
  val updatedAt: String,
) {
  val needsStatusCheck: Boolean
    get() = phase.needsStatusCheck
}

fun isoTimestamp(): String = Instant.now().toString()

data class PaymentReceipt(
  val recipientName: String,
  val amountMinor: Int,
  val supportReference: String,
  val transactionId: String?,
  val transactionDate: String?,
  val method: String?,
  val provider: String?,
  val note: String?,
  val status: String?,
)

fun resolvedSupportReference(snapshot: IntentSnapshot, intent: PaymentIntent?): String {
  val explicit = intent?.supportReference?.trim()
  if (!explicit.isNullOrEmpty()) return explicit
  val stored = snapshot.supportReference?.trim()
  if (!stored.isNullOrEmpty()) return stored
  val transactionReference = intent?.transaction?.reference ?: snapshot.transaction?.reference
  if (!transactionReference.isNullOrEmpty()) return transactionReference
  val id = intent?.id?.takeIf { it.isNotEmpty() } ?: snapshot.intentId?.takeIf { it.isNotEmpty() }
  val source = id ?: snapshot.idempotencyKey
  return "MER-${source.take(8).uppercase(Locale.ROOT)}"
}

fun applying(result: StatusPollResult, snapshot: IntentSnapshot): IntentSnapshot {
  val intent = result.intent
  val next = snapshot.copy(
    intentId = intent?.id?.takeIf { it.isNotEmpty() } ?: snapshot.intentId,
    amountMinor = intent?.amountMinor ?: snapshot.amountMinor,
    recipientName = intent?.recipientName?.takeIf { it.isNotEmpty() } ?: snapshot.recipientName,
    recipientId = intent?.recipientId?.takeIf { it.isNotEmpty() } ?: snapshot.recipientId,
    method = intent?.method?.takeIf { it.isNotEmpty() } ?: snapshot.method,
    note = intent?.note ?: snapshot.note,
    provider = intent?.provider?.takeIf { it.isNotEmpty() } ?: snapshot.provider,
    transaction = intent?.transaction ?: snapshot.transaction,
    supportReference = intent?.supportReference?.takeIf { it.isNotEmpty() } ?: snapshot.supportReference,
    detail = when (result.phase) {
      IntentPhase.declined -> recoveryFeedback(IntentPhase.declined)
      IntentPhase.succeeded -> recoveryFeedback(IntentPhase.succeeded)
      else -> intent?.error?.takeIf { it.isNotEmpty() } ?: recoveryFeedback(result.phase)
    },
    phase = result.phase,
    updatedAt = isoTimestamp(),
  )
  return next.copy(supportReference = resolvedSupportReference(next, intent))
}

fun makeReceipt(snapshot: IntentSnapshot, intent: PaymentIntent? = null): PaymentReceipt {
  val transaction = intent?.transaction ?: snapshot.transaction
  val amount = intent?.amountMinor ?: transaction?.amount ?: snapshot.amountMinor
  return PaymentReceipt(
    recipientName = intent?.recipientName ?: snapshot.recipientName,
    amountMinor = amount,
    supportReference = resolvedSupportReference(snapshot, intent),
    transactionId = transaction?.id ?: intent?.id?.takeIf { it.isNotEmpty() } ?: snapshot.intentId,
    transactionDate = transaction?.date,
    method = transaction?.method ?: intent?.method ?: snapshot.method,
    provider = transaction?.provider ?: intent?.provider ?: snapshot.provider,
    note = transaction?.note ?: intent?.note ?: snapshot.note,
    status = transaction?.status ?: if (snapshot.phase == IntentPhase.succeeded) "completed" else snapshot.phase.name,
  )
}

fun paymentIntentUrl(baseUrl: String, id: String): String {
  require(Regex("^[A-Za-z0-9_-]{1,64}$").matches(id)) { "Invalid payment intent id" }
  val normalized = baseUrl.removeSuffix("/")
  require(normalized.endsWith("/api/v1")) { "API base URL must end with /api/v1" }
  return normalized.removeSuffix("/api/v1") + "/api/v2/payment-intents/$id"
}

data class StatusPollResult(
  val phase: IntentPhase,
  val intent: PaymentIntent?,
  val attempts: Int,
)

/**
 * Polls GET /api/v2/payment-intents/{id} with bounded jittered backoff.
 * This never submits a payment.
 */
class PaymentStatusPoller(
  private val getIntent: suspend (String) -> PaymentIntent,
  private val sleep: suspend (Long) -> Unit = { delay(it) },
  private val randomUnit: () -> Double = { Math.random() },
  private val maxAttempts: Int = StatusBackoff.MAX_ATTEMPTS,
  private val initialBackoffMs: Long = StatusBackoff.INITIAL_MS,
  private val maxBackoffMs: Long = StatusBackoff.MAX_MS,
  private val maxElapsedMs: Long = StatusBackoff.MAX_ELAPSED_MS,
) {
  init {
    require(maxAttempts >= 1) { "At least one attempt is required" }
  }

  suspend fun poll(intentId: String): StatusPollResult {
    var attempt = 0
    var elapsed = 0L
    var last: PaymentIntent? = null
    while (attempt < maxAttempts) {
      attempt += 1
      try {
        val intent = getIntent(intentId)
        last = intent
        val phase = presentationPhase(intent)
        if (phase == IntentPhase.succeeded || phase == IntentPhase.declined) {
          return StatusPollResult(phase, intent, attempt)
        }
      } catch (_: Exception) {
        // A failed lookup stays unknown and does not create another payment.
      }
      if (attempt >= maxAttempts) break
      val wait = StatusBackoff.backoffMillis(attempt - 1, randomUnit(), initialBackoffMs, maxBackoffMs)
      if (elapsed >= maxElapsedMs || wait > maxElapsedMs - elapsed) break
      sleep(wait)
      elapsed += wait
    }
    val phase = last?.let { presentationPhase(it) } ?: IntentPhase.unknown
    if (phase == IntentPhase.succeeded || phase == IntentPhase.declined) {
      return StatusPollResult(phase, last, attempt)
    }
    val open = if (phase == IntentPhase.pending || phase == IntentPhase.processing) phase else IntentPhase.unknown
    return StatusPollResult(open, last, attempt)
  }
}

/** JSON file of intent snapshots keyed by rehearsal session. Survives process death. */
class FileIntentSnapshotStore(
  private val file: File,
  private val mapper: ObjectMapper = ObjectMapper().registerKotlinModule(),
) {
  fun load(sessionId: String): IntentSnapshot? = read()[sessionId]

  fun save(snapshot: IntentSnapshot) {
    val sessions = read().toMutableMap()
    sessions[snapshot.sessionId] = snapshot
    write(sessions)
  }

  fun remove(sessionId: String) {
    val sessions = read().toMutableMap()
    sessions.remove(sessionId)
    write(sessions)
  }

  /** Prefer a snapshot that still needs a status check, otherwise the newest stored outcome. */
  fun latestRecoverable(): IntentSnapshot? {
    val sessions = read().values
    val open = sessions.filter {
      val action = recoveryAction(it)
      action is RecoveryAction.Poll || action is RecoveryAction.HoldUnknown
    }
    val pool = if (open.isEmpty()) sessions else open
    return pool.maxByOrNull { it.updatedAt }
  }

  private fun read(): Map<String, IntentSnapshot> {
    if (!file.exists()) return emptyMap()
    return try {
      val type = mapper.typeFactory.constructMapType(
        Map::class.java,
        String::class.java,
        IntentSnapshot::class.java,
      )
      mapper.readValue(file, type)
    } catch (_: Exception) {
      emptyMap()
    }
  }

  private fun write(sessions: Map<String, IntentSnapshot>) {
    file.parentFile?.mkdirs()
    mapper.writeValue(file, sessions)
  }
}
