package com.atlassian.meridian

import java.net.URI
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Rehearsal Strong Customer Authentication and bank-return checks.
 * The signing key is random process memory, not a provider credential.
 * Bank URLs are confined to a reserved .test host. Nothing here calls Adyen or Worldpay.
 */
enum class ReturnOutcome {
  accepted,
  replayed,
  invalid,
  expired,
  ignored;

  fun userMessage(): String = when (this) {
    accepted -> "Bank return accepted. The same payment key will be used."
    replayed -> "This bank return was already used. The payment was not sent again."
    invalid -> "This bank return is not valid. The payment was not sent."
    expired -> "This bank return has expired. The payment was not sent."
    ignored -> "That link is not a bank return. The payment was not sent."
  }
}

data class ReturnDecision(
  val outcome: ReturnOutcome,
  val idempotencyKey: String,
  val allowsPaymentSubmit: Boolean,
) {
  /** Return handling never creates a payment. Callers submit only after a fresh acceptance. */
  val createsPayment: Boolean get() = false
}

data class IssuedBankHandoff(
  val handoffUrl: String,
  val returnUrl: String,
  val state: String,
  val idempotencyKey: String,
  val expiresAtEpochSeconds: Long,
)

sealed class UrlCheck {
  data class Allowed(val url: String) : UrlCheck()
  data class Refused(val reason: String) : UrlCheck()
}

internal sealed class LinkMatch {
  data object Unrelated : LinkMatch()
  data class Malformed(val reason: String) : LinkMatch()
  data class Ready(val url: String, val state: String) : LinkMatch()
}

object BankHandoffPolicy {
  const val bankHost: String = "bank.meridian-rehearsal.test"
  const val returnHost: String = "app.meridian-rehearsal.test"
  const val bankPath: String = "/handoff"
  const val returnPath: String = "/bank/return"

  fun inspectBankHandoff(url: String): UrlCheck = verdict(matchLink(url, bankHost, bankPath))

  fun inspectReturnLink(url: String): UrlCheck = verdict(matchLink(url, returnHost, returnPath))

  private fun verdict(match: LinkMatch): UrlCheck = when (match) {
    is LinkMatch.Ready -> UrlCheck.Allowed(match.url)
    is LinkMatch.Malformed -> UrlCheck.Refused(match.reason)
    LinkMatch.Unrelated -> UrlCheck.Refused("Host is not allowlisted")
  }

  internal fun matchReturn(url: String): LinkMatch = matchLink(url, returnHost, returnPath)
}

private val stateQuery = Regex("""state=([A-Za-z0-9_-]+)\.([0-9a-f]{64})""")

private fun matchLink(url: String, host: String, path: String): LinkMatch {
  if (url.isEmpty() || url.any { it.isISOControl() || it.isWhitespace() || it == '\\' }) {
    return LinkMatch.Unrelated
  }
  if (!url.startsWith("https://")) {
    return if (url.startsWith("http://") && url.contains(host)) {
      LinkMatch.Malformed("Only HTTPS URLs can be opened")
    } else {
      LinkMatch.Unrelated
    }
  }
  val uri = try {
    URI(url)
  } catch (_: Exception) {
    return LinkMatch.Malformed("URL is not usable")
  }
  if (uri.userInfo != null || (uri.rawAuthority?.contains('@') == true)) {
    return LinkMatch.Malformed("URL userinfo is not allowed")
  }
  val parsedHost = uri.host?.lowercase() ?: return LinkMatch.Malformed("Host is missing")
  if (parsedHost != host || uri.path != path) return LinkMatch.Unrelated
  if (uri.port != -1 && uri.port != 443) return LinkMatch.Malformed("Unexpected port")
  if (uri.rawFragment != null) return LinkMatch.Malformed("Fragments are not allowed")
  val query = uri.rawQuery ?: return LinkMatch.Malformed("Missing state")
  val state = stateQuery.matchEntire(query) ?: return LinkMatch.Malformed("Return state is missing or not opaque")
  return LinkMatch.Ready(url, state.groupValues[1] + "." + state.groupValues[2])
}

object PinConfirmation {
  fun rejectReason(pin: String, repeated: String): String? {
    if (pin.length !in 4..6 || pin.any { !it.isDigit() }) {
      return "PIN must be 4 to 6 digits"
    }
    if (pin != repeated) return "PIN entries do not match"
    return null
  }
}

