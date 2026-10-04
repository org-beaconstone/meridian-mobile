package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.io.File
import java.nio.file.Files
import java.nio.file.attribute.PosixFilePermission
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

interface CatalogCache {
  fun load(sessionId: String): CatalogResponse?
  fun save(sessionId: String, catalog: CatalogResponse)
  fun ciphertext(sessionId: String): ByteArray? = null
}

class MemoryEncryptedCatalogCache : CatalogCache {
  private val key: SecretKey = newAesKey()
  private val blobs = mutableMapOf<String, ByteArray>()

  override fun load(sessionId: String): CatalogResponse? {
    val blob = synchronized(blobs) { blobs[sessionId] } ?: return null
    return CatalogCipher.open(blob, sessionId, key)
  }

  override fun save(sessionId: String, catalog: CatalogResponse) {
    val blob = CatalogCipher.seal(catalog, sessionId, key) ?: return
    synchronized(blobs) { blobs[sessionId] = blob }
  }

  override fun ciphertext(sessionId: String): ByteArray? = synchronized(blobs) { blobs[sessionId] }
}

class FileEncryptedCatalogCache(directory: File) : CatalogCache {
  private val store: CatalogCache = open(directory)

  override fun load(sessionId: String): CatalogResponse? = store.load(sessionId)

  override fun save(sessionId: String, catalog: CatalogResponse) {
    store.save(sessionId, catalog)
  }

  override fun ciphertext(sessionId: String): ByteArray? = store.ciphertext(sessionId)

  private fun open(directory: File): CatalogCache {
    return try {
      if (!directory.exists() && !directory.mkdirs()) return MemoryEncryptedCatalogCache()
      AesFileCatalogCache(directory, loadOrCreateKey(directory))
    } catch (_: Exception) {
      MemoryEncryptedCatalogCache()
    }
  }

  private fun loadOrCreateKey(directory: File): SecretKey {
    val keyFile = File(directory, "catalog.key")
    if (keyFile.isFile && keyFile.length() == 32L) {
      return SecretKeySpec(keyFile.readBytes(), "AES")
    }
    val key = newAesKey()
    keyFile.writeBytes(key.encoded)
    restrictToOwner(keyFile)
    return key
  }
}

private class AesFileCatalogCache(
  private val directory: File,
  private val key: SecretKey,
) : CatalogCache {
  override fun load(sessionId: String): CatalogResponse? {
    val file = fileFor(sessionId)
    if (!file.isFile) return null
    return CatalogCipher.open(file.readBytes(), sessionId, key)
  }

  override fun save(sessionId: String, catalog: CatalogResponse) {
    val blob = CatalogCipher.seal(catalog, sessionId, key) ?: return
    val file = fileFor(sessionId)
    file.writeBytes(blob)
    restrictToOwner(file)
  }

  override fun ciphertext(sessionId: String): ByteArray? {
    val file = fileFor(sessionId)
    return if (file.isFile) file.readBytes() else null
  }

  private fun fileFor(sessionId: String): File = File(directory, CatalogCipher.filename(sessionId))
}

internal data class CatalogEnvelope(
  val sessionId: String,
  val catalog: CatalogResponse,
)

private object CatalogCipher {
  private val mapper = ObjectMapper().registerKotlinModule()
  private val random = SecureRandom()
  private val magic = byteArrayOf('M'.code.toByte(), 'C'.code.toByte(), 'A'.code.toByte(), 'T'.code.toByte())

  fun filename(sessionId: String): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(sessionId.toByteArray(Charsets.UTF_8))
    return digest.joinToString("") { "%02x".format(it) } + ".bin"
  }

  fun seal(catalog: CatalogResponse, sessionId: String, key: SecretKey): ByteArray? {
    return try {
      val plain = mapper.writeValueAsBytes(CatalogEnvelope(sessionId, catalog))
      val iv = ByteArray(12)
      random.nextBytes(iv)
      val cipher = Cipher.getInstance("AES/GCM/NoPadding")
      cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, iv))
      cipher.updateAAD(sessionId.toByteArray(Charsets.UTF_8))
      val encrypted = cipher.doFinal(plain)
      magic + byteArrayOf(1) + iv + encrypted
    } catch (_: Exception) {
      null
    }
  }

  fun open(blob: ByteArray, sessionId: String, key: SecretKey): CatalogResponse? {
    if (blob.size < 5 + 12 + 16) return null
    if (!blob.copyOfRange(0, 4).contentEquals(magic) || blob[4] != 1.toByte()) return null
    return try {
      val iv = blob.copyOfRange(5, 17)
      val encrypted = blob.copyOfRange(17, blob.size)
      val cipher = Cipher.getInstance("AES/GCM/NoPadding")
      cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
      cipher.updateAAD(sessionId.toByteArray(Charsets.UTF_8))
      val plain = cipher.doFinal(encrypted)
      val envelope = mapper.readValue(plain, CatalogEnvelope::class.java)
      if (envelope.sessionId != sessionId) null else envelope.catalog
    } catch (_: Exception) {
      null
    }
  }
}

private fun newAesKey(): SecretKey {
  val generator = KeyGenerator.getInstance("AES")
  generator.init(256)
  return generator.generateKey()
}

private fun restrictToOwner(file: File) {
  try {
    Files.setPosixFilePermissions(
      file.toPath(),
      setOf(PosixFilePermission.OWNER_READ, PosixFilePermission.OWNER_WRITE),
    )
  } catch (_: UnsupportedOperationException) {
    // Posix permissions are unavailable on this file system.
  }
}
