package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.node.ObjectNode
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.io.File
import java.nio.file.Files
import kotlin.math.abs

/**
 * Consumer contracts and cross-platform scenarios shared with the Swift SDK.
 * Live rehearsal submits integer GBP pence on Adyen card or Worldpay bank.
 * EUR amounts decode for the newer money model and are not posted.
 */

private val contractMapper = ObjectMapper().registerKotlinModule()

fun formatMinorUnits(minorUnits: Int, currency: String): String {
  val negative = minorUnits < 0
  val units = abs(minorUnits.toLong())
  val major = (units / 100).toInt()
  val minor = (units % 100).toInt()
  val symbol = when (currency) {
    "GBP" -> "£"
    "EUR" -> "€"
    else -> currency
  }
  val sign = if (negative) "-" else ""
  return "$sign$symbol${groupedMajorUnits(major)}.${minor.toString().padStart(2, '0')}"
}

internal fun groupedMajorUnits(value: Int): String {
  val digits = value.toString()
  val grouped = StringBuilder()
  digits.reversed().forEachIndexed { index, character ->
    if (index != 0 && index % 3 == 0) grouped.append(',')
    grouped.append(character)
  }
  return grouped.reverse().toString()
}

object AccessibilityCopy {
  const val balanceBaseSp = 38.0
  const val confirmLabel = "Confirm payment"
  const val confirmHint = "Submits the reviewed GBP payment. No real money moves."
  const val confirmTalkBack = "$confirmLabel. $confirmHint"
  const val arrangement = "start"

  fun balanceLabel(formatted: String): String = "Everyday account balance, $formatted"

  fun scaledBalanceSp(fontScale: Double): Double = balanceBaseSp * fontScale

  fun minimumTouchTargetDp(fontScale: Double): Double = 48.0 * maxOf(fontScale, 1.0)

  fun startEdge(direction: String): String = if (direction == "rtl") "right" else "left"

  fun balance(
    minorUnits: Int,
    currency: String,
    fontScale: Double,
    direction: String,
  ): BalanceAccessibility {
    val amount = formatMinorUnits(minorUnits, currency)
    val label = balanceLabel(amount)
    return BalanceAccessibility(
      voiceOverLabel = label,
      talkBackDescription = label,
      scaledSp = scaledBalanceSp(fontScale),
      minimumTouchTargetDp = minimumTouchTargetDp(fontScale),
      startEdge = startEdge(direction),
      arrangement = arrangement,
      amountText = amount,
      amountDirection = "ltr",
    )
  }
}

data class BalanceAccessibility(
  val voiceOverLabel: String,
  val talkBackDescription: String,
  val scaledSp: Double,
  val minimumTouchTargetDp: Double,
  val startEdge: String,
  val arrangement: String,
  val amountText: String,
  val amountDirection: String,
)

data class DecodedIntent(
  val recipientId: String,
  val minorUnits: Int,
  val currency: String,
  val method: String,
  val note: String,
  val scenario: String,
  val providerId: String,
  val submittable: Boolean,
)

data class MoneySample(
  val providerId: String,
  val minorUnits: Int,
  val currency: String,
)

data class CatalogView(
  val recipientIds: List<String>,
  val providerIds: List<String>,
  val currencies: Map<String, List<String>>,
  val samples: List<MoneySample>,
  val rejections: List<String>,
) {
  val accepted: Boolean get() = rejections.isEmpty()
}

sealed class Decode<out T> {
  data class Ok<T>(val value: T) : Decode<T>()
  data class Reject(val reason: String) : Decode<Nothing>()
}

data class CatalogCache(
  val body: String,
  val fetchedAtEpochMs: Long,
  val ttlMs: Long,
) {
  fun isFresh(nowEpochMs: Long): Boolean =
    nowEpochMs >= fetchedAtEpochMs && nowEpochMs - fetchedAtEpochMs < ttlMs
}

