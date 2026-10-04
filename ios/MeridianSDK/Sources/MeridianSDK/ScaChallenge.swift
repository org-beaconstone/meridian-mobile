import Foundation

public enum ScaMethod: String, Equatable {
  case biometric
  case passcode
}

public enum ScaStatus: Equatable {
  case required
  case passcodeFallback
  case passed(ScaMethod)
  case failed
  case timedOut
}

/// In-process SCA rehearsal. No biometric hardware, customer secret, or provider call is used.
public struct ScaChallenge: Equatable {
  public let id: String
  public let paymentKey: String
  public let method: PaymentMethod
  public let provider: ProviderId
  public let timeoutSteps: Int
  public private(set) var status: ScaStatus
  private var elapsed: Int

  public init(id: String, paymentKey: String, method: PaymentMethod, timeoutSteps: Int = 3) {
    self.id = id
    self.paymentKey = paymentKey
    self.method = method
    self.provider = providerFor(method: method)
    self.timeoutSteps = timeoutSteps
    self.status = .required
    self.elapsed = 0
  }

  public func rehearsalPasscode() -> String {
    ScaChallenge.passcodeFor(challengeId: id)
  }

  public static func passcodeFor(challengeId: String) -> String {
    var accumulator = 0
    for character in challengeId.unicodeScalars {
      accumulator = (accumulator * 33 + Int(character.value)) % 1_000_000
    }
    return String(format: "%06d", accumulator)
  }

  public mutating func advance() {
    elapsed += 1
    expireIfNeeded()
  }

  public mutating func submitBiometric(matched: Bool) {
    if expireIfNeeded() { return }
    guard status == .required else { return }
    status = matched ? .passed(.biometric) : .passcodeFallback
  }

  public mutating func submitPasscode(_ code: String) {
    if expireIfNeeded() { return }
    guard status == .passcodeFallback else { return }
    status = code == rehearsalPasscode() ? .passed(.passcode) : .failed
  }

  @discardableResult
  private mutating func expireIfNeeded() -> Bool {
    if status == .timedOut { return true }
    if elapsed >= timeoutSteps && (status == .required || status == .passcodeFallback) {
      status = .timedOut
      return true
    }
    return false
  }
}

public func assertSimulatedScaFlows() throws {
  var biometric = ScaChallenge(id: "sca-biometric-pass", paymentKey: "pay-biometric", method: .card)
  biometric.submitBiometric(matched: true)
  if biometric.status != .passed(.biometric) || biometric.provider != .adyen || biometric.paymentKey != "pay-biometric" {
    throw MeridianError.validationError("Biometric pass did not stay on Adyen")
  }

  var fallback = ScaChallenge(id: "sca-passcode-fallback", paymentKey: "pay-fallback", method: .bank)
  fallback.submitBiometric(matched: false)
  if fallback.status != .passcodeFallback || fallback.provider != .worldpay {
    throw MeridianError.validationError("Biometric failure did not fall back to passcode")
  }
  fallback.submitPasscode("000000")
  if fallback.status != .failed || fallback.provider != .worldpay {
    throw MeridianError.validationError("Wrong passcode must fail without switching provider")
  }
  var fallbackOk = ScaChallenge(id: "sca-passcode-fallback", paymentKey: "pay-fallback", method: .bank)
  fallbackOk.submitBiometric(matched: false)
  fallbackOk.submitPasscode(fallbackOk.rehearsalPasscode())
  if fallbackOk.status != .passed(.passcode) || fallbackOk.provider != .worldpay || fallbackOk.paymentKey != "pay-fallback" {
    throw MeridianError.validationError("Passcode fallback did not stay on Worldpay")
  }

  var timed = ScaChallenge(id: "sca-timeout", paymentKey: "pay-timeout", method: .card, timeoutSteps: 2)
  timed.advance()
  timed.advance()
  if timed.status != .timedOut || timed.provider != .adyen || timed.paymentKey != "pay-timeout" {
    throw MeridianError.validationError("Timeout changed the card provider or payment key")
  }
  timed.submitBiometric(matched: true)
  if timed.status != .timedOut || timed.provider != .adyen {
    throw MeridianError.validationError("Timed-out biometric was accepted")
  }

  var expiredFallback = ScaChallenge(id: "sca-timeout-fallback", paymentKey: "pay-timeout-fallback", method: .bank, timeoutSteps: 2)
  expiredFallback.submitBiometric(matched: false)
  expiredFallback.advance()
  expiredFallback.advance()
  expiredFallback.submitPasscode(expiredFallback.rehearsalPasscode())
  if expiredFallback.status != .timedOut || expiredFallback.provider != .worldpay {
    throw MeridianError.validationError("Timed-out passcode fallback switched provider")
  }
}
