package com.atlassian.meridian

import com.fasterxml.jackson.annotation.JsonIgnore
import com.fasterxml.jackson.annotation.JsonInclude
import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.io.File
import java.io.FileOutputStream
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.security.GeneralSecurityException
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.coroutines.cancellation.CancellationException

const val LIVE_ELIGIBILITY_CAPABILITY = "live-eligibility"
const val DEFAULT_CATALOG_TTL_SECONDS = 300L
const val MAX_CATALOG_TTL_SECONDS = 86_400L

private val ACCOUNT_SCOPE = Regex("^[A-Za-z0-9_-]{1,64}$")
private val CORRIDOR = Regex("^[A-Za-z0-9_-]{1,32}$")

private val catalogMapper = ObjectMapper().registerKotlinModule().apply {
  configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)
  setSerializationInclusion(JsonInclude.Include.NON_NULL)
}

private val catalogFields = setOf("accountScope", "corridor", "currency", "ttlSeconds", "methods")
private val descriptorFields = setOf(
  "id",
  "method",
  "provider",
  "displayName",
  "currency",
  "corridor",
  "requiresLiveEligibility",
  "capabilities",
  "ttlSeconds",
)

/**
 * Open payment-method descriptor. Unknown JSON attributes are recorded and ignored
 * so an older build can read a newer catalog without failing.
 * Payable checkout still accepts only the hardcoded Adyen card and Worldpay bank pairs.
 */
data class PaymentMethodDescriptor(
  val id: String,
  val method: String,
  val provider: String,
  val displayName: String = "",
  val currency: String = "GBP",
  val corridor: String = "",
  val requiresLiveEligibility: Boolean = false,
  val capabilities: List<String> = emptyList(),
  val ttlSeconds: Long? = null,
  @get:JsonIgnore
  val ignoredAttributeNames: List<String> = emptyList(),
) {
  val requiresFreshEligibility: Boolean
    get() = requiresLiveEligibility || capabilities.any { it.equals(LIVE_ELIGIBILITY_CAPABILITY, ignoreCase = true) }

  val isHardcodedBaseline: Boolean
    get() = (provider == "adyen" && method == "card") || (provider == "worldpay" && method == "bank")
}

data class PaymentMethodsCatalog(
  val accountScope: String,
  val corridor: String,
  val currency: String,
  val ttlSeconds: Long,
  val methods: List<PaymentMethodDescriptor>,
  val ignoredAttributeNames: List<String> = emptyList(),
)

data class ResolvedPaymentCatalog(
  val accountScope: String,
  val corridor: String,
  val currency: String,
  val available: List<PaymentMethodDescriptor>,
  val withheld: List<PaymentMethodDescriptor>,
  val stale: Boolean,
  val fromCache: Boolean,
) {
  val payableBaseline: List<PaymentMethodDescriptor>
    get() = available.filter { it.isHardcodedBaseline }

  val failClosed: Boolean
    get() = withheld.isNotEmpty()
}

data class CachedCatalogEnvelope(
  val schema: Int = 1,
  val accountScope: String,
  val corridor: String,
  val currency: String,
  val storedAtEpochMs: Long,
  val ttlSeconds: Long,
  val methods: List<StoredPaymentMethod>,
)

data class StoredPaymentMethod(
  val id: String,
  val method: String,
  val provider: String,
  val displayName: String,
  val currency: String,
  val corridor: String,
  val requiresLiveEligibility: Boolean,
  val capabilities: List<String>,
  val ttlSeconds: Long? = null,
)

fun validateCatalogQuery(accountScope: String, corridor: String, currency: String) {
  if (!ACCOUNT_SCOPE.matches(accountScope)) {
    throw MeridianError.ValidationError("Invalid account scope")
  }
  if (!CORRIDOR.matches(corridor)) {
    throw MeridianError.ValidationError("Invalid corridor")
  }
  if (currency != "GBP") {
    throw MeridianError.ValidationError("Currency must be GBP")
  }
}

fun normalizeCatalogTtl(seconds: Long): Long = when {
  seconds < 0 -> 0
  seconds > MAX_CATALOG_TTL_SECONDS -> MAX_CATALOG_TTL_SECONDS
  else -> seconds
}

