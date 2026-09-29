package com.atlassian.meridian

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.Instant

/**
 * Computes a canonical SHA-256 hex hash of payment business parameters.
 *
 * The hash uniquely identifies the business intent of a payment so that
 * resumption logic can verify no parameters changed between attempts.
 */
fun businessPayloadHash(
  recipientId: String,
  amountMinor: Int,
  method: PaymentMethod,
  note: String,
  scenario: Scenario,
): String {
  val canonical = "$recipientId|$amountMinor|${method.name}|$note|${scenario.name}"
  val digest = MessageDigest.getInstance("SHA-256")
  val hash = digest.digest(canonical.toByteArray(StandardCharsets.UTF_8))
  return hash.joinToString("") { "%02x".format(it) }
}

/**
 * Persistent store for [PaymentIntentSnapshot] records, isolated by customer account.
 *
 * Platform implementations:
 * - JVM/test: [InMemoryPaymentIntentStore]
 * - Android: EncryptedPaymentIntentStore (app module, backed by EncryptedSharedPreferences)
 */
interface PaymentIntentStore {
  /** Persist or replace a snapshot for the given account. */
  fun save(snapshot: PaymentIntentSnapshot, accountId: String)

  /** Return all snapshots for the account (includes expired entries). */
  fun loadAll(accountId: String): List<PaymentIntentSnapshot>

  /**
   * Return the first non-expired active (pending) intent for the account, or null.
   * Intended for resumption on app restart or process recovery.
   */
  fun loadActiveIntent(accountId: String): PaymentIntentSnapshot? =
    loadAll(accountId).firstOrNull { it.isActive && !it.isExpired }

  /** Remove a specific snapshot by [paymentIntentId]. */
  fun delete(paymentIntentId: String, accountId: String)

  /** Remove all expired snapshots for the account. */
  fun purgeExpired(accountId: String) {
    loadAll(accountId)
      .filter { it.isExpired }
      .forEach { delete(it.paymentIntentId, accountId) }
  }
}

/**
 * Non-persistent in-memory implementation of [PaymentIntentStore].
 *
 * Suitable for unit tests and environments without platform secure storage.
 * Data does not survive process termination.
 */
class InMemoryPaymentIntentStore : PaymentIntentStore {
  private val storage: MutableMap<String, MutableList<PaymentIntentSnapshot>> =
    mutableMapOf()

  override fun save(snapshot: PaymentIntentSnapshot, accountId: String) {
    val list = storage.getOrPut(accountId) { mutableListOf() }
    val idx = list.indexOfFirst { it.paymentIntentId == snapshot.paymentIntentId }
    if (idx >= 0) list[idx] = snapshot else list.add(snapshot)
  }

  override fun loadAll(accountId: String): List<PaymentIntentSnapshot> =
    storage[accountId]?.toList() ?: emptyList()

  override fun delete(paymentIntentId: String, accountId: String) {
    storage[accountId]?.removeAll { it.paymentIntentId == paymentIntentId }
  }
}
