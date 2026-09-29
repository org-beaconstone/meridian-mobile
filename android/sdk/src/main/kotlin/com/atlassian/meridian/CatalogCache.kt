package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.io.File
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

enum class CatalogOrigin {
  NETWORK,
  CACHE,
  FALLBACK,
  BASELINE,
}

data class CatalogLoad(
  val catalog: CatalogResponse,
  val origin: CatalogOrigin,
)

data class StoredCatalog(
  val fetchedAtEpochMillis: Long,
  val catalog: CatalogResponse,
)

interface CatalogStore {
  fun load(): StoredCatalog?
  fun save(stored: StoredCatalog)
}

class InMemoryCatalogStore : CatalogStore {
  private val lock = Any()
  private var stored: StoredCatalog? = null

  override fun load(): StoredCatalog? = synchronized(lock) { stored }

  override fun save(stored: StoredCatalog) {
    synchronized(lock) { this.stored = stored }
  }
}

/**
 * AES-GCM catalog blob plus a local 256-bit key file. The key stays on device
 * and is never embedded in source.
 */
class EncryptedFileCatalogStore(
  private val directory: File,
) : CatalogStore {
  private val mapper = ObjectMapper().registerKotlinModule()
  private val random = SecureRandom()
  private val lock = Any()
  private val keyFile = File(directory, "catalog.key")
  private val dataFile = File(directory, "catalog.bin")

  override fun load(): StoredCatalog? = synchronized(lock) {
    if (!dataFile.isFile || !keyFile.isFile) return null
    return try {
      val plain = decrypt(dataFile.readBytes(), keyFile.readBytes())
      mapper.readValue(plain, StoredCatalog::class.java)
    } catch (_: Exception) {
      null
    }
  }

  override fun save(stored: StoredCatalog) {
    synchronized(lock) {
      try {
        directory.mkdirs()
        val key = readOrCreateKey()
        val plain = mapper.writeValueAsBytes(stored)
        dataFile.writeBytes(encrypt(plain, key))
        dataFile.setReadable(false, false)
        dataFile.setReadable(true, true)
        dataFile.setWritable(false, false)
        dataFile.setWritable(true, true)
      } catch (_: Exception) {
        // A cache write failure must not take down the payment flow.
      }
    }
  }

  private fun readOrCreateKey(): ByteArray {
    if (keyFile.isFile) {
      val existing = keyFile.readBytes()
      if (existing.size == 32) return existing
    }
    val created = ByteArray(32)
    random.nextBytes(created)
    keyFile.writeBytes(created)
    keyFile.setReadable(false, false)
    keyFile.setReadable(true, true)
    keyFile.setWritable(false, false)
    keyFile.setWritable(true, true)
    return created
  }

  private fun encrypt(plain: ByteArray, key: ByteArray): ByteArray {
    val nonce = ByteArray(12)
    random.nextBytes(nonce)
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
    val body = cipher.doFinal(plain)
    return nonce + body
  }

  private fun decrypt(blob: ByteArray, key: ByteArray): ByteArray {
    require(blob.size > 12) { "Catalog blob is truncated" }
    val nonce = blob.copyOfRange(0, 12)
    val body = blob.copyOfRange(12, blob.size)
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
    return cipher.doFinal(body)
  }
}

fun defaultCatalogDirectory(sessionId: String): File {
  val safe = sessionId.replace(Regex("[^A-Za-z0-9_-]"), "_")
  val root = System.getProperty("meridian.catalog.dir")
    ?: (System.getProperty("java.io.tmpdir") + "/meridian-catalog")
  return File(root, safe)
}

internal fun isCatalogGateway(statusCode: Int): Boolean =
  statusCode == 500 || statusCode == 502 || statusCode == 503 || statusCode == 504

internal fun fallbackCatalog(cached: StoredCatalog?): CatalogLoad {
  if (cached != null) return CatalogLoad(cached.catalog, CatalogOrigin.FALLBACK)
  return CatalogLoad(ProviderBaseline.catalog(), CatalogOrigin.BASELINE)
}
