package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule

private val contractMapper = ObjectMapper().registerKotlinModule()

data class CatalogRecipient(
  val id: String,
  val name: String,
  val initials: String,
  val detail: String,
  val category: String,
  val color: String,
  val price: Money?,
)

data class CatalogProvider(
  val id: String,
  val name: String,
  val description: String,
  val methods: List<String>,
)

data class CatalogDocument(
  val demoDate: String,
  val recipients: List<CatalogRecipient>,
  val providers: List<CatalogProvider>,
)

data class PaymentIntent(
  val recipientId: String,
  val money: Money,
  val method: String,
  val note: String,
  val scenario: String,
) {
  val submittable: Boolean get() = money.gbpPence?.let { it in 1..1_000_000 } == true
  val wireAmountMinor: Int? get() = if (submittable) money.gbpPence else null
}

private val categories = setOf("Shopping", "Food & drink", "Transport", "Bills", "Lifestyle")
private val providerMethods = mapOf("adyen" to listOf("card"), "worldpay" to listOf("bank"))
private val providerNames = mapOf("adyen" to "Adyen", "worldpay" to "Worldpay")
private val scenarios = setOf("success", "declined", "unavailable", "pending")

fun decodeCatalog(node: JsonNode): Decoded<CatalogDocument> {
  if (!node.isObject) return Decoded.Err(ContractError("MALFORMED_CATALOG", "Catalog must be an object"))
  val demoDate = node.get("demoDate")?.takeIf { it.isTextual }?.asText()
    ?: return Decoded.Err(ContractError("MALFORMED_CATALOG", "demoDate is required"))
  if (!isCalendarDate(demoDate)) return Decoded.Err(ContractError("MALFORMED_CATALOG", "demoDate is not a calendar date"))
  val recipientNodes = node.get("recipients")?.takeIf { it.isArray }
    ?: return Decoded.Err(ContractError("MALFORMED_CATALOG", "recipients are required"))
  val providerNodes = node.get("providers")?.takeIf { it.isArray }
    ?: return Decoded.Err(ContractError("MALFORMED_CATALOG", "providers are required"))
  val recipients = mutableListOf<CatalogRecipient>()
  val seenIds = mutableSetOf<String>()
  for (recipient in recipientNodes) {
    val decoded = decodeRecipient(recipient)
    if (decoded is Decoded.Err) return decoded
    val value = (decoded as Decoded.Ok).value
    if (!seenIds.add(value.id)) return Decoded.Err(ContractError("MALFORMED_CATALOG", "Duplicate recipient"))
    recipients += value
  }
  val providers = mutableListOf<CatalogProvider>()
  val seenProviders = mutableSetOf<String>()
  for (provider in providerNodes) {
    if (!provider.isObject) return Decoded.Err(ContractError("MALFORMED_CATALOG", "Provider must be an object"))
    val id = provider.get("id")?.takeIf { it.isTextual }?.asText()
      ?: return Decoded.Err(ContractError("MALFORMED_CATALOG", "Provider id is required"))
    if (id !in providerMethods) return Decoded.Err(ContractError("UNKNOWN_PROVIDER", "Provider is not in the mobile baseline"))
    if (!seenProviders.add(id)) return Decoded.Err(ContractError("MALFORMED_CATALOG", "Duplicate provider"))
    val name = provider.get("name")?.takeIf { it.isTextual }?.asText()?.trim().orEmpty()
    val description = provider.get("description")?.takeIf { it.isTextual }?.asText()?.trim().orEmpty()
    val methodsNode = provider.get("methods")
    if (name != providerNames[id] || description.isEmpty() || methodsNode == null || !methodsNode.isArray) {
      return Decoded.Err(ContractError("MALFORMED_CATALOG", "Provider fields are invalid"))
    }
    val methods = methodsNode.map { if (it.isTextual) it.asText() else "" }
    if (methods != providerMethods[id]) return Decoded.Err(ContractError("MALFORMED_CATALOG", "Provider methods do not match the baseline"))
    providers += CatalogProvider(id, name, description, methods)
  }
  if (seenProviders != providerMethods.keys) {
    return Decoded.Err(ContractError("MALFORMED_CATALOG", "Catalog must list Adyen and Worldpay"))
  }
  return Decoded.Ok(CatalogDocument(demoDate, recipients, providers))
}