data class PaymentAttempt(
  val idempotencyKey: String,
  val method: PaymentMethod,
  val scaConfirmed: Boolean = false,
  val bankAccepted: Boolean = false,
) {
  val readyToSubmit: Boolean
    get() = when (method) {
      PaymentMethod.card -> scaConfirmed
      PaymentMethod.bank -> bankAccepted
    }

  fun confirmingBiometric(succeeded: Boolean): PaymentAttempt =
    if (succeeded) copy(scaConfirmed = true) else this

  fun confirmingPin(pin: String, repeated: String): Pair<PaymentAttempt, String?> {
    val error = PinConfirmation.rejectReason(pin, repeated)
    return if (error == null) Pair(copy(scaConfirmed = true), null) else Pair(this, error)
  }

  fun applying(decision: ReturnDecision): PaymentAttempt {
    if (method != PaymentMethod.bank) return this
    if (
      decision.outcome == ReturnOutcome.accepted &&
      decision.allowsPaymentSubmit &&
      !decision.createsPayment &&
      decision.idempotencyKey == idempotencyKey
    ) {
      return copy(bankAccepted = true)
    }
    return this
  }

  fun submitIfReady(block: (String) -> Unit): Boolean {
    if (!readyToSubmit) return false
    block(idempotencyKey)
    return true
  }
}

class ReturnStateVault(
  key: ByteArray? = null,
  ttlSeconds: Long = DEFAULT_TTL_SECONDS,
  private val now: () -> Long = { System.currentTimeMillis() / 1000 },
) {
  private val key: ByteArray
  private val ttlSeconds: Long
  private val consumed = HashSet<String>()
  private val lock = Any()

  init {
    val material = key ?: randomKey()
    require(material.size >= 16) { "Return state key is too short" }
    this.key = material.copyOf()
    this.ttlSeconds = ttlSeconds.coerceIn(1, DEFAULT_TTL_SECONDS)
  }

  fun issue(sessionId: String, paymentKey: String): IssuedBankHandoff {
    require(sessionPattern.matches(sessionId)) { "Invalid session" }
    require(paymentKeyPattern.matches(paymentKey)) { "Invalid payment key" }
    val exp = now() + ttlSeconds
    val nonce = java.util.UUID.randomUUID().toString()
    val payload = canonical(exp, nonce, paymentKey, sessionId)
    val token = sign(key, payload)
    val handoff = "https://${BankHandoffPolicy.bankHost}${BankHandoffPolicy.bankPath}?state=$token"
    val ret = "https://${BankHandoffPolicy.returnHost}${BankHandoffPolicy.returnPath}?state=$token"
    check(BankHandoffPolicy.inspectBankHandoff(handoff) is UrlCheck.Allowed) { "Handoff URL left the allowlist" }
    check(BankHandoffPolicy.inspectReturnLink(ret) is UrlCheck.Allowed) { "Return URL is not an app link" }
    return IssuedBankHandoff(handoff, ret, token, paymentKey, exp)
  }

  fun cancel(state: String) {
    val parsed = parseToken(state) ?: return
    synchronized(lock) { consumed.add(parsed.nonce) }
  }

  fun intercept(url: String, expectedSession: String, expectedPaymentKey: String): ReturnDecision {
    fun finish(outcome: ReturnOutcome, allow: Boolean) = ReturnDecision(
      outcome = outcome,
      idempotencyKey = expectedPaymentKey,
      allowsPaymentSubmit = allow,
    )

    val ready = when (val match = BankHandoffPolicy.matchReturn(url)) {
      LinkMatch.Unrelated -> return finish(ReturnOutcome.ignored, false)
      is LinkMatch.Malformed -> return finish(ReturnOutcome.invalid, false)
      is LinkMatch.Ready -> match
    }
    val parsed = parseToken(ready.state) ?: return finish(ReturnOutcome.invalid, false)
    if (now() >= parsed.exp) return finish(ReturnOutcome.expired, false)
    synchronized(lock) {
      if (parsed.nonce in consumed) return finish(ReturnOutcome.replayed, false)
      consumed.add(parsed.nonce)
    }
    if (parsed.session != expectedSession || parsed.paymentKey != expectedPaymentKey) {
      return finish(ReturnOutcome.invalid, false)
    }
    return finish(ReturnOutcome.accepted, true)
  }

  private fun parseToken(token: String): Claims? {
    val parts = token.split('.')
    if (parts.size != 2) return null
    val payloadBytes = Base64Url.decode(parts[0]) ?: return null
    val payload = payloadBytes.toString(Charsets.UTF_8)
    val provided = decodeHexMac(parts[1]) ?: return null
    val expected = hmacSha256(key, payload.toByteArray(Charsets.UTF_8))
    if (!constantTimeEquals(provided, expected)) return null
    return parsePayload(payload)
  }

  companion object {
    const val DEFAULT_TTL_SECONDS: Long = 300

    private val sessionPattern = Regex("^[A-Za-z0-9_-]{3,64}$")
    private val paymentKeyPattern = Regex("^[A-Za-z0-9_-]{1,100}$")
    private val payloadPattern = Regex(
      """\{"exp":(\d{1,12}),"nonce":"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})","paymentKey":"([A-Za-z0-9_-]{1,100})","session":"([A-Za-z0-9_-]{3,64})","v":1\}""",
    )

    internal fun canonical(exp: Long, nonce: String, paymentKey: String, session: String): String =
      """{"exp":$exp,"nonce":"$nonce","paymentKey":"$paymentKey","session":"$session","v":1}"""

    internal fun sign(key: ByteArray, payload: String): String {
      val mac = hmacSha256(key, payload.toByteArray(Charsets.UTF_8))
      return Base64Url.encode(payload.toByteArray(Charsets.UTF_8)) + "." + hex(mac)
    }

    internal fun hmacSha256(key: ByteArray, message: ByteArray): ByteArray {
      val mac = Mac.getInstance("HmacSHA256")
      mac.init(SecretKeySpec(key, "HmacSHA256"))
      return mac.doFinal(message)
    }

    private fun parsePayload(payload: String): Claims? {
      val match = payloadPattern.matchEntire(payload) ?: return null
      val expText = match.groupValues[1]
      val exp = expText.toLongOrNull() ?: return null
      if (exp <= 0 || exp.toString() != expText) return null
      return Claims(
        exp = exp,
        nonce = match.groupValues[2],
        paymentKey = match.groupValues[3],
        session = match.groupValues[4],
      )
    }

    private fun randomKey(): ByteArray {
      val bytes = ByteArray(32)
      SecureRandom().nextBytes(bytes)
      return bytes
    }
  }
}

