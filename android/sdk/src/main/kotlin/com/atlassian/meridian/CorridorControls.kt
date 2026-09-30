package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper

const val PAYMENTS_PAUSED_MESSAGE = "New payments are paused. Status and receipts stay available."

/** GB is the domestic rehearsal corridor. EU is the European corridor. */
enum class PaymentCorridor {
  GB,
  EU,
  ;

  companion object {
    fun fromRaw(raw: String): PaymentCorridor? = when (raw.uppercase()) {
      "GB" -> GB
      "EU" -> EU
      else -> null
    }
  }
}

data class CorridorMethod(
  val id: String,
  val provider: ProviderId,
  val method: PaymentMethod,
  val corridor: PaymentCorridor,
  val label: String,
) {
  companion object {
    val baseline: List<CorridorMethod> = listOf(
      CorridorMethod("adyen-card-gb", ProviderId.adyen, PaymentMethod.card, PaymentCorridor.GB, "Debit card · Adyen"),
      CorridorMethod("worldpay-bank-gb", ProviderId.worldpay, PaymentMethod.bank, PaymentCorridor.GB, "Bank payment · Worldpay"),
      CorridorMethod("adyen-card-eu", ProviderId.adyen, PaymentMethod.card, PaymentCorridor.EU, "Debit card · Adyen · European corridor"),
      CorridorMethod("worldpay-bank-eu", ProviderId.worldpay, PaymentMethod.bank, PaymentCorridor.EU, "Bank payment · Worldpay · European corridor"),
    )

    fun forCorridors(corridors: List<PaymentCorridor>): List<CorridorMethod> =
      baseline.filter { it.corridor in corridors }
  }
}

data class CorridorFlags(
  val multiProviderSelection: Boolean,
  val europeanCorridorEnabled: Boolean,
  val darkLaunch: Boolean,
  val killSwitch: Boolean,
  val canaryAccounts: List<String>,
) {
  companion object {
    val rehearsalDefault = CorridorFlags(
      multiProviderSelection = true,
      europeanCorridorEnabled = false,
      darkLaunch = false,
      killSwitch = false,
      canaryAccounts = emptyList(),
    )
  }
}

data class CatalogSnapshot(
  val version: Int,
  val methods: List<CorridorMethod>,
)

enum class IntentStatus {
  inFlight,
  completed,
  declined,
}

data class IntentReceipt(
  val reference: String,
  val amountMinor: Int,
  val methodId: String,
  val provider: ProviderId,
)

data class PaymentIntentRecord(
  val id: String,
  val idempotencyKey: String,
  val accountId: String,
  val recipientId: String,
  val amountMinor: Int,
  val note: String,
  val methodId: String,
  val provider: ProviderId,
  val method: PaymentMethod,
  val corridor: PaymentCorridor,
  val snapshot: CatalogSnapshot,
  val status: IntentStatus,
  val receipt: IntentReceipt?,
)

data class DarkLaunchEvent(
  val generation: Int,
  val accountId: String,
  val catalogVersion: Int,
  val corridor: String,
  val europeanMethodsHidden: Boolean,
)

enum class IntentRejection {
  KILL_SWITCH,
  METHOD_UNAVAILABLE,
  INVALID_AMOUNT,
  MISSING_IDEMPOTENCY_KEY,
  ;

  val message: String
    get() = when (this) {
      KILL_SWITCH -> PAYMENTS_PAUSED_MESSAGE
      METHOD_UNAVAILABLE -> "That payment method is not available."
      INVALID_AMOUNT -> "Amount must be from 1 to 1000000 pence."
      MISSING_IDEMPOTENCY_KEY -> "Idempotency key is required."
    }
}

sealed class IntentResult {
  data class Created(val intent: PaymentIntentRecord) : IntentResult()
  data class Rejected(val reason: IntentRejection) : IntentResult()
}

/**
 * Server-driven corridor flags, dark launch telemetry, the operational kill switch,
 * and catalog rollback. Applying a payload replaces the previous flags immediately.
 * In-flight intents keep the catalog snapshot copied at creation.
 */
