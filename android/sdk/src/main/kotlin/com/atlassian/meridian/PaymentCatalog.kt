package com.atlassian.meridian

import kotlin.math.pow

// Customer-facing rails for the Adyen card / Worldpay bank baseline.
// Vendor names stay off the UI. No further provider is recognized.

const val paymentWideBreakpoint = 600.0

enum class PaymentCorridor(
  val code: String,
  val title: String,
  val summary: String,
  val eligibleMethods: Set<PaymentMethod>,
) {
  UNITED_KINGDOM(
    "GB",
    "United Kingdom",
    "Domestic debit and credit cards in GBP",
    setOf(PaymentMethod.card),
  ),
  EUROZONE(
    "EU",
    "Eurozone",
    "Cards and SEPA Instant Transfer in GBP",
    setOf(PaymentMethod.card, PaymentMethod.bank),
  ),
  OTHER(
    "XX",
    "Other destinations",
    "Destinations outside the supported rails",
    emptySet(),
  ),
}

data class PaymentOption(
  val method: PaymentMethod,
  val railLabel: String,
  val accessibilityLabel: String,
)

sealed class PaymentMethodPhase {
  data object Loading : PaymentMethodPhase()
  data class Unavailable(val message: String) : PaymentMethodPhase()
  data class Empty(val corridor: PaymentCorridor) : PaymentMethodPhase()
  data class Ready(val options: List<PaymentOption>) : PaymentMethodPhase()
}

data class ContrastColor(val red: Int, val green: Int, val blue: Int) {
  constructor(hex: Int) : this((hex shr 16) and 0xFF, (hex shr 8) and 0xFF, hex and 0xFF)

  val argb: Int get() = (0xFF shl 24) or (red shl 16) or (green shl 8) or blue
}

object PaymentTextColors {
  val ink = ContrastColor(0x142C35)
  val canvas = ContrastColor(0xF8F9F6)
  val surface = ContrastColor(0xFFFFFF)
  val secondary = ContrastColor(0x31464F)
  val onInk = ContrastColor(0xFFFFFF)
  val onInkMuted = ContrastColor(0xD5DFD7)
  val action = ContrastColor(0x1868DB)
  val selectedFill = ContrastColor(0xE7EEE8)
  val border = ContrastColor(0x3E5248)
  val shimmer = ContrastColor(0xE3E8E1)

  val textPairs: List<Pair<ContrastColor, ContrastColor>> = listOf(
    ink to surface,
    ink to canvas,
    secondary to surface,
    secondary to canvas,
    onInk to ink,
    onInkMuted to ink,
    onInk to action,
    ink to selectedFill,
    secondary to selectedFill,
  )

  val controlPairs: List<Pair<ContrastColor, ContrastColor>> = listOf(
    border to surface,
    action to surface,
    ink to surface,
  )
}

const val paymentMethodsLoadingLabel = "Loading payment methods"
const val paymentMethodsUnavailableLabel =
  "Payment methods couldn't be loaded. Check the connection and try again. Amounts stay in British pounds (GBP)."

fun railLabel(method: PaymentMethod): String = when (method) {
  PaymentMethod.card -> "Debit / Credit Card"
  PaymentMethod.bank -> "SEPA Instant Transfer"
}

fun railAccessibilityLabel(method: PaymentMethod): String = when (method) {
  PaymentMethod.card -> "Debit or credit card. Currency British pounds, GBP."
  PaymentMethod.bank -> "SEPA Instant Transfer. Currency British pounds, GBP."
}

fun corridorAccessibilityLabel(corridor: PaymentCorridor): String =
  "${corridor.title}. ${corridor.summary}. Currency British pounds, GBP."

fun railLabelForMethodName(name: String): String = when (name.lowercase()) {
  PaymentMethod.card.name -> railLabel(PaymentMethod.card)
  PaymentMethod.bank.name -> railLabel(PaymentMethod.bank)
  else -> "Payment"
}

/** Recognized baseline only: Adyen settles card, Worldpay settles bank. */
fun baselineMethod(providerId: String): PaymentMethod? = when (providerId.lowercase()) {
  ProviderId.adyen.name -> PaymentMethod.card
  ProviderId.worldpay.name -> PaymentMethod.bank
  else -> null
}

fun paymentOptions(catalog: CatalogResponse, corridor: PaymentCorridor): List<PaymentOption> {
  val eligible = corridor.eligibleMethods
  val seen = mutableSetOf<PaymentMethod>()
  val options = mutableListOf<PaymentOption>()
  for (provider in catalog.providers) {
    val method = baselineMethod(provider.id) ?: continue
    if (method !in eligible) continue
    if (provider.methods.none { it.equals(method.name, ignoreCase = true) }) continue
    if (!seen.add(method)) continue
    options += PaymentOption(
      method = method,
      railLabel = railLabel(method),
      accessibilityLabel = railAccessibilityLabel(method),
    )
  }
  return options
}

fun paymentMethodPhase(
  catalog: CatalogResponse?,
  retrieving: Boolean,
  failed: Boolean,
  corridor: PaymentCorridor,
): PaymentMethodPhase {
  if (catalog == null) {
    if (retrieving) return PaymentMethodPhase.Loading
    if (failed) return PaymentMethodPhase.Unavailable(paymentMethodsUnavailableLabel)
    return PaymentMethodPhase.Loading
  }
  val options = paymentOptions(catalog, corridor)
  if (options.isEmpty()) return PaymentMethodPhase.Empty(corridor)
  return PaymentMethodPhase.Ready(options)
}

fun emptyPaymentMethodsMessage(corridor: PaymentCorridor): String =
  "No payment methods are available for ${corridor.title}. None of the catalogued rails can be used for this corridor. Amounts stay in British pounds (GBP)."

fun containsVendorMark(text: String): Boolean {
  val folded = text.lowercase()
  return folded.contains("adyen") || folded.contains("worldpay")
}

/** Side-by-side rails only when the width still fits after font scaling. */
fun usesSideBySideRails(widthPoints: Double, fontScale: Double): Boolean {
  if (widthPoints <= 0.0 || fontScale <= 0.0) return false
  return widthPoints / fontScale >= paymentWideBreakpoint
}

fun contrastRatio(foreground: ContrastColor, background: ContrastColor): Double {
  val lighter = maxOf(relativeLuminance(foreground), relativeLuminance(background))
  val darker = minOf(relativeLuminance(foreground), relativeLuminance(background))
  return (lighter + 0.05) / (darker + 0.05)
}

private fun relativeLuminance(color: ContrastColor): Double {
  fun channel(value: Int): Double {
    val srgb = value / 255.0
    return if (srgb <= 0.04045) srgb / 12.92 else ((srgb + 0.055) / 1.055).pow(2.4)
  }
  return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
}
