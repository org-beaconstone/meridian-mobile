package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule

class CatalogCache {
  private var sessionId: String? = null
  private var storedAt: Long = 0
  private var ttlMillis: Long = 0
  private var document: CatalogDocument? = null

  fun store(session: String, document: CatalogDocument, at: Long, ttlMillis: Long) {
    sessionId = session
    this.document = document
    storedAt = at
    this.ttlMillis = ttlMillis
  }

  fun read(session: String, at: Long): String {
    if (document == null || sessionId != session) return "miss"
    if (at >= storedAt + ttlMillis) return "expired"
    return "hit"
  }

  companion object {
    const val defaultTtlMillis: Long = 30_000
  }
}

data class StoredAttempt(
  val sessionId: String,
  val key: String,
  val recipientId: String,
  val currency: String,
  val minor: Int,
  val exponent: Int,
  val method: String,
  val note: String,
  val status: String,
)

class IdempotencyJournal {
  private var attempt: StoredAttempt? = null

  val status: String get() = attempt?.status ?: "empty"
  val key: String? get() = attempt?.key
  val sessionId: String? get() = attempt?.sessionId

  fun begin(
    sessionId: String,
    key: String,
    recipientId: String,
    currency: String,
    minor: Int,
    exponent: Int,
    method: String,
    note: String,
  ): ContractError? {
    if (!sessionPattern.matches(sessionId) || !keyPattern.matches(key) || !recipientPattern.matches(recipientId)) {
      return ContractError("MALFORMED_ATTEMPT", "Payment attempt is invalid")
    }
    if (method != "card" && method != "bank") return ContractError("MALFORMED_ATTEMPT", "Payment method is invalid")
    if (!Regex("^[A-Z]{3}$").matches(currency) || exponent !in 0..4 || minor < 0 || note.length > 200) {
      return ContractError("MALFORMED_ATTEMPT", "Payment attempt is invalid")
    }
    val existing = attempt
    if (existing != null && existing.status != "completed") {
      return ContractError("IDEMPOTENCY_RETAINED", "An unfinished payment key is retained")
    }
    attempt = StoredAttempt(sessionId, key, recipientId, currency, minor, exponent, method, note, "draft")
    return null
  }

  fun markUncertain(): ContractError? {
    val existing = attempt ?: return ContractError("MISSING_ATTEMPT", "No payment attempt")
    if (existing.status == "completed") return ContractError("ALREADY_COMPLETED", "Payment already completed")
    attempt = existing.copy(status = "uncertain")
    return null
  }

  fun markCompleted(): ContractError? {
    val existing = attempt ?: return ContractError("MISSING_ATTEMPT", "No payment attempt")
    attempt = existing.copy(status = "completed")
    return null
  }

  fun discardDraft(): ContractError? {
    val existing = attempt ?: return ContractError("MISSING_ATTEMPT", "No payment attempt")
    if (existing.status != "draft") return ContractError("IDEMPOTENCY_RETAINED", "Uncertain payment key is retained")
    attempt = null
    return null
  }

  fun retry(
    note: String,
    recipientId: String? = null,
    minor: Int? = null,
    method: String? = null,
    currency: String? = null,
  ): Decoded<String> {
    val existing = attempt ?: return Decoded.Err(ContractError("MISSING_ATTEMPT", "No payment attempt"))
    val same = (recipientId ?: existing.recipientId) == existing.recipientId &&
      (minor ?: existing.minor) == existing.minor &&
      (method ?: existing.method) == existing.method &&
      (currency ?: existing.currency) == existing.currency &&
      note == existing.note
    if (!same) return Decoded.Err(ContractError("IDEMPOTENCY_MISMATCH", "Idempotency key reused with a different payload"))
    return Decoded.Ok(existing.key)
  }

  fun snapshot(): String {
    val current = attempt ?: return emptySnapshot
    return buildString {
      append("{\"version\":1,\"empty\":false")
      append(",\"sessionId\":${jsonString(current.sessionId)}")
      append(",\"key\":${jsonString(current.key)}")
      append(",\"status\":${jsonString(current.status)}")
      append(",\"recipientId\":${jsonString(current.recipientId)}")
      append(",\"currency\":${jsonString(current.currency)}")
      append(",\"minor\":${current.minor}")
      append(",\"exponent\":${current.exponent}")
      append(",\"method\":${jsonString(current.method)}")
      append(",\"note\":${jsonString(current.note)}}")
    }
  }

  fun kill() {
    val restored = restore(snapshot())
    attempt = restored.attempt
  }

  companion object {
    const val snapshotDefaultsKey = "meridian.idempotency.snapshot"
    const val emptySnapshot = "{\"version\":1,\"empty\":true}"
    private val mapper = ObjectMapper().registerKotlinModule()
    private val sessionPattern = Regex("^[A-Za-z0-9_-]{3,64}$")
    private val keyPattern = Regex("^[A-Za-z0-9_-]{1,100}$")
    private val recipientPattern = Regex("^[a-z0-9-]{1,64}$")

    fun restore(snapshot: String): IdempotencyJournal {
      val journal = IdempotencyJournal()
      val node = mapper.readTree(snapshot)
      if (node.path("empty").asBoolean(false) || node.path("version").asInt() != 1) return journal
      if (!node.hasNonNull("key")) return journal
      journal.attempt = StoredAttempt(
        sessionId = node.path("sessionId").asText(),
        key = node.path("key").asText(),
        recipientId = node.path("recipientId").asText(),
        currency = node.path("currency").asText(),
        minor = node.path("minor").asInt(),
        exponent = node.path("exponent").asInt(),
        method = node.path("method").asText(),
        note = node.path("note").asText(),
        status = node.path("status").asText(),
      )
      return journal
    }
  }
}

