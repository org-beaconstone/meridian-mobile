package com.atlassian.meridian

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID

/** How long a snapshot is kept after it reaches a terminal status. */
object PaymentIntentRetention {
  const val TERMINAL_WINDOW_MILLIS: Long = 24L * 60L * 60L * 1000L
}

enum class PaymentIntentStatus {
  created,
  submitted,
  pending,
  requiresAction,
  unknown,
  completed,
  declined,
  failed,
  cancelled,
  ;

  val isTerminal: Boolean
    get() = this == completed || this == declined || this == failed || this == cancelled

  val isActive: Boolean
    get() = !isTerminal
}

open class PaymentIntentException(message: String) : Exception(message)

class ActivePaymentIntentException(val paymentIntentId: String) :
  PaymentIntentException("Active payment intent $paymentIntentId is still in progress")

object PaymentIntentIds {
  private val accountPattern = Regex("^[A-Za-z0-9_-]{3,64}$")
  private val intentPattern = Regex("^[A-Za-z0-9_-]{8,80}$")

  fun isValidCustomerAccountId(value: String): Boolean = accountPattern.matches(value)

  fun isValidPaymentIntentId(value: String): Boolean = intentPattern.matches(value)

  fun newPaymentIntentId(): String = "pi_${UUID.randomUUID()}"

  fun newIdempotencyKey(): String = UUID.randomUUID().toString()
}

object PaymentIntentStorageKeys {
  const val LAST_ACCOUNT_KEY = "__last_customer_account__"

  fun snapshotKey(customerAccountId: String, paymentIntentId: String): String {
    require(PaymentIntentIds.isValidCustomerAccountId(customerAccountId)) { "Invalid customer account" }
    require(PaymentIntentIds.isValidPaymentIntentId(paymentIntentId)) { "Invalid payment intent id" }
    return "$customerAccountId|$paymentIntentId"
  }

  fun belongsToAccount(key: String, customerAccountId: String): Boolean =
    key.startsWith("$customerAccountId|")
}

object PaymentIntentHash {
  fun sha256Hex(text: String): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
    return digest.joinToString("") { "%02x".format(it.toInt() and 0xff) }
  }

  fun escape(value: String): String = buildString {
    append('"')
    for (character in value) {
      when (character) {
        '\\' -> append("\\\\")
        '"' -> append("\\\"")
        '\n' -> append("\\n")
        '\r' -> append("\\r")
        '\t' -> append("\\t")
        else -> append(character)
      }
    }
    append('"')
  }

  /** Canonical business payload. Amount is integer GBP pence. Key order is fixed. */
  fun canonicalBusinessPayload(
    customerAccountId: String,
    recipientId: String,
    amountMinor: Int,
    method: String,
    note: String,
    scenario: String,
  ): String =
    "{\"v\":1,\"customerAccountId\":${escape(customerAccountId)},\"recipientId\":${escape(recipientId)},\"amountMinor\":$amountMinor,\"method\":${escape(method)},\"note\":${escape(note)},\"scenario\":${escape(scenario)}}"

  fun businessPayloadHash(
    customerAccountId: String,
    recipientId: String,
    amountMinor: Int,
    method: String,
    note: String,
    scenario: String,
  ): String = sha256Hex(
    canonicalBusinessPayload(customerAccountId, recipientId, amountMinor, method, note, scenario),
  )

  fun returnStateHash(returnState: String): String = sha256Hex(returnState)

  fun newReturnState(): String {
    val bytes = ByteArray(32)
    SecureRandom().nextBytes(bytes)
    return bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }
  }
}

/**
 * Local record of an in-progress or recently finished payment.
 * The raw return-state token is not stored; only its hash is.
 */
data class PaymentIntentSnapshot(
  val paymentIntentId: String,
  val idempotencyKey: String,
  val businessPayloadHash: String,
  val status: PaymentIntentStatus,
  val returnStateHash: String,
  val customerAccountId: String,
  val recipientId: String,
  val amountMinor: Int,
  val method: String,
  val note: String,
  val scenario: String,
  val createdAtEpochMillis: Long,
  val updatedAtEpochMillis: Long,
  val terminalAtEpochMillis: Long? = null,
)

data class PreparedPaymentIntent(
  val snapshot: PaymentIntentSnapshot,
  /** Present only when this call created the snapshot. Resume does not reveal the original token. */
  val returnState: String?,
)

interface PaymentIntentSnapshotStore {
  fun load(customerAccountId: String): List<PaymentIntentSnapshot>

  fun save(snapshot: PaymentIntentSnapshot)

  fun delete(customerAccountId: String, paymentIntentId: String)

  fun lastCustomerAccountId(): String?

  fun rememberCustomerAccountId(customerAccountId: String)
}

