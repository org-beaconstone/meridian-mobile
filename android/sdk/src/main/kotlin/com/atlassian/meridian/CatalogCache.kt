package com.atlassian.meridian

import java.io.File
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.spec.MGF1ParameterSpec
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import javax.crypto.spec.SecretKeySpec
import kotlin.coroutines.cancellation.CancellationException

/**
 * Encrypted catalog cache keyed by account scope, corridor, and currency.
 *
 * Blobs are AES-256-GCM with the cache key as additional authenticated data, so a blob
 * cannot be replayed under a different scope. The AES key is held in platform protected
 * storage: Android Keystore wrapping on device, or an owner-only key file for the JVM rehearsal.
 *
 * Stale methods that require live eligibility are withheld. A timeout reads this same key
 * and does not send the caller to a different provider.
 */
class CatalogCache(
  private val store: CatalogBlobStore,
  private val keys: CatalogKeyProvider,
) {
  private val lock = Any()

  fun store(scope: CatalogScope, rawJson: String, nowEpochMs: Long) {
    parsePaymentMethodsCatalog(rawJson, scope)
    val plaintext = envelope(scope, nowEpochMs, rawJson)
    val secret = keys.loadOrCreateKey()
    val blob = CatalogCipher.encrypt(secret, scope.storageKey, plaintext)
    synchronized(lock) {
      store.write(scope.storageKey, blob)
    }
  }

  fun read(scope: CatalogScope, nowEpochMs: Long): CatalogResolution? {
    val blob = synchronized(lock) { store.read(scope.storageKey) } ?: return null
    val plaintext = try {
      CatalogCipher.decrypt(keys.loadOrCreateKey(), scope.storageKey, blob)
    } catch (error: MeridianError) {
      throw error
    } catch (error: Exception) {
      throw MeridianError.CatalogUnavailable("Catalog cache blob failed authentication", error)
    }
    val opened = openEnvelope(plaintext, scope)
    return eligibility(opened.catalog, opened.storedAtEpochMs, nowEpochMs, fromCache = true)
  }

  /**
   * Fetch the catalog, encrypt it, and return methods that pass the expiry policy.
   * On a transport or HTTP failure, read the same cache key. Never requests another corridor or provider.
   */
  suspend fun resolve(
    client: MeridianClient,
    accountScope: String,
    corridor: String,
    currency: String = "GBP",
    nowEpochMs: Long,
  ): CatalogResolution {
    val scope = CatalogScope.parse(accountScope, corridor, currency)
    try {
      val fetched = client.fetchPaymentMethods(scope.accountScope, scope.corridor, scope.currency)
      store(scope, fetched.rawJson, nowEpochMs)
      return eligibility(fetched.catalog, nowEpochMs, nowEpochMs, fromCache = false)
    } catch (cancelled: CancellationException) {
      throw cancelled
    } catch (error: Exception) {
      val cached = try {
        read(scope, nowEpochMs)
      } catch (corrupt: MeridianError) {
        throw MeridianError.CatalogUnavailable(
          "Cached payment methods failed validation",
          corrupt,
        )
      }
      return cached ?: throw error
    }
  }

  companion object {
    fun platformProtected(directory: File): CatalogCache {
      directory.mkdirs()
      val keyProvider: CatalogKeyProvider = if (AndroidKeystoreKeyProtector.isAvailable()) {
        WrappedFileCatalogKeyProvider(
          File(directory, "catalog.key.wrapped"),
          AndroidKeystoreKeyProtector(),
        )
      } else {
        FileCatalogKeyProvider(File(directory, "catalog.key"))
      }
      return CatalogCache(FileCatalogBlobStore(File(directory, "blobs")), keyProvider)
    }
  }
}

data class CatalogResolution(
  val scope: CatalogScope,
  val methods: List<PaymentMethodDescriptor>,
  val fromCache: Boolean,
  val stale: Boolean,
  val withheldLiveEligibility: Int,
)

