package com.atlassian.meridian

import kotlinx.coroutines.delay
import java.util.UUID

private val UUID_V4 = Regex(
  "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
)

/** UUID version 4 idempotency key for one payment attempt. */
fun newPaymentIdempotencyKey(): String = UUID.randomUUID().toString()

fun isUuidV4(value: String): Boolean = UUID_V4.matches(value)

/**
 * Retry policy for ambiguous gateway responses from POST /payments.
 * The payment method and idempotency key stay on the original attempt.
 */
object GatewayRetry {
  const val MAX_ATTEMPTS = 3
  const val INITIAL_BACKOFF_MS = 200L
  const val MAX_BACKOFF_MS = 1_600L

  fun isTimeout(statusCode: Int): Boolean = statusCode == 502 || statusCode == 504

  fun backoffMillis(
    retryIndex: Int,
    randomUnit: Double,
    initialMs: Long = INITIAL_BACKOFF_MS,
    maxMs: Long = MAX_BACKOFF_MS,
  ): Long {
    require(retryIndex >= 0) { "retryIndex must be >= 0" }
    var delayMs = initialMs
    repeat(retryIndex) {
      delayMs = (delayMs * 2).coerceAtMost(maxMs)
    }
    val jitter = (randomUnit.coerceIn(0.0, 1.0) * (initialMs / 2.0)).toLong()
    return delayMs + jitter
  }
}

/**
 * Submits one GBP payment to POST /payments.
 * HTTP 502 and 504 retry with exponential backoff. The rehearsal session,
 * idempotency key, amount, and method are the same on every attempt.
 */
class PaymentOrchestrator(
  private val client: MeridianClient,
  private val maxAttempts: Int = GatewayRetry.MAX_ATTEMPTS,
  private val initialBackoffMs: Long = GatewayRetry.INITIAL_BACKOFF_MS,
  private val sleep: suspend (Long) -> Unit = { delay(it) },
  private val randomUnit: () -> Double = { Math.random() },
) {
  init {
    require(maxAttempts >= 1) { "At least one attempt is required" }
  }

  suspend fun submit(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = Scenario.success,
    idempotencyKey: String,
    onRetry: (attempt: Int, statusCode: Int) -> Unit = { _, _ -> },
  ): PaymentResponse {
    if (!isUuidV4(idempotencyKey)) {
      throw MeridianError.ValidationError("Idempotency key must be a UUID v4")
    }

    var attempt = 1
    while (true) {
      try {
        return client.submitPayment(
          recipientId = recipientId,
          amountMinor = amountMinor,
          method = method,
          note = note,
          scenario = scenario,
          idempotencyKey = idempotencyKey,
        )
      } catch (error: MeridianError.HttpError) {
        if (!GatewayRetry.isTimeout(error.statusCode) || attempt >= maxAttempts) {
          if (GatewayRetry.isTimeout(error.statusCode)) {
            throw MeridianError.HttpError(
              error.statusCode,
              "Gateway timed out. Retry keeps this payment on the same method and the same key.",
            )
          }
          throw error
        }
        onRetry(attempt + 1, error.statusCode)
        sleep(GatewayRetry.backoffMillis(attempt - 1, randomUnit(), initialBackoffMs))
        attempt += 1
      }
    }
  }
}
