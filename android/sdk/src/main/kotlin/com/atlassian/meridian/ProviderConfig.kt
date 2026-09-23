package com.atlassian.meridian

import com.fasterxml.jackson.annotation.JsonIgnoreProperties
import java.io.Serializable
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.logging.Level
import java.util.logging.Logger

/**
 * Milestone 3 renders the payment picker from remote configuration.
 * Rollback sets the flag back to [ProviderPickerMode.MILESTONE_2_BASELINE],
 * which restores Adyen card and Worldpay bank without reverting picker code.
 */
enum class ProviderPickerMode {
  MILESTONE_2_BASELINE,
  REMOTE_CONFIG,
}

enum class ProviderConfigSource {
  REMOTE,
  CACHE,
  MILESTONE_2_BASELINE,
}

object ProviderPickerFlags {
  const val ENVIRONMENT_VARIABLE = "MERIDIAN_PROVIDER_PICKER"
  const val SYSTEM_PROPERTY = "meridian.provider.picker"
  const val HEALTH_LOGGER = "com.atlassian.meridian.mmob402"

  /** Shipped Milestone 3 default. Rollback does not change this constant; it overrides the flag. */
  val shippedDefault: ProviderPickerMode = ProviderPickerMode.REMOTE_CONFIG

  @Volatile
  var runtimeOverride: ProviderPickerMode? = null

  fun resolve(
    runtimeOverride: ProviderPickerMode? = this.runtimeOverride,
    environment: String? = System.getenv(ENVIRONMENT_VARIABLE),
    systemProperty: String? = System.getProperty(SYSTEM_PROPERTY),
  ): ProviderPickerMode {
    runtimeOverride?.let { return it }
    parse(systemProperty)?.let { return it }
    parse(environment)?.let { return it }
    return shippedDefault
  }

  fun parse(value: String?): ProviderPickerMode? {
    return when (value?.trim()?.lowercase(Locale.US)) {
      "remote", "m3", "milestone3" -> ProviderPickerMode.REMOTE_CONFIG
      "milestone2", "m2", "baseline" -> ProviderPickerMode.MILESTONE_2_BASELINE
      null, "" -> null
      else -> null
    }
  }
}

@JsonIgnoreProperties(ignoreUnknown = true)
data class PaymentProviderConfigResponse(
  val providers: List<PaymentProviderResponse> = emptyList(),
  val configVersion: String = "",
) : Serializable

@JsonIgnoreProperties(ignoreUnknown = true)
data class PaymentProviderResponse(
  val id: String = "",
  val name: String = "",
  val methods: List<String> = emptyList(),
  val corridors: List<String> = emptyList(),
) : Serializable

data class ConfiguredProvider(
  val id: ProviderId,
  val name: String,
  val methods: List<PaymentMethod>,
  val corridors: List<String>,
) : Serializable

data class PaymentProviderConfig(
  val providers: List<ConfiguredProvider>,
  val configVersion: String,
) : Serializable

data class ProviderPickerResult(
  val providers: List<ConfiguredProvider>,
  val source: ProviderConfigSource,
  val configVersion: String,
) : Serializable

data class PickerOption(
  val providerId: ProviderId,
  val method: PaymentMethod,
  val label: String,
) : Serializable

data class ProviderConfigHealthSnapshot(
  val fetchAttempts: Int,
  val fetchSuccesses: Int,
  val fallbacks: Int,
  val successRate: Double,
  val fallbackRate: Double,
) {
  fun successPercent(): String = formatRatePercent(successRate)
  fun fallbackPercent(): String = formatRatePercent(fallbackRate)
}

fun formatRatePercent(rate: Double): String = String.format(Locale.US, "%.0f%%", rate * 100.0)

/**
 * Last successful remote configuration, keyed by rehearsal session.
 * The Milestone 2 baseline is the seed used when a session has no cache yet.
 */
class ProviderConfigStore {
  private val entries = ConcurrentHashMap<String, PaymentProviderConfig>()

  fun get(sessionId: String): PaymentProviderConfig? = entries[sessionId]

  fun put(sessionId: String, config: PaymentProviderConfig) {
    entries[sessionId] = config
  }

  companion object {
    val shared: ProviderConfigStore = ProviderConfigStore()
  }
}

/**
 * Leading health indicators for MMOB-402: remote configuration fetch success
 * and fallback-to-cache. Rates are successes/attempts and fallbacks/attempts.
 */
class ProviderConfigHealth {
  private val lock = Any()
  private var fetchAttempts = 0
  private var fetchSuccesses = 0
  private var fallbacks = 0
  private val logger = Logger.getLogger(ProviderPickerFlags.HEALTH_LOGGER)

  init {
    logger.level = Level.INFO
  }

  fun recordSuccess(configVersion: String) {
    log(event = "fetch_success", configVersion = configVersion, reason = null, success = true)
  }

  fun recordFallback(configVersion: String, reason: String) {
    log(event = "fallback_to_cache", configVersion = configVersion, reason = reason, success = false)
  }

  fun snapshot(): ProviderConfigHealthSnapshot = synchronized(lock) { snapshotLocked() }

