package com.atlassian.meridian

import com.fasterxml.jackson.core.JsonParser
import com.fasterxml.jackson.databind.DeserializationContext
import com.fasterxml.jackson.databind.JsonDeserializer
import com.fasterxml.jackson.databind.JsonMappingException
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.node.ObjectNode
import kotlin.math.round

/**
 * Consumer contract for catalog and payment-intent payloads.
 * Legacy documents use integer GBP pence. Newer documents use a money
 * object. Only GBP with minor unit 2 is payable. Card stays Adyen and
 * bank stays Worldpay.
 */
object ConsumerContract {
  const val version: String = "1"
  const val acceptedCurrency: String = "GBP"
  private val mapper = ObjectMapper()

  fun evaluateCatalog(json: String): ContractResult {
    val root = readObject(json) ?: return rejected("MALFORMED_CATALOG", "invalid_json")
    return evaluateCatalogObject(root)
  }

  fun evaluatePaymentIntent(json: String): ContractResult {
    val root = readObject(json) ?: return rejected("MALFORMED_INTENT", "invalid_json")
    return evaluateIntentObject(root)
  }

  fun evaluateTransaction(json: String): ContractResult {
    val root = readObject(json) ?: return rejected("MALFORMED_AMOUNT", "invalid_json")
    val amount = root.get("amount") ?: return rejected("MALFORMED_AMOUNT", "missing_amount")
    return try {
      val money = parseMoneyNode(amount)
      accepted(
        currency = money.currency,
        minorUnit = 2,
        amountMinor = money.minor,
        legacyShape = money.legacyShape,
        provider = root.path("provider").asText(null),
        method = root.path("method").asText(null),
      )
    } catch (error: ContractRejection) {
      rejected(error.code, error.message ?: error.code)
    }
  }

  fun encodeLegacyPaymentIntent(
    recipientId: String,
    amountMinor: Int,
    method: String,
    note: String,
    scenario: String,
  ): String {
    val payload = linkedMapOf(
      "amountMinor" to amountMinor,
      "method" to method,
      "note" to note,
      "recipientId" to recipientId,
      "scenario" to scenario,
    )
    return mapper.writeValueAsString(payload)
  }
}

class ContractRejection(val code: String, message: String) : Exception(message)

data class ContractResult(
  val accepted: Boolean,
  val code: String,
  val detail: String,
  val currency: String? = null,
  val minorUnit: Int? = null,
  val amountMinor: Int? = null,
  val legacyShape: Boolean? = null,
  val providerIds: List<String> = emptyList(),
  val recipientIds: List<String> = emptyList(),
  val method: String? = null,
  val provider: String? = null,
)

data class ParsedMoney(val minor: Int, val currency: String, val legacyShape: Boolean)

fun parseMoneyNode(node: JsonNode): ParsedMoney {
  if (node.isObject) {
    val minorNode = node.get("minor") ?: throw ContractRejection("MALFORMED_AMOUNT", "missing_minor")
    if (!minorNode.isIntegralNumber) throw ContractRejection("MALFORMED_AMOUNT", "fractional_minor")
    val currency = node.get("currency")?.asText() ?: throw ContractRejection("MALFORMED_AMOUNT", "missing_currency")
    if (currency != "GBP") throw ContractRejection("UNSUPPORTED_CURRENCY", currency)
    val minorUnit = node.get("minorUnit")
    if (minorUnit != null && (!minorUnit.isIntegralNumber || minorUnit.intValue() != 2)) {
      throw ContractRejection("INVALID_MINOR_UNIT", "minor_unit")
    }
    return ParsedMoney(minorNode.intValue(), "GBP", false)
  }
  if (node.isIntegralNumber) return ParsedMoney(node.intValue(), "GBP", true)
  throw ContractRejection("MALFORMED_AMOUNT", "fractional_minor")
}

class TransactionDeserializer : JsonDeserializer<Transaction>() {
  override fun deserialize(parser: JsonParser, context: DeserializationContext): Transaction {
    val node = parser.codec.readTree<JsonNode>(parser)
    try {
      val amountNode = node.get("amount") ?: throw ContractRejection("MALFORMED_AMOUNT", "missing_amount")
      val money = parseMoneyNode(amountNode)
      return Transaction(
        id = requiredText(node, "id"),
        reference = requiredText(node, "reference"),
        recipientId = requiredText(node, "recipientId"),
        name = requiredText(node, "name"),
        category = requiredText(node, "category"),
        amount = money.minor,
        date = requiredText(node, "date"),
        provider = requiredText(node, "provider"),
        method = requiredText(node, "method"),
        status = requiredText(node, "status"),
        note = requiredText(node, "note"),
      )
    } catch (error: ContractRejection) {
      throw JsonMappingException.from(parser, "${error.code}:${error.message}")
    }
  }

  private fun requiredText(node: JsonNode, field: String): String {
    val value = node.get(field) ?: throw ContractRejection("MALFORMED_AMOUNT", "missing_$field")
    if (!value.isTextual) throw ContractRejection("MALFORMED_AMOUNT", "missing_$field")
    return value.asText()
  }
}