class CorridorControls {
  private val mapper = ObjectMapper()
  var flags: CorridorFlags = CorridorFlags.rehearsalDefault
    private set
  var activeCatalog: CatalogSnapshot
    private set
  var telemetry: List<DarkLaunchEvent> = emptyList()
    private set
  private var history: MutableMap<Int, CatalogSnapshot>
  private val intentsById = linkedMapOf<String, PaymentIntentRecord>()
  private val intentIdByKey = linkedMapOf<String, String>()
  private var generation = 0
  private var identity = 0

  init {
    val initial = CatalogSnapshot(1, CorridorMethod.forCorridors(listOf(PaymentCorridor.GB)))
    activeCatalog = initial
    history = mutableMapOf(1 to initial)
  }

  fun reset() {
    val fresh = CorridorControls()
    flags = fresh.flags
    activeCatalog = fresh.activeCatalog
    history = fresh.history
    telemetry = emptyList()
    intentsById.clear()
    intentIdByKey.clear()
    generation = 0
  }

  /** Returns false when the payload is not a config object. State is left unchanged. */
  fun applyServerPayload(json: String): Boolean {
    val node = try {
      mapper.readTree(json)
    } catch (_: Exception) {
      return false
    }
    if (node == null || !node.isObject) return false
    flags = CorridorFlags(
      multiProviderSelection = boolFlag(node, "multi_provider_selection", true),
      europeanCorridorEnabled = boolFlag(node, "european_corridor", false),
      darkLaunch = boolFlag(node, "dark_launch", false),
      killSwitch = boolFlag(node, "payments_kill_switch", false),
      canaryAccounts = stringList(node),
    )
    generation += 1
    if (node.has("catalogs")) install(node.get("catalogs"))
    val versionNode = node.get("catalogVersion")
    if (versionNode != null && versionNode.isIntegralNumber) {
      activate(versionNode.intValue())
    }
    return true
  }

  fun publishCatalog(version: Int, corridors: List<PaymentCorridor>): Boolean {
    val seen = corridors.distinct()
    if (version <= 0 || seen.isEmpty()) return false
    val snapshot = CatalogSnapshot(version, CorridorMethod.forCorridors(seen))
    history[version] = snapshot
    activeCatalog = snapshot
    return true
  }

  /** Activates a stored catalog version. Intent snapshots are not rewritten. */
  fun rollbackCatalog(toVersion: Int): Boolean = activate(toVersion)

  fun visibleMethods(accountId: String): List<CorridorMethod> {
    val allowEurope = europeanMethodsVisible(accountId)
    return activeCatalog.methods.filter { method ->
      if (method.corridor == PaymentCorridor.EU && !allowEurope) return@filter false
      if (!flags.multiProviderSelection && !(method.provider == ProviderId.adyen && method.method == PaymentMethod.card)) {
        return@filter false
      }
      true
    }
  }

  /** Records one dark-launch telemetry event per flag generation and account. */
  fun resolve(accountId: String): List<CorridorMethod> {
    val methods = visibleMethods(accountId)
    if (flags.darkLaunch) {
      val already = telemetry.any { it.generation == generation && it.accountId == accountId }
      if (!already) {
        telemetry = telemetry + DarkLaunchEvent(
          generation = generation,
          accountId = accountId,
          catalogVersion = activeCatalog.version,
          corridor = "EU",
          europeanMethodsHidden = methods.none { it.corridor == PaymentCorridor.EU },
        )
      }
    }
    return methods
  }

  fun blocksNewIntent(idempotencyKey: String): Boolean {
    if (intentIdByKey.containsKey(idempotencyKey)) return false
    return flags.killSwitch
  }