  private fun log(event: String, configVersion: String, reason: String?, success: Boolean) {
    val snap = synchronized(lock) {
      fetchAttempts += 1
      if (success) fetchSuccesses += 1 else fallbacks += 1
      snapshotLocked()
    }
    val safeReason = reason?.replace(Regex("\\s+"), " ")?.take(200).orEmpty()
    logger.info(
      String.format(
        Locale.US,
        "MMOB-402 provider-config event=%s configVersion=%s successRate=%.4f fallbackToCacheRate=%.4f attempts=%d successes=%d fallbacks=%d reason=%s",
        event,
        configVersion,
        snap.successRate,
        snap.fallbackRate,
        snap.fetchAttempts,
        snap.fetchSuccesses,
        snap.fallbacks,
        safeReason,
      ),
    )
  }

  private fun snapshotLocked(): ProviderConfigHealthSnapshot {
    return ProviderConfigHealthSnapshot(
      fetchAttempts = fetchAttempts,
      fetchSuccesses = fetchSuccesses,
      fallbacks = fallbacks,
      successRate = ratio(fetchSuccesses, fetchAttempts),
      fallbackRate = ratio(fallbacks, fetchAttempts),
    )
  }

  private fun ratio(part: Int, total: Int): Double = if (total == 0) 0.0 else part.toDouble() / total.toDouble()
}

private val providerIdPattern = Regex("^[a-z0-9][a-z0-9_-]{0,63}$")

/** Adyen card and Worldpay bank. This is the Milestone 2 flagged default, not a third provider. */
fun milestone2BaselineConfig(): PaymentProviderConfig {
  return PaymentProviderConfig(
    providers = listOf(
      ConfiguredProvider(
        id = ProviderId.adyen,
        name = "Debit card",
        methods = listOf(PaymentMethod.card),
        corridors = listOf("UK", "US"),
      ),
      ConfiguredProvider(
        id = ProviderId.worldpay,
        name = "Bank payment",
        methods = listOf(PaymentMethod.bank),
        corridors = listOf("UK", "US"),
      ),
    ),
    configVersion = "milestone-2",
  )
}

fun validatePaymentProviderConfig(raw: PaymentProviderConfigResponse): PaymentProviderConfig {
  val version = raw.configVersion.trim()
  if (version.isEmpty()) {
    throw MeridianError.ValidationError("Payment provider configuration is missing configVersion")
  }
  val providers = raw.providers.mapNotNull { provider -> acceptedProvider(provider) }.distinctBy { it.id }
  if (providers.isEmpty()) {
    throw MeridianError.ValidationError("Payment provider configuration has no usable providers")
  }
  return PaymentProviderConfig(providers = providers, configVersion = version)
}

fun PaymentProviderConfig.providersForCorridor(corridor: String): List<ConfiguredProvider> {
  val key = corridor.trim().uppercase(Locale.US)
  if (key.isEmpty()) return emptyList()
  return providers.filter { provider -> provider.corridors.any { it.equals(key, ignoreCase = true) } }
}

fun pickerOptions(providers: List<ConfiguredProvider>): List<PickerOption> {
  return providers.flatMap { provider ->
    provider.methods.map { method ->
      val base = pickerLabel(provider, method)
      val label = if (provider.methods.size > 1) "$base · ${method.name}" else base
      PickerOption(providerId = provider.id, method = method, label = label)
    }
  }
}

/**
 * Keeps the customer's provider when a refresh arrives during review or an uncertain retry.
 * A timeout must not move the payment onto a different provider.
 */
fun retainProviderSelection(
  current: PickerOption?,
  options: List<PickerOption>,
  locked: Boolean,
): PickerOption? {
  if (current != null && (locked || options.any { it.providerId == current.providerId && it.method == current.method })) {
    return current
  }
  return options.firstOrNull()
}

private fun acceptedProvider(provider: PaymentProviderResponse): ConfiguredProvider? {
  val id = provider.id.trim().lowercase(Locale.US)
  if (!providerIdPattern.matches(id)) return null
  val name = provider.name.trim()
  if (name.isEmpty() || name.length > 80) return null
  val methods = provider.methods.mapNotNull { parsePaymentMethod(it) }.distinct()
  if (methods.isEmpty()) return null
  val corridors = provider.corridors.map { it.trim().uppercase(Locale.US) }.filter { it.isNotEmpty() }.distinct()
  if (corridors.isEmpty()) return null
  return ConfiguredProvider(id = ProviderId(id), name = name, methods = methods, corridors = corridors)
}

private fun parsePaymentMethod(value: String): PaymentMethod? {
  val normalized = value.trim().lowercase(Locale.US)
  return PaymentMethod.values().firstOrNull { it.name == normalized }
}

private fun pickerLabel(provider: ConfiguredProvider, method: PaymentMethod): String {
  val brand = when (provider.id.rawValue) {
    ProviderId.adyen.rawValue -> if (method == PaymentMethod.card) "Adyen" else null
    ProviderId.worldpay.rawValue -> if (method == PaymentMethod.bank) "Worldpay" else null
    else -> null
  }
  if (brand != null && !provider.name.contains(brand, ignoreCase = true)) {
    return "${provider.name} · $brand"
  }
  return provider.name
}
