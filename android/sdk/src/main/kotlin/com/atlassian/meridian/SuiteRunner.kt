package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlin.math.abs

object MeridianSuites {
  private val mapper = ObjectMapper().registerKotlinModule()

  fun contractFailures(json: String): List<String> {
    val failures = mutableListOf<String>()
    liveCatalogRoundTripFailure()?.let { failures += it }
    val root = mapper.readTree(json)
    val cases = root.path("cases")
    if (!cases.isArray || cases.size() == 0) failures += "contract has no cases"
    for (item in cases) {
      val id = item.path("id").asText("missing-id")
      try {
        when (item.path("type").asText()) {
          "money" -> checkMoney(id, item, failures)
          "catalog" -> checkCatalog(id, item, failures)
          "payment-intent" -> checkIntent(id, item, failures)
          else -> failures += "$id unknown contract type"
        }
      } catch (error: Exception) {
        failures += "$id threw ${error.message}"
      }
    }
    return failures
  }

  fun scenarioFailures(json: String): List<String> {
    val failures = mutableListOf<String>()
    val root = mapper.readTree(json)
    val cases = root.path("cases")
    if (!cases.isArray || cases.size() == 0) failures += "scenarios have no cases"
    for (item in cases) {
      val id = item.path("id").asText("missing-id")
      try {
        when (item.path("type").asText()) {
          "format" -> {
            val display = formatMoney(item.path("currency").asText(), item.path("minor").asInt(), item.path("exponent").asInt())
            if (display != item.path("display").asText()) failures += "$id display $display"
          }
          "parse-amount" -> checkParse(id, item, failures)
          "cache" -> checkCache(id, item, failures)
          "idempotency" -> checkIdempotency(id, item, failures)
          "deep-link" -> checkDeepLink(id, item, failures)
          "catalog" -> checkCatalog(id, item, failures)
          "accessibility" -> checkAccessibility(id, item, failures)
          "font-scale" -> checkFont(id, item, failures)
          "rtl" -> checkRtl(id, item, failures)
          else -> failures += "$id unknown scenario type"
        }
      } catch (error: Exception) {
        failures += "$id threw ${error.message}"
      }
    }
    return failures
  }

  private fun checkMoney(id: String, item: JsonNode, failures: MutableList<String>) {
    val expect = item.path("expect")
    when (val decoded = decodeMoney(item.path("value"))) {
      is Decoded.Err -> {
        if (expect.path("ok").asBoolean(false)) failures += "$id unexpected ${decoded.error.code}"
        else if (decoded.error.code != expect.path("code").asText()) failures += "$id code ${decoded.error.code}"
      }
      is Decoded.Ok -> {
        if (!expect.path("ok").asBoolean(false)) {
          failures += "$id expected ${expect.path("code").asText()}"
          return
        }
        val money = decoded.value
        if (money.currency != expect.path("currency").asText()) failures += "$id currency"
        if (money.minor != expect.path("minor").asInt()) failures += "$id minor"
        if (money.exponent != expect.path("exponent").asInt()) failures += "$id exponent"
        if (expect.has("display") && money.display != expect.path("display").asText()) failures += "$id display ${money.display}"
        if (!optionalIntEquals(money.gbpPence, expect.get("gbpPence"))) failures += "$id gbpPence"
      }
    }
  }