internal fun eligibility(
  catalog: PaymentMethodsCatalog,
  storedAtEpochMs: Long,
  nowEpochMs: Long,
  fromCache: Boolean,
): CatalogResolution {
  val ageMillis = nowEpochMs - storedAtEpochMs
  val ageSeconds = if (ageMillis <= 0L) 0L else ageMillis / 1000L
  val kept = mutableListOf<PaymentMethodDescriptor>()
  var withheld = 0
  for (method in catalog.methods) {
    if (!method.enabled) continue
    val ttl = minOf(catalog.ttlSeconds, method.ttlSeconds)
    val staleMethod = ageSeconds >= ttl
    if (staleMethod && method.requiresLiveEligibility) {
      withheld += 1
      continue
    }
    kept.add(method)
  }
  return CatalogResolution(
    scope = CatalogScope(catalog.accountScope, catalog.corridor, catalog.currency),
    methods = kept,
    fromCache = fromCache,
    stale = ageSeconds >= catalog.ttlSeconds,
    withheldLiveEligibility = withheld,
  )
}

interface CatalogBlobStore {
  fun read(key: String): ByteArray?
  fun write(key: String, data: ByteArray)
}

interface CatalogKeyProvider {
  fun loadOrCreateKey(): SecretKey
}

class MemoryCatalogBlobStore : CatalogBlobStore {
  private val values = linkedMapOf<String, ByteArray>()

  override fun read(key: String): ByteArray? = values[key]?.copyOf()

  override fun write(key: String, data: ByteArray) {
    values[key] = data.copyOf()
  }

  fun peek(key: String): ByteArray? = values[key]?.copyOf()

  fun copy(from: String, to: String) {
    val bytes = values[from] ?: error("missing catalog blob")
    values[to] = bytes.copyOf()
  }
}

class MemoryCatalogKeyProvider : CatalogKeyProvider {
  private val key: SecretKey = SecretKeySpec(randomAesKey(), "AES")

  override fun loadOrCreateKey(): SecretKey = key
}

class FileCatalogBlobStore(private val directory: File) : CatalogBlobStore {
  override fun read(key: String): ByteArray? {
    val file = fileFor(key)
    if (!file.isFile) return null
    return file.readBytes()
  }

  override fun write(key: String, data: ByteArray) {
    directory.mkdirs()
    val file = fileFor(key)
    val temporary = File(directory, file.name + ".tmp")
    temporary.writeBytes(data)
    restrictToOwner(temporary)
    if (!temporary.renameTo(file)) {
      file.writeBytes(data)
      temporary.delete()
    }
    restrictToOwner(file)
  }

  private fun fileFor(key: String): File = File(directory, sha256Hex(key) + ".bin")
}

class FileCatalogKeyProvider(private val file: File) : CatalogKeyProvider {
  override fun loadOrCreateKey(): SecretKey {
    if (file.isFile) {
      val existing = file.readBytes()
      if (existing.size != 32) {
        throw MeridianError.CatalogUnavailable("Protected catalog key is unusable")
      }
      return SecretKeySpec(existing, "AES")
    }
    file.parentFile?.mkdirs()
    val created = randomAesKey()
    file.writeBytes(created)
    restrictToOwner(file)
    return SecretKeySpec(created, "AES")
  }
}

/**
 * Persists an AES key that has been wrapped by [protector]. On Android the wrapper key
 * lives in the platform keystore and the file holds only ciphertext.
 */
class WrappedFileCatalogKeyProvider(
  private val file: File,
  private val protector: CatalogKeyProtector,
) : CatalogKeyProvider {
  override fun loadOrCreateKey(): SecretKey {
    if (file.isFile) {
      val encoded = protector.unprotect(file.readBytes())
      if (encoded.size != 32) {
        throw MeridianError.CatalogUnavailable("Protected catalog key is unusable")
      }
      return SecretKeySpec(encoded, "AES")
    }
    file.parentFile?.mkdirs()
    val created = randomAesKey()
    file.writeBytes(protector.protect(created))
    restrictToOwner(file)
    return SecretKeySpec(created, "AES")
  }
}

interface CatalogKeyProtector {
  fun protect(keyBytes: ByteArray): ByteArray
  fun unprotect(protectedKey: ByteArray): ByteArray
}

