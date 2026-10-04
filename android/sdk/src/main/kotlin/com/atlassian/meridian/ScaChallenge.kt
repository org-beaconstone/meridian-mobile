package com.atlassian.meridian

import java.security.MessageDigest
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlin.random.Random

/**
 * In-app PSD2 strong customer authentication for the rehearsal.
 * Possession is the in-app device binding. The second factor is inherence
 * (biometrics) or knowledge (the security passcode). The signed
 * scaChallengeToken never includes the passcode and is not a provider credential.
 */
enum class ScaFactor { possession, knowledge, inherence }

enum class BiometricOutcome { succeeded, rejected, bypassed, unavailable }

enum class ScaPhase { Biometric, Passcode, Verified }

data class ScaPaymentBinding(
  val recipientId: String,
  val amountMinor: Int,
  val method: PaymentMethod,
  val idempotencyKey: String,
)

data class ScaVerification(
  val scaChallengeToken: String,
  val factors: List<ScaFactor>,
  val biometric: BiometricOutcome,
)

data class ScaSnapshot(
  val phase: ScaPhase,
  val rejectionBanner: String?,
  val biometric: BiometricOutcome?,
  val maskedPasscode: String,
  val enteredCount: Int,
  val failures: Int,
  val secondsLocked: Long,
  val passcodeMessage: String?,
  val verification: ScaVerification?,
)

object ScaChallenge {
  const val REJECTION_BANNER = "Authentication challenge failed. Please verify with your passcode."
  const val BIOMETRICS_UNAVAILABLE_NOTE = "Biometrics are unavailable on this device."
  const val INCORRECT_PASSCODE = "Incorrect passcode."
  const val TOO_MANY_ATTEMPTS = "Too many attempts. Try again shortly."
  const val PIN_LENGTH = 6
  const val MAX_ATTEMPTS = 5
  const val LOCKOUT_SECONDS = 30L
  /** Fictional rehearsal knowledge factor. It is never sent to the API or a provider. */
  const val REHEARSAL_PIN = "135790"
  const val IN_APP_BINDING = "meridian-in-app"
  const val SALT = "meridian-sca-rehearsal-salt-v1"
  const val DEVICE_KEY_MATERIAL = "meridian-sca-rehearsal-device-v1"
}

class ScaSigner(private val key: ByteArray) {
  fun sign(
    binding: ScaPaymentBinding,
    factors: List<ScaFactor>,
    biometric: BiometricOutcome,
    challengeId: String,
    issuedAtEpoch: Long,
    nonce: String,
  ): String? {
    val canonical = canonical(binding, factors, biometric, challengeId, issuedAtEpoch, nonce) ?: return null
    val payload = canonical.toByteArray(Charsets.UTF_8)
    return base64Url(payload) + "." + base64Url(hmacSha256(key, payload))
  }

  fun authenticatedPayload(token: String): String? {
    val parts = token.split('.', limit = 2)
    if (parts.size != 2) return null
    val payload = decodeBase64Url(parts[0]) ?: return null
    val provided = decodeBase64Url(parts[1]) ?: return null
    if (!constantTimeEquals(hmacSha256(key, payload), provided)) return null
    return payload.toString(Charsets.UTF_8)
  }

  fun verify(token: String, binding: ScaPaymentBinding): Boolean {
    val payload = authenticatedPayload(token) ?: return false
    val lines = payload.lines()
    if (lines.size != 11 || lines[0] != "v1") return false
    if (lines[1].isEmpty() || lines[9].isEmpty()) return false
    val factors = lines[2].split('+').toSet()
    val secondFactor = factors.contains(ScaFactor.knowledge.name) || factors.contains(ScaFactor.inherence.name)
    if (!factors.contains(ScaFactor.possession.name) || !secondFactor) return false
    if (BiometricOutcome.values().none { it.name == lines[3] }) return false
    return lines[4] == binding.amountMinor.toString() &&
      lines[5] == binding.recipientId &&
      lines[6] == binding.method.name &&
      lines[7] == binding.idempotencyKey &&
      lines[10] == ScaChallenge.IN_APP_BINDING
  }

  private fun canonical(
    binding: ScaPaymentBinding,
    factors: List<ScaFactor>,
    biometric: BiometricOutcome,
    challengeId: String,
    issuedAtEpoch: Long,
    nonce: String,
  ): String? {
    val fields = listOf(challengeId, binding.recipientId, binding.method.name, binding.idempotencyKey, nonce)
    if (fields.any { it.isEmpty() || it.contains('\n') || it.contains('\r') }) return null
    if (binding.amountMinor <= 0 || factors.isEmpty()) return null
    val factorList = factors.map { it.name }.sorted().joinToString("+")
    return listOf(
      "v1",
      challengeId,
      factorList,
      biometric.name,
      binding.amountMinor.toString(),
      binding.recipientId,
      binding.method.name,
      binding.idempotencyKey,
      issuedAtEpoch.toString(),
      nonce,
      ScaChallenge.IN_APP_BINDING,
    ).joinToString("\n")
  }