fun CatalogResponse.assertConsumerContract() {
  val result = validateCatalogFields(
    demoDate = demoDate,
    currency = currency,
    minorUnit = minorUnit,
    legacyShape = false,
    recipients = recipients.map {
      RecipientDraft(it.id, it.name, it.initials, it.detail, it.category, it.color)
    },
    providers = providers.map { ProviderDraft(it.id, it.name, it.description, it.methods) },
  )
  if (!result.accepted) throw ContractRejection(result.code, result.detail)
}

data class RecipientDraft(
  val id: String,
  val name: String,
  val initials: String,
  val detail: String,
  val category: String,
  val color: String,
)

data class ProviderDraft(
  val id: String,
  val name: String,
  val description: String,
  val methods: List<String>,
)

fun providerForMethod(method: String): String? = when (method) {
  "card" -> "adyen"
  "bank" -> "worldpay"
  else -> null
}

fun layoutDirectionForLanguage(language: String): String {
  val code = language.lowercase().split('-', '_').firstOrNull().orEmpty()
  return if (code in setOf("ar", "he", "fa", "ur", "dv", "ps")) "rtl" else "ltr"
}

fun fontScaleFor(bucket: String): Double = when (bucket) {
  "large" -> 1.3
  "accessibility" -> 2.0
  else -> 1.0
}

fun scaledFontSize(base: Double, fontScale: Double): Double {
  val clamped = fontScale.coerceIn(1.0, 3.0)
  return round(base * clamped * 10.0) / 10.0
}

data class AccessibilityDescriptor(
  val platform: String,
  val label: String,
  val hint: String,
  val role: String,
  val fontScale: Double,
  val scaledFontPt: Double,
  val layoutDirection: String,
  val minimumTouchTargetPt: Int,
  val mirrorsInRightToLeft: Boolean,
)

fun paymentConfirmationAccessibility(
  amountLabel: String,
  recipientName: String,
  method: String,
  language: String,
  fontScale: Double,
  platform: String,
): AccessibilityDescriptor {
  val methodPhrase = if (method == "bank") "bank payment, Worldpay" else "debit card, Adyen"
  val minimum = if (platform == "talkback") 48 else 44
  return AccessibilityDescriptor(
    platform = platform,
    label = "Confirm payment of $amountLabel to $recipientName using $methodPhrase",
    hint = "Submits the fictional rehearsal payment. No real money moves.",
    role = "button",
    fontScale = fontScale,
    scaledFontPt = scaledFontSize(38.0, fontScale),
    layoutDirection = layoutDirectionForLanguage(language),
    minimumTouchTargetPt = minimum,
    mirrorsInRightToLeft = true,
  )
}

private fun readObject(json: String): ObjectNode? = try {
  val node = ObjectMapper().readTree(json)
  node as? ObjectNode
} catch (_: Exception) {
  null
}

private fun rejected(code: String, detail: String) = ContractResult(accepted = false, code = code, detail = detail)

private fun accepted(
  currency: String,
  minorUnit: Int,
  amountMinor: Int?,
  legacyShape: Boolean,
  providerIds: List<String> = emptyList(),
  recipientIds: List<String> = emptyList(),
  method: String? = null,
  provider: String? = null,
) = ContractResult(
  accepted = true,
  code = "OK",
  detail = "",
  currency = currency,
  minorUnit = minorUnit,
  amountMinor = amountMinor,
  legacyShape = legacyShape,
  providerIds = providerIds,
  recipientIds = recipientIds,
  method = method,
  provider = provider,
)

private fun evaluateCatalogObject(root: ObjectNode): ContractResult {
  val legacyShape = !root.has("currency") && !root.has("minorUnit")
  if (root.has("currency")) {
    val currencyNode = root.get("currency")
    if (!currencyNode.isTextual) return rejected("MALFORMED_CATALOG", "currency_type")
    if (currencyNode.asText() != "GBP") return rejected("UNSUPPORTED_CURRENCY", currencyNode.asText())
  }
  val minorUnit = if (root.has("minorUnit")) {
    val node = root.get("minorUnit")
    if (!node.isIntegralNumber || node.intValue() != 2) return rejected("INVALID_MINOR_UNIT", "minor_unit")
    node.intValue()
  } else {
    2
  }
  if (!root.path("recipients").isArray) return rejected("MALFORMED_CATALOG", "missing_recipients")
  if (!root.path("providers").isArray) return rejected("MALFORMED_CATALOG", "missing_providers")
  val recipients = root.path("recipients").map { row ->
    RecipientDraft(
      id = row.path("id").asText(""),
      name = row.path("name").asText(""),
      initials = row.path("initials").asText(""),
      detail = row.path("detail").asText(""),
      category = row.path("category").asText(""),
      color = row.path("color").asText(""),
    )
  }
  val providers = root.path("providers").map { row ->
    ProviderDraft(
      id = row.path("id").asText(""),
      name = row.path("name").asText(""),
      description = row.path("description").asText(""),
      methods = row.path("methods").map { it.asText() },
    )
  }
  return validateCatalogFields(
    demoDate = root.path("demoDate").asText(""),
    currency = if (root.has("currency")) root.path("currency").asText() else "GBP",
    minorUnit = minorUnit,
    legacyShape = legacyShape,
    recipients = recipients,
    providers = providers,
  )
}

