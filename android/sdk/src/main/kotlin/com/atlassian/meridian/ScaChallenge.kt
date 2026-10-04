package com.atlassian.meridian

enum class ScaMethod { biometric, passcode }

sealed class ScaStatus {
  data object Required : ScaStatus()
  data object PasscodeFallback : ScaStatus()
  data class Passed(val method: ScaMethod) : ScaStatus()
  data object Failed : ScaStatus()
  data object TimedOut : ScaStatus()
}

/**
 * In-process SCA rehearsal. Biometric and passcode results are simulated.
 * Nothing is sent to a provider and no customer credential is stored.
 */
class ScaChallenge(
  val id: String,
  val paymentKey: String,
  val method: PaymentMethod,
  val timeoutSteps: Int = 3,
) {
  val provider: ProviderId = providerFor(method)
  var status: ScaStatus = ScaStatus.Required
    private set
  private var elapsed = 0

  fun rehearsalPasscode(): String = passcodeFor(id)

  fun advance() {
    elapsed += 1
    expireIfNeeded()
  }

  fun submitBiometric(matched: Boolean) {
    if (expireIfNeeded()) return
    if (status !is ScaStatus.Required) return
    status = if (matched) ScaStatus.Passed(ScaMethod.biometric) else ScaStatus.PasscodeFallback
  }

  fun submitPasscode(code: String) {
    if (expireIfNeeded()) return
    if (status !is ScaStatus.PasscodeFallback) return
    status = if (code == rehearsalPasscode()) ScaStatus.Passed(ScaMethod.passcode) else ScaStatus.Failed
  }

  private fun expireIfNeeded(): Boolean {
    if (status is ScaStatus.TimedOut) return true
    if (elapsed >= timeoutSteps && (status is ScaStatus.Required || status is ScaStatus.PasscodeFallback)) {
      status = ScaStatus.TimedOut
      return true
    }
    return false
  }

  companion object {
    fun passcodeFor(challengeId: String): String {
      var accumulator = 0
      for (character in challengeId) {
        accumulator = (accumulator * 33 + character.code) % 1_000_000
      }
      return "%06d".format(accumulator)
    }
  }
}

fun assertSimulatedScaFlows() {
  val biometric = ScaChallenge("sca-biometric-pass", "pay-biometric", PaymentMethod.card)
  biometric.submitBiometric(true)
  check(biometric.status == ScaStatus.Passed(ScaMethod.biometric))
  check(biometric.provider == ProviderId.adyen)
  check(biometric.paymentKey == "pay-biometric")

  val wrong = ScaChallenge("sca-passcode-fallback", "pay-fallback", PaymentMethod.bank)
  wrong.submitBiometric(false)
  check(wrong.status is ScaStatus.PasscodeFallback)
  check(wrong.provider == ProviderId.worldpay)
  wrong.submitPasscode("000000")
  check(wrong.status is ScaStatus.Failed)
  check(wrong.provider == ProviderId.worldpay)

  val fallback = ScaChallenge("sca-passcode-fallback", "pay-fallback", PaymentMethod.bank)
  fallback.submitBiometric(false)
  fallback.submitPasscode(fallback.rehearsalPasscode())
  check(fallback.status == ScaStatus.Passed(ScaMethod.passcode))
  check(fallback.provider == ProviderId.worldpay)
  check(fallback.paymentKey == "pay-fallback")

  val timed = ScaChallenge("sca-timeout", "pay-timeout", PaymentMethod.card, timeoutSteps = 2)
  timed.advance()
  timed.advance()
  check(timed.status is ScaStatus.TimedOut)
  check(timed.provider == ProviderId.adyen)
  check(timed.paymentKey == "pay-timeout")
  timed.submitBiometric(true)
  check(timed.status is ScaStatus.TimedOut)
  check(timed.provider == ProviderId.adyen)

  val expiredFallback = ScaChallenge("sca-timeout-fallback", "pay-timeout-fallback", PaymentMethod.bank, timeoutSteps = 2)
  expiredFallback.submitBiometric(false)
  expiredFallback.advance()
  expiredFallback.advance()
  expiredFallback.submitPasscode(expiredFallback.rehearsalPasscode())
  check(expiredFallback.status is ScaStatus.TimedOut)
  check(expiredFallback.provider == ProviderId.worldpay)
}
