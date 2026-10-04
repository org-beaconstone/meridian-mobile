package com.atlassian.meridian

import com.fasterxml.jackson.annotation.JsonIgnoreProperties

/**
 * Bounded retry for transient gateway failures on a payment that already has an idempotency key.
 * HTTP 502 and 504 are retried. Business outcomes (including simulated 503) are not.
 * The client never selects a different provider while retrying.
 */
class RetryPolicy(
  val maxAttempts: Int = 3,
  val initialDelayMillis: Long = 200,
  val maxDelayMillis: Long = 1_600,
  val jitter: (Long) -> Long = { base ->
    if (base <= 0L) 0L else (0L..base / 5).random()
  },
) {
  fun retries(statusCode: Int): Boolean = statusCode == 502 || statusCode == 504

  /** Delay before starting [beforeAttempt] (2 is the second try). */
  fun delayMillis(beforeAttempt: Int): Long {
    val exponent = (beforeAttempt - 2).coerceIn(0, 8)
    var scaled = initialDelayMillis
    repeat(exponent) {
      if (scaled > maxDelayMillis) return maxDelayMillis + jitter(maxDelayMillis)
      scaled *= 2
    }
    val capped = minOf(scaled, maxDelayMillis)
    return capped + jitter(capped)
  }
}

@JsonIgnoreProperties(ignoreUnknown = true)
data class RailHealth(
  val method: String = "",
  val provider: String = "",
  val status: String = "",
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class CorridorHealth(
  val id: String = "",
  val status: String = "healthy",
  val currency: String? = null,
  val rails: List<RailHealth> = emptyList(),
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class SessionHealth(
  val status: String = "UP",
  val simulation: Boolean? = null,
  val corridors: List<CorridorHealth> = emptyList(),
)

data class SessionHealthSnapshot(
  val health: SessionHealth? = null,
  val reachable: Boolean = false,
  val detail: String? = null,
)

data class RailPrompt(
  val corridorId: String,
  val selectedMethod: PaymentMethod,
  val alternateMethod: PaymentMethod,
  val reason: String,
)

sealed class CorridorNotice {
  data class SwitchRail(val prompt: RailPrompt) : CorridorNotice()
  data class Unavailable(val corridorId: String, val message: String) : CorridorNotice()
}

fun baselineProvider(method: PaymentMethod): String = when (method) {
  PaymentMethod.card -> "adyen"
  PaymentMethod.bank -> "worldpay"
}

fun railLabel(method: PaymentMethod): String = when (method) {
  PaymentMethod.card -> "Debit card · Adyen"
  PaymentMethod.bank -> "Bank payment · Worldpay"
}

/**
 * GBP rehearsal only. A rail is eligible when it is the hardcoded Adyen card or Worldpay bank
 * pairing and the corridor reports it healthy. Any other provider id is ignored.
 */
fun corridorNotice(health: SessionHealth, selected: PaymentMethod): CorridorNotice? {
  val corridor = gbpCorridor(health) ?: return null
  val baseline = corridor.rails.filter { isBaselineRail(it) }
  val selectedRail = baseline.firstOrNull { it.method.equals(selected.name, ignoreCase = true) }
  val selectedStatus = when {
    selectedRail != null -> normalizeStatus(selectedRail.status)
    normalizeStatus(corridor.status) == "outage" -> "outage"
    else -> "healthy"
  }
  if (selectedStatus != "degraded" && selectedStatus != "outage") return null

  val alternate = baseline.firstOrNull { rail ->
    !rail.method.equals(selected.name, ignoreCase = true) && normalizeStatus(rail.status) == "healthy"
  }
  if (alternate != null) {
    val method = if (alternate.method.equals("card", ignoreCase = true)) PaymentMethod.card else PaymentMethod.bank
    return CorridorNotice.SwitchRail(
      RailPrompt(
        corridorId = corridor.id.ifEmpty { "GB" },
        selectedMethod = selected,
        alternateMethod = method,
        reason = selectedStatus,
      )
    )
  }
  val corridorId = corridor.id.ifEmpty { "GB" }
  return CorridorNotice.Unavailable(
    corridorId,
    "Corridor $corridorId is unavailable. No other rehearsed rail is healthy. Your payment details are unchanged.",
  )
}

internal fun gbpCorridor(health: SessionHealth): CorridorHealth? {
  return health.corridors.firstOrNull { corridor ->
    corridor.currency.equals("GBP", ignoreCase = true) ||
      corridor.id.equals("GB", ignoreCase = true) ||
      corridor.id.equals("GBP", ignoreCase = true)
  }
}

internal fun isBaselineRail(rail: RailHealth): Boolean {
  val method = rail.method.lowercase()
  val provider = rail.provider.lowercase()
  return (method == "card" && provider == "adyen") || (method == "bank" && provider == "worldpay")
}

internal fun normalizeStatus(raw: String): String = when (raw.lowercase()) {
  "healthy", "up", "ok", "available" -> "healthy"
  "degraded", "degradation" -> "degraded"
  "outage", "down", "unavailable" -> "outage"
  else -> "unknown"
}