fun validateCatalogFields(
  demoDate: String,
  currency: String,
  minorUnit: Int,
  legacyShape: Boolean,
  recipients: List<RecipientDraft>,
  providers: List<ProviderDraft>,
): ContractResult {
  if (currency != "GBP") return rejected("UNSUPPORTED_CURRENCY", currency)
  if (minorUnit != 2) return rejected("INVALID_MINOR_UNIT", "minor_unit")
  val issues = mutableListOf<String>()
  if (demoDate.isBlank()) issues += "missing_demo_date"
  if (recipients.isEmpty()) issues += "empty_recipients"
  val categories = setOf("Shopping", "Food & drink", "Transport", "Bills", "Lifestyle")
  val seenRecipients = mutableListOf<String>()
  for (recipient in recipients) {
    val id = recipient.id.trim()
    if (id.isEmpty()) issues += "empty_recipient_id"
    else if (id in seenRecipients) issues += "duplicate_recipient"
    else seenRecipients += id
    if (recipient.name.isBlank()) issues += "missing_name"
    if (recipient.initials.isBlank()) issues += "missing_initials"
    if (recipient.detail.isBlank()) issues += "missing_detail"
    if (recipient.color.isBlank()) issues += "missing_color"
    if (recipient.category !in categories) issues += "unknown_category"
  }
  val baseline = mapOf("adyen" to listOf("card"), "worldpay" to listOf("bank"))
  val seenProviders = mutableListOf<String>()
  for (provider in providers) {
    val expected = baseline[provider.id]
    if (expected == null) {
      issues += "unknown_provider"
      continue
    }
    if (provider.methods != expected) issues += "provider_method_mismatch"
    if (provider.name.isBlank()) issues += "missing_provider_name"
    if (provider.description.isBlank()) issues += "missing_provider_description"
    if (provider.id in seenProviders) issues += "duplicate_provider" else seenProviders += provider.id
  }
  if ("adyen" !in seenProviders || "worldpay" !in seenProviders) issues += "missing_baseline_provider"
  if (issues.isNotEmpty()) return rejected("MALFORMED_CATALOG", issues.joinToString(","))
  return accepted(
    currency = "GBP",
    minorUnit = 2,
    amountMinor = null,
    legacyShape = legacyShape,
    providerIds = seenProviders.sorted(),
    recipientIds = seenRecipients,
  )
}

private fun evaluateIntentObject(root: ObjectNode): ContractResult {
  val recipientId = root.path("recipientId").asText("")
  if (recipientId.isBlank()) return rejected("MALFORMED_INTENT", "missing_recipient")
  val method = root.path("method").asText("")
  val provider = providerForMethod(method) ?: return rejected("MALFORMED_INTENT", "unknown_method")
  val scenario = if (root.has("scenario")) root.path("scenario").asText("") else "success"
  if (scenario !in setOf("success", "declined", "unavailable", "pending")) {
    return rejected("MALFORMED_INTENT", "unknown_scenario")
  }
  if (root.has("note") && !root.get("note").isTextual) return rejected("MALFORMED_INTENT", "note_type")
  val note = root.path("note").asText("")
  if (note.length > 200) return rejected("MALFORMED_INTENT", "note_too_long")
  val hasMinor = root.has("amountMinor")
  val hasObject = root.has("amount")
  if (hasMinor && hasObject) return rejected("MALFORMED_INTENT", "conflicting_amount")
  if (!hasMinor && !hasObject) return rejected("MALFORMED_AMOUNT", "missing_amount")
  val parsed = if (hasMinor) {
    val node = root.get("amountMinor")
    if (!node.isIntegralNumber) return rejected("MALFORMED_AMOUNT", "fractional_minor")
    val minor = node.intValue()
    if (minor <= 0 || minor > 1_000_000) return rejected("MALFORMED_AMOUNT", "amount_out_of_range")
    ParsedMoney(minor, "GBP", true)
  } else {
    try {
      val money = parseMoneyNode(root.get("amount"))
      if (money.legacyShape) return rejected("MALFORMED_AMOUNT", "amount_shape")
      if (money.minor <= 0 || money.minor > 1_000_000) return rejected("MALFORMED_AMOUNT", "amount_out_of_range")
      money
    } catch (error: ContractRejection) {
      return rejected(error.code, error.message ?: error.code)
    }
  }
  return accepted(
    currency = parsed.currency,
    minorUnit = 2,
    amountMinor = parsed.minor,
    legacyShape = parsed.legacyShape,
    method = method,
    provider = provider,
  )
}