private data class Claims(
  val exp: Long,
  val nonce: String,
  val paymentKey: String,
  val session: String,
)

internal object Base64Url {
  private const val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

  fun encode(data: ByteArray): String {
    val out = StringBuilder((data.size * 4 + 2) / 3)
    var i = 0
    while (i < data.size) {
      val b0 = data[i].toInt() and 0xFF
      val b1 = if (i + 1 < data.size) data[i + 1].toInt() and 0xFF else -1
      val b2 = if (i + 2 < data.size) data[i + 2].toInt() and 0xFF else -1
      out.append(alphabet[b0 shr 2])
      out.append(alphabet[((b0 and 0x03) shl 4) or (if (b1 >= 0) b1 shr 4 else 0)])
      if (b1 >= 0) {
        out.append(alphabet[((b1 and 0x0F) shl 2) or (if (b2 >= 0) b2 shr 6 else 0)])
      }
      if (b2 >= 0) out.append(alphabet[b2 and 0x3F])
      i += 3
    }
    return out.toString()
  }

  fun decode(text: String): ByteArray? {
    if (text.isEmpty() || text.length % 4 == 1) return null
    val table = IntArray(128) { -1 }
    alphabet.forEachIndexed { index, c -> table[c.code] = index }
    val out = ArrayList<Byte>(text.length * 3 / 4)
    var buffer = 0
    var bits = 0
    for (ch in text) {
      if (ch.code >= 128) return null
      val value = table[ch.code]
      if (value < 0) return null
      buffer = (buffer shl 6) or value
      bits += 6
      if (bits >= 8) {
        bits -= 8
        out.add(((buffer shr bits) and 0xFF).toByte())
      }
    }
    if (bits >= 6) return null
    return out.toByteArray()
  }
}

internal fun hex(data: ByteArray): String {
  val alphabet = "0123456789abcdef"
  val out = StringBuilder(data.size * 2)
  for (byte in data) {
    val value = byte.toInt() and 0xFF
    out.append(alphabet[value ushr 4])
    out.append(alphabet[value and 0x0F])
  }
  return out.toString()
}

internal fun decodeHexMac(text: String): ByteArray? {
  if (text.length != 64 || text.any { it !in '0'..'9' && it !in 'a'..'f' }) return null
  val out = ByteArray(32)
  for (i in 0 until 32) {
    val hi = text[i * 2].digitToInt(16)
    val lo = text[i * 2 + 1].digitToInt(16)
    out[i] = ((hi shl 4) or lo).toByte()
  }
  return out
}

internal fun constantTimeEquals(a: ByteArray, b: ByteArray): Boolean {
  if (a.size != b.size) return false
  var diff = 0
  for (i in a.indices) diff = diff or (a[i].toInt() xor b[i].toInt())
  return diff == 0
}
