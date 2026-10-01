package com.atlassian.meridian

import com.fasterxml.jackson.annotation.JsonIgnoreProperties
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/**
 * Terminal snapshots are kept for this window so a restart can still show the
 * outcome and the idempotency key, then they are removed.
 */
object PaymentIntentRetention {
  const val TERMINAL_WINDOW_MS: Long = 24L * 60L * 60L * 1000L
}

enum class PaymentIntentStatus {
  created,
  pending,
  processing,
  succeeded,
  declined,
  failed,
  cancelled;

  val isTerminal: Boolean
    get() = this == succeeded || this == declined || this == failed || this == cancelled
}

@JsonIgnoreProperties(ignoreUnknown = true)
data class PaymentReturnState(
  val ok: Boolean,
  val paymentId: String? = null,
  val code: String? = null,
  val error: String? = null,
  val stateVersion: Int? = null,
  val balancePence: Int? = null,
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class PaymentIntentSnapshot(
  val paymentIntentId: String,
  val customerAccountId: String,
  val idempotencyKey: String,
  val businessPayloadHash: String,
  val status: PaymentIntentStatus,
  val returnState: PaymentReturnState? = null,
  val returnStateHash: String? = null,
  val recipientId: String,
  val amountMinor: Int,
  val method: PaymentMethod,
  val note: String,
  val createdAtEpochMs: Long,
  val updatedAtEpochMs: Long,
  val terminalAtEpochMs: Long? = null,
) {
  fun isExpired(nowEpochMs: Long): Boolean {
    if (!status.isTerminal) return false
    val terminalAt = terminalAtEpochMs ?: updatedAtEpochMs
    return nowEpochMs >= terminalAt + PaymentIntentRetention.TERMINAL_WINDOW_MS
  }
}

data class PaymentIntentDraft(
  val customerAccountId: String,
  val paymentIntentId: String,
  val idempotencyKey: String,
  val recipientId: String,
  val amountMinor: Int,
  val method: PaymentMethod,
  val note: String,
)

data class BeginPaymentIntent(
  val snapshot: PaymentIntentSnapshot,
  val created: Boolean,
  val payloadMatches: Boolean,
)

class SnapshotError(message: String) : MeridianError(message)

object PaymentIntentAccounts {
  private val accountPattern = Regex("^[A-Za-z0-9._-]{1,128}$")
  private val idPattern = Regex("^[A-Za-z0-9_-]{8,80}$")
  private val recipientPattern = Regex("^[A-Za-z0-9_-]{1,128}$")

  fun isValidAccount(id: String): Boolean = accountPattern.matches(id)

  fun requireAccount(id: String) {
    if (!isValidAccount(id)) {
      throw SnapshotError("Customer account id is required")
    }
  }

  fun requireIntentId(id: String, label: String) {
    if (!idPattern.matches(id)) {
      throw SnapshotError("$label is invalid")
    }
  }

  fun requireDraft(draft: PaymentIntentDraft) {
    requireAccount(draft.customerAccountId)
    requireIntentId(draft.paymentIntentId, "Payment intent id")
    requireIntentId(draft.idempotencyKey, "Idempotency key")
    if (!recipientPattern.matches(draft.recipientId)) {
      throw SnapshotError("Recipient id is invalid")
    }
    if (draft.amountMinor !in 1..1_000_000) {
      throw SnapshotError("Amount must be between 1 and 1000000 pence")
    }
    if (draft.note.length > 200 || draft.note.any { it.code < 0x20 }) {
      throw SnapshotError("Reference is too long")
    }
  }
}

internal fun jsonString(value: String): String {
  val builder = StringBuilder(value.length + 2)
  builder.append('"')
  for (ch in value) {
    when (ch) {
      '\\' -> builder.append("\\\\")
      '"' -> builder.append("\\\"")
      '\n' -> builder.append("\\n")
      '\r' -> builder.append("\\r")
      '\t' -> builder.append("\\t")
      else -> {
        if (ch.code < 0x20) {
          builder.append("\\u")
          builder.append(ch.code.toString(16).padStart(4, '0'))
        } else {
          builder.append(ch)
        }
      }
    }
  }
  builder.append('"')
  return builder.toString()
}

internal fun sha256Hex(text: String): String {
  val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
  val builder = StringBuilder(digest.size * 2)
  for (byte in digest) {
    builder.append("%02x".format(byte.toInt() and 0xff))
  }
  return builder.toString()
}

fun businessPayloadHash(
  customerAccountId: String,
  recipientId: String,
  amountMinor: Int,
  method: PaymentMethod,
  note: String,
): String {
  val canonical = buildString {
    append("{\"amountMinor\":")
    append(amountMinor)
    append(",\"customerAccountId\":")
    append(jsonString(customerAccountId))
    append(",\"method\":")
    append(jsonString(method.name))
    append(",\"note\":")
    append(jsonString(note))
    append(",\"recipientId\":")
    append(jsonString(recipientId))
    append('}')
  }
  return sha256Hex(canonical)
}

fun returnStateHash(state: PaymentReturnState): String {
  val canonical = buildString {
    append("{\"balancePence\":")
    append(state.balancePence?.toString() ?: "null")
    append(",\"code\":")
    append(state.code?.let(::jsonString) ?: "null")
    append(",\"error\":")
    append(state.error?.let(::jsonString) ?: "null")
    append(",\"ok\":")
    append(if (state.ok) "true" else "false")
    append(",\"paymentId\":")
    append(state.paymentId?.let(::jsonString) ?: "null")
    append(",\"stateVersion\":")
    append(state.stateVersion?.toString() ?: "null")
    append('}')
  }
  return sha256Hex(canonical)
}

fun paymentIntentStatus(response: PaymentResponse): PaymentIntentStatus {
  if (response.ok) return PaymentIntentStatus.succeeded
  val code = response.code?.uppercase() ?: ""
  if (code.contains("PENDING") || response.transaction?.status == TransactionStatus.pending.name) {
    return PaymentIntentStatus.pending
  }
  if (code.contains("DECLIN") || response.transaction?.status == TransactionStatus.declined.name) {
    return PaymentIntentStatus.declined
  }
  if (code.contains("UNAVAILABLE") || code.contains("TIMEOUT")) {
    return PaymentIntentStatus.processing
  }
  if (code.isEmpty()) return PaymentIntentStatus.processing
  return PaymentIntentStatus.failed
}

fun paymentReturnState(response: PaymentResponse): PaymentReturnState {
  return PaymentReturnState(
    ok = response.ok,
    paymentId = response.paymentId ?: response.transaction?.id,
    code = response.code,
    error = response.error,
    stateVersion = response.state?.version,
    balancePence = response.state?.balance,
  )
}

/** Filesystem-safe scope key. The customer account id itself stays inside the encrypted record. */
fun accountStorageKey(customerAccountId: String): String = sha256Hex(customerAccountId)

interface PaymentIntentSnapshotStore {
  fun save(snapshot: PaymentIntentSnapshot)
  fun load(customerAccountId: String, paymentIntentId: String): PaymentIntentSnapshot?
  fun loadAll(customerAccountId: String): List<PaymentIntentSnapshot>
  fun delete(customerAccountId: String, paymentIntentId: String)
}

class InMemoryPaymentIntentSnapshotStore : PaymentIntentSnapshotStore {
  private val lock = Any()
  private val records = HashMap<String, MutableMap<String, PaymentIntentSnapshot>>()

  override fun save(snapshot: PaymentIntentSnapshot) {
    PaymentIntentAccounts.requireAccount(snapshot.customerAccountId)
    synchronized(lock) {
      val account = records.getOrPut(snapshot.customerAccountId) { HashMap() }
      account[snapshot.paymentIntentId] = snapshot.copy()
    }
  }

  override fun load(customerAccountId: String, paymentIntentId: String): PaymentIntentSnapshot? {
    synchronized(lock) {
      return records[customerAccountId]?.get(paymentIntentId)?.takeIf {
        it.customerAccountId == customerAccountId
      }
    }
  }

  override fun loadAll(customerAccountId: String): List<PaymentIntentSnapshot> {
    synchronized(lock) {
      return records[customerAccountId].orEmpty().values
        .filter { it.customerAccountId == customerAccountId }
        .map { it.copy() }
    }
  }

  override fun delete(customerAccountId: String, paymentIntentId: String) {
    synchronized(lock) {
      records[customerAccountId]?.remove(paymentIntentId)
    }
  }
}

/** One preference file per customer account, matching the encrypted on-device layout. */
interface SecurePreferenceFile {
  fun get(key: String): String?
  fun put(key: String, value: String)
  fun remove(key: String)
  fun entries(): Map<String, String>
}

fun interface SecurePreferenceFiles {
  fun fileFor(customerAccountId: String): SecurePreferenceFile
}

class PreferencePaymentIntentSnapshotStore(
  private val files: SecurePreferenceFiles,
  private val mapper: ObjectMapper = ObjectMapper().registerKotlinModule(),
) : PaymentIntentSnapshotStore {
  override fun save(snapshot: PaymentIntentSnapshot) {
    PaymentIntentAccounts.requireAccount(snapshot.customerAccountId)
    val payload = mapper.writeValueAsString(snapshot)
    files.fileFor(snapshot.customerAccountId).put(snapshot.paymentIntentId, payload)
  }

  override fun load(customerAccountId: String, paymentIntentId: String): PaymentIntentSnapshot? {
    PaymentIntentAccounts.requireAccount(customerAccountId)
    val raw = files.fileFor(customerAccountId).get(paymentIntentId) ?: return null
    val snapshot = mapper.readValue(raw, PaymentIntentSnapshot::class.java)
    return snapshot.takeIf {
      it.customerAccountId == customerAccountId && it.paymentIntentId == paymentIntentId
    }
  }

  override fun loadAll(customerAccountId: String): List<PaymentIntentSnapshot> {
    PaymentIntentAccounts.requireAccount(customerAccountId)
    return files.fileFor(customerAccountId).entries().values.mapNotNull { raw ->
      runCatching { mapper.readValue(raw, PaymentIntentSnapshot::class.java) }.getOrNull()
    }.filter { it.customerAccountId == customerAccountId }
  }

  override fun delete(customerAccountId: String, paymentIntentId: String) {
    PaymentIntentAccounts.requireAccount(customerAccountId)
    files.fileFor(customerAccountId).remove(paymentIntentId)
  }
}

class MemorySecurePreferenceFiles : SecurePreferenceFiles {
  private val files = ConcurrentHashMap<String, MemorySecurePreferenceFile>()

  override fun fileFor(customerAccountId: String): SecurePreferenceFile {
    val key = accountStorageKey(customerAccountId)
    return files.getOrPut(key) { MemorySecurePreferenceFile() }
  }
}

class MemorySecurePreferenceFile : SecurePreferenceFile {
  private val lock = Any()
  private val values = LinkedHashMap<String, String>()

  override fun get(key: String): String? = synchronized(lock) { values[key] }

  override fun put(key: String, value: String) {
    synchronized(lock) { values[key] = value }
  }

  override fun remove(key: String) {
    synchronized(lock) { values.remove(key) }
  }

  override fun entries(): Map<String, String> = synchronized(lock) { LinkedHashMap(values) }
}

class PaymentIntentSnapshotRepository(
  private val store: PaymentIntentSnapshotStore,
) {
  private val lock = Any()

  fun begin(draft: PaymentIntentDraft, nowEpochMs: Long): BeginPaymentIntent = synchronized(lock) {
    PaymentIntentAccounts.requireDraft(draft)
    purgeExpiredLocked(draft.customerAccountId, nowEpochMs)
    val hash = businessPayloadHash(
      customerAccountId = draft.customerAccountId,
      recipientId = draft.recipientId,
      amountMinor = draft.amountMinor,
      method = draft.method,
      note = draft.note,
    )
    val active = store.loadAll(draft.customerAccountId).filter { !it.status.isTerminal }
    val samePayload = active.firstOrNull { it.businessPayloadHash == hash }
    if (samePayload != null) {
      return BeginPaymentIntent(snapshot = samePayload, created = false, payloadMatches = true)
    }
    val other = active.firstOrNull()
    if (other != null) {
      return BeginPaymentIntent(snapshot = other, created = false, payloadMatches = false)
    }
    val snapshot = PaymentIntentSnapshot(
      paymentIntentId = draft.paymentIntentId,
      customerAccountId = draft.customerAccountId,
      idempotencyKey = draft.idempotencyKey,
      businessPayloadHash = hash,
      status = PaymentIntentStatus.processing,
      returnState = null,
      returnStateHash = null,
      recipientId = draft.recipientId,
      amountMinor = draft.amountMinor,
      method = draft.method,
      note = draft.note,
      createdAtEpochMs = nowEpochMs,
      updatedAtEpochMs = nowEpochMs,
      terminalAtEpochMs = null,
    )
    store.save(snapshot)
    BeginPaymentIntent(snapshot = snapshot, created = true, payloadMatches = true)
  }

  fun recordOutcome(
    customerAccountId: String,
    paymentIntentId: String,
    response: PaymentResponse,
    nowEpochMs: Long,
  ): PaymentIntentSnapshot = synchronized(lock) {
    val current = requireOwned(customerAccountId, paymentIntentId)
    if (current.status.isTerminal) return current
    val status = paymentIntentStatus(response)
    val returnState = paymentReturnState(response)
    val updated = current.copy(
      status = status,
      returnState = returnState,
      returnStateHash = returnStateHash(returnState),
      updatedAtEpochMs = nowEpochMs,
      terminalAtEpochMs = if (status.isTerminal) current.terminalAtEpochMs ?: nowEpochMs else null,
    )
    store.save(updated)
    updated
  }

  fun markUncertain(
    customerAccountId: String,
    paymentIntentId: String,
    nowEpochMs: Long,
  ): PaymentIntentSnapshot = synchronized(lock) {
    val current = requireOwned(customerAccountId, paymentIntentId)
    if (current.status.isTerminal) return current
    val updated = current.copy(
      status = PaymentIntentStatus.processing,
      updatedAtEpochMs = nowEpochMs,
      terminalAtEpochMs = null,
    )
    store.save(updated)
    updated
  }

  fun cancel(
    customerAccountId: String,
    paymentIntentId: String,
    nowEpochMs: Long,
  ): PaymentIntentSnapshot? = synchronized(lock) {
    PaymentIntentAccounts.requireAccount(customerAccountId)
    val current = store.load(customerAccountId, paymentIntentId) ?: return null
    if (current.customerAccountId != customerAccountId) return null
    if (current.status.isTerminal) return current
    val updated = current.copy(
      status = PaymentIntentStatus.cancelled,
      updatedAtEpochMs = nowEpochMs,
      terminalAtEpochMs = nowEpochMs,
    )
    store.save(updated)
    updated
  }

  fun resumeActive(customerAccountId: String, nowEpochMs: Long): List<PaymentIntentSnapshot> =
    synchronized(lock) {
      PaymentIntentAccounts.requireAccount(customerAccountId)
      purgeExpiredLocked(customerAccountId, nowEpochMs)
      store.loadAll(customerAccountId).filter { !it.status.isTerminal && !it.isExpired(nowEpochMs) }
    }

  fun load(
    customerAccountId: String,
    paymentIntentId: String,
    nowEpochMs: Long,
  ): PaymentIntentSnapshot? = synchronized(lock) {
    PaymentIntentAccounts.requireAccount(customerAccountId)
    purgeExpiredLocked(customerAccountId, nowEpochMs)
    store.load(customerAccountId, paymentIntentId)?.takeIf { !it.isExpired(nowEpochMs) }
  }

  fun purgeExpired(customerAccountId: String, nowEpochMs: Long): Int = synchronized(lock) {
    PaymentIntentAccounts.requireAccount(customerAccountId)
    purgeExpiredLocked(customerAccountId, nowEpochMs)
  }

  private fun purgeExpiredLocked(customerAccountId: String, nowEpochMs: Long): Int {
    val expired = store.loadAll(customerAccountId).filter { it.isExpired(nowEpochMs) }
    expired.forEach { store.delete(customerAccountId, it.paymentIntentId) }
    return expired.size
  }

  private fun requireOwned(customerAccountId: String, paymentIntentId: String): PaymentIntentSnapshot {
    PaymentIntentAccounts.requireAccount(customerAccountId)
    val snapshot = store.load(customerAccountId, paymentIntentId)
      ?: throw SnapshotError("Payment intent was not found")
    if (snapshot.customerAccountId != customerAccountId) {
      throw SnapshotError("Payment intent belongs to a different customer account")
    }
    return snapshot
  }
}