data class PersistedIntent(
  val idempotencyKey: String,
  val recipientId: String,
  val minorUnits: Int,
  val currency: String,
  val method: String,
  val note: String,
  val providerId: String,
)

data class IssuedReturn(
  val nonce: String,
  val paymentId: String,
  val expiresAtEpochMs: Long,
  val consumed: Boolean,
)

sealed class ReturnDecision {
  data class Accepted(val paymentId: String) : ReturnDecision()
  data class Rejected(val reason: String) : ReturnDecision()
}

class SessionCheckpoint(private val directory: File) {
  private val intentFile = File(directory, "intent.json")
  private val returnsFile = File(directory, "returns.json")
  private val cacheFile = File(directory, "catalog-cache.json")

  init {
    directory.mkdirs()
  }

  fun begin(intent: PersistedIntent): PersistedIntent {
    loadIntent()?.let { return it }
    intentFile.writeText(contractMapper.writeValueAsString(intent))
    return intent
  }

  fun loadIntent(): PersistedIntent? {
    if (!intentFile.isFile) return null
    return contractMapper.readValue(intentFile, PersistedIntent::class.java)
  }

  fun issueReturn(nonce: String, paymentId: String, expiresAtEpochMs: Long) {
    val current = loadReturns().filterNot { it.nonce == nonce }
    val next = current + IssuedReturn(nonce, paymentId, expiresAtEpochMs, consumed = false)
    returnsFile.writeText(contractMapper.writeValueAsString(next))
  }

  fun consume(url: String, nowEpochMs: Long): ReturnDecision {
    val parsed = parseReturnLink(url) ?: return ReturnDecision.Rejected("malformed deep link")
    val issued = loadReturns()
    val match = issued.find { it.nonce == parsed.nonce && it.paymentId == parsed.paymentId }
      ?: return ReturnDecision.Rejected("unknown return state")
    if (nowEpochMs >= match.expiresAtEpochMs) return ReturnDecision.Rejected("expired return state")
    if (match.consumed) return ReturnDecision.Rejected("replayed deep link")
    val updated = issued.map {
      if (it.nonce == match.nonce) it.copy(consumed = true) else it
    }
    returnsFile.writeText(contractMapper.writeValueAsString(updated))
    return ReturnDecision.Accepted(match.paymentId)
  }

  fun writeCache(cache: CatalogCache) {
    cacheFile.writeText(contractMapper.writeValueAsString(cache))
  }

  fun readCache(nowEpochMs: Long): CatalogCache? {
    if (!cacheFile.isFile) return null
    val cache = contractMapper.readValue(cacheFile, CatalogCache::class.java)
    return if (cache.isFresh(nowEpochMs)) cache else null
  }

  private fun loadReturns(): List<IssuedReturn> {
    if (!returnsFile.isFile) return emptyList()
    val type = contractMapper.typeFactory.constructCollectionType(List::class.java, IssuedReturn::class.java)
    return contractMapper.readValue(returnsFile, type)
  }
}

data class ParsedReturnLink(val nonce: String, val paymentId: String)

fun parseReturnLink(url: String): ParsedReturnLink? {
  val prefix = "meridian://payments/return?"
  if (!url.startsWith(prefix)) return null
  val params = url.removePrefix(prefix).split("&").mapNotNull { part ->
    val pieces = part.split("=", limit = 2)
    if (pieces.size == 2 && pieces[0].isNotEmpty() && pieces[1].isNotEmpty()) pieces[0] to pieces[1] else null
  }.toMap()
  val nonce = params["state"] ?: return null
  val paymentId = params["paymentId"] ?: return null
  return ParsedReturnLink(nonce, paymentId)
}

fun readContractTree(file: File): JsonNode = contractMapper.readTree(file)

