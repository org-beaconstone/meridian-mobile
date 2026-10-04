package com.atlassian.meridian

const val PAYMENT_METHOD_UNAVAILABLE_TEXT =
  "This payment method is temporarily unavailable in your region."

data class CorridorContext(val region: String, val currency: String) {
  companion object {
    val gbp = CorridorContext(region = "GB", currency = "GBP")
  }
}

data class SelectablePaymentMethod(
  val id: String,
  val method: PaymentMethod,
  val title: String,
  val selectable: Boolean,
  val helperText: String?,
  val accessibilityLabel: String,
)

data class PaymentMethodSheetModel(
  val loading: Boolean,
  val options: List<SelectablePaymentMethod>,
) {
  val placeholderCount: Int get() = if (loading) 2 else 0
}

private data class BaselineMethod(
  val providerId: String,
  val method: PaymentMethod,
  val title: String,
)

private val baselineMethods = listOf(
  BaselineMethod("adyen", PaymentMethod.card, "Adyen Card"),
  BaselineMethod("worldpay", PaymentMethod.bank, "Worldpay"),
)

/**
 * Builds the GBP corridor sheet from the catalog. Entries outside the contracted
 * Adyen card and Worldpay bank pairing are omitted. An unavailable selection is
 * not replaced with the other method.
 */
fun paymentMethodSheetModel(
  providers: List<Provider>?,
  corridor: CorridorContext = CorridorContext.gbp,
): PaymentMethodSheetModel {
  if (providers == null) return PaymentMethodSheetModel(loading = true, options = emptyList())
  val corridorOpen = corridor.currency == "GBP" && corridor.region == "GB"
  val drafts = mutableListOf<Draft>()
  val seen = mutableSetOf<PaymentMethod>()
  for (provider in providers) {
    val baseline = baselineMethods.firstOrNull { it.providerId == provider.id } ?: continue
    if (baseline.method.name !in provider.methods) continue
    if (!seen.add(baseline.method)) continue
    val selectable = corridorOpen && isCatalogAvailable(provider.availability)
    drafts.add(Draft(provider.id, baseline.method, baseline.title, selectable))
  }
  val options = drafts.mapIndexed { index, draft ->
    SelectablePaymentMethod(
      id = draft.id,
      method = draft.method,
      title = draft.title,
      selectable = draft.selectable,
      helperText = if (draft.selectable) null else PAYMENT_METHOD_UNAVAILABLE_TEXT,
      accessibilityLabel = "Select ${draft.title}, radio button, ${index + 1} of ${drafts.size}",
    )
  }
  return PaymentMethodSheetModel(loading = false, options = options)
}

fun submittablePaymentMethod(
  selected: PaymentMethod,
  model: PaymentMethodSheetModel,
): PaymentMethod? {
  if (model.loading) return null
  val option = model.options.firstOrNull { it.method == selected } ?: return null
  if (!option.selectable) return null
  return selected
}

fun paymentMethodBlockMessage(
  selected: PaymentMethod,
  model: PaymentMethodSheetModel,
): String? {
  if (submittablePaymentMethod(selected, model) != null) return null
  if (model.loading) return "Payment methods are still loading."
  return model.options.firstOrNull { it.method == selected }?.helperText
    ?: "Choose an available payment method."
}

private fun isCatalogAvailable(availability: String?): Boolean {
  val status = availability?.trim()?.lowercase() ?: "available"
  return status == "available"
}

private data class Draft(
  val id: String,
  val method: PaymentMethod,
  val title: String,
  val selectable: Boolean,
)