/**
 * Wraps the catalog AES key with an Android Keystore RSA key. Compiled without the Android SDK;
 * the keystore types are loaded only when the platform classes exist.
 */
internal class AndroidKeystoreKeyProtector : CatalogKeyProtector {
  override fun protect(keyBytes: ByteArray): ByteArray {
    val cipher = oaepCipher()
    cipher.init(Cipher.WRAP_MODE, publicKey(), oaep())
    return cipher.wrap(SecretKeySpec(keyBytes, "AES"))
  }

  override fun unprotect(protectedKey: ByteArray): ByteArray {
    val cipher = oaepCipher()
    cipher.init(Cipher.UNWRAP_MODE, privateKey(), oaep())
    val unwrapped = cipher.unwrap(protectedKey, "AES", Cipher.SECRET_KEY)
    return unwrapped.encoded
      ?: throw MeridianError.CatalogUnavailable("Protected catalog key is unusable")
  }

  private fun publicKey(): java.security.PublicKey {
    ensureKeyPair()
    val keyStore = androidKeyStore()
    return keyStore.getCertificate(ALIAS)?.publicKey
      ?: throw MeridianError.CatalogUnavailable("Android keystore certificate is missing")
  }

  private fun privateKey(): java.security.PrivateKey {
    ensureKeyPair()
    val key = androidKeyStore().getKey(ALIAS, null)
    return key as? java.security.PrivateKey
      ?: throw MeridianError.CatalogUnavailable("Android keystore private key is missing")
  }

  private fun ensureKeyPair() {
    val keyStore = androidKeyStore()
    if (keyStore.containsAlias(ALIAS)) return
    val generator = KeyPairGenerator.getInstance("RSA", "AndroidKeyStore")
    generator.initialize(keyGenParameterSpec())
    generator.generateKeyPair()
  }

  private fun keyGenParameterSpec(): java.security.spec.AlgorithmParameterSpec {
    return try {
      val keyProperties = Class.forName("android.security.keystore.KeyProperties")
      val purposeEncrypt = keyProperties.getField("PURPOSE_ENCRYPT").getInt(null)
      val purposeDecrypt = keyProperties.getField("PURPOSE_DECRYPT").getInt(null)
      val digestSha256 = keyProperties.getField("DIGEST_SHA256").get(null) as String
      val digestSha512 = keyProperties.getField("DIGEST_SHA512").get(null) as String
      val padding = keyProperties.getField("ENCRYPTION_PADDING_RSA_OAEP").get(null) as String
      val builderClass = Class.forName("android.security.keystore.KeyGenParameterSpec\$Builder")
      val builder = builderClass
        .getConstructor(String::class.java, Integer.TYPE)
        .newInstance(ALIAS, purposeEncrypt or purposeDecrypt)
      val stringArray = Array<String>::class.java
      // Cast to Any so Method.invoke does not spread the String array across its own varargs.
      builderClass.getMethod("setDigests", stringArray)
        .invoke(builder, arrayOf(digestSha256, digestSha512) as Any)
      builderClass.getMethod("setEncryptionPaddings", stringArray)
        .invoke(builder, arrayOf(padding) as Any)
      builderClass.getMethod("setKeySize", Integer.TYPE).invoke(builder, 2048)
      builderClass.getMethod("build").invoke(builder) as java.security.spec.AlgorithmParameterSpec
    } catch (error: Exception) {
      throw MeridianError.CatalogUnavailable("Android keystore is unavailable", error)
    }
  }

  companion object {
    private const val ALIAS = "meridian.catalog.wrap"

    fun isAvailable(): Boolean = try {
      Class.forName("android.security.keystore.KeyGenParameterSpec")
      true
    } catch (_: ClassNotFoundException) {
      false
    }
  }
}

private fun androidKeyStore(): KeyStore {
  val keyStore = KeyStore.getInstance("AndroidKeyStore")
  keyStore.load(null)
  return keyStore
}

private fun oaepCipher(): Cipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")

private fun oaep(): OAEPParameterSpec = OAEPParameterSpec(
  "SHA-256",
  "MGF1",
  MGF1ParameterSpec.SHA256,
  PSource.PSpecified.DEFAULT,
)