fun decodePaymentIntent(body: JsonNode): Decode<DecodedIntent> {
  val recipientId = textOrNull(body, "recipientId")
  if (recipientId.isNullOrBlank()) return Decode.Reject("recipient id is required")
  val method = textOrNull(body, "method")
  val providerId = when (method) {
    "card" -> "adyen"
    "bank" -> "worldpay"
    else -> return Decode.Reject("unsupported payment method")
  }
  val scenario = textOrNull(body, "scenario")
    ?: return Decode.Reject("unknown scenario")
  if (scenario !in setOf("success", "declined", "unavailable", "pending")) {
    return Decode.Reject("unknown scenario")
  }
  val note = if (body.has("note") && !body.get("note").isNull) body.get("note").asText() else ""
  val money = decodeMoney(body) 
  when (money) {
    is Decode.Reject -> return money
    is Decode.Ok -> {
      val amount = money.value
      val submittable = amount.currency == "GBP" && amount.minorUnits in 1..1_000_000
      return Decode.Ok(
        DecodedIntent(
          recipientId = recipientId,
          minorUnits = amount.minorUnits,
          currency = amount.currency,
          method = method,
          note = note,
          scenario = scenario,
          providerId = providerId,
          submittable = submittable,
        )
      )
    }
  }
}

private data class MoneyParts(val minorUnits: Int, val currency: String)

private fun decodeMoney(body: JsonNode): Decode<MoneyParts> {
  val amountNode = if (body.has("amount") && !body.get("amount").isNull) body.get("amount") else body.get("amountMinor")
    ?: return Decode.Reject("minor units must be an integer")
  return decodeMoneyNode(amountNode)
}

private fun decodeMoneyNode(node: JsonNode): Decode<MoneyParts> {
  if (node.isObject) {
    val raw = when {
      node.has("minorUnits") -> node.get("minorUnits")
      node.has("amountMinor") -> node.get("amountMinor")
      else -> return Decode.Reject("minor units must be an integer")
    }
    val units = integralMinor(raw) ?: return Decode.Reject("minor units must be an integer")
    if (units <= 0) return Decode.Reject("minor units must be positive")
    val currencyNode = node.get("currency")
    val currency = if (currencyNode == null || currencyNode.isNull) "GBP" else currencyNode.asText()
    if (currency != "GBP" && currency != "EUR") return Decode.Reject("unknown currency")
    return Decode.Ok(MoneyParts(units, currency))
  }
  val units = integralMinor(node) ?: return Decode.Reject("minor units must be an integer")
  if (units <= 0) return Decode.Reject("minor units must be positive")
  return Decode.Ok(MoneyParts(units, "GBP"))
}

private fun integralMinor(node: JsonNode): Int? {
  if (!node.isIntegralNumber || !node.canConvertToInt()) return null
  return node.intValue()
}

fun encodeLegacyPayment(intent: DecodedIntent): Decode<ObjectNode> {
  if (!intent.submittable) return Decode.Reject("Only GBP integer pence can be submitted")
  val node = contractMapper.createObjectNode()
  node.put("recipientId", intent.recipientId)
  node.put("amountMinor", intent.minorUnits)
  node.put("method", intent.method)
  node.put("note", intent.note)
  node.put("scenario", intent.scenario)
  return Decode.Ok(node)
}