  companion object {
    fun rehearsal(): ScaSigner =
      ScaSigner(sha256(ScaChallenge.DEVICE_KEY_MATERIAL.toByteArray(Charsets.UTF_8)))

    fun randomNonce(): String {
      val bytes = Random.Default.nextBytes(16)
      return bytes.joinToString("") { "%02x".format(it) }
    }
  }
}

class ScaChallengeEngine(
  val binding: ScaPaymentBinding,
  private val signer: ScaSigner = ScaSigner.rehearsal(),
  private val challengeId: String = UUID.randomUUID().toString(),
  private val nonceProvider: () -> String = { ScaSigner.randomNonce() },
) {
  var phase: ScaPhase = ScaPhase.Biometric
    private set
  var rejectionBanner: String? = null
    private set
  var biometric: BiometricOutcome? = null
    private set
  var enteredCount: Int = 0
    private set
  var failures: Int = 0
    private set
  var lockedUntilEpoch: Long? = null
    private set
  var passcodeMessage: String? = null
    private set
  var verification: ScaVerification? = null
    private set

  private var entered: String = ""
  private val expectedHash: ByteArray = hashPin(ScaChallenge.REHEARSAL_PIN)

  fun maskedPasscode(): String {
    val filled = enteredCount.coerceAtMost(ScaChallenge.PIN_LENGTH)
    return "•".repeat(filled) + "○".repeat(ScaChallenge.PIN_LENGTH - filled)
  }

  fun secondsLocked(nowEpoch: Long): Long {
    val until = lockedUntilEpoch ?: return 0
    val remaining = until - nowEpoch
    return if (remaining <= 0) 0 else remaining
  }

  fun snapshot(nowEpoch: Long): ScaSnapshot = ScaSnapshot(
    phase = phase,
    rejectionBanner = rejectionBanner,
    biometric = biometric,
    maskedPasscode = maskedPasscode(),
    enteredCount = enteredCount,
    failures = failures,
    secondsLocked = secondsLocked(nowEpoch),
    passcodeMessage = passcodeMessage,
    verification = verification,
  )

  fun rejectBiometrics(nowEpoch: Long): ScaSnapshot {
    if (phase == ScaPhase.Biometric) {
      biometric = BiometricOutcome.rejected
      rejectionBanner = ScaChallenge.REJECTION_BANNER
      phase = ScaPhase.Passcode
      clearEntry()
    }
    return snapshot(nowEpoch)
  }

  fun bypassBiometrics(nowEpoch: Long): ScaSnapshot {
    if (phase == ScaPhase.Biometric) {
      biometric = BiometricOutcome.bypassed
      rejectionBanner = null
      phase = ScaPhase.Passcode
      clearEntry()
    }
    return snapshot(nowEpoch)
  }

  fun markBiometricsUnavailable(nowEpoch: Long): ScaSnapshot {
    if (phase == ScaPhase.Biometric) {
      biometric = BiometricOutcome.unavailable
      rejectionBanner = null
      phase = ScaPhase.Passcode
      clearEntry()
    }
    return snapshot(nowEpoch)
  }

  fun succeedBiometrics(nowEpoch: Long): ScaSnapshot {
    if (phase == ScaPhase.Biometric) {
      biometric = BiometricOutcome.succeeded
      issue(listOf(ScaFactor.possession, ScaFactor.inherence), BiometricOutcome.succeeded, nowEpoch)
    }
    return snapshot(nowEpoch)
  }

  fun appendDigit(digit: Int, nowEpoch: Long): ScaSnapshot {
    if (phase != ScaPhase.Passcode || digit !in 0..9) return snapshot(nowEpoch)
    val locked = lockedUntilEpoch
    if (locked != null && nowEpoch < locked) {
      passcodeMessage = ScaChallenge.TOO_MANY_ATTEMPTS
      return snapshot(nowEpoch)
    }
    if (locked != null) {
      lockedUntilEpoch = null
      failures = 0
      passcodeMessage = null
    }
    entered += digit.toString()
    enteredCount = entered.length
    if (entered.length < ScaChallenge.PIN_LENGTH) {
      passcodeMessage = null
      return snapshot(nowEpoch)
    }
    val attempt = entered
    clearEntry()
    if (matches(attempt)) {
      val outcome = biometric ?: BiometricOutcome.bypassed
      issue(listOf(ScaFactor.possession, ScaFactor.knowledge), outcome, nowEpoch)
      return snapshot(nowEpoch)
    }
    failures += 1
    if (failures >= ScaChallenge.MAX_ATTEMPTS) {
      lockedUntilEpoch = nowEpoch + ScaChallenge.LOCKOUT_SECONDS
      passcodeMessage = ScaChallenge.TOO_MANY_ATTEMPTS
    } else {
      passcodeMessage = ScaChallenge.INCORRECT_PASSCODE
    }
    return snapshot(nowEpoch)
  }

  fun deleteDigit(nowEpoch: Long): ScaSnapshot {
    if (phase == ScaPhase.Passcode && lockedUntilEpoch == null && entered.isNotEmpty()) {
      entered = entered.dropLast(1)
      enteredCount = entered.length
    }
    return snapshot(nowEpoch)
  }

  override fun toString(): String =
    "ScaChallengeEngine(phase=$phase, failures=$failures, entered=$enteredCount)"

  private fun clearEntry() {
    entered = ""
    enteredCount = 0
  }

  private fun matches(pin: String): Boolean {
    if (pin.length != ScaChallenge.PIN_LENGTH || pin.any { !it.isDigit() }) return false
    return constantTimeEquals(hashPin(pin), expectedHash)
  }

  private fun issue(factors: List<ScaFactor>, outcome: BiometricOutcome, nowEpoch: Long) {
    val token = signer.sign(binding, factors, outcome, challengeId, nowEpoch, nonceProvider()) ?: return
    verification = ScaVerification(
      scaChallengeToken = token,
      factors = factors.sortedBy { it.name },
      biometric = outcome,
    )
    phase = ScaPhase.Verified
    rejectionBanner = null
    passcodeMessage = null
    lockedUntilEpoch = null
    clearEntry()
  }
}