fun buildPaymentMethodsUrl(
  baseUrl: String,
  accountScope: String,
  corridor: String,
  currency: String,
): String {
  validateCatalogQuery(accountScope, corridor, currency)
  val trimmed = baseUrl.removeSuffix("/")
  val origin = if (trimmed.endsWith("/api/v1")) trimmed.removeSuffix("/api/v1") else trimmed
  val scope = URLEncoder.encode(accountScope, StandardCharsets.UTF_8.name())
  val encodedCorridor = URLEncoder.encode(corridor, StandardCharsets.UTF_8.name())
  val encodedCurrency = URLEncoder.encode(currency, StandardCharsets.UTF_8.name())
  return "$origin/api/v2/payment-methods?accountScope=$scope&corridor=$encodedCorridor&currency=$encodedCurrency"
}

fun catalogStorageKey(accountScope: String, corridor: String, currency: String): String {
  validateCatalogQuery(accountScope, corridor, currency)
  return listOf(accountScope, corridor, currency).joinToString("\u001f")
}

fun catalogSessionDirectoryName(sessionId: String): String {
  require(sessionId.isNotEmpty()) { "Session ID is required" }
  val digest = MessageDigest.getInstance("SHA-256").digest(sessionId.toByteArray(StandardCharsets.UTF_8))
  return digest.joinToString("") { "%02x".format(it) }
}

fun parsePaymentMethodsCatalog(json: String): PaymentMethodsCatalog {
  val node = try {
    catalogMapper.readTree(json)
  } catch (error: Exception) {
    throw MeridianError.DecodingError("Failed to parse payment method catalog: ${error.message}", error)
  }
  if (node == null || !node.isObject) {
    throw MeridianError.DecodingError("Catalog must be a JSON object")
  }
  val accountScope = requiredText(node, "accountScope")
  val corridor = requiredText(node, "corridor")
  val currency = requiredText(node, "currency")
  val ttlSeconds = optionalLong(node, "ttlSeconds") ?: DEFAULT_CATALOG_TTL_SECONDS
  val methodsNode = node.get("methods")
  if (methodsNode != null && !methodsNode.isNull && !methodsNode.isArray) {
    throw MeridianError.DecodingError("methods must be an array")
  }
  val methods = if (methodsNode == null || methodsNode.isNull) {
    emptyList()
  } else {
    methodsNode.mapNotNull { parseDescriptor(it) }
  }
  val ignored = node.fieldNames().asSequence().filter { it !in catalogFields }.sorted().toList()
  return PaymentMethodsCatalog(
    accountScope = accountScope,
    corridor = corridor,
    currency = currency,
    ttlSeconds = ttlSeconds,
    methods = methods,
    ignoredAttributeNames = ignored,
  )
}

fun PaymentMethodsCatalog.forRequest(
  accountScope: String,
  corridor: String,
  currency: String,
): PaymentMethodsCatalog {
  if (this.accountScope != accountScope || this.corridor != corridor) {
    throw MeridianError.ValidationError("Catalog scope does not match the request")
  }
  if (this.currency != "GBP" || currency != "GBP") {
    throw MeridianError.ValidationError("Currency must be GBP")
  }
  val kept = methods.mapNotNull { method ->
    val methodCurrency = method.currency.ifEmpty { "GBP" }
    val methodCorridor = method.corridor.ifEmpty { corridor }
    if (methodCurrency != "GBP" || methodCorridor != corridor) {
      null
    } else {
      method.copy(currency = "GBP", corridor = methodCorridor)
    }
  }
  return copy(ttlSeconds = normalizeCatalogTtl(ttlSeconds), methods = kept)
}

object CatalogExpiryPolicy {
  fun resolve(
    catalog: PaymentMethodsCatalog,
    storedAtEpochMs: Long,
    nowEpochMs: Long,
    fromCache: Boolean,
  ): ResolvedPaymentCatalog {
    val available = ArrayList<PaymentMethodDescriptor>()
    val withheld = ArrayList<PaymentMethodDescriptor>()
    var anyStale = false
    val catalogTtl = normalizeCatalogTtl(catalog.ttlSeconds)
    for (method in catalog.methods) {
      val methodTtl = method.ttlSeconds?.let { normalizeCatalogTtl(it) }
      val ttl = if (methodTtl == null) catalogTtl else minOf(methodTtl, catalogTtl)
      val stale = nowEpochMs >= storedAtEpochMs + ttl * 1000
      if (stale) anyStale = true
      if (stale && method.requiresFreshEligibility) {
        withheld.add(method)
      } else {
        available.add(method)
      }
    }
    return ResolvedPaymentCatalog(
      accountScope = catalog.accountScope,
      corridor = catalog.corridor,
      currency = catalog.currency,
      available = available,
      withheld = withheld,
      stale = anyStale,
      fromCache = fromCache,
    )
  }
}

