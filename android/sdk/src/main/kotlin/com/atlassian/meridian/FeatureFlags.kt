package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.io.File

/** Remote flag that partitions dynamic catalog hydration and Euro display controls. */
object FeatureFlags {
  const val mobileEuPayments = "enable_mobile_eu_payments"

  fun cacheKey(sessionId: String) = "$mobileEuPayments:$sessionId"
}

data class FeatureFlagEvaluation(
  val key: String = FeatureFlags.mobileEuPayments,
  val enabled: Boolean = false,
  val variant: String = "legacy",
  val source: String = "default",
) : java.io.Serializable {
  companion object {
    fun legacy(source: String) = FeatureFlagEvaluation(
      key = FeatureFlags.mobileEuPayments,
      enabled = false,
      variant = "legacy",
      source = source,
    )
  }
}

data class PaymentTelemetryEvent(
  val action: String,
  val flagKey: String,
  val variant: String,
  val currency: String,
  val idempotencyKey: String,
  val sessionId: String,
) : java.io.Serializable

interface FeatureFlagCache {
  fun read(key: String): FeatureFlagEvaluation?
  fun write(key: String, evaluation: FeatureFlagEvaluation)
}

class InMemoryFeatureFlagCache : FeatureFlagCache {
  private val values = linkedMapOf<String, FeatureFlagEvaluation>()

  override fun read(key: String): FeatureFlagEvaluation? = synchronized(values) { values[key] }

  override fun write(key: String, evaluation: FeatureFlagEvaluation) {
    synchronized(values) { values[key] = evaluation }
  }
}

class FileFeatureFlagCache(
  private val file: File = File(System.getProperty("user.home") ?: System.getProperty("java.io.tmpdir"), ".meridian/feature-flags.json"),
) : FeatureFlagCache {
  private val mapper = ObjectMapper().registerKotlinModule()

  override fun read(key: String): FeatureFlagEvaluation? {
    val all = load()
    return all[key]
  }

  override fun write(key: String, evaluation: FeatureFlagEvaluation) {
    synchronized(file) {
      val all = load().toMutableMap()
      all[key] = evaluation
      file.parentFile?.mkdirs()
      mapper.writeValue(file, all)
    }
  }

  private fun load(): Map<String, FeatureFlagEvaluation> {
    if (!file.exists()) return emptyMap()
    return try {
      val node = mapper.readTree(file)
      if (!node.isObject) return emptyMap()
      node.fields().asSequence().associate { (key, value) ->
        key to mapper.treeToValue(value, FeatureFlagEvaluation::class.java)
      }
    } catch (_: Exception) {
      emptyMap()
    }
  }
}

object FeatureFlagParser {
  private val mapper = ObjectMapper().registerKotlinModule()

  /** A JSON object that omits the flag is the kill switch. Null means the payload is not an object. */
  fun parse(json: String): Pair<Boolean, String>? {
    val root = try {
      mapper.readTree(json)
    } catch (_: Exception) {
      return null
    }
    if (!root.isObject) return null
    val value = lookup(root, FeatureFlags.mobileEuPayments) ?: return false to "legacy"
    return interpret(value)
  }

  fun interpret(value: JsonNode): Pair<Boolean, String> {
    if (value.isBoolean) {
      return if (value.booleanValue()) true to "dynamic" else false to "legacy"
    }
    if (value.isNumber) {
      return if (value.intValue() == 0) false to "legacy" else true to "dynamic"
    }
    if (value.isTextual) {
      return interpretText(value.textValue())
    }
    if (value.isObject) {
      if (value.path("killSwitch").asBoolean(false) || value.path("kill_switch").asBoolean(false)) {
        return false to "legacy"
      }
      val raw = when {
        value.has("enabled") -> value.get("enabled")
        value.has("value") -> value.get("value")
        value.has("on") -> value.get("on")
        else -> null
      }
      val enabled = raw?.let { interpret(it).first } ?: false
      if (!enabled) return false to "legacy"
      return true to (sanitize(value.path("variant").asText(null)) ?: "dynamic")
    }
    return false to "legacy"
  }

  private fun lookup(root: JsonNode, key: String): JsonNode? {
    if (root.has(key)) return root.get(key)
    val objects = listOf(root.get("flags"), root.get("featureFlags"))
    for (flags in objects) {
      if (flags != null && flags.isObject && flags.has(key)) return flags.get(key)
      if (flags != null && flags.isArray) {
        val match = flags.firstOrNull { row ->
          row.path("key").asText() == key || row.path("name").asText() == key
        }
        if (match != null) return match
      }
    }
    return null
  }

  private fun interpretText(text: String): Pair<Boolean, String> {
    return when (text.trim().lowercase()) {
      "1", "true", "on", "enabled", "dynamic", "treatment" -> true to "dynamic"
      else -> false to "legacy"
    }
  }

  fun sanitize(variant: String?): String? {
    if (variant.isNullOrBlank()) return null
    val trimmed = variant.trim()
    if (trimmed.length > 64) return null
    if (!trimmed.matches(Regex("[A-Za-z0-9_-]+"))) return null
    return trimmed
  }
}

object PaymentTelemetry {
  fun event(
    evaluation: FeatureFlagEvaluation,
    idempotencyKey: String,
    sessionId: String,
    displayCurrency: String,
  ): PaymentTelemetryEvent {
    val enabled = evaluation.enabled && evaluation.key == FeatureFlags.mobileEuPayments
    val variant = if (enabled) FeatureFlagParser.sanitize(evaluation.variant) ?: "dynamic" else "legacy"
    val currency = if (enabled && displayCurrency == "EUR") "EUR" else "GBP"
    return PaymentTelemetryEvent(
      action = "payment.submit",
      flagKey = FeatureFlags.mobileEuPayments,
      variant = variant,
      currency = currency,
      idempotencyKey = idempotencyKey,
      sessionId = sessionId,
    )
  }

  fun headerValue(event: PaymentTelemetryEvent) = "${event.flagKey}=${event.variant}"
}
