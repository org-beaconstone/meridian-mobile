package com.atlassian.meridian

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import com.fasterxml.jackson.module.kotlin.readValue

/**
 * Android implementation of [PaymentIntentStore] backed by [EncryptedSharedPreferences].
 *
 * All snapshot data is AES-256 encrypted at rest using the Android Keystore system.
 * Snapshots are scoped per customer account: each account's data is stored under its
 * own key, preventing cross-account access.
 *
 * Storage key format: "meridian_pi_{accountId}"
 */
class EncryptedPaymentIntentStore(context: Context) : PaymentIntentStore {

  private val mapper = ObjectMapper().registerKotlinModule()

  private val prefs = EncryptedSharedPreferences.create(
    context,
    "meridian_payment_intents",
    MasterKey.Builder(context)
      .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
      .build(),
    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
  )

  private fun accountKey(accountId: String) = "meridian_pi_$accountId"

  override fun save(snapshot: PaymentIntentSnapshot, accountId: String) {
    val existing = loadAll(accountId).toMutableList()
    val idx = existing.indexOfFirst { it.paymentIntentId == snapshot.paymentIntentId }
    if (idx >= 0) existing[idx] = snapshot else existing.add(snapshot)
    prefs.edit()
      .putString(accountKey(accountId), mapper.writeValueAsString(existing))
      .apply()
  }

  override fun loadAll(accountId: String): List<PaymentIntentSnapshot> {
    val json = prefs.getString(accountKey(accountId), null) ?: return emptyList()
    return try {
      mapper.readValue(json)
    } catch (_: Exception) {
      emptyList()
    }
  }

  override fun delete(paymentIntentId: String, accountId: String) {
    val remaining = loadAll(accountId).filterNot { it.paymentIntentId == paymentIntentId }
    prefs.edit()
      .putString(accountKey(accountId), mapper.writeValueAsString(remaining))
      .apply()
  }
}