interface CatalogSealer {
  fun seal(plaintext: ByteArray): ByteArray
  fun open(sealed: ByteArray): ByteArray
}

object CatalogBlob {
  val MAGIC = byteArrayOf(0x4D, 0x52, 0x43, 0x31)
  const val NONCE_LENGTH = 12
  const val TAG_LENGTH = 16

  fun frame(nonce: ByteArray, cipherTextAndTag: ByteArray): ByteArray {
    require(nonce.size == NONCE_LENGTH) { "Catalog nonce must be 96 bits" }
    return MAGIC + nonce + cipherTextAndTag
  }

  fun split(sealed: ByteArray): Pair<ByteArray, ByteArray> {
    val header = MAGIC.size + NONCE_LENGTH
    if (sealed.size < header + TAG_LENGTH) {
      throw MeridianError.DecodingError("Catalog blob is truncated")
    }
    if (!sealed.copyOfRange(0, MAGIC.size).contentEquals(MAGIC)) {
      throw MeridianError.DecodingError("Catalog blob magic mismatch")
    }
    val nonce = sealed.copyOfRange(MAGIC.size, header)
    val body = sealed.copyOfRange(header, sealed.size)
    return nonce to body
  }
}

class AesGcmCatalogSealer(key: ByteArray) : CatalogSealer {
  private val keySpec = SecretKeySpec(key.copyOf(), "AES")
  private val random = SecureRandom()

  init {
    require(key.size == 32) { "Catalog key must be 256 bits" }
  }

  override fun seal(plaintext: ByteArray): ByteArray {
    val nonce = ByteArray(CatalogBlob.NONCE_LENGTH)
    random.nextBytes(nonce)
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, keySpec, GCMParameterSpec(128, nonce))
    return CatalogBlob.frame(nonce, cipher.doFinal(plaintext))
  }

  override fun open(sealed: ByteArray): ByteArray {
    try {
      val (nonce, body) = CatalogBlob.split(sealed)
      val cipher = Cipher.getInstance("AES/GCM/NoPadding")
      cipher.init(Cipher.DECRYPT_MODE, keySpec, GCMParameterSpec(128, nonce))
      return cipher.doFinal(body)
    } catch (error: MeridianError) {
      throw error
    } catch (error: GeneralSecurityException) {
      throw MeridianError.DecodingError("Catalog blob failed authentication", error)
    }
  }
}

interface ProtectedBlobStore {
  fun write(storageKey: String, blob: ByteArray)
  fun read(storageKey: String): ByteArray?
  fun delete(storageKey: String)
}

class MemoryProtectedBlobStore : ProtectedBlobStore {
  private val lock = Any()
  private val blobs = LinkedHashMap<String, ByteArray>()

  val keys: Set<String>
    get() = synchronized(lock) { blobs.keys.toSet() }

  override fun write(storageKey: String, blob: ByteArray) {
    synchronized(lock) { blobs[storageKey] = blob.copyOf() }
  }

  override fun read(storageKey: String): ByteArray? = synchronized(lock) { blobs[storageKey]?.copyOf() }

  override fun delete(storageKey: String) {
    synchronized(lock) { blobs.remove(storageKey) }
  }
}

class FileProtectedBlobStore(private val directory: File) : ProtectedBlobStore {
  init {
    if (!directory.isDirectory && !directory.mkdirs()) {
      throw MeridianError.ValidationError("Unable to create catalog cache directory")
    }
    restrictToOwner(directory, executable = true)
  }

