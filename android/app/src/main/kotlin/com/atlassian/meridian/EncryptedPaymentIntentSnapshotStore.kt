package com.atlassian.meridian

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.util.concurrent.ConcurrentHashMap

/**
 * Account-scoped payment intent snapshots in EncryptedSharedPreferences.
 * Keys are AES-256-SIV and values are AES-256-GCM, with a separate file per
 * customer account. Backup is already disabled on the application manifest.
 */
class EncryptedPaymentIntentSnapshotStore(
  context: Context,
) : PaymentIntentSnapshotStore {
  private val appContext = context.applicationContext
  private val masterKey: MasterKey by lazy {
    MasterKey.Builder(appContext)
      .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
      .build()
  }
  private val openFiles = ConcurrentHashMap<String, SecurePreferenceFile>()
  private val fileGate = Any()
  private val delegate = PreferencePaymentIntentSnapshotStore(
    SecurePreferenceFiles { customerAccountId -> fileFor(customerAccountId) },
  )

  private fun fileFor(customerAccountId: String): SecurePreferenceFile {
    val fileName = "meridian_pi_${accountStorageKey(customerAccountId)}"
    openFiles[fileName]?.let { return it }
    return synchronized(fileGate) {
      openFiles[fileName]?.let { return@synchronized it }
      val preferences = EncryptedSharedPreferences.create(
        appContext,
        fileName,
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
      )
      SharedPreferencesFile(preferences).also { openFiles[fileName] = it }
    }
  }

  override fun save(snapshot: PaymentIntentSnapshot) = delegate.save(snapshot)

  override fun load(customerAccountId: String, paymentIntentId: String): PaymentIntentSnapshot? =
    delegate.load(customerAccountId, paymentIntentId)

  override fun loadAll(customerAccountId: String): List<PaymentIntentSnapshot> =
    delegate.loadAll(customerAccountId)

  override fun delete(customerAccountId: String, paymentIntentId: String) =
    delegate.delete(customerAccountId, paymentIntentId)
}

private class SharedPreferencesFile(
  private val preferences: SharedPreferences,
) : SecurePreferenceFile {
  private val lock = Any()

  override fun get(key: String): String? = synchronized(lock) {
    preferences.getString(key, null)
  }

  override fun put(key: String, value: String) {
    val committed = synchronized(lock) {
      preferences.edit().putString(key, value).commit()
    }
    if (!committed) throw SnapshotError("Encrypted preference commit failed")
  }

  override fun remove(key: String) {
    val committed = synchronized(lock) {
      preferences.edit().remove(key).commit()
    }
    if (!committed) throw SnapshotError("Encrypted preference delete failed")
  }

  override fun entries(): Map<String, String> = synchronized(lock) {
    val copy = LinkedHashMap<String, String>()
    for ((key, value) in preferences.all) {
      if (value is String) copy[key] = value
    }
    copy
  }
}
