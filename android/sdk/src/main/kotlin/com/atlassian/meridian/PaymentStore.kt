package com.atlassian.meridian

import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.io.File

/** One cached payment row. Legacy rows that omit currency are read as GBP. */
data class CachedPaymentRecord(
  val id: String,
  val minorUnits: Int,
  val currency: CurrencyCode,
  val reference: String,
  val recipientId: String,
  val providerId: ProviderId,
  val method: PaymentMethod,
  val status: TransactionStatus,
  val note: String = "",
  val idempotencyKey: String = "",
) {
  fun replacingIdempotencyKey(key: String): CachedPaymentRecord = copy(idempotencyKey = key)
}

data class RoutedPaymentRecords(
  val gbp: List<CachedPaymentRecord>,
  val eur: List<CachedPaymentRecord>,
)

fun paymentCacheMapper(): ObjectMapper =
  ObjectMapper().registerKotlinModule().apply {
    configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)
  }

fun routeCachedPayments(bytes: ByteArray, mapper: ObjectMapper = paymentCacheMapper()): RoutedPaymentRecords {
  val json = try {
    mapper.readTree(bytes)
  } catch (error: Exception) {
    throw MeridianError.DecodingError("Payment cache JSON could not be read", error)
  }
  val gbp = mutableListOf<CachedPaymentRecord>()
  val eur = mutableListOf<CachedPaymentRecord>()
  fun addAll(records: List<CachedPaymentRecord>) {
    records.forEach { record ->
      if (record.currency == CurrencyCode.eur) eur += record else gbp += record
    }
  }
  when {
    json.isObject && (json.has("GBPStore") || json.has("EURStore")) -> {
      if (json.has("GBPStore")) addAll(arrayRecords(json.get("GBPStore")))
      if (json.has("EURStore")) addAll(arrayRecords(json.get("EURStore")))
    }
    json.isObject && json.has("transactions") -> addAll(arrayRecords(json.get("transactions")))
    json.isObject && json.has("records") -> addAll(arrayRecords(json.get("records")))
    json.isArray -> addAll(json.map { parseCachedRecord(it) })
    json.isObject -> addAll(listOf(parseCachedRecord(json)))
    else -> throw MeridianError.DecodingError("Unrecognised payment cache payload")
  }
  return RoutedPaymentRecords(gbp, eur)
}

private fun arrayRecords(node: JsonNode): List<CachedPaymentRecord> {
  if (!node.isArray) throw MeridianError.DecodingError("Payment cache partition must be an array")
  return node.map { parseCachedRecord(it) }
}

fun parseCachedRecord(node: JsonNode): CachedPaymentRecord {
  if (!node.isObject) throw MeridianError.DecodingError("Payment record must be an object")
  val id = text(node, "id")
  if (id.isBlank()) throw MeridianError.DecodingError("Payment record id is required")
  val providerRaw = when {
    node.hasNonNull("providerId") -> node.get("providerId").asText()
    node.hasNonNull("provider") -> node.get("provider").asText()
    else -> throw MeridianError.DecodingError("Payment record provider is required")
  }
  val providerId = try {
    ProviderId.valueOf(providerRaw)
  } catch (error: IllegalArgumentException) {
    throw MeridianError.ValidationError("Unknown provider id")
  }
  val methodRaw = text(node, "method")
  val method = try {
    PaymentMethod.valueOf(methodRaw)
  } catch (error: IllegalArgumentException) {
    throw MeridianError.DecodingError("Payment record method is required")
  }
  val statusRaw = text(node, "status")
  val status = try {
    TransactionStatus.valueOf(statusRaw)
  } catch (error: IllegalArgumentException) {
    throw MeridianError.DecodingError("Payment record status is required")
  }
  return CachedPaymentRecord(
    id = id,
    minorUnits = integerMinorUnits(node),
    currency = currencyCode(node.get("currency")),
    reference = text(node, "reference"),
    recipientId = text(node, "recipientId"),
    providerId = providerId,
    method = method,
    status = status,
    note = text(node, "note"),
    idempotencyKey = text(node, "idempotencyKey"),
  )
}

private fun currencyCode(node: JsonNode?): CurrencyCode {
  if (node == null || node.isNull) return CurrencyCode.gbp
  return try {
    CurrencyCode.fromWire(node.asText())
  } catch (error: IllegalArgumentException) {
    throw MeridianError.ValidationError("Unknown currency code")
  }
}

private fun integerMinorUnits(node: JsonNode): Int {
  val value = when {
    node.hasNonNull("minorUnits") -> node.get("minorUnits")
    node.hasNonNull("amount") -> node.get("amount")
    else -> throw MeridianError.DecodingError("Payment record amount is required")
  }
  if (!value.isIntegralNumber) {
    throw MeridianError.ValidationError("minor units must be an integer")
  }
  return value.asInt()
}

private fun text(node: JsonNode, field: String): String =
  if (node.hasNonNull(field)) node.get(field).asText() else ""