  private fun checkCatalog(id: String, item: JsonNode, failures: MutableList<String>) {
    val expect = item.path("expect")
    when (val decoded = decodeCatalog(item.path("payload"))) {
      is Decoded.Err -> {
        if (expect.path("ok").asBoolean(false)) failures += "$id unexpected ${decoded.error.code}"
        else if (decoded.error.code != expect.path("code").asText()) failures += "$id code ${decoded.error.code}"
      }
      is Decoded.Ok -> {
        if (!expect.path("ok").asBoolean(false)) {
          failures += "$id expected rejection"
          return
        }
        val document = decoded.value
        if (expect.has("demoDate") && document.demoDate != expect.path("demoDate").asText()) failures += "$id demoDate"
        if (expect.has("recipientCount") && document.recipients.size != expect.path("recipientCount").asInt()) failures += "$id recipientCount"
        if (expect.has("providerIds")) {
          val ids = expect.path("providerIds").map { it.asText() }
          if (document.providers.map { it.id } != ids) failures += "$id providers ${document.providers.map { it.id }}"
        }
        if (expect.has("prices")) {
          for (price in expect.path("prices")) {
            val recipient = document.recipients.find { it.id == price.path("id").asText() }
            if (recipient == null) {
              failures += "$id missing recipient"
              continue
            }
            if (price.path("absent").asBoolean(false)) {
              if (recipient.price != null) failures += "$id price present"
              continue
            }
            val money = recipient.price
            if (money == null) {
              failures += "$id price missing"
              continue
            }
            if (money.currency != price.path("currency").asText() || money.minor != price.path("minor").asInt() || money.exponent != price.path("exponent").asInt()) {
              failures += "$id price fields"
            }
            if (price.has("display") && money.display != price.path("display").asText()) failures += "$id price display"
            if (price.has("gbpPence") && !optionalIntEquals(money.gbpPence, price.get("gbpPence"))) failures += "$id price gbp"
          }
        }
      }
    }
  }

  private fun checkIntent(id: String, item: JsonNode, failures: MutableList<String>) {
    val expect = item.path("expect")
    when (val decoded = decodePaymentIntent(item.path("payload"))) {
      is Decoded.Err -> {
        if (expect.path("ok").asBoolean(false)) failures += "$id unexpected ${decoded.error.code}"
        else if (decoded.error.code != expect.path("code").asText()) failures += "$id code ${decoded.error.code}"
      }
      is Decoded.Ok -> {
        if (!expect.path("ok").asBoolean(false)) {
          failures += "$id expected rejection"
          return
        }
        val intent = decoded.value
        if (expect.has("currency") && intent.money.currency != expect.path("currency").asText()) failures += "$id currency"
        if (expect.has("minor") && intent.money.minor != expect.path("minor").asInt()) failures += "$id minor"
        if (expect.has("exponent") && intent.money.exponent != expect.path("exponent").asInt()) failures += "$id exponent"
        if (expect.has("display") && intent.money.display != expect.path("display").asText()) failures += "$id display"
        if (expect.has("gbpPence") && !optionalIntEquals(intent.money.gbpPence, expect.get("gbpPence"))) failures += "$id gbpPence"
        if (expect.has("method") && intent.method != expect.path("method").asText()) failures += "$id method"
        if (expect.has("note") && intent.note != expect.path("note").asText()) failures += "$id note"
        if (expect.has("scenario") && intent.scenario != expect.path("scenario").asText()) failures += "$id scenario"
        if (expect.has("submittable") && intent.submittable != expect.path("submittable").asBoolean()) failures += "$id submittable"
        if (expect.has("wireAmountMinor") && !optionalIntEquals(intent.wireAmountMinor, expect.get("wireAmountMinor"))) failures += "$id wire"
      }
    }
  }

  private fun checkParse(id: String, item: JsonNode, failures: MutableList<String>) {
    val (pence, error) = parseAmount(item.path("input").asText())
    if (item.has("error")) {
      if (pence != null || error != item.path("error").asText()) failures += "$id parse ${pence ?: "null"} ${error ?: "null"}"
    } else if (pence != item.path("pence").asInt() || error != null) {
      failures += "$id parse ${pence ?: "null"} ${error ?: "null"}"
    }
  }

