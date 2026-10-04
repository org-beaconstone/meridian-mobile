package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.io.File
import java.security.SecureRandom
import java.util.UUID
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Payment fields bound to one idempotency key.
 * A retry or challenge must carry the same fingerprint as the initial attempt.
 */
data class PaymentAttempt(
  val recipientId: String,
  val amountMinor: Int,
  val method: String,
  val note: String,
  val scenario: String,
) {
  fun fingerprint(): String = listOf(recipientId, amountMinor.toString(), method, note, scenario)
    .joinToString(UNIT_SEPARATOR) { escapeFingerprintPart(it) }

  companion object {
    private const val UNIT_SEPARATOR = "\u001f"

    fun fromFingerprint(value: String): PaymentAttempt? {
      val parts = value.split(UNIT_SEPARATOR)
      if (parts.size != 5) return null
      val amount = parts[1].unescapeFingerprintPart().toIntOrNull() ?: return null
      return PaymentAttempt(
        recipientId = parts[0].unescapeFingerprintPart(),
        amountMinor = amount,
        method = parts[2].unescapeFingerprintPart(),
        note = parts[3].unescapeFingerprintPart(),
        scenario = parts[4].unescapeFingerprintPart(),
      )
    }
  }
}

internal fun escapeFingerprintPart(value: String): String =
  value.replace("\\", "\\\\").replace("\u001f", "\\u001f")

internal fun String.unescapeFingerprintPart(): String {
  val out = StringBuilder()
  var index = 0
  while (index < length) {
    if (this[index] == '\\' && index + 1 < length) {
      when {
        this[index + 1] == '\\' -> {
          out.append('\\')
          index += 2
          continue
        }
        startsWith("\\u001f", index) -> {
          out.append('\u001f')
          index += 6
          continue
        }
      }
    }
    out.append(this[index])
    index += 1
  }
  return out.toString()
}

data class IdempotencyRecord(
  val transactionId: String,
  val key: String,
  val createdAtEpochMillis: Long,
  val fingerprint: String? = null,
)

data class IdempotencySnapshot(
  val version: Int = 1,
  val records: List<IdempotencyRecord> = emptyList(),
)

interface IdempotencyStore {
  fun load(): List<IdempotencyRecord>
  fun save(records: List<IdempotencyRecord>)
}

class MemoryIdempotencyStore : IdempotencyStore {
  private val lock = ReentrantLock()
  private var records: List<IdempotencyRecord> = emptyList()

  override fun load(): List<IdempotencyRecord> = lock.withLock { records.toList() }

  override fun save(records: List<IdempotencyRecord>) = lock.withLock {
    this.records = records.toList()
  }
}

class FileIdempotencyStore(
  val file: File,
  private val mapper: ObjectMapper = ObjectMapper().registerKotlinModule(),
) : IdempotencyStore {
  private val lock = ReentrantLock()

  override fun load(): List<IdempotencyRecord> = lock.withLock {
    if (!file.exists() || file.length() == 0L) return emptyList()
    try {
      mapper.readValue(file, IdempotencySnapshot::class.java).records
    } catch (error: Exception) {
      throw MeridianError.ValidationError(
        "Idempotency store is unreadable at ${file.path}",
        error,
      )
    }
  }

  override fun save(records: List<IdempotencyRecord>) = lock.withLock {
    val parent = file.parentFile ?: File(".")
    parent.mkdirs()
    val tmp = File(parent, "${file.name}.tmp")
    mapper.writeValue(tmp, IdempotencySnapshot(version = 1, records = records))
    if (!tmp.renameTo(file)) {
      file.writeBytes(tmp.readBytes())
      tmp.delete()
    }
  }

  companion object {
    fun fileFor(directory: File, sessionId: String): File {
      val safe = sessionId.replace(Regex("[^A-Za-z0-9_-]"), "_")
      return File(directory, "idempotency-$safe.json")
    }
  }
}

/**
 * Generates, persists, and attaches UUID v4 idempotency keys for one payment lifecycle.
 *
 * Keys are cryptographically random UUID v4 strings. The same key is reused for network
 * retries and two-factor challenge submissions. In-flight keys expire after 24 hours so
 * they stay inside the gateway's Redis deduplication window. The cache drops a key after
 * successful terminal settlement or an explicit cancellation.
 */
