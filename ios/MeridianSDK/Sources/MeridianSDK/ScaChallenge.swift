import Foundation

/// Local PSD2 step-up for a fictional rehearsal payment.
///
/// The Java API decides when Strong Customer Authentication applies and answers
/// `POST /payments` with HTTP 202 and `code: SCA_STEP_UP_REQUIRED`. This handler
/// extracts the challenge payload and expiration, then withholds `scaChallengeToken`
/// until Face ID, Touch ID, or the in-app passcode succeeds. The resubmit uses the
/// original idempotency key and the original Adyen card or Worldpay bank method.
/// Biometric samples and the passcode never leave the device.
public enum ScaStepUp {
  public static let code = "SCA_STEP_UP_REQUIRED"
  public static let biometricPrompt = "Confirm with Face ID / Fingerprint to authorize European payment"
  public static let failureMessage = "Authentication challenge failed. Please verify with your passcode."
}

public struct InFlightPayment: Equatable {
  public let recipientId: String
  public let amountMinor: Int
  public let method: PaymentMethod
  public let note: String
  public let scenario: Scenario
  public let idempotencyKey: String

  public init(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String,
    scenario: Scenario,
    idempotencyKey: String
  ) {
    self.recipientId = recipientId
    self.amountMinor = amountMinor
    self.method = method
    self.note = note
    self.scenario = scenario
    self.idempotencyKey = idempotencyKey
  }
}

public struct ScaChallenge: Equatable {
  public let payload: String
  public let expiresAt: Date
  public let scaChallengeToken: String
}

public struct ScaResubmission: Equatable {
  public let recipientId: String
  public let amountMinor: Int
  public let method: PaymentMethod
  public let note: String
  public let scenario: Scenario
  public let idempotencyKey: String
  public let scaChallengeToken: String
}

public enum ScaPhase: Equatable {
  case biometric(ScaChallenge)
  case passcode(ScaChallenge, message: String?)
  case ready(ScaChallenge)
  case failed(message: String)
}

public struct ScaChallengeHandler: Equatable {
  public let payment: InFlightPayment
  public let phase: ScaPhase

  public init(payment: InFlightPayment, phase: ScaPhase) {
    self.payment = payment
    self.phase = phase
  }

  /// Returns nil when the response is not an HTTP 202 step-up.
  /// An expired or incomplete challenge becomes `.failed` and does not resubmit.
  public static func begin(
    statusCode: Int,
    body: PaymentResponse,
    payment: InFlightPayment,
    now: Date = Date()
  ) -> ScaChallengeHandler? {
    guard statusCode == 202, body.code == ScaStepUp.code else { return nil }
    guard let challenge = extract(body), challenge.expiresAt > now else {
      return ScaChallengeHandler(payment: payment, phase: .failed(message: ScaStepUp.failureMessage))
    }
    return ScaChallengeHandler(payment: payment, phase: .biometric(challenge))
  }

  public func biometricUnavailableOrFailed(now: Date = Date()) -> ScaChallengeHandler {
    guard case let .biometric(challenge) = phase else { return self }
    if challenge.expiresAt <= now {
      return ScaChallengeHandler(payment: payment, phase: .failed(message: ScaStepUp.failureMessage))
    }
    return ScaChallengeHandler(payment: payment, phase: .passcode(challenge, message: nil))
  }

  public func biometricSucceeded(now: Date = Date()) -> ScaChallengeHandler {
    guard case let .biometric(challenge) = phase else { return self }
    if challenge.expiresAt <= now {
      return ScaChallengeHandler(payment: payment, phase: .failed(message: ScaStepUp.failureMessage))
    }
    return ScaChallengeHandler(payment: payment, phase: .ready(challenge))
  }

  public func passcodeVerified(now: Date = Date()) -> ScaChallengeHandler {
    guard case let .passcode(challenge, _) = phase else { return self }
    if challenge.expiresAt <= now {
      return ScaChallengeHandler(payment: payment, phase: .failed(message: ScaStepUp.failureMessage))
    }
    return ScaChallengeHandler(payment: payment, phase: .ready(challenge))
  }

  public func passcodeRejected(now: Date = Date()) -> ScaChallengeHandler {
    guard case let .passcode(challenge, _) = phase else { return self }
    if challenge.expiresAt <= now {
      return ScaChallengeHandler(payment: payment, phase: .failed(message: ScaStepUp.failureMessage))
    }
    return ScaChallengeHandler(
      payment: payment,
      phase: .passcode(challenge, message: ScaStepUp.failureMessage)
    )
  }

  /// Token is released only after biometric or passcode success, on the original key and method.
  public func resubmission() -> ScaResubmission? {
    guard case let .ready(challenge) = phase else { return nil }
    return ScaResubmission(
      recipientId: payment.recipientId,
      amountMinor: payment.amountMinor,
      method: payment.method,
      note: payment.note,
      scenario: payment.scenario,
      idempotencyKey: payment.idempotencyKey,
      scaChallengeToken: challenge.scaChallengeToken
    )
  }
}

public enum RehearsalPasscode {
  public static func isWellFormed(_ value: String) -> Bool {
    value.count == 6 && value.allSatisfy(\.isNumber)
  }

  /// Local comparison only. The passcode is not part of the payment body.
  public static func matches(entered: String, enrolled: String) -> Bool {
    guard isWellFormed(entered), isWellFormed(enrolled) else { return false }
    var diff: UInt8 = 0
    for (left, right) in zip(entered.utf8, enrolled.utf8) {
      diff |= left ^ right
    }
    return diff == 0
  }
}

func parseScaTimestamp(_ raw: String) -> Date? {
  let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = formatter.date(from: value) { return date }
  formatter.formatOptions = [.withInternetDateTime]
  return formatter.date(from: value)
}

private func extract(_ body: PaymentResponse) -> ScaChallenge? {
  let nested = body.challenge
  let payload = firstText(nested?.payload, body.challengePayload)
  let expiresRaw = firstText(
    nested?.expiresAt,
    nested?.expirationTimestamp,
    nested?.expiration,
    body.expiresAt,
    body.expirationTimestamp,
    body.expiration
  )
  let token = firstText(nested?.scaChallengeToken, nested?.token, body.scaChallengeToken)
  guard let payload, let expiresRaw, let token, let expiresAt = parseScaTimestamp(expiresRaw) else {
    return nil
  }
  return ScaChallenge(payload: payload, expiresAt: expiresAt, scaChallengeToken: token)
}

private func firstText(_ values: String?...) -> String? {
  for value in values {
    if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
      return trimmed
    }
  }
  return nil
}