private fun jsonString(value: String): String {
  val escaped = value.replace("\\", "\\\\").replace("\"", "\\\"")
  return "\"$escaped\""
}

data class ArmedReturn(
  val sessionId: String,
  val paymentId: String,
  val nonce: String,
  val exp: Long,
  val key: String,
  var consumed: Boolean = false,
)

class ReturnStateGuard {
  private var selected: String = ""
  private val armed = mutableListOf<ArmedReturn>()

  val selectedSession: String get() = selected

  fun select(session: String) {
    selected = session
  }

  fun arm(sessionId: String, paymentId: String, nonce: String, exp: Long, key: String): ContractError? {
    if (sessionId != selected) return ContractError("SESSION_MISMATCH", "Return state does not match the selected room")
    if (paymentId.isBlank() || nonce.isBlank() || key.isBlank()) return ContractError("MALFORMED_LINK", "Return link is incomplete")
    if (armed.any { it.nonce == nonce }) return ContractError("REPLAY", "Return nonce was already used")
    armed += ArmedReturn(sessionId, paymentId, nonce, exp, key)
    return null
  }

  fun open(paymentId: String, nonce: String, now: Long): Decoded<String> {
    val item = armed.find { it.nonce == nonce && it.paymentId == paymentId }
      ?: return Decoded.Err(ContractError("MALFORMED_LINK", "Return link is not recognised"))
    if (item.sessionId != selected) return Decoded.Err(ContractError("SESSION_MISMATCH", "Return link does not match the selected room"))
    if (item.consumed) return Decoded.Err(ContractError("REPLAY", "This return link was already used"))
    if (now >= item.exp) return Decoded.Err(ContractError("EXPIRED", "This return link has expired"))
    item.consumed = true
    return Decoded.Ok(item.key)
  }

  fun openUrl(url: String, now: Long): Decoded<String> {
    val params = parseReturnUrl(url)
      ?: return Decoded.Err(ContractError("MALFORMED_LINK", "Return link is invalid"))
    if (params.getValue("session") != selected) {
      return Decoded.Err(ContractError("SESSION_MISMATCH", "Return link does not match the selected room"))
    }
    return open(params.getValue("paymentId"), params.getValue("nonce"), now)
  }

  fun userMessage(result: Decoded<String>): String = when (result) {
    is Decoded.Ok -> "Returned from payment. Retry uses the original payment key."
    is Decoded.Err -> when (result.error.code) {
      "REPLAY" -> "This return link was already used."
      "EXPIRED" -> "This return link has expired."
      "SESSION_MISMATCH" -> "Return link does not match the selected room."
      else -> "Return link was rejected."
    }
  }
}

fun parseReturnUrl(url: String): Map<String, String>? {
  val prefix = "meridian://payments/return?"
  if (!url.startsWith(prefix)) return null
  val query = url.removePrefix(prefix)
  if (query.isEmpty()) return null
  val params = linkedMapOf<String, String>()
  for (part in query.split("&")) {
    val bits = part.split("=", limit = 2)
    if (bits.size != 2 || bits[0].isEmpty()) return null
    val decoded = percentDecode(bits[1]) ?: return null
    params[bits[0]] = decoded
  }
  val paymentId = params["paymentId"]
  val nonce = params["nonce"]
  val session = params["session"]
  val exp = params["exp"]?.toLongOrNull()
  if (paymentId.isNullOrBlank() || nonce.isNullOrBlank() || session.isNullOrBlank() || exp == null) return null
  return params
}

private fun percentDecode(value: String): String? {
  val bytes = ArrayList<Byte>()
  var index = 0
  while (index < value.length) {
    val char = value[index]
    if (char == '%' && index + 2 < value.length) {
      val hex = value.substring(index + 1, index + 3)
      val parsed = hex.toIntOrNull(16) ?: return null
      bytes += parsed.toByte()
      index += 3
    } else if (char == '+') {
      bytes += ' '.code.toByte()
      index += 1
    } else {
      val code = char.code
      if (code > 127) return null
      bytes += code.toByte()
      index += 1
    }
  }
  return bytes.toByteArray().toString(Charsets.UTF_8)
}

data class A11yNode(
  val id: String,
  val voiceOverLabel: String,
  val talkBackDescription: String,
  val traits: List<String>,
  val textDirection: String,
  val scalesWithFont: Boolean,
  val mirrorsInRtl: Boolean,
  val minTouchTargetPt: Int = 44,
  val minTouchTargetDp: Int = 48,
)

object AccessibilityCatalog {
  val nodes: List<A11yNode> = listOf(
    A11yNode("balance", "Everyday account balance", "Everyday account balance", listOf("updatesFrequently"), "ltr", true, false),
    A11yNode("amount-input", "Amount in pounds", "Amount in pounds", listOf("textField"), "ltr", true, false),
    A11yNode("review-payment", "Review payment", "Review payment", listOf("button"), "locale", true, false),
    A11yNode("confirm-payment", "Confirm payment", "Confirm payment", listOf("button"), "locale", true, false),
    A11yNode("method-card", "Debit card · Adyen", "Debit card · Adyen", listOf("button"), "locale", true, false),
    A11yNode("method-bank", "Bank payment · Worldpay", "Bank payment · Worldpay", listOf("button"), "locale", true, false),
    A11yNode("connect", "Connect", "Connect", listOf("button"), "locale", true, false),
    A11yNode("back-navigation", "Back", "Back", listOf("button"), "locale", true, true),
  )

  fun node(id: String): A11yNode? = nodes.find { it.id == id }
}