  private fun checkCache(id: String, item: JsonNode, failures: MutableList<String>) {
    val decoded = decodeCatalog(item.path("catalog"))
    if (decoded is Decoded.Err) {
      failures += "$id catalog ${decoded.error.code}"
      return
    }
    val document = (decoded as Decoded.Ok).value
    val cache = CatalogCache()
    val ttl = item.path("ttl").asLong()
    for (step in item.path("steps")) {
      when (step.path("op").asText()) {
        "store" -> cache.store(step.path("session").asText(), document, step.path("at").asLong(), ttl)
        "read" -> {
          val actual = cache.read(step.path("session").asText(), step.path("at").asLong())
          if (actual != step.path("expect").asText()) failures += "$id read@$actual"
        }
        else -> failures += "$id unknown cache op"
      }
    }
  }

  private fun checkIdempotency(id: String, item: JsonNode, failures: MutableList<String>) {
    var journal = IdempotencyJournal()
    for (step in item.path("steps")) {
      when (step.path("op").asText()) {
        "begin" -> {
          val error = journal.begin(
            step.path("session").asText(),
            step.path("key").asText(),
            step.path("recipientId").asText(),
            step.path("currency").asText(),
            step.path("minor").asInt(),
            step.path("exponent").asInt(),
            step.path("method").asText(),
            step.path("note").asText(),
          )
          expectResult(id, step, error, failures)
        }
        "markUncertain" -> journal.markUncertain()?.let { failures += "$id markUncertain ${it.code}" }
        "markCompleted" -> journal.markCompleted()?.let { failures += "$id markCompleted ${it.code}" }
        "discardDraft" -> expectResult(id, step, journal.discardDraft(), failures)
        "retry" -> {
          val result = journal.retry(
            note = step.path("note").asText(),
            recipientId = step.takeIf { it.has("recipientId") }?.path("recipientId")?.asText(),
            minor = step.takeIf { it.has("minor") }?.path("minor")?.asInt(),
            method = step.takeIf { it.has("method") }?.path("method")?.asText(),
            currency = step.takeIf { it.has("currency") }?.path("currency")?.asText(),
          )
          when (result) {
            is Decoded.Err -> {
              if (step.path("expect").asText() != "rejected" || result.error.code != step.path("code").asText()) {
                failures += "$id retry ${result.error.code}"
              }
            }
            is Decoded.Ok -> {
              if (step.path("expect").asText() != "accepted" || result.value != step.path("key").asText()) {
                failures += "$id retry accepted ${result.value}"
              }
            }
          }
        }
        "kill" -> journal.kill()
        "restore" -> journal = IdempotencyJournal.restore(step.path("snapshot").asText())
        "expect" -> {
          if (journal.status != step.path("status").asText()) failures += "$id status ${journal.status}"
          val expectedKey = if (step.path("key").isNull) null else step.path("key").asText()
          if (journal.key != expectedKey) failures += "$id key ${journal.key}"
        }
        "expectSnapshot" -> {
          if (journal.snapshot() != step.path("snapshot").asText()) failures += "$id snapshot ${journal.snapshot()}"
        }
        else -> failures += "$id unknown idempotency op"
      }
    }
  }

  private fun checkDeepLink(id: String, item: JsonNode, failures: MutableList<String>) {
    val guard = ReturnStateGuard()
    for (step in item.path("steps")) {
      when (step.path("op").asText()) {
        "select" -> guard.select(step.path("session").asText())
        "arm" -> expectResult(
          id,
          step,
          guard.arm(step.path("session").asText(), step.path("paymentId").asText(), step.path("nonce").asText(), step.path("exp").asLong(), step.path("key").asText()),
          failures,
        )
        "open" -> expectDecoded(id, step, guard.open(step.path("paymentId").asText(), step.path("nonce").asText(), step.path("now").asLong()), failures)
        "openUrl" -> expectDecoded(id, step, guard.openUrl(step.path("url").asText(), step.path("now").asLong()), failures)
        "expectSelected" -> if (guard.selectedSession != step.path("session").asText()) failures += "$id selected ${guard.selectedSession}"
        else -> failures += "$id unknown deep-link op"
      }
    }
  }