  override fun write(storageKey: String, blob: ByteArray) {
    val target = fileFor(storageKey)
    val temporary = File(directory, target.name + ".tmp")
    try {
      FileOutputStream(temporary).use { it.write(blob) }
      restrictToOwner(temporary, executable = false)
      if (target.exists() && !target.delete()) {
        throw MeridianError.ValidationError("Unable to replace catalog cache blob")
      }
      if (!temporary.renameTo(target)) {
        throw MeridianError.ValidationError("Unable to store catalog cache blob")
      }
      restrictToOwner(target, executable = false)
    } catch (error: MeridianError) {
      temporary.delete()
      throw error
    } catch (error: Exception) {
      temporary.delete()
      throw MeridianError.ValidationError("Unable to store catalog cache blob")
    }
  }

  override fun read(storageKey: String): ByteArray? {
    val target = fileFor(storageKey)
    if (!target.isFile) return null
    return target.readBytes()
  }

  override fun delete(storageKey: String) {
    fileFor(storageKey).delete()
  }

  private fun fileFor(storageKey: String): File {
    val digest = MessageDigest.getInstance("SHA-256").digest(storageKey.toByteArray(StandardCharsets.UTF_8))
    val name = digest.joinToString("") { "%02x".format(it) }
    return File(directory, "$name.bin")
  }
}

class CatalogCache(
  private val store: ProtectedBlobStore,
  private val sealer: CatalogSealer,
) {
  fun storageKey(accountScope: String, corridor: String, currency: String): String =
    catalogStorageKey(accountScope, corridor, currency)

  fun write(catalog: PaymentMethodsCatalog, storedAtEpochMs: Long) {
    val envelope = CachedCatalogEnvelope(
      schema = 1,
      accountScope = catalog.accountScope,
      corridor = catalog.corridor,
      currency = catalog.currency,
      storedAtEpochMs = storedAtEpochMs,
      ttlSeconds = normalizeCatalogTtl(catalog.ttlSeconds),
      methods = catalog.methods.map {
        StoredPaymentMethod(
          id = it.id,
          method = it.method,
          provider = it.provider,
          displayName = it.displayName,
          currency = it.currency,
          corridor = it.corridor,
          requiresLiveEligibility = it.requiresLiveEligibility,
          capabilities = it.capabilities,
          ttlSeconds = it.ttlSeconds,
        )
      },
    )
    val plaintext = catalogMapper.writeValueAsBytes(envelope)
    store.write(storageKey(catalog.accountScope, catalog.corridor, catalog.currency), sealer.seal(plaintext))
  }

  fun read(
    accountScope: String,
    corridor: String,
    currency: String,
    nowEpochMs: Long,
  ): ResolvedPaymentCatalog? {
    val key = storageKey(accountScope, corridor, currency)
    val blob = store.read(key) ?: return null
    val plaintext = try {
      sealer.open(blob)
    } catch (error: Exception) {
      store.delete(key)
      return null
    }
    val envelope = try {
      parseCachedEnvelope(plaintext)
    } catch (error: Exception) {
      store.delete(key)
      return null
    }
    if (
      envelope == null ||
      envelope.accountScope != accountScope ||
      envelope.corridor != corridor ||
      envelope.currency != currency ||
      envelope.currency != "GBP"
    ) {
      store.delete(key)
      return null
    }
    val catalog = PaymentMethodsCatalog(
      accountScope = envelope.accountScope,
      corridor = envelope.corridor,
      currency = envelope.currency,
      ttlSeconds = envelope.ttlSeconds,
      methods = envelope.methods,
    )
    return CatalogExpiryPolicy.resolve(catalog, envelope.storedAtEpochMs, nowEpochMs, fromCache = true)
  }
}

class PaymentMethodCatalogService(
  private val client: MeridianClient,
  private val cache: CatalogCache,
  private val clock: () -> Long = { System.currentTimeMillis() },
) {
  suspend fun load(
    accountScope: String,
    corridor: String,
    currency: String = "GBP",
  ): ResolvedPaymentCatalog {
    validateCatalogQuery(accountScope, corridor, currency)
    val cached = cache.read(accountScope, corridor, currency, clock())
    if (cached != null && !cached.stale) return cached
    return try {
      val fresh = client.fetchPaymentMethods(accountScope, corridor, currency)
      val storedAt = clock()
      cache.write(fresh, storedAt)
      CatalogExpiryPolicy.resolve(fresh, storedAt, storedAt, fromCache = false)
    } catch (cancelled: CancellationException) {
      throw cancelled
    } catch (error: Exception) {
      cached ?: throw error
    }
  }
}

