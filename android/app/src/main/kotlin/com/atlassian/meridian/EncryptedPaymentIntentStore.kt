package com.atlassian.meridian

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Android implementation of [PaymentIntentStore] backed by [EncryptedSharedPreferences].
 *
 * Data is stored in platform-protected encrypted storage (AES-256-GCM) scoped to the
 * authenticated customer account via the `customerId` parameter. Each snapshot is
 * serialised as JSON and stored under the key `snapshot_{idempotencyKey}`.
 *
 * Requires the `androidx.security:security-crypto` dependency in the app module.
 *
 * @param context Android [Context] used to open the encrypted preferences file.
 * @param customerId The authenticated session / customer identifier used to namespace
 *   the preferences file, isolating one account's intents from another.
 */
class EncryptedPaymentIntentStore(
  context: Context,
  customerId: String,
) : PaymentIntentStore {

  private val prefs = run {
    val masterKey = MasterKey.Builder(context)
      .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
      .build()
    EncryptedSharedPreferences.create(
      context,
      // Preference file name is scoped to the customer so sessions stay isolated.
      "meridian_payment_intents_${customerId.replace(Regex("[^A-Za-z0-9_-]"), "_")}",
      masterKey,
      EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
      EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )
  }

  private val mapper = ObjectMapper().registerKotlinModule()

  private fun prefKey(idempotencyKey: String) = "snapshot_$idempotencyKey"

  override suspend fun save(snapshot: PaymentIntentSnapshot): Unit =
    withContext(Dispatchers.IO) {
      val json = mapper.writeValueAsString(snapshot)
      prefs.edit().putString(prefKey(snapshot.idempotencyKey), json).apply()
    }

  override suspend fun load(idempotencyKey: String): PaymentIntentSnapshot? =
    withContext(Dispatchers.IO) {
      val json = prefs.getString(prefKey(idempotencyKey), null) ?: return@withContext null
      val snapshot = try {
        mapper.readValue(json, PaymentIntentSnapshot::class.java)
      } catch (_: Exception) {
        return@withContext null
      }
      if (snapshot.isExpired) {
        delete(idempotencyKey)
        return@withContext null
      }
      snapshot
    }

  override suspend fun loadActive(): List<PaymentIntentSnapshot> =
    withContext(Dispatchers.IO) {
      val all = prefs.all
      val active = mutableListOf<PaymentIntentSnapshot>()
      for ((_, value) in all) {
        val json = value as? String ?: continue
        val snapshot = try {
          mapper.readValue(json, PaymentIntentSnapshot::class.java)
        } catch (_: Exception) {
          continue
        }
        when {
          snapshot.isExpired -> delete(snapshot.idempotencyKey)
          !snapshot.status.isTerminal -> active.add(snapshot)
        }
      }
      active
    }

  override suspend fun delete(idempotencyKey: String): Unit =
    withContext(Dispatchers.IO) {
      prefs.edit().remove(prefKey(idempotencyKey)).apply()
    }
}
