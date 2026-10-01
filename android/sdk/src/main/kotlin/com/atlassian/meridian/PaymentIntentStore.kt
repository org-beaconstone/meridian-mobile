package com.atlassian.meridian

import com.fasterxml.jackson.annotation.JsonIgnoreProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.security.MessageDigest
import java.io.Serializable

// MARK: - PaymentIntentStatus

/** Lifecycle status of a payment intent snapshot. */
enum class PaymentIntentStatus(
  /** Terminal statuses are eligible for expiry after the retention window. */
  val isTerminal: Boolean
) : Serializable {
  created(false),    // Snapshot recorded; request not yet sent or outcome unknown
  pending(false),    // Server acknowledged with PAYMENT_PENDING; awaiting confirmation
  completed(true),   // Server confirmed payment success
  declined(true),    // Server rejected the payment
  expired(true);     // Snapshot passed terminal retention window and was invalidated
}

// MARK: - PaymentIntentSnapshot

/**
 * Captures the durable state of a single payment intent so it can be resumed
 * after a process crash or app restart.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
data class PaymentIntentSnapshot(
  /** Server-assigned payment intent ID (equals idempotencyKey until populated). */
  var paymentIntentId: String,
  /** Client-generated UUID sent as the Idempotency-Key header. */
  val idempotencyKey: String,
  /** SHA-256 hex digest of the canonical payment request payload. */
  val businessPayloadHash: String,
  /** Current lifecycle status. */
  var status: PaymentIntentStatus,
  /** SHA-256 hex digest of the bank state returned by the server, or null. */
  var returnStateHash: String? = null,
  /** Epoch-millisecond timestamp when the snapshot was first created. */
  val createdAt: Long = System.currentTimeMillis(),
  /** Epoch-millisecond timestamp of the most recent status update. */
  var updatedAt: Long = System.currentTimeMillis(),
) : Serializable {

  companion object {
    /** Snapshots in a terminal state are purged after this duration (ms). */
    const val TERMINAL_RETENTION_MS = 86_400_000L // 24 hours
  }

  val isExpired: Boolean
    get() = status.isTerminal &&
      (System.currentTimeMillis() - updatedAt) > TERMINAL_RETENTION_MS
}

// MARK: - Hash helpers

/** Returns a lower-case hex-encoded SHA-256 digest of the UTF-8 string. */
fun sha256Hex(input: String): String {
  val digest = MessageDigest.getInstance("SHA-256")
  val hashBytes = digest.digest(input.toByteArray(Charsets.UTF_8))
  return hashBytes.joinToString("") { "%02x".format(it) }
}

/** Canonical hash of a payment request payload. */
fun paymentPayloadHash(
  recipientId: String,
  amountMinor: Int,
  method: String,
  note: String,
): String = sha256Hex("$recipientId|$amountMinor|$method|$note")

/** Hash of a bank state snapshot for change detection. */
fun bankStateHash(version: Int, balance: Int): String = sha256Hex("$version|$balance")

// MARK: - PaymentIntentStore interface

/**
 * Durable store for payment intent snapshots, scoped to an authenticated
 * customer account.
 */
interface PaymentIntentStore {
  /** Persist or replace a snapshot. */
  suspend fun save(snapshot: PaymentIntentSnapshot)

  /**
   * Load a single snapshot by idempotency key.
   * Returns null when not found or when the snapshot has passed its retention window.
   */
  suspend fun load(idempotencyKey: String): PaymentIntentSnapshot?

  /**
   * Return all non-terminal snapshots for the current account.
   * Expired entries are removed as a side effect.
   */
  suspend fun loadActive(): List<PaymentIntentSnapshot>

  /** Remove a snapshot permanently. */
  suspend fun delete(idempotencyKey: String)
}

// MARK: - InMemoryPaymentIntentStore

/**
 * A non-persistent, in-memory [PaymentIntentStore] suitable for unit tests
 * and environments where platform storage is unavailable.
 */
class InMemoryPaymentIntentStore : PaymentIntentStore {
  private val mutex = Mutex()
  private val store = mutableMapOf<String, PaymentIntentSnapshot>()

  override suspend fun save(snapshot: PaymentIntentSnapshot) {
    mutex.withLock { store[snapshot.idempotencyKey] = snapshot.copy() }
  }

  override suspend fun load(idempotencyKey: String): PaymentIntentSnapshot? {
    val snapshot = mutex.withLock { store[idempotencyKey]?.copy() } ?: return null
    return if (snapshot.isExpired) {
      delete(idempotencyKey)
      null
    } else {
      snapshot
    }
  }

  override suspend fun loadActive(): List<PaymentIntentSnapshot> =
    withContext(Dispatchers.Default) {
      val all = mutex.withLock { store.values.map { it.copy() } }
      val active = mutableListOf<PaymentIntentSnapshot>()
      for (snapshot in all) {
        when {
          snapshot.isExpired -> delete(snapshot.idempotencyKey)
          !snapshot.status.isTerminal -> active.add(snapshot)
        }
      }
      active
    }

  override suspend fun delete(idempotencyKey: String) {
    mutex.withLock { store.remove(idempotencyKey) }
  }
}
