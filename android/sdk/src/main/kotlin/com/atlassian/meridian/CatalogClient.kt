package com.atlassian.meridian

import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.kotlinModule
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

const val DEFAULT_CATALOG_TTL_MILLIS: Long = 15 * 60 * 1000

private val knownProviderIds = ProviderId.entries.map { it.name }.toSet()

fun meridianMapper(): ObjectMapper = ObjectMapper().registerModule(kotlinModule()).apply {
  configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)
}

/** Compiled-in Adyen card and Worldpay bank catalog used when nothing has been saved yet. */
fun baselineCatalog(): CatalogResponse = CatalogResponse(
  demoDate = "",
  recipients = emptyList(),
  providers = listOf(
    Provider(
      id = ProviderId.adyen.name,
      name = "Adyen",
      description = "Card payment processor",
      methods = listOf(PaymentMethod.card.name),
    ),
    Provider(
      id = ProviderId.worldpay.name,
      name = "Worldpay",
      description = "Bank payment processor",
      methods = listOf(PaymentMethod.bank.name),
    ),
  ),
)

data class CachedCatalog(
  val catalog: CatalogResponse,
  val fetchedAtEpochMs: Long,
) : java.io.Serializable

interface CatalogStore {
  fun read(cacheKey: String): CachedCatalog?
  fun write(cacheKey: String, entry: CachedCatalog)
}

class MemoryCatalogStore : CatalogStore {
  private val entries = java.util.concurrent.ConcurrentHashMap<String, CachedCatalog>()

  override fun read(cacheKey: String): CachedCatalog? = entries[cacheKey]

  override fun write(cacheKey: String, entry: CachedCatalog) {
    entries[cacheKey] = entry
  }
}

fun defaultCatalogDirectory(): File {
  val override = System.getProperty("meridian.catalog.dir")
  if (!override.isNullOrBlank()) return File(override)
  return File(File(System.getProperty("user.home"), ".meridian"), "catalog")
}

/**
 * AES-GCM file cache. The key stays in the app-private directory next to the ciphertext.
 * This is local catalog storage for the rehearsal, not a credential store.
 */
class EncryptedFileCatalogStore(
  private val directory: File,
) : CatalogStore {
  private val mapper = meridianMapper()
  private val key: SecretKey

  init {
    directory.mkdirs()
    val keyFile = File(directory, "catalog.key")
    val raw = if (keyFile.isFile && keyFile.length() == 32L) {
      keyFile.readBytes()
    } else {
      ByteArray(32).also { bytes ->
        SecureRandom().nextBytes(bytes)
        keyFile.writeBytes(bytes)
        keyFile.setReadable(false, false)
        keyFile.setReadable(true, true)
        keyFile.setWritable(false, false)
        keyFile.setWritable(true, true)
      }
    }
    key = SecretKeySpec(raw, "AES")
  }

  override fun read(cacheKey: String): CachedCatalog? {
    val file = fileFor(cacheKey)
    if (!file.isFile) return null
    return try {
      val plain = decrypt(file.readBytes())
      mapper.readValue(plain, CachedCatalog::class.java)
    } catch (_: Exception) {
      null
    }
  }

  override fun write(cacheKey: String, entry: CachedCatalog) {
    val plain = mapper.writeValueAsBytes(entry)
    fileFor(cacheKey).writeBytes(encrypt(plain))
  }

  private fun fileFor(cacheKey: String): File {
    val digest = MessageDigest.getInstance("SHA-256").digest(cacheKey.toByteArray(Charsets.UTF_8))
    val name = digest.joinToString("") { "%02x".format(it) }
    return File(directory, "$name.catalog")
  }

  private fun encrypt(plain: ByteArray): ByteArray {
    val iv = ByteArray(12)
    SecureRandom().nextBytes(iv)
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, iv))
    val encrypted = cipher.doFinal(plain)
    return iv + encrypted
  }

  private fun decrypt(payload: ByteArray): ByteArray {
    require(payload.size > 12) { "Catalog cache is too short" }
    val iv = payload.copyOfRange(0, 12)
    val encrypted = payload.copyOfRange(12, payload.size)
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
    return cipher.doFinal(encrypted)
  }
}

/**
 * Loads GET /catalog and keeps the last accepted Adyen/Worldpay snapshot.
 * Unrecognized provider ids and gateway failures reuse that snapshot.
 */
class CatalogClient(
  private val cacheKey: String,
  private val store: CatalogStore,
  private val ttlMillis: Long,
  private val clock: () -> Long,
  private val fetch: suspend () -> CatalogResponse,
) {
  var usingFallback: Boolean = false
    private set

  init {
    require(ttlMillis >= 0) { "Catalog TTL must be zero or positive" }
  }

  suspend fun load(): CatalogResponse {
    val cached = store.read(cacheKey)
    val now = clock()
    if (cached != null && now - cached.fetchedAtEpochMs < ttlMillis) {
      usingFallback = false
      return presentCatalog(cached.catalog)
    }
    try {
      val accepted = acceptCatalog(fetch())
      if (accepted == null) {
        usingFallback = true
        return presentCatalog(cached?.catalog ?: baselineCatalog())
      }
      store.write(cacheKey, CachedCatalog(accepted, now))
      usingFallback = false
      return presentCatalog(accepted)
    } catch (error: MeridianError.HttpError) {
      if (error.statusCode == 500 || error.statusCode == 502 || error.statusCode == 504) {
        return fallback(cached)
      }
      throw error
    } catch (_: MeridianError.DecodingError) {
      return fallback(cached)
    } catch (_: MeridianError.NetworkError) {
      return fallback(cached)
    } catch (_: IOException) {
      return fallback(cached)
    }
  }

  private fun fallback(cached: CachedCatalog?): CatalogResponse {
    usingFallback = true
    return presentCatalog(cached?.catalog ?: baselineCatalog())
  }
}

internal fun acceptCatalog(catalog: CatalogResponse): CatalogResponse? {
  if (catalog.providers.any { it.id !in knownProviderIds }) return null
  return catalog
}

internal fun presentCatalog(catalog: CatalogResponse): CatalogResponse = catalog.copy(
  providers = catalog.providers.filter { it.available },
  corridors = catalog.corridors.filter { it.available },
)
