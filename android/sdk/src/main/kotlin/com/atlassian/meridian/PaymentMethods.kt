package com.atlassian.meridian

const val PAYMENT_RAIL_REGION_UNAVAILABLE =
  "This payment method is temporarily unavailable in your region."

data class PaymentMethodOption(
  val method: PaymentMethod,
  val providerId: ProviderId,
  val title: String,
  val badge: String,
  val available: Boolean,
  val warning: String?,
) {
  fun accessibilityAnnouncement(position: Int, total: Int): String {
    val base = "Select $title, radio button, $position of $total"
    return if (available && warning == null) base else "$base. ${warning ?: PAYMENT_RAIL_REGION_UNAVAILABLE}"
  }
}

private data class BaselineRail(
  val providerId: ProviderId,
  val method: PaymentMethod,
  val title: String,
  val fallbackName: String,
)

/** Adyen card and Worldpay bank are the only rails this client will offer. */
private val baselineRails = listOf(
  BaselineRail(ProviderId.adyen, PaymentMethod.card, "Debit card", "Adyen"),
  BaselineRail(ProviderId.worldpay, PaymentMethod.bank, "Bank payment", "Worldpay"),
)

/**
 * Builds the payment sheet from a resolved catalog. Rails outside the baseline pair are ignored.
 * A baseline rail that is absent, or present without its method, is shown disabled.
 */
fun resolvePaymentRails(providers: List<Provider>): List<PaymentMethodOption> {
  return baselineRails.map { rail ->
    val named = providers.firstOrNull { it.id == rail.providerId.name }
    val name = named?.name?.trim()?.takeIf { it.isNotEmpty() } ?: rail.fallbackName
    val match = named?.takeIf { provider -> provider.methods.contains(rail.method.name) }
    if (match == null) {
      PaymentMethodOption(
        method = rail.method,
        providerId = rail.providerId,
        title = rail.title,
        badge = "${rail.title} · $name",
        available = false,
        warning = PAYMENT_RAIL_REGION_UNAVAILABLE,
      )
    } else {
      PaymentMethodOption(
        method = rail.method,
        providerId = rail.providerId,
        title = rail.title,
        badge = paymentBadge(rail.title, match.name, match.description),
        available = true,
        warning = null,
      )
    }
  }
}

private fun paymentBadge(title: String, name: String, description: String): String {
  val trimmedName = name.trim().ifEmpty { title }
  val detail = description.trim()
  return if (detail.isEmpty()) "$title · $trimmedName" else "$title · $trimmedName ($detail)"
}