private data class ReadEnvelope(
  val accountScope: String,
  val corridor: String,
  val currency: String,
  val storedAtEpochMs: Long,
  val ttlSeconds: Long,
  val methods: List<PaymentMethodDescriptor>,
)

private fun parseCachedEnvelope(plaintext: ByteArray): ReadEnvelope? {
  val node = catalogMapper.readTree(plaintext)
  if (node == null || !node.isObject) return null
  val schemaNode = node.get("schema")
  val schema = when {
    schemaNode == null || schemaNode.isNull -> 1L
    schemaNode.isIntegralNumber -> schemaNode.longValue()
    else -> return null
  }
  if (schema != 1L) return null
  val accountScope = optionalText(node, "accountScope") ?: return null
  val corridor = optionalText(node, "corridor") ?: return null
  val currency = optionalText(node, "currency") ?: return null
  val storedAt = optionalLong(node, "storedAtEpochMs") ?: return null
  val ttlSeconds = optionalLong(node, "ttlSeconds") ?: return null
  val methodsNode = node.get("methods")
  if (methodsNode != null && !methodsNode.isNull && !methodsNode.isArray) return null
  val methods = if (methodsNode == null || methodsNode.isNull) emptyList() else methodsNode.mapNotNull { parseDescriptor(it) }
  return ReadEnvelope(
    accountScope = accountScope,
    corridor = corridor,
    currency = currency,
    storedAtEpochMs = storedAt,
    ttlSeconds = ttlSeconds,
    methods = methods,
  )
}

private fun parseDescriptor(node: JsonNode): PaymentMethodDescriptor? {
  if (!node.isObject) return null
  val id = optionalText(node, "id")?.takeIf { it.isNotEmpty() } ?: return null
  val method = optionalText(node, "method")?.takeIf { it.isNotEmpty() } ?: return null
  val provider = optionalText(node, "provider")?.takeIf { it.isNotEmpty() } ?: return null
  val ignored = node.fieldNames().asSequence().filter { it !in descriptorFields }.sorted().toList()
  return PaymentMethodDescriptor(
    id = id,
    method = method,
    provider = provider,
    displayName = optionalText(node, "displayName") ?: "",
    currency = optionalText(node, "currency") ?: "",
    corridor = optionalText(node, "corridor") ?: "",
    requiresLiveEligibility = optionalBoolean(node, "requiresLiveEligibility") ?: false,
    capabilities = optionalStringList(node, "capabilities"),
    ttlSeconds = optionalLong(node, "ttlSeconds"),
    ignoredAttributeNames = ignored,
  )
}

private fun requiredText(node: JsonNode, field: String): String {
  val value = optionalText(node, field)
  if (value.isNullOrEmpty()) {
    throw MeridianError.DecodingError("Catalog $field is required")
  }
  return value
}

private fun optionalText(node: JsonNode, field: String): String? {
  val value = node.get(field) ?: return null
  if (value.isNull || !value.isTextual) return null
  return value.asText()
}

private fun optionalBoolean(node: JsonNode, field: String): Boolean? {
  val value = node.get(field) ?: return null
  if (value.isNull || !value.isBoolean) return null
  return value.booleanValue()
}

private fun optionalLong(node: JsonNode, field: String): Long? {
  val value = node.get(field) ?: return null
  if (value.isNull || !value.isIntegralNumber) return null
  return value.longValue()
}

private fun optionalStringList(node: JsonNode, field: String): List<String> {
  val value = node.get(field) ?: return emptyList()
  if (value.isNull || !value.isArray) return emptyList()
  return value.mapNotNull { item -> if (item.isTextual) item.asText() else null }
}

private fun restrictToOwner(file: File, executable: Boolean) {
  file.setReadable(false, false)
  file.setReadable(true, true)
  file.setWritable(false, false)
  file.setWritable(true, true)
  if (executable) {
    file.setExecutable(false, false)
    file.setExecutable(true, true)
  } else {
    file.setExecutable(false, false)
  }
}