fun validateCatalog(body: JsonNode): CatalogView {
  val rejections = mutableListOf<String>()
  val recipientIds = mutableListOf<String>()
  val recipients = body.get("recipients")
  if (recipients == null || !recipients.isArray) {
    rejections += "recipients must be a list"
  } else {
    recipients.forEach { recipient ->
      val id = textOrNull(recipient, "id")
      if (id.isNullOrBlank()) rejections += "recipient id is required" else recipientIds += id
      if (textOrNull(recipient, "name").isNullOrBlank()) rejections += "recipient name is required"
      val category = textOrNull(recipient, "category")
      if (category !in setOf("Shopping", "Food & drink", "Transport", "Bills", "Lifestyle")) {
        rejections += "unknown category"
      }
    }
  }

  val providerIds = mutableListOf<String>()
  val currencies = linkedMapOf<String, List<String>>()
  val samples = mutableListOf<MoneySample>()
  val providers = body.get("providers")
  if (providers == null || !providers.isArray) {
    rejections += "providers must be a list"
  } else {
    providers.forEach { provider ->
      val id = textOrNull(provider, "id")
      if (id.isNullOrBlank()) {
        rejections += "provider id is required"
        return@forEach
      }
      if (id != "adyen" && id != "worldpay") {
        rejections += "unknown provider"
        return@forEach
      }
      providerIds += id
      val methodsNode = provider.get("methods")
      val methods = if (methodsNode != null && methodsNode.isArray) methodsNode.map { it.asText() } else emptyList()
      if (methods.isEmpty() || methods.any { it != "card" && it != "bank" }) {
        rejections += "unsupported payment method"
      } else if (id == "adyen" && methods != listOf("card")) {
        rejections += "baseline method mismatch"
      } else if (id == "worldpay" && methods != listOf("bank")) {
        rejections += "baseline method mismatch"
      }
      val currencyNode = provider.get("currencies")
      val codes = if (currencyNode != null && currencyNode.isArray) {
        currencyNode.map { it.asText() }
      } else {
        listOf("GBP")
      }
      if (codes.any { it != "GBP" && it != "EUR" }) rejections += "unknown currency"
      currencies[id] = codes
      if (provider.has("sampleAmount") && !provider.get("sampleAmount").isNull) {
        when (val sample = decodeMoneyNode(provider.get("sampleAmount"))) {
          is Decode.Reject -> rejections += sample.reason
          is Decode.Ok -> samples += MoneySample(id, sample.value.minorUnits, sample.value.currency)
        }
      }
    }
  }
  if ("adyen" !in providerIds || "worldpay" !in providerIds) rejections += "baseline providers required"
  return CatalogView(recipientIds, providerIds, currencies, samples, rejections)
}

private fun textOrNull(node: JsonNode, field: String): String? {
  if (!node.has(field) || node.get(field).isNull) return null
  return node.get(field).asText()
}

data class SectionResult(val name: String, val failures: List<String>)

data class SuiteReport(val sections: List<SectionResult>) {
  val failures: List<String> get() = sections.flatMap { section -> section.failures.map { "${section.name}: $it" } }
}

fun locateContractsDirectory(start: File = File(System.getProperty("user.dir"))): File {
  var dir: File? = start.absoluteFile
  repeat(8) {
    val current = dir ?: return@repeat
    if (File(current, "contracts/scenarios/parity.json").isFile) return File(current, "contracts")
    dir = current.parentFile
  }
  error("Could not find contracts/scenarios/parity.json from ${start.absolutePath}")
}

fun runParitySuite(contracts: File): SuiteReport {
  val parity = readContractTree(File(contracts, "scenarios/parity.json"))
  val repoRoot = contracts.parentFile
  val sections = listOf(
    sectionMoney(parity),
    sectionLegacyIntent(contracts),
    sectionMultiCurrencyIntent(contracts),
    sectionLegacyCatalog(contracts),
    sectionMultiCurrencyCatalog(contracts),
    sectionCache(parity, contracts),
    sectionProcessDeath(parity),
    sectionReplayedDeepLink(parity),
    sectionExpiredReturn(parity),
    sectionMalformedCatalog(contracts),
    sectionAccessibility(parity, repoRoot),
  )
  return SuiteReport(sections)
}

private fun sectionMoney(parity: JsonNode): SectionResult {
  val failures = mutableListOf<String>()
  parity.get("money").forEach { row ->
    val formatted = formatMinorUnits(row.get("minorUnits").intValue(), row.get("currency").asText())
    val expected = row.get("formatted").asText()
    if (formatted != expected) failures += "format ${row.get("minorUnits").intValue()} ${row.get("currency").asText()} -> $formatted, expected $expected"
    if (row.get("currency").asText() == "GBP" && money(row.get("minorUnits").intValue()) != expected) {
      failures += "money() diverged for ${row.get("minorUnits").intValue()}"
    }
  }
  return SectionResult("money formatting", failures)
}

