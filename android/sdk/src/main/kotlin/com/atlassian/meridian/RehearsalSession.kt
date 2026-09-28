package com.atlassian.meridian

/**
 * Client rehearsal against the shared Java mock.
 * Amounts stay integer GBP pence. Card stays Adyen and bank stays Worldpay.
 * A gateway timeout or provider-unavailable response retries the same idempotency key and method.
 * HTTP 202 is pending confirmation: the payment is not settled and the key is kept.
 */
class RehearsalSession(private val client: MeridianClient) {
  private var lastCatalog: CatalogResponse? = null

  val sessionId: String get() = client.sessionId

  suspend fun hydrateCatalog(): CatalogHydration {
    return try {
      val fresh = client.getCatalog()
      lastCatalog = fresh
      CatalogHydration(fresh, CatalogSource.LIVE, false)
    } catch (_: Exception) {
      val cached = lastCatalog
      if (cached != null) {
        CatalogHydration(cached, CatalogSource.LAST_KNOWN_GOOD, true)
      } else {
        CatalogHydration(null, CatalogSource.EMPTY, true)
      }
    }
  }

  suspend fun submit(attempt: PaymentAttempt): PaymentOutcome {
    val problem = validate(attempt)
    if (problem != null) {
      return PaymentOutcome.Rejected(problem, attempt)
    }
    // Provider is fixed by the selected method and is not sent as a switchable field.
    baselineProvider(attempt.method)
    return try {
      val submission = client.submitPaymentDetailed(
        recipientId = attempt.recipientId,
        amountMinor = attempt.amountMinor,
        method = attempt.method,
        note = attempt.note,
        scenario = attempt.scenario,
        idempotencyKey = attempt.idempotencyKey,
      )
      classify(submission, attempt)
    } catch (e: MeridianError.NetworkError) {
      PaymentOutcome.Retryable(e.message ?: "Network error", attempt)
    } catch (e: MeridianError.DecodingError) {
      PaymentOutcome.Retryable(e.message ?: "Uncertain response", attempt)
    } catch (e: MeridianError.HttpError) {
      if (e.statusCode == 408 || e.statusCode >= 500) {
        PaymentOutcome.Retryable(e.message ?: "HTTP ${e.statusCode}", attempt)
      } else {
        PaymentOutcome.Rejected(e.message ?: "HTTP ${e.statusCode}", attempt)
      }
    } catch (e: MeridianError) {
      PaymentOutcome.Rejected(e.message ?: "Payment rejected", attempt)
    }
  }

  private fun validate(attempt: PaymentAttempt): String? {
    if (!IDEMPOTENCY.matches(attempt.idempotencyKey)) {
      return "Invalid Idempotency-Key"
    }
    if (attempt.amountMinor !in 1..1_000_000) {
      return "Amount must be integer pence from 1 to 1000000"
    }
    if (attempt.note.length > 200) {
      return "Reference exceeds 200 characters"
    }
    return null
  }

  private fun classify(submission: PaymentSubmission, attempt: PaymentAttempt): PaymentOutcome {
    val status = submission.statusCode
    val code = submission.body.code
    return when {
      status == 202 || code == "PAYMENT_PENDING" -> PaymentOutcome.Pending(submission.body, attempt)
      status == 503 || code == "PROVIDER_UNAVAILABLE" -> PaymentOutcome.Retryable(
        submission.body.error ?: "Provider unavailable. Retry the same payment.",
        attempt,
      )
      status == 422 || code == "PAYMENT_DECLINED" -> PaymentOutcome.Declined(submission.body, attempt)
      status == 409 -> PaymentOutcome.Rejected(
        submission.body.error ?: "Idempotency key belongs to a different payment",
        attempt,
      )
      submission.body.ok && status in 200..299 -> PaymentOutcome.Settled(submission.body, attempt)
      status >= 500 -> PaymentOutcome.Retryable(submission.body.error ?: "HTTP $status", attempt)
      else -> PaymentOutcome.Rejected(submission.body.error ?: "HTTP $status", attempt)
    }
  }

  companion object {
    private val IDEMPOTENCY = Regex("^[A-Za-z0-9_-]{1,100}$")
  }
}

enum class CatalogSource {
  LIVE,
  LAST_KNOWN_GOOD,
  EMPTY,
}

data class CatalogHydration(
  val catalog: CatalogResponse?,
  val source: CatalogSource,
  val degraded: Boolean,
)

data class PaymentAttempt(
  val recipientId: String,
  val amountMinor: Int,
  val method: PaymentMethod,
  val note: String,
  val scenario: Scenario,
  val idempotencyKey: String,
) {
  val provider: String get() = baselineProvider(method)
}

sealed class PaymentOutcome {
  data class Settled(val response: PaymentResponse, val attempt: PaymentAttempt) : PaymentOutcome()
  data class Pending(val response: PaymentResponse, val attempt: PaymentAttempt) : PaymentOutcome()
  data class Declined(val response: PaymentResponse, val attempt: PaymentAttempt) : PaymentOutcome()
  data class Retryable(val message: String, val attempt: PaymentAttempt) : PaymentOutcome()
  data class Rejected(val message: String, val attempt: PaymentAttempt) : PaymentOutcome()
}