  fun createIntent(
    idempotencyKey: String,
    accountId: String,
    recipientId: String,
    amountMinor: Int,
    note: String = "",
    methodId: String,
  ): IntentResult {
    val existingId = intentIdByKey[idempotencyKey]
    if (existingId != null) {
      val existing = intentsById[existingId]
      if (existing != null) return IntentResult.Created(existing)
    }
    if (idempotencyKey.isEmpty() || idempotencyKey.length > 100) {
      return IntentResult.Rejected(IntentRejection.MISSING_IDEMPOTENCY_KEY)
    }
    if (flags.killSwitch) return IntentResult.Rejected(IntentRejection.KILL_SWITCH)
    if (amountMinor < 1 || amountMinor > 1_000_000) {
      return IntentResult.Rejected(IntentRejection.INVALID_AMOUNT)
    }
    val selected = visibleMethods(accountId).firstOrNull { it.id == methodId }
      ?: return IntentResult.Rejected(IntentRejection.METHOD_UNAVAILABLE)
    identity += 1
    val record = PaymentIntentRecord(
      id = "intent-$identity",
      idempotencyKey = idempotencyKey,
      accountId = accountId,
      recipientId = recipientId,
      amountMinor = amountMinor,
      note = note,
      methodId = selected.id,
      provider = selected.provider,
      method = selected.method,
      corridor = selected.corridor,
      snapshot = activeCatalog.copy(methods = activeCatalog.methods.toList()),
      status = IntentStatus.inFlight,
      receipt = null,
    )
    intentsById[record.id] = record
    intentIdByKey[idempotencyKey] = record.id
    return IntentResult.Created(record)
  }

  fun intent(id: String): PaymentIntentRecord? = intentsById[id]

  fun status(intentId: String): IntentStatus? = intentsById[intentId]?.status

  fun receipt(intentId: String): IntentReceipt? = intentsById[intentId]?.receipt

  /** True when the intent's own snapshot still contains its method, whatever the live catalog is. */
  fun snapshotRemainsValid(intentId: String): Boolean {
    val intent = intentsById[intentId] ?: return false
    return intent.snapshot.version > 0 && intent.snapshot.methods.any { it.id == intent.methodId }
  }

  fun complete(intentId: String, reference: String): IntentReceipt? {
    val intent = intentsById[intentId] ?: return null
    val receipt = IntentReceipt(reference, intent.amountMinor, intent.methodId, intent.provider)
    intentsById[intentId] = intent.copy(status = IntentStatus.completed, receipt = receipt)
    return receipt
  }

  fun markDeclined(intentId: String) {
    val intent = intentsById[intentId] ?: return
    intentsById[intentId] = intent.copy(status = IntentStatus.declined)
  }

  private fun europeanMethodsVisible(accountId: String): Boolean {
    if (flags.darkLaunch) return false
    if (!flags.europeanCorridorEnabled) return false
    if (flags.canaryAccounts.isEmpty()) return true
    return accountId in flags.canaryAccounts
  }

  private fun activate(version: Int): Boolean {
    val snapshot = history[version] ?: return false
    activeCatalog = snapshot
    return true
  }

  private fun install(node: JsonNode?) {
    if (node == null || !node.isArray) return
    val next = linkedMapOf<Int, CatalogSnapshot>()
    for (item in node) {
      if (!item.isObject) continue
      val versionNode = item.get("version")
      if (versionNode == null || !versionNode.isIntegralNumber) continue
      val version = versionNode.intValue()
      if (version <= 0) continue
      val names = item.get("corridors")
      if (names == null || !names.isArray) continue
      val corridors = mutableListOf<PaymentCorridor>()
      for (name in names) {
        if (!name.isTextual) continue
        val corridor = PaymentCorridor.fromRaw(name.asText()) ?: continue
        if (corridor !in corridors) corridors.add(corridor)
      }
      if (corridors.isEmpty()) continue
      next[version] = CatalogSnapshot(version, CorridorMethod.forCorridors(corridors))
    }
    if (next.isNotEmpty()) history = next
  }

  private fun boolFlag(root: JsonNode, key: String, defaultValue: Boolean): Boolean {
    val flags = root.get("flags")
    val chosen = when {
      flags != null && flags.isObject && flags.has(key) -> flags.get(key)
      root.has(key) -> root.get(key)
      else -> null
    } ?: return defaultValue
    return coerce(chosen)
  }

  private fun coerce(node: JsonNode): Boolean {
    if (node.isNull) return false
    if (node.isBoolean) return node.booleanValue()
    if (node.isTextual) return node.asText().equals("true", ignoreCase = true)
    return false
  }

  private fun stringList(root: JsonNode): List<String> {
    val node = when {
      root.has("canaryAccounts") -> root.get("canaryAccounts")
      root.has("controlledAccounts") -> root.get("controlledAccounts")
      else -> return emptyList()
    }
    if (!node.isArray) return emptyList()
    return node.mapNotNull { item -> if (item.isTextual) item.asText() else null }
  }
}