private fun sectionLegacyIntent(contracts: File): SectionResult {
  val failures = mutableListOf<String>()
  val doc = readContractTree(File(contracts, "consumer/payment-intent-legacy.json"))
  val body = doc.get("request").get("body")
  val expect = doc.get("expect")
  when (val decoded = decodePaymentIntent(body)) {
    is Decode.Reject -> failures += decoded.reason
    is Decode.Ok -> {
      val intent = decoded.value
      if (intent.minorUnits != expect.get("minorUnits").intValue()) failures += "minor units ${intent.minorUnits}"
      if (intent.currency != expect.get("currency").asText()) failures += "currency ${intent.currency}"
      if (intent.submittable != expect.get("submittable").booleanValue()) failures += "submittable ${intent.submittable}"
      if (intent.providerId != expect.get("providerId").asText()) failures += "provider ${intent.providerId}"
      when (val encoded = encodeLegacyPayment(intent)) {
        is Decode.Reject -> failures += encoded.reason
        is Decode.Ok -> {
          val keys = encoded.value.fieldNames().asSequence().toList().sorted()
          val expectedKeys = expect.get("legacyKeys").map { it.asText() }.sorted()
          if (keys != expectedKeys) failures += "legacy keys $keys"
          if (encoded.value != body) failures += "re-encoded legacy body changed"
        }
      }
      val header = doc.get("request").get("headers").get("Idempotency-Key").asText()
      if (header != "intent-key-144") failures += "idempotency header drifted"
      if (doc.get("request").get("headers").get("X-Rehearsal-Session").asText().isBlank()) {
        failures += "session header missing"
      }
    }
  }
  return SectionResult("legacy integer payment intent", failures)
}

private fun sectionMultiCurrencyIntent(contracts: File): SectionResult {
  val failures = mutableListOf<String>()
  val legacyBody = readContractTree(File(contracts, "consumer/payment-intent-legacy.json")).get("request").get("body")
  val doc = readContractTree(File(contracts, "consumer/payment-intent-multi-currency.json"))
  doc.get("intents").forEach { row ->
    val name = row.get("name").asText()
    val expect = row.get("expect")
    when (val decoded = decodePaymentIntent(row.get("body"))) {
      is Decode.Reject -> {
        val expectedReject = if (expect.has("reject")) expect.get("reject").asText() else null
        if (expectedReject == null) failures += "$name rejected: ${decoded.reason}"
        else if (decoded.reason != expectedReject) failures += "$name reason ${decoded.reason}"
      }
      is Decode.Ok -> {
        if (expect.has("reject")) {
          failures += "$name should reject"
          return@forEach
        }
        val intent = decoded.value
        if (intent.minorUnits != expect.get("minorUnits").intValue()) failures += "$name minor ${intent.minorUnits}"
        if (intent.currency != expect.get("currency").asText()) failures += "$name currency ${intent.currency}"
        if (intent.submittable != expect.get("submittable").booleanValue()) failures += "$name submittable ${intent.submittable}"
        if (intent.providerId != expect.get("providerId").asText()) failures += "$name provider ${intent.providerId}"
        if (expect.has("legacyAmountMinor")) {
          when (val encoded = encodeLegacyPayment(intent)) {
            is Decode.Reject -> failures += "$name encode ${encoded.reason}"
            is Decode.Ok -> {
              if (encoded.value.get("amountMinor").intValue() != expect.get("legacyAmountMinor").intValue()) {
                failures += "$name legacy amount"
              }
              if (!encoded.value.has("currency")) {
                // Currency stays off the rehearsal wire. GBP objects collapse to integer pence.
              } else failures += "$name leaked currency onto the rehearsal body"
              if (name.startsWith("gbp object") && encoded.value != legacyBody) {
                failures += "$name is not backward compatible with the legacy integer payload"
              }
            }
          }
        } else if (!intent.submittable) {
          val encoded = encodeLegacyPayment(intent)
          if (encoded !is Decode.Reject || encoded.reason != "Only GBP integer pence can be submitted") {
            failures += "$name was submitted"
          }
        }
      }
    }
  }
  return SectionResult("multi-currency payment intent", failures)
}