class InMemoryPaymentIntentStore : PaymentIntentSnapshotStore {
  private val lock = Any()
  private val snapshots = linkedMapOf<String, PaymentIntentSnapshot>()
  private var lastAccount: String? = null

  override fun load(customerAccountId: String): List<PaymentIntentSnapshot> {
    require(PaymentIntentIds.isValidCustomerAccountId(customerAccountId)) { "Invalid customer account" }
    return synchronized(lock) {
      snapshots.filter { (key, snapshot) ->
        PaymentIntentStorageKeys.belongsToAccount(key, customerAccountId) &&
          snapshot.customerAccountId == customerAccountId
      }.values.toList()
    }
  }

  override fun save(snapshot: PaymentIntentSnapshot) {
    val key = PaymentIntentStorageKeys.snapshotKey(snapshot.customerAccountId, snapshot.paymentIntentId)
    synchronized(lock) { snapshots[key] = snapshot }
  }

  override fun delete(customerAccountId: String, paymentIntentId: String) {
    val key = PaymentIntentStorageKeys.snapshotKey(customerAccountId, paymentIntentId)
    synchronized(lock) {
      if (snapshots[key]?.customerAccountId == customerAccountId) snapshots.remove(key)
    }
  }

  override fun lastCustomerAccountId(): String? = synchronized(lock) {
    lastAccount?.takeIf { PaymentIntentIds.isValidCustomerAccountId(it) }
  }

  override fun rememberCustomerAccountId(customerAccountId: String) {
    require(PaymentIntentIds.isValidCustomerAccountId(customerAccountId)) { "Invalid customer account" }
    synchronized(lock) { lastAccount = customerAccountId }
  }
}

