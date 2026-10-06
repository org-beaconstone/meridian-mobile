package com.atlassian.meridian

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule

/**
 * Account-scoped payment intent snapshots in EncryptedSharedPreferences.
 * Keys are encrypted with AES-256-SIV and values with AES-256-GCM. The master key
 * lives in the Android Keystore. Backup is already disabled on the application.
 * This type is Android-only and is not part of the JVM Maven module.
 */
class EncryptedPaymentIntentStore(context: Context) : PaymentIntentSnapshotStore {
  private val appContext = context.applicationContext
  private val mapper = ObjectMapper().registerKotlinModule()
  private val lock = Any()
  private val preferences: SharedPreferences by lazy { openPreferences() }

  override fun load(customerAccountId: String): List<PaymentIntentSnapshot> {
    require(PaymentIntentIds.isValidCustomerAccountId(customerAccountId)) { "Invalid customer account" }
    return synchronized(lock) {
      preferences.all.mapNotNull { (key, value) ->
        if (!PaymentIntentStorageKeys.belongsToAccount(key, customerAccountId)) return@mapNotNull null
        val json = value as? String ?: return@mapNotNull null
        val snapshot = runCatching { mapper.readValue(json, PaymentIntentSnapshot::class.java) }.getOrNull()
          ?: return@mapNotNull null
        snapshot.takeIf { it.customerAccountId == customerAccountId }
      }
    }
  }

  override fun save(snapshot: PaymentIntentSnapshot) {
    val key = PaymentIntentStorageKeys.snapshotKey(snapshot.customerAccountId, snapshot.paymentIntentId)
    val json = mapper.writeValueAsString(snapshot)
    synchronized(lock) {
      val written = preferences.edit().putString(key, json).commit()
      if (!written) throw PaymentIntentException("Encrypted payment intent storage could not be saved")
    }
  }

  override fun delete(customerAccountId: String, paymentIntentId: String) {
    val key = PaymentIntentStorageKeys.snapshotKey(customerAccountId, paymentIntentId)
    synchronized(lock) {
      val current = preferences.getString(key, null)
      if (current != null) {
        val snapshot = runCatching { mapper.readValue(current, PaymentIntentSnapshot::class.java) }.getOrNull()
        if (snapshot != null && snapshot.customerAccountId != customerAccountId) return
      }
      val removed = preferences.edit().remove(key).commit()
      if (!removed) throw PaymentIntentException("Encrypted payment intent storage could not be updated")
    }
  }

  override fun lastCustomerAccountId(): String? = synchronized(lock) {
    preferences.getString(PaymentIntentStorageKeys.LAST_ACCOUNT_KEY, null)
      ?.takeIf { PaymentIntentIds.isValidCustomerAccountId(it) }
  }

  override fun rememberCustomerAccountId(customerAccountId: String) {
    require(PaymentIntentIds.isValidCustomerAccountId(customerAccountId)) { "Invalid customer account" }
    synchronized(lock) {
      val written = preferences.edit().putString(PaymentIntentStorageKeys.LAST_ACCOUNT_KEY, customerAccountId).commit()
      if (!written) throw PaymentIntentException("Encrypted payment intent storage could not remember the account")
    }
  }

  private fun openPreferences(): SharedPreferences {
    val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
    return EncryptedSharedPreferences.create(
      FILE_NAME,
      masterKeyAlias,
      appContext,
      EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
      EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )
  }

  companion object {
    const val FILE_NAME = "meridian_payment_intents"
  }
}
