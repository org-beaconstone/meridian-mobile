package com.atlassian.meridian

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Android Keystore holds the catalog AES key. Cache files store ciphertext only.
 * The blob key remains account scope, corridor, and currency. Session id chooses
 * the directory so rehearsal rooms do not share snapshots.
 */
fun openAndroidCatalogCache(context: Context, sessionId: String): CatalogCache {
  val directory = File(context.noBackupFilesDir, "catalog-cache/${catalogSessionDirectoryName(sessionId)}")
  return CatalogCache(FileProtectedBlobStore(directory), AndroidKeystoreCatalogSealer())
}

class AndroidKeystoreCatalogSealer(
  private val alias: String = "meridian.catalog.cache.v1",
) : CatalogSealer {
  init {
    ensureKey()
  }

  override fun seal(plaintext: ByteArray): ByteArray {
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, secretKey())
    val nonce = cipher.iv
    if (nonce.size != CatalogBlob.NONCE_LENGTH) {
      throw MeridianError.ValidationError("Catalog encryption nonce was not 96 bits")
    }
    return CatalogBlob.frame(nonce, cipher.doFinal(plaintext))
  }

  override fun open(sealed: ByteArray): ByteArray {
    val (nonce, body) = CatalogBlob.split(sealed)
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, nonce))
    return cipher.doFinal(body)
  }

  private fun ensureKey() {
    val keyStore = loadKeyStore()
    if (keyStore.containsAlias(alias)) return
    val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
    val spec = KeyGenParameterSpec.Builder(
      alias,
      KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
    )
      .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
      .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
      .setKeySize(256)
      .setRandomizedEncryptionRequired(true)
      .build()
    generator.init(spec)
    generator.generateKey()
  }

  private fun secretKey(): SecretKey {
    val key = loadKeyStore().getKey(alias, null) as? SecretKey
    return key ?: throw MeridianError.ValidationError("Catalog key is unavailable")
  }

  private fun loadKeyStore(): KeyStore =
    KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
}