private object CatalogCipher {
  private val magic = byteArrayOf(0x4D, 0x52, 0x43, 0x31) // MRC1
  private val random = SecureRandom()

  fun encrypt(key: SecretKey, aad: String, plaintext: ByteArray): ByteArray {
    val nonce = ByteArray(12)
    random.nextBytes(nonce)
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, nonce))
    cipher.updateAAD(aad.toByteArray(Charsets.UTF_8))
    val ciphertext = cipher.doFinal(plaintext)
    return magic + nonce + ciphertext
  }

  fun decrypt(key: SecretKey, aad: String, blob: ByteArray): ByteArray {
    if (blob.size < magic.size + 12 + 16 || !blob.copyOfRange(0, magic.size).contentEquals(magic)) {
      throw MeridianError.CatalogUnavailable("Catalog cache blob is not readable")
    }
    return try {
      val nonce = blob.copyOfRange(magic.size, magic.size + 12)
      val ciphertext = blob.copyOfRange(magic.size + 12, blob.size)
      val cipher = Cipher.getInstance("AES/GCM/NoPadding")
      cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, nonce))
      cipher.updateAAD(aad.toByteArray(Charsets.UTF_8))
      cipher.doFinal(ciphertext)
    } catch (error: MeridianError) {
      throw error
    } catch (error: Exception) {
      throw MeridianError.CatalogUnavailable("Catalog cache blob failed authentication", error)
    }
  }
}

private data class OpenedCatalog(
  val catalog: PaymentMethodsCatalog,
  val storedAtEpochMs: Long,
)

private fun envelope(scope: CatalogScope, storedAtEpochMs: Long, rawJson: String): ByteArray {
  val node = catalogMapper.createObjectNode()
  node.put("v", 1)
  node.put("storedAtEpochMs", storedAtEpochMs)
  node.put("accountScope", scope.accountScope)
  node.put("corridor", scope.corridor)
  node.put("currency", scope.currency)
  node.put("body", rawJson)
  return catalogMapper.writeValueAsBytes(node)
}

private fun openEnvelope(plaintext: ByteArray, expected: CatalogScope): OpenedCatalog {
  val root = try {
    catalogMapper.readTree(plaintext)
  } catch (error: Exception) {
    throw MeridianError.CatalogUnavailable("Catalog cache blob is not readable", error)
  }
  if (!root.isObject || root.get("v")?.asInt() != 1) {
    throw MeridianError.CatalogUnavailable("Catalog cache blob is not readable")
  }
  val storedAt = root.get("storedAtEpochMs")
  if (storedAt == null || !storedAt.isIntegralNumber) {
    throw MeridianError.CatalogUnavailable("Catalog cache blob is not readable")
  }
  val accountScope = root.get("accountScope")?.asText()
  val corridor = root.get("corridor")?.asText()
  val currency = root.get("currency")?.asText()
  if (accountScope != expected.accountScope || corridor != expected.corridor || currency != expected.currency) {
    throw MeridianError.CatalogUnavailable("Catalog cache blob does not match the requested scope")
  }
  val body = root.get("body")?.takeIf { it.isTextual }?.asText()
    ?: throw MeridianError.CatalogUnavailable("Catalog cache blob is not readable")
  return OpenedCatalog(parsePaymentMethodsCatalog(body, expected), storedAt.longValue())
}

private fun randomAesKey(): ByteArray = ByteArray(32).also { SecureRandom().nextBytes(it) }

private fun restrictToOwner(file: File) {
  file.setReadable(false, false)
  file.setWritable(false, false)
  file.setExecutable(false, false)
  file.setReadable(true, true)
  file.setWritable(true, true)
}

private fun sha256Hex(text: String): String {
  val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
  val alphabet = "0123456789abcdef"
  val out = StringBuilder(digest.size * 2)
  for (byte in digest) {
    val value = byte.toInt() and 0xFF
    out.append(alphabet[value ushr 4])
    out.append(alphabet[value and 0x0F])
  }
  return out.toString()
}