/** File-backed partition. Writes stay inside this directory. */
open class CurrencySubStore(
  val name: String,
  val currency: CurrencyCode,
  directory: File,
  private val mapper: ObjectMapper = paymentCacheMapper(),
) {
  val paymentsFile: File = File(directory, "payments.json")
  private val lock = Any()

  init {
    directory.mkdirs()
  }

  fun load(): List<CachedPaymentRecord> = synchronized(lock) { loadUnlocked() }

  fun isEmpty(): Boolean = load().isEmpty()

  fun readBytes(): ByteArray = synchronized(lock) {
    if (!paymentsFile.exists()) ByteArray(0) else paymentsFile.readBytes()
  }

  fun save(records: List<CachedPaymentRecord>) {
    synchronized(lock) {
      records.firstOrNull { it.currency != currency }?.let { wrong ->
        throw MeridianError.ValidationError("$name cannot store ${wrong.currency.wire}")
      }
      writeUnlocked(records)
    }
  }

  /** Inserts or replaces a row. An existing idempotency key is kept. */
  fun upsert(record: CachedPaymentRecord) {
    synchronized(lock) {
      if (record.currency != currency) {
        throw MeridianError.ValidationError("${record.currency.wire} records stay out of $name")
      }
      val records = loadUnlocked().toMutableList()
      val index = records.indexOfFirst { existing ->
        existing.id == record.id ||
          (existing.idempotencyKey.isNotEmpty() && existing.idempotencyKey == record.idempotencyKey)
      }
      if (index >= 0) {
        val retained = records[index].idempotencyKey.ifEmpty { record.idempotencyKey }
        records[index] = record.replacingIdempotencyKey(retained)
      } else {
        records += record
      }
      writeUnlocked(records)
    }
  }

  private fun loadUnlocked(): List<CachedPaymentRecord> {
    if (!paymentsFile.exists() || paymentsFile.length() == 0L) return emptyList()
    val bytes = paymentsFile.readBytes()
    try {
      val type = mapper.typeFactory.constructCollectionType(List::class.java, CachedPaymentRecord::class.java)
      val records: List<CachedPaymentRecord> = mapper.readValue(bytes, type)
      if (records.any { it.currency != currency }) {
        throw MeridianError.ValidationError("$name contains another currency and was left unchanged")
      }
      return records
    } catch (error: MeridianError) {
      throw error
    } catch (_: Exception) {
      // Canonical rows failed; try the legacy shape below.
    }
    return try {
      val routed = routeCachedPayments(bytes, mapper)
      val mine = if (currency == CurrencyCode.gbp) routed.gbp else routed.eur
      val other = if (currency == CurrencyCode.gbp) routed.eur else routed.gbp
      if (other.isNotEmpty()) {
        throw MeridianError.ValidationError("$name contains another currency and was left unchanged")
      }
      mine
    } catch (error: MeridianError) {
      throw error
    } catch (error: Exception) {
      throw MeridianError.DecodingError("$name could not be read and was left unchanged", error)
    }
  }

  private fun writeUnlocked(records: List<CachedPaymentRecord>) {
    paymentsFile.parentFile?.mkdirs()
    val temporary = File(paymentsFile.parentFile, "payments.json.tmp")
    temporary.writeBytes(mapper.writeValueAsBytes(records))
    if (paymentsFile.exists() && !paymentsFile.delete()) {
      throw MeridianError.ValidationError("Unable to replace $name")
    }
    if (!temporary.renameTo(paymentsFile)) {
      throw MeridianError.ValidationError("Unable to commit $name")
    }
  }
}

class GBPStore(
  directory: File,
  mapper: ObjectMapper = paymentCacheMapper(),
) : CurrencySubStore("GBPStore", CurrencyCode.gbp, directory, mapper)

class EURStore(
  directory: File,
  mapper: ObjectMapper = paymentCacheMapper(),
) : CurrencySubStore("EURStore", CurrencyCode.eur, directory, mapper)

/**
 * Root cache split into GBPStore and EURStore directories.
 * A legacy file at the root is copied into GBPStore and is not rewritten.
 */
class IsolatedPaymentCache(
  val rootDirectory: File,
  private val mapper: ObjectMapper = paymentCacheMapper(),
) {
  val gbpStore: GBPStore = GBPStore(File(rootDirectory, "GBPStore"), mapper)
  val eurStore: EURStore = EURStore(File(rootDirectory, "EURStore"), mapper)

  init {
    rootDirectory.mkdirs()
    for (name in listOf("payments.json", "cache.json")) {
      val legacy = File(rootDirectory, name)
      if (legacy.isFile) adoptLegacyFile(legacy)
    }
  }

  /** Fills an empty domain from [bytes]. A domain that already has rows is left as-is. */
  fun importCached(bytes: ByteArray) {
    val routed = routeCachedPayments(bytes, mapper)
    if (routed.gbp.isNotEmpty() && gbpStore.isEmpty()) {
      gbpStore.save(routed.gbp)
    }
    if (routed.eur.isNotEmpty() && eurStore.isEmpty()) {
      eurStore.save(routed.eur)
    }
  }

  /** Reads a legacy cache without modifying that file. */
  fun adoptLegacyFile(source: File) {
    val before = source.readBytes()
    importCached(before)
    val after = source.readBytes()
    check(before.contentEquals(after)) { "Legacy cache was modified" }
  }
}