class IdempotencyKeyManager(
  private val store: IdempotencyStore = MemoryIdempotencyStore(),
  private val clock: () -> Long = { System.currentTimeMillis() },
  private val uuidGenerator: () -> String = { secureUuidV4() },
  val ttlMillis: Long = TWENTY_FOUR_HOURS_MILLIS,
) {
  private val lock = ReentrantLock()
  private val entries = linkedMapOf<String, IdempotencyRecord>()

  init {
    require(ttlMillis > 0L) { "Idempotency TTL must be positive" }
    lock.withLock {
      for (record in store.load()) {
        entries[record.transactionId] = record
      }
    }
  }

  fun begin(transactionId: String, fingerprint: String? = null): String = lock.withLock {
    require(transactionId.isNotBlank()) { "transactionId is required" }
    val existing = entries[transactionId]
    if (existing != null && !isExpired(existing)) {
      bindFingerprint(existing, fingerprint)
      return existing.key
    }
    val key = uuidGenerator()
    require(isUuidV4(key)) { "Idempotency key generator must return a UUID v4" }
    val record = IdempotencyRecord(
      transactionId = transactionId,
      key = key,
      createdAtEpochMillis = clock(),
      fingerprint = fingerprint,
    )
    write(transactionId, record)
    record.key
  }

  fun keyForRetry(transactionId: String, fingerprint: String? = null): String =
    requireActive(transactionId, fingerprint)

  fun keyForChallenge(transactionId: String, fingerprint: String? = null): String =
    requireActive(transactionId, fingerprint)

  fun activeKey(transactionId: String): String? = lock.withLock {
    entries[transactionId]?.takeUnless { isExpired(it) }?.key
  }

  fun activeRecords(): List<IdempotencyRecord> = lock.withLock {
    entries.values.filterNot { isExpired(it) }
  }

  fun storedRecords(): List<IdempotencyRecord> = lock.withLock {
    entries.values.toList()
  }

  fun settle(transactionId: String) = purge(transactionId)

  fun cancel(transactionId: String) = purge(transactionId)

  private fun requireActive(transactionId: String, fingerprint: String?): String = lock.withLock {
    val existing = entries[transactionId] ?: throw MeridianError.MissingIdempotencyKey(transactionId)
    if (isExpired(existing)) {
      throw MeridianError.IdempotencyKeyExpired(transactionId)
    }
    bindFingerprint(existing, fingerprint)
    existing.key
  }

  private fun bindFingerprint(existing: IdempotencyRecord, fingerprint: String?) {
    if (fingerprint == null) return
    val bound = existing.fingerprint
    if (bound == null) {
      write(existing.transactionId, existing.copy(fingerprint = fingerprint))
      return
    }
    if (bound != fingerprint) {
      throw MeridianError.ValidationError(
        "Idempotency key is bound to a different payment",
      )
    }
  }

  private fun purge(transactionId: String) = lock.withLock {
    write(transactionId, null)
  }

  private fun write(transactionId: String, record: IdempotencyRecord?) {
    val previous = entries[transactionId]
    if (record == null) entries.remove(transactionId) else entries[transactionId] = record
    try {
      persistLocked()
    } catch (error: Exception) {
      if (previous == null) entries.remove(transactionId) else entries[transactionId] = previous
      throw error
    }
  }

  private fun isExpired(record: IdempotencyRecord): Boolean =
    clock() - record.createdAtEpochMillis >= ttlMillis

  private fun persistLocked() {
    store.save(entries.values.toList())
  }

  companion object {
    const val TWENTY_FOUR_HOURS_MILLIS: Long = 24L * 60 * 60 * 1000
    const val HEADER: String = "Idempotency-Key"

    private val secureRandom = SecureRandom()
    private val UUID_V4 =
      Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")

    fun isUuidV4(value: String): Boolean = UUID_V4.matches(value.lowercase())

    fun secureUuidV4(): String {
      val bytes = ByteArray(16)
      secureRandom.nextBytes(bytes)
      bytes[6] = ((bytes[6].toInt() and 0x0f) or 0x40).toByte()
      bytes[8] = ((bytes[8].toInt() and 0x3f) or 0x80).toByte()
      var msb = 0L
      var lsb = 0L
      for (index in 0 until 8) {
        msb = (msb shl 8) or (bytes[index].toLong() and 0xff)
      }
      for (index in 8 until 16) {
        lsb = (lsb shl 8) or (bytes[index].toLong() and 0xff)
      }
      return UUID(msb, lsb).toString()
    }
  }
}
