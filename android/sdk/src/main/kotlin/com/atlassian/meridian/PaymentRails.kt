package com.atlassian.meridian

enum class RailAvailability {
  available, degraded, unavailable
}

/** Copy shown when a catalog rail is degraded, unavailable, or offline. */
const val regionalUnavailabilityWarning = "This payment method is temporarily unavailable in your region."

const val adyenCardTitle = "Debit card"
const val adyenCardBadge = "Adyen card (UK debit, usually instant)"
const val worldpayBankTitle = "Bank payment"
const val worldpayBankBadge = "Worldpay bank transfer (Free, arrives next working day)"

data class PaymentRail(
  val id: String,
  val provider: ProviderId,
  val method: PaymentMethod,
  val title: String,
  val badge: String,
  val availability: RailAvailability,
  val warning: String?,
  val position: Int,
  val total: Int,
) {
  val selectable: Boolean get() = availability == RailAvailability.available

  val announcement: String get() = paymentOptionAnnouncement(title, position, total)
}

fun paymentOptionAnnouncement(title: String, index: Int, total: Int): String =
  "Select $title, radio button, $index of $total"

/**
 * Payment options for the native bottom sheet.
 * Only the Adyen card and Worldpay bank baseline is offered. Any other catalog provider is ignored
 * and is not named in the resolved options.
 */
fun resolvePaymentRails(providers: List<Provider>): List<PaymentRail> {
  data class Draft(
    val provider: ProviderId,
    val method: PaymentMethod,
    val title: String,
    val badge: String,
    val availability: RailAvailability,
  )

  val drafts = mutableListOf<Draft>()
  val seen = mutableSetOf<String>()
  for (provider in providers) {
    for (methodName in provider.methods) {
      val baseline = baselineRail(provider.id, methodName) ?: continue
      val key = "${baseline.provider.name}:${baseline.method.name}"
      if (!seen.add(key)) continue
      drafts += Draft(
        provider = baseline.provider,
        method = baseline.method,
        title = baseline.title,
        badge = baseline.badge,
        availability = parseRailAvailability(provider.status),
      )
    }
  }

  val total = drafts.size
  return drafts.mapIndexed { index, draft ->
    PaymentRail(
      id = "${draft.provider.name}-${draft.method.name}",
      provider = draft.provider,
      method = draft.method,
      title = draft.title,
      badge = draft.badge,
      availability = draft.availability,
      warning = if (draft.availability == RailAvailability.available) null else regionalUnavailabilityWarning,
      position = index + 1,
      total = total,
    )
  }
}

private data class BaselineRail(
  val provider: ProviderId,
  val method: PaymentMethod,
  val title: String,
  val badge: String,
)

private fun baselineRail(providerId: String, methodName: String): BaselineRail? {
  return when (Pair(providerId.trim().lowercase(), methodName.trim().lowercase())) {
    Pair("adyen", "card") -> BaselineRail(ProviderId.adyen, PaymentMethod.card, adyenCardTitle, adyenCardBadge)
    Pair("worldpay", "bank") -> BaselineRail(ProviderId.worldpay, PaymentMethod.bank, worldpayBankTitle, worldpayBankBadge)
    else -> null
  }
}

private fun parseRailAvailability(status: String?): RailAvailability {
  return when (status?.trim()?.lowercase()) {
    null, "", "available", "online" -> RailAvailability.available
    "degraded" -> RailAvailability.degraded
    else -> RailAvailability.unavailable
  }
}