private fun decodeRecipient(node: JsonNode): Decoded<CatalogRecipient> {
  if (!node.isObject) return Decoded.Err(ContractError("MALFORMED_CATALOG", "Recipient must be an object"))
  val id = node.get("id")?.takeIf { it.isTextual }?.asText()?.trim().orEmpty()
  val name = node.get("name")?.takeIf { it.isTextual }?.asText()?.trim().orEmpty()
  val initials = node.get("initials")?.takeIf { it.isTextual }?.asText()?.trim().orEmpty()
  val detail = node.get("detail")?.takeIf { it.isTextual }?.asText()?.trim().orEmpty()
  val category = node.get("category")?.takeIf { it.isTextual }?.asText().orEmpty()
  val color = node.get("color")?.takeIf { it.isTextual }?.asText().orEmpty()
  if (!Regex("^[a-z0-9-]{1,64}$").matches(id)) return Decoded.Err(ContractError("MALFORMED_CATALOG", "Recipient id is invalid"))
  if (name.isEmpty() || name.length > 80 || name.any { it < ' ' }) return Decoded.Err(ContractError("MALFORMED_CATALOG", "Recipient name is invalid"))
  if (!Regex("^[A-Za-z0-9]{1,4}$").matches(initials)) return Decoded.Err(ContractError("MALFORMED_CATALOG", "Recipient initials are invalid"))
  if (detail.isEmpty() || detail.length > 120) return Decoded.Err(ContractError("MALFORMED_CATALOG", "Recipient detail is invalid"))
  if (category !in categories) return Decoded.Err(ContractError("MALFORMED_CATALOG", "Recipient category is invalid"))
  if (!Regex("^#[0-9A-Fa-f]{6}$").matches(color)) return Decoded.Err(ContractError("MALFORMED_CATALOG", "Recipient color is invalid"))
  val priceNode = node.get("price")
  val price = if (priceNode == null || priceNode.isNull) {
    null
  } else {
    when (val decoded = decodeMoney(priceNode)) {
      is Decoded.Err -> return decoded
      is Decoded.Ok -> decoded.value
    }
  }
  return Decoded.Ok(CatalogRecipient(id, name, initials, detail, category, color, price))
}

fun decodePaymentIntent(node: JsonNode): Decoded<PaymentIntent> {
  if (!node.isObject) return Decoded.Err(ContractError("MALFORMED_INTENT", "Payment intent must be an object"))
  val recipientId = node.get("recipientId")?.takeIf { it.isTextual }?.asText()?.trim().orEmpty()
  if (!Regex("^[a-z0-9-]{1,64}$").matches(recipientId)) {
    return Decoded.Err(ContractError("MALFORMED_INTENT", "Recipient is invalid"))
  }
  val method = node.get("method")?.takeIf { it.isTextual }?.asText().orEmpty()
  if (method != "card" && method != "bank") return Decoded.Err(ContractError("MALFORMED_INTENT", "Payment method is invalid"))
  val noteNode = node.get("note")
  val note = if (noteNode == null || noteNode.isNull) "" else if (noteNode.isTextual) noteNode.asText() else return Decoded.Err(ContractError("MALFORMED_INTENT", "Note is invalid"))
  if (note.length > 200) return Decoded.Err(ContractError("MALFORMED_INTENT", "Note is too long"))
  val scenarioNode = node.get("scenario")
  val scenario = if (scenarioNode == null || scenarioNode.isNull) "success" else if (scenarioNode.isTextual) scenarioNode.asText() else return Decoded.Err(ContractError("MALFORMED_INTENT", "Scenario is invalid"))
  if (scenario !in scenarios) return Decoded.Err(ContractError("MALFORMED_INTENT", "Scenario is invalid"))
  val amountNode = node.get("amountMinor")
  val moneyNode = node.get("money")
  if ((amountNode == null || amountNode.isNull) && (moneyNode == null || moneyNode.isNull)) {
    return Decoded.Err(ContractError("MISSING_AMOUNT", "Amount is required"))
  }
  val legacy = if (amountNode == null || amountNode.isNull) null else when (val decoded = decodeMoney(amountNode)) {
    is Decoded.Err -> return decoded
    is Decoded.Ok -> decoded.value
  }
  val modern = if (moneyNode == null || moneyNode.isNull) null else when (val decoded = decodeMoney(moneyNode)) {
    is Decoded.Err -> return decoded
    is Decoded.Ok -> decoded.value
  }
  val money = when {
    legacy != null && modern != null -> {
      if (modern.currency != "GBP" || modern.exponent != 2 || modern.minor != legacy.minor) {
        return Decoded.Err(ContractError("CONFLICTING_AMOUNT", "Integer amount and money object disagree"))
      }
      modern
    }
    modern != null -> modern
    else -> legacy!!
  }
  return Decoded.Ok(PaymentIntent(recipientId, money, method, note, scenario))
}

fun decodeLiveCatalog(catalog: CatalogResponse): Decoded<CatalogDocument> =
  decodeCatalog(contractMapper.valueToTree(catalog))

fun validateLiveCatalog(catalog: CatalogResponse): ContractError? =
  when (val decoded = decodeLiveCatalog(catalog)) {
    is Decoded.Ok -> null
    is Decoded.Err -> decoded.error
  }

fun liveCatalogRoundTripFailure(): String? {
  val catalog = CatalogResponse(
    demoDate = "2026-09-18",
    recipients = listOf(
      Recipient("northline-studio", "Northline Studio", "NS", "Design tools & materials", "Shopping", "#FF6B6B"),
      Recipient("birch-bloom", "Birch & Bloom", "BB", "Organic café & bistro", "Food & drink", "#FFD93D"),
    ),
    providers = listOf(
      Provider("adyen", "Adyen", "Card payment processor", listOf("card")),
      Provider("worldpay", "Worldpay", "Bank transfer processor", listOf("bank")),
    ),
  )
  val error = validateLiveCatalog(catalog)
  return if (error == null) null else "live-catalog ${error.code}: ${error.message}"
}