private fun sectionLegacyCatalog(contracts: File): SectionResult =
  sectionCatalog(contracts, "consumer/catalog-legacy.json", "legacy catalog", samples = false)

private fun sectionMultiCurrencyCatalog(contracts: File): SectionResult =
  sectionCatalog(contracts, "consumer/catalog-multi-currency.json", "multi-currency catalog", samples = true)

private fun sectionCatalog(contracts: File, path: String, name: String, samples: Boolean): SectionResult {
  val failures = mutableListOf<String>()
  val doc = readContractTree(File(contracts, path))
  val view = validateCatalog(doc.get("response").get("body"))
  val expect = doc.get("expect")
  if (view.accepted != expect.get("accepted").booleanValue()) failures += "accepted ${view.accepted} ${view.rejections}"
  if (view.providerIds != expect.get("providerIds").map { it.asText() }) failures += "providers ${view.providerIds}"
  if (view.recipientIds != expect.get("recipientIds").map { it.asText() }) failures += "recipients ${view.recipientIds}"
  val expectedCurrencies = expect.get("currencies")
  expectedCurrencies.fieldNames().forEach { id ->
    val got = view.currencies[id] ?: emptyList()
    val want = expectedCurrencies.get(id).map { it.asText() }
    if (got != want) failures += "currencies $id $got"
  }
  if (samples) {
    val want = expect.get("samples").map {
      MoneySample(it.get("providerId").asText(), it.get("minorUnits").intValue(), it.get("currency").asText())
    }
    if (view.samples != want) failures += "samples ${view.samples}"
  }
  if (view.providerIds.any { it != "adyen" && it != "worldpay" }) failures += "third provider accepted"
  return SectionResult(name, failures)
}

private fun sectionCache(parity: JsonNode, contracts: File): SectionResult {
  val failures = mutableListOf<String>()
  val fetchedAt = 1_000_000L
  parity.get("cache").forEach { row ->
    val cache = CatalogCache("catalog", fetchedAt, row.get("ttlMs").longValue())
    val fresh = cache.isFresh(fetchedAt + row.get("ageMs").longValue())
    if (fresh != row.get("fresh").booleanValue()) {
      failures += "age ${row.get("ageMs").longValue()} fresh=$fresh"
    }
  }
  val legacy = File(contracts, "consumer/catalog-legacy.json").readText()
  val freshDir = Files.createTempDirectory("meridian-cache-fresh").toFile()
  val freshStore = SessionCheckpoint(freshDir)
  freshStore.writeCache(CatalogCache(legacy, fetchedAt, 300_000))
  val reloaded = SessionCheckpoint(freshDir).readCache(fetchedAt + 1_000)
  if (reloaded?.body != legacy) failures += "fresh catalog cache did not survive reload"
  val staleDir = Files.createTempDirectory("meridian-cache-stale").toFile()
  val staleStore = SessionCheckpoint(staleDir)
  staleStore.writeCache(CatalogCache(legacy, fetchedAt, 300_000))
  if (SessionCheckpoint(staleDir).readCache(fetchedAt + 300_000) != null) {
    failures += "expired catalog cache was served after process reload"
  }
  return SectionResult("cache expiry", failures)
}