internal fun sha256(data: ByteArray): ByteArray =
  MessageDigest.getInstance("SHA-256").digest(data)

internal fun hmacSha256(key: ByteArray, message: ByteArray): ByteArray {
  val mac = Mac.getInstance("HmacSHA256")
  mac.init(SecretKeySpec(key, "HmacSHA256"))
  return mac.doFinal(message)
}

internal fun hashPin(pin: String): ByteArray =
  sha256((ScaChallenge.SALT + "\n" + pin).toByteArray(Charsets.UTF_8))

internal fun constantTimeEquals(lhs: ByteArray, rhs: ByteArray): Boolean {
  if (lhs.size != rhs.size) return false
  var diff = 0
  for (index in lhs.indices) {
    diff = diff or (lhs[index].toInt() xor rhs[index].toInt())
  }
  return diff == 0
}

private const val BASE64_URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

internal fun base64Url(data: ByteArray): String {
  val out = StringBuilder((data.size + 2) / 3 * 4)
  var index = 0
  while (index < data.size) {
    val b0 = data[index].toInt() and 0xFF
    val b1 = if (index + 1 < data.size) data[index + 1].toInt() and 0xFF else 0
    val b2 = if (index + 2 < data.size) data[index + 2].toInt() and 0xFF else 0
    out.append(BASE64_URL[b0 shr 2])
    out.append(BASE64_URL[((b0 and 0x03) shl 4) or (b1 shr 4)])
    if (index + 1 < data.size) out.append(BASE64_URL[((b1 and 0x0F) shl 2) or (b2 shr 6)])
    if (index + 2 < data.size) out.append(BASE64_URL[b2 and 0x3F])
    index += 3
  }
  return out.toString()
}

internal fun decodeBase64Url(value: String): ByteArray? {
  val map = IntArray(128) { -1 }
  BASE64_URL.forEachIndexed { index, char -> map[char.code] = index }
  map['+'.code] = map['-'.code]
  map['/'.code] = map['_'.code]
  val cleaned = value.trimEnd('=')
  if (cleaned.isEmpty() && value.isNotEmpty()) return ByteArray(0)
  if (cleaned.any { it.code >= 128 || map[it.code] < 0 }) return null
  val out = ArrayList<Byte>(cleaned.length * 3 / 4)
  var buffer = 0
  var bits = 0
  for (char in cleaned) {
    buffer = (buffer shl 6) or map[char.code]
    bits += 6
    if (bits >= 8) {
      bits -= 8
      out.add(((buffer shr bits) and 0xFF).toByte())
    }
  }
  return out.toByteArray()
}