  private fun checkAccessibility(id: String, item: JsonNode, failures: MutableList<String>) {
    val expected = item.path("elements")
    if (AccessibilityCatalog.nodes.size != expected.size()) failures += "$id node count"
    val minPt = item.path("minTouchTargetPt").asInt()
    val minDp = item.path("minTouchTargetDp").asInt()
    expected.forEachIndexed { index, node ->
      val actual = AccessibilityCatalog.nodes.getOrNull(index)
      if (actual == null || actual.id != node.path("id").asText()) {
        failures += "$id node $index"
        return@forEachIndexed
      }
      if (actual.voiceOverLabel != node.path("voiceOverLabel").asText()) failures += "$id voiceover ${actual.id}"
      if (actual.talkBackDescription != node.path("talkBackDescription").asText()) failures += "$id talkback ${actual.id}"
      if (actual.traits != node.path("traits").map { it.asText() }) failures += "$id traits ${actual.id}"
      if (actual.textDirection != node.path("textDirection").asText()) failures += "$id direction ${actual.id}"
      if (actual.scalesWithFont != node.path("scalesWithFont").asBoolean()) failures += "$id scale ${actual.id}"
      if (actual.mirrorsInRtl != node.path("mirrorsInRtl").asBoolean()) failures += "$id mirror ${actual.id}"
      if (actual.minTouchTargetPt != minPt || actual.minTouchTargetDp != minDp) failures += "$id target ${actual.id}"
    }
  }

  private fun checkFont(id: String, item: JsonNode, failures: MutableList<String>) {
    val height = buttonHeight(item.path("platform").asText(), item.path("fontScale").asDouble())
    if (abs(height - item.path("minHeight").asDouble()) > 0.001) failures += "$id height $height"
    val lines = wrappedLines(item.path("text").asText(), item.path("fontScale").asDouble(), item.path("containerWidth").asDouble(), item.path("baseSize").asDouble())
    if (lines != item.path("lines").asInt()) failures += "$id lines $lines"
  }

  private fun checkRtl(id: String, item: JsonNode, failures: MutableList<String>) {
    val edges = horizontalEdges(item.path("direction").asText())
    if (edges.first != item.path("startEdge").asText() || edges.second != item.path("endEdge").asText()) failures += "$id edges"
    val balance = AccessibilityCatalog.node("balance")
    if (balance?.textDirection != item.path("amountDirection").asText()) failures += "$id amount direction"
    val direction = item.path("direction").asText()
    for (nodeId in item.path("mirrored").map { it.asText() }) {
      val node = AccessibilityCatalog.node(nodeId)
      if (node == null || !(node.mirrorsInRtl && direction == "rtl")) failures += "$id mirrored $nodeId"
    }
    for (nodeId in item.path("notMirrored").map { it.asText() }) {
      val node = AccessibilityCatalog.node(nodeId)
      val active = node?.mirrorsInRtl == true && direction == "rtl"
      if (node == null || active) failures += "$id notMirrored $nodeId"
    }
  }

  private fun expectResult(id: String, step: JsonNode, error: ContractError?, failures: MutableList<String>) {
    val expect = step.path("expect").asText("accepted")
    if (expect == "accepted" && error != null) failures += "$id ${step.path("op").asText()} ${error.code}"
    if (expect == "rejected" && error?.code != step.path("code").asText()) failures += "$id ${step.path("op").asText()} ${error?.code}"
  }

  private fun expectDecoded(id: String, step: JsonNode, result: Decoded<String>, failures: MutableList<String>) {
    when (result) {
      is Decoded.Err -> if (step.path("expect").asText() != "rejected" || result.error.code != step.path("code").asText()) failures += "$id ${step.path("op").asText()} ${result.error.code}"
      is Decoded.Ok -> if (step.path("expect").asText() != "accepted" || result.value != step.path("key").asText()) failures += "$id ${step.path("op").asText()} ${result.value}"
    }
  }

  private fun optionalIntEquals(actual: Int?, expected: JsonNode?): Boolean {
    if (expected == null || expected.isNull || expected.isMissingNode) return actual == null
    return actual == expected.asInt()
  }
}