private fun sectionProcessDeath(parity: JsonNode): SectionResult {
  val failures = mutableListOf<String>()
  val spec = parity.get("processDeath")
  val intent = PersistedIntent(
    idempotencyKey = spec.get("idempotencyKey").asText(),
    recipientId = spec.get("recipientId").asText(),
    minorUnits = spec.get("amountMinor").intValue(),
    currency = spec.get("currency").asText(),
    method = spec.get("method").asText(),
    note = spec.get("note").asText(),
    providerId = spec.get("providerId").asText(),
  )
  val dir = Files.createTempDirectory("meridian-process-death").toFile()
  val first = SessionCheckpoint(dir).begin(intent)
  val restored = SessionCheckpoint(dir).loadIntent()
  if (restored != first) failures += "restored intent $restored"
  if (restored?.idempotencyKey != intent.idempotencyKey) failures += "idempotency key was not retained"
  val conflicting = intent.copy(minorUnits = spec.get("conflictingAmountMinor").intValue(), idempotencyKey = "rotated-key")
  val kept = SessionCheckpoint(dir).begin(conflicting)
  if (kept.idempotencyKey != intent.idempotencyKey || kept.minorUnits != intent.minorUnits) {
    failures += "in-flight intent was replaced after restart"
  }
  if (kept.providerId != "adyen" || kept.method != "card") failures += "provider changed across process death"
  return SectionResult("idempotency persistence and process death", failures)
}

private fun sectionReplayedDeepLink(parity: JsonNode): SectionResult {
  val failures = mutableListOf<String>()
  val spec = parity.get("returns")
  val dir = Files.createTempDirectory("meridian-replay").toFile()
  val store = SessionCheckpoint(dir)
  store.issueReturn(spec.get("nonce").asText(), spec.get("paymentId").asText(), spec.get("expiresAtEpochMs").longValue())
  val accepted = store.consume(spec.get("validUrl").asText(), spec.get("acceptedAtEpochMs").longValue())
  if (accepted !is ReturnDecision.Accepted || accepted.paymentId != spec.get("paymentId").asText()) {
    failures += "first return was not accepted"
  }
  val replay = SessionCheckpoint(dir).consume(spec.get("validUrl").asText(), spec.get("acceptedAtEpochMs").longValue())
  val replayReason = (replay as? ReturnDecision.Rejected)?.reason
  if (replayReason != spec.get("replayReason").asText()) failures += "replay reason $replayReason"
  val malformed = store.consume(spec.get("malformedUrl").asText(), spec.get("acceptedAtEpochMs").longValue())
  if ((malformed as? ReturnDecision.Rejected)?.reason != spec.get("malformedReason").asText()) {
    failures += "malformed deep link was not rejected"
  }
  val unknown = store.consume(spec.get("unknownUrl").asText(), spec.get("acceptedAtEpochMs").longValue())
  if ((unknown as? ReturnDecision.Rejected)?.reason != spec.get("unknownReason").asText()) {
    failures += "unknown return state was not rejected"
  }
  return SectionResult("replayed deep links", failures)
}

private fun sectionExpiredReturn(parity: JsonNode): SectionResult {
  val failures = mutableListOf<String>()
  val spec = parity.get("returns")
  val dir = Files.createTempDirectory("meridian-expired-return").toFile()
  val store = SessionCheckpoint(dir)
  store.issueReturn(spec.get("nonce").asText(), spec.get("paymentId").asText(), spec.get("expiresAtEpochMs").longValue())
  val expired = store.consume(spec.get("validUrl").asText(), spec.get("expiredAtEpochMs").longValue())
  val reason = (expired as? ReturnDecision.Rejected)?.reason
  if (reason != spec.get("expiredReason").asText()) failures += "expired reason $reason"
  val afterRestart = SessionCheckpoint(dir).consume(spec.get("validUrl").asText(), spec.get("expiredAtEpochMs").longValue())
  if ((afterRestart as? ReturnDecision.Rejected)?.reason != spec.get("expiredReason").asText()) {
    failures += "expiry was forgotten after process reload"
  }
  return SectionResult("expired return states", failures)
}

