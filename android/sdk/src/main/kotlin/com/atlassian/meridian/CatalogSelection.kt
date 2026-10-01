package com.atlassian.meridian

data class MethodChoice(
  val id: String,
  val method: String,
  val providerId: String,
  val providerName: String,
  val descriptor: String,
  val logoUrl: String?,
  val logoLabel: String,
  val methodLabel: String,
  val eligible: Boolean,
  val requiresBank: Boolean,
  val banks: List<BankChoice>,
)

data class MethodGroup(
  val descriptor: String,
  val methods: List<MethodChoice>,
)

data class SelectionState(
  val methodId: String? = null,
  val bankId: String? = null,
)

enum class SelectorContentState {
  loading, empty, ready
}

const val methodSelectorEmptyMessage = "No payment methods are available."
const val bankSelectorEmptyMessage = "No banks are available for this method."

fun logoLabel(name: String): String {
  val parts = name.split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
  val initials = parts.take(2).mapNotNull { it.firstOrNull()?.toString() }.joinToString("")
  val label = initials.uppercase()
  if (label.isNotEmpty()) return label.take(2)
  return "?"
}

fun methodLabel(method: String): String {
  return when (method.trim().lowercase()) {
    "card" -> "Debit card"
    "bank" -> "Bank payment"
    "" -> "Payment method"
    else -> {
      val trimmed = method.trim()
      trimmed.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
    }
  }
}

fun eligibilityLabel(eligible: Boolean): String = if (eligible) "Eligible" else "Unavailable"

fun payableMethod(raw: String): PaymentMethod? =
  PaymentMethod.values().firstOrNull { it.name.equals(raw.trim(), ignoreCase = true) }

fun descriptor(provider: Provider): String {
  val description = provider.description.trim()
  if (description.isNotEmpty()) return description
  val name = provider.name.trim()
  if (name.isNotEmpty()) return name
  return "Payment methods"
}

fun methodRequiresBank(method: String, provider: Provider): Boolean {
  provider.requiresBank?.let { return it }
  return method.trim().equals("bank", ignoreCase = true)
}

fun methodGroups(providers: List<Provider>): List<MethodGroup> {
  val order = mutableListOf<String>()
  val buckets = linkedMapOf<String, MutableList<MethodChoice>>()
  for (provider in providers) {
    val group = descriptor(provider)
    if (buckets[group] == null) {
      order.add(group)
      buckets[group] = mutableListOf()
    }
    provider.methods.forEachIndexed { index, method ->
      val name = provider.name.trim()
      buckets.getValue(group).add(
        MethodChoice(
          id = "${provider.id}|$method|$index",
          method = method,
          providerId = provider.id,
          providerName = name.ifEmpty { methodLabel(method) },
          descriptor = group,
          logoUrl = provider.logoUrl,
          logoLabel = logoLabel(if (name.isEmpty()) method else name),
          methodLabel = methodLabel(method),
          eligible = provider.eligible != false,
          requiresBank = methodRequiresBank(method, provider),
          banks = provider.banks.orEmpty(),
        )
      )
    }
  }
  return order.mapNotNull { key ->
    val methods = buckets[key].orEmpty()
    if (methods.isEmpty()) null else MethodGroup(key, methods)
  }
}

fun allMethodChoices(providers: List<Provider>): List<MethodChoice> =
  methodGroups(providers).flatMap { it.methods }

fun methodChoice(id: String?, providers: List<Provider>): MethodChoice? {
  if (id == null) return null
  return allMethodChoices(providers).firstOrNull { it.id == id }
}

fun reconciledSelection(current: SelectionState, providers: List<Provider>): SelectionState {
  val choices = allMethodChoices(providers)
  val method = choices.firstOrNull { it.id == current.methodId && it.eligible }
    ?: choices.firstOrNull { it.eligible }
  val bankId = if (method != null && method.requiresBank && current.bankId != null && method.banks.any { it.id == current.bankId }) {
    current.bankId
  } else {
    null
  }
  return SelectionState(methodId = method?.id, bankId = bankId)
}

fun filterBanks(banks: List<BankChoice>, query: String): List<BankChoice> {
  val trimmed = query.trim()
  if (trimmed.isEmpty()) return banks
  return banks.filter { bank ->
    bank.name.contains(trimmed, ignoreCase = true) || bank.id.contains(trimmed, ignoreCase = true)
  }
}

fun bankEmptyMessage(banks: List<BankChoice>, query: String): String {
  if (banks.isEmpty()) return bankSelectorEmptyMessage
  return "No banks match \"${query.trim()}\"."
}

fun methodSelectorState(loading: Boolean, groups: List<MethodGroup>): SelectorContentState {
  if (loading) return SelectorContentState.loading
  if (groups.isEmpty() || groups.all { it.methods.isEmpty() }) return SelectorContentState.empty
  return SelectorContentState.ready
}

fun bankSelectorState(loading: Boolean, banks: List<BankChoice>, query: String): SelectorContentState {
  if (loading) return SelectorContentState.loading
  if (filterBanks(banks, query).isEmpty()) return SelectorContentState.empty
  return SelectorContentState.ready
}

fun isRegularSelectorWidth(smallestWidthDp: Int): Boolean = smallestWidthDp >= 600

fun isLargeAccessibilityText(fontScale: Float): Boolean = fontScale >= 1.3f

fun selectorUsesFullScreen(isRegularWidth: Boolean, isAccessibilityText: Boolean): Boolean =
  isRegularWidth || isAccessibilityText