class PaymentIntentLedger(
  private val store: PaymentIntentSnapshotStore,
  private val nowMillis: () -> Long = { System.currentTimeMillis() },
  private val retentionMillis: Long = PaymentIntentRetention.TERMINAL_WINDOW_MILLIS,
) {
  fun rememberCustomerAccount(customerAccountId: String) {
    require(PaymentIntentIds.isValidCustomerAccountId(customerAccountId)) { "Invalid customer account" }
    synchronized(this) { store.rememberCustomerAccountId(customerAccountId) }
  }

  fun lastCustomerAccountId(): String? = synchronized(this) { store.lastCustomerAccountId() }

  fun purgeExpired(customerAccountId: String) {
    synchronized(this) {
      val now = nowMillis()
      for (snapshot in store.load(customerAccountId)) {
        if (snapshot.customerAccountId != customerAccountId) continue
        val terminalAt = snapshot.terminalAtEpochMillis ?: continue
        if (snapshot.status.isTerminal && now >= terminalAt + retentionMillis) {
          store.delete(customerAccountId, snapshot.paymentIntentId)
        }
      }
    }
  }

  fun snapshots(customerAccountId: String): List<PaymentIntentSnapshot> = synchronized(this) {
    purgeExpired(customerAccountId)
    store.load(customerAccountId)
      .filter { it.customerAccountId == customerAccountId }
      .sortedByDescending { it.updatedAtEpochMillis }
  }

  fun activeIntents(customerAccountId: String): List<PaymentIntentSnapshot> =
    snapshots(customerAccountId).filter { it.status.isActive }

  fun snapshot(customerAccountId: String, paymentIntentId: String): PaymentIntentSnapshot =
    synchronized(this) {
      store.load(customerAccountId).firstOrNull {
        it.paymentIntentId == paymentIntentId && it.customerAccountId == customerAccountId
      } ?: throw PaymentIntentException("Payment intent snapshot was not found")
    }

  fun begin(
    customerAccountId: String,
    recipientId: String,
    amountMinor: Int,
    method: String,
    note: String,
    scenario: String,
  ): PreparedPaymentIntent = synchronized(this) {
    validate(customerAccountId, recipientId, amountMinor, note)
    purgeExpired(customerAccountId)
    val hash = PaymentIntentHash.businessPayloadHash(
      customerAccountId,
      recipientId,
      amountMinor,
      method,
      note,
      scenario,
    )
    val existing = store.load(customerAccountId)
      .filter { it.customerAccountId == customerAccountId && it.status.isActive }
      .maxByOrNull { it.updatedAtEpochMillis }
    if (existing != null) {
      if (
        existing.businessPayloadHash == hash &&
        existing.recipientId == recipientId &&
        existing.amountMinor == amountMinor &&
        existing.method == method &&
        existing.note == note &&
        existing.scenario == scenario
      ) {
        val touched = existing.copy(updatedAtEpochMillis = nowMillis())
        store.save(touched)
        store.rememberCustomerAccountId(customerAccountId)
        return PreparedPaymentIntent(touched, null)
      }
      if (existing.status == PaymentIntentStatus.created) {
        cancel(customerAccountId, existing.paymentIntentId)
      } else {
        throw ActivePaymentIntentException(existing.paymentIntentId)
      }
    }
    val returnState = PaymentIntentHash.newReturnState()
    val now = nowMillis()
    val snapshot = PaymentIntentSnapshot(
      paymentIntentId = PaymentIntentIds.newPaymentIntentId(),
      idempotencyKey = PaymentIntentIds.newIdempotencyKey(),
      businessPayloadHash = hash,
      status = PaymentIntentStatus.created,
      returnStateHash = PaymentIntentHash.returnStateHash(returnState),
      customerAccountId = customerAccountId,
      recipientId = recipientId,
      amountMinor = amountMinor,
      method = method,
      note = note,
      scenario = scenario,
      createdAtEpochMillis = now,
      updatedAtEpochMillis = now,
    )
    store.save(snapshot)
    store.rememberCustomerAccountId(customerAccountId)
    PreparedPaymentIntent(snapshot, returnState)
  }

  fun markSubmitted(customerAccountId: String, paymentIntentId: String): PaymentIntentSnapshot =
    synchronized(this) {
      val current = snapshot(customerAccountId, paymentIntentId)
      if (current.status.isTerminal) {
        throw PaymentIntentException("Payment intent ${current.paymentIntentId} is already finished")
      }
      val updated = current.copy(
        status = PaymentIntentStatus.submitted,
        updatedAtEpochMillis = nowMillis(),
        terminalAtEpochMillis = null,
      )
      store.save(updated)
      updated
    }

  fun record(
    response: PaymentResponse,
    customerAccountId: String,
    paymentIntentId: String,
  ): PaymentIntentSnapshot = synchronized(this) {
    val current = snapshot(customerAccountId, paymentIntentId)
    if (current.status.isTerminal) return current
    val status = statusFor(response)
    val now = nowMillis()
    val updated = current.copy(
      status = status,
      updatedAtEpochMillis = now,
      terminalAtEpochMillis = if (status.isTerminal) now else null,
    )
    store.save(updated)
    updated
  }

  fun markUncertain(customerAccountId: String, paymentIntentId: String): PaymentIntentSnapshot =
    synchronized(this) {
      val current = snapshot(customerAccountId, paymentIntentId)
      if (current.status.isTerminal) {
        throw PaymentIntentException("Payment intent ${current.paymentIntentId} is already finished")
      }
      val updated = current.copy(
        status = PaymentIntentStatus.unknown,
        updatedAtEpochMillis = nowMillis(),
        terminalAtEpochMillis = null,
      )
      store.save(updated)
      updated
    }

  fun cancel(customerAccountId: String, paymentIntentId: String): PaymentIntentSnapshot =
    synchronized(this) {
      val current = snapshot(customerAccountId, paymentIntentId)
      if (current.status.isTerminal) return current
      val now = nowMillis()
      val updated = current.copy(
        status = PaymentIntentStatus.cancelled,
        updatedAtEpochMillis = now,
        terminalAtEpochMillis = now,
      )
      store.save(updated)
      updated
    }

  fun verifyReturnState(snapshot: PaymentIntentSnapshot, returnState: String): Boolean {
    val actual = PaymentIntentHash.returnStateHash(returnState)
    return constantTimeEquals(snapshot.returnStateHash, actual)
  }

  private fun validate(customerAccountId: String, recipientId: String, amountMinor: Int, note: String) {
    if (!PaymentIntentIds.isValidCustomerAccountId(customerAccountId)) {
      throw PaymentIntentException("Customer account must be 3-64 characters of letters, numbers, _ or -")
    }
    if (recipientId.isBlank()) throw PaymentIntentException("Recipient is required")
    if (amountMinor <= 0) throw PaymentIntentException("Amount must be greater than zero")
    if (amountMinor > 1_000_000) throw PaymentIntentException("Amount cannot exceed £10,000")
    if (note.length > 200) throw PaymentIntentException("Reference is too long")
  }

  private fun constantTimeEquals(left: String, right: String): Boolean {
    val a = left.toByteArray(Charsets.UTF_8)
    val b = right.toByteArray(Charsets.UTF_8)
    if (a.size != b.size) return false
    var diff = 0
    for (index in a.indices) diff = diff or (a[index].toInt() xor b[index].toInt())
    return diff == 0
  }

  companion object {
    fun statusFor(response: PaymentResponse): PaymentIntentStatus {
      if (response.ok) {
        return when (response.transaction?.status) {
          "declined" -> PaymentIntentStatus.declined
          "pending" -> PaymentIntentStatus.pending
          "completed", null -> PaymentIntentStatus.completed
          else -> PaymentIntentStatus.unknown
        }
      }
      return when (response.code) {
        "PAYMENT_PENDING" -> PaymentIntentStatus.pending
        "DECLINED", "INSUFFICIENT_BALANCE" -> PaymentIntentStatus.declined
        else -> PaymentIntentStatus.unknown
      }
    }
  }
}