private fun sectionMalformedCatalog(contracts: File): SectionResult {
  val failures = mutableListOf<String>()
  val doc = readContractTree(File(contracts, "consumer/catalog-malformed.json"))
  doc.get("cases").forEach { row ->
    val name = row.get("name").asText()
    val view = validateCatalog(row.get("body"))
    if (view.accepted) failures += "$name was accepted"
    if (view.rejections != listOf(row.get("reason").asText())) {
      failures += "$name rejections ${view.rejections}"
    }
  }
  return SectionResult("malformed catalog entries", failures)
}

private fun sectionAccessibility(parity: JsonNode, repoRoot: File): SectionResult {
  val failures = mutableListOf<String>()
  parity.get("accessibility").forEach { row ->
    val got = AccessibilityCopy.balance(
      minorUnits = row.get("minorUnits").intValue(),
      currency = row.get("currency").asText(),
      fontScale = row.get("fontScale").doubleValue(),
      direction = row.get("direction").asText(),
    )
    fun check(field: String, actual: String, expected: String) {
      if (actual != expected) failures += "$field $actual"
    }
    check("voiceOver", got.voiceOverLabel, row.get("voiceOverLabel").asText())
    check("talkBack", got.talkBackDescription, row.get("talkBackDescription").asText())
    if (kotlin.math.abs(got.scaledSp - row.get("scaledSp").doubleValue()) > 0.001) failures += "scaledSp ${got.scaledSp}"
    if (kotlin.math.abs(got.minimumTouchTargetDp - row.get("minimumTouchTargetDp").doubleValue()) > 0.001) {
      failures += "touch target ${got.minimumTouchTargetDp}"
    }
    check("startEdge", got.startEdge, row.get("startEdge").asText())
    check("arrangement", got.arrangement, row.get("arrangement").asText())
    check("amount", got.amountText, row.get("amountText").asText())
    check("amountDirection", got.amountDirection, row.get("amountDirection").asText())
    if (got.amountText.any { it.isDigit() && got.amountDirection != "ltr" }) failures += "amount digits were mirrored"
  }
  val confirm = parity.get("confirm")
  if (AccessibilityCopy.confirmLabel != confirm.get("voiceOverLabel").asText()) failures += "confirm label"
  if (AccessibilityCopy.confirmHint != confirm.get("voiceOverHint").asText()) failures += "confirm hint"
  if (AccessibilityCopy.confirmTalkBack != confirm.get("talkBackDescription").asText()) failures += "confirm talkback"
  val manifest = File(repoRoot, "android/app/src/main/AndroidManifest.xml").readText()
  if (!manifest.contains("android:supportsRtl=\"true\"")) failures += "Android manifest is missing supportsRtl"
  val activity = File(repoRoot, "android/app/src/main/kotlin/com/atlassian/meridian/MainActivity.kt").readText()
  if (!activity.contains("AccessibilityCopy.balanceLabel") || !activity.contains("AccessibilityCopy.confirmTalkBack")) {
    failures += "TalkBack descriptions are not bound in the Compose UI"
  }
  if (!activity.contains("minimumTouchTargetDp") || !activity.contains(".sp")) {
    failures += "large font scaling is not bound in the Compose UI"
  }
  val swiftUi = File(repoRoot, "ios/App/MeridianApp.swift").readText()
  if (!swiftUi.contains("AccessibilityCopy.balanceLabel") || !swiftUi.contains("accessibilityHint")) {
    failures += "VoiceOver labels are not bound in the SwiftUI view"
  }
  if (!swiftUi.contains("ScaledMetric") || !swiftUi.contains("alignment: .leading")) {
    failures += "SwiftUI large type or leading-edge layout is missing"
  }
  return SectionResult("accessibility and localisation", failures)
}
