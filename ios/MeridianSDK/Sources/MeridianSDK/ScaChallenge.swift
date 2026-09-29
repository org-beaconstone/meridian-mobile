import Foundation

/// Local PSD2 step-up for a fictional rehearsal payment.
///
/// The Java API decides when Strong Customer Authentication applies and answers
/// `POST /payments` with HTTP 202 and `code: SCA_STEP_UP_REQUIRED`. This handler
/// keeps the original recipient, amount, method, and idempotency key, and it
/// withholds `scaChallengeToken` until Face ID, Touch ID, or the in-app passcode
/// succeeds. Biometric samples and the passcode never leave the device.
public enum ScaCopy {
  public static let stepUpCode = "SCA_STEP_UP_REQUIRED"
  public static let biometricPrompt = "Confirm with Face ID / Fingerprint to authorize European payment"
  public static let failureMessage = "Authentication challenge failed. Please verify with your passcode."
  /// Fictional rehearsal passcode. Compared on device only.
  public static let rehearsalPasscode = "135790"
}

public enum BiometricStatus: Equatable {
  case success
  case failed
  case unavailable
  case cancelled
}

public struct PaymentDraft: Equatable {
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
  public let token: String?

  public init(payload: String, expiresAt: Date, token: String? = nil) {
    self.payload = payload
    self.expiresAt = expiresAt
    self.token = token
  }

  public func isExpired(at now: Date = Date()) -> Bool {
    now >= expiresAt
  }

  /// Explicit gateway token when present; otherwise the challenge payload is echoed back.
  public var tokenForResubmit: String {
    if let token, !token.isEmpty { return token }
    return payload
  }
}

public enum ScaIntercept: Equatable {
  case notStepUp
  case invalid
  case expired(ScaChallenge)
  case required(ScaChallenge)
}

public enum ScaPhase: Equatable {
  case biometric
  case passcode
  case ready
  case failed
}

public struct ScaSession: Equatable {
  public let draft: PaymentDraft
  public let challenge: ScaChallenge
  public private(set) var phase: ScaPhase
  public private(set) var message: String?

  public init(draft: PaymentDraft, challenge: ScaChallenge, now: Date = Date()) {
    self.draft = draft
    self.challenge = challenge
    if challenge.isExpired(at: now) {
      self.phase = .failed
      self.message = ScaCopy.failureMessage
    } else {
      self.phase = .biometric
      self.message = nil
    }
  }

  public var resubmitToken: String? {
    guard phase == .ready else { return nil }
    return challenge.tokenForResubmit
  }

  public var showsPasscode: Bool {
    phase == .passcode || phase == .failed
  }

  public func afterBiometric(_ status: BiometricStatus, now: Date = Date()) -> ScaSession {
    guard phase == .biometric else { return self }
    var copy = self
    if challenge.isExpired(at: now) {
      copy.phase = .failed
      copy.message = ScaCopy.failureMessage
      return copy
    }
    if status == .success {
      copy.phase = .ready
      copy.message = nil
    } else {
      copy.phase = .passcode
      copy.message = nil
    }
    return copy
  }

  public func afterPasscode(_ entered: String, now: Date = Date()) -> ScaSession {
    guard phase == .passcode || phase == .failed else { return self }
    var copy = self
    if challenge.isExpired(at: now) {
      copy.phase = .failed
      copy.message = ScaCopy.failureMessage
      return copy
    }
    if RehearsalPasscode.matches(entered) {
      copy.phase = .ready
      copy.message = nil
    } else {
      copy.phase = .failed
      copy.message = ScaCopy.failureMessage
    }
    return copy
  }
}

public enum RehearsalPasscode {
  public static func matches(_ entered: String, expected: String = ScaCopy.rehearsalPasscode) -> Bool {
    guard entered.count == 6, expected.count == 6, entered.allSatisfy(\.isNumber) else { return false }
    var diff: UInt8 = 0
    for (left, right) in zip(entered.utf8, expected.utf8) {
      diff |= left ^ right
    }
    return diff == 0
  }
}

public enum ScaInterpreter {
  /// HTTP 202 plus `SCA_STEP_UP_REQUIRED` is the only step-up signal.
  /// `PAYMENT_PENDING` stays a normal pending result.
  public static func intercept(statusCode: Int, body: Data, now: Date = Date()) -> ScaIntercept {
    guard statusCode == 202,
      let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
      (object["code"] as? String) == ScaCopy.stepUpCode
    else { return .notStepUp }
    guard let challenge = extract(object) else { return .invalid }
    if challenge.isExpired(at: now) { return .expired(challenge) }
    return .required(challenge)
  }
}

private func extract(_ object: [String: Any]) -> ScaChallenge? {
  let nested = (object["challenge"] as? [String: Any]) ?? (object["scaChallenge"] as? [String: Any])
  let payload = firstString(nested, keys: ["payload", "challengePayload"])
    ?? firstString(object, keys: ["challengePayload", "payload"])
  let expiryValue = firstValue(nested, keys: ["expiresAt", "expiration", "expirationTimestamp", "expiry"])
    ?? firstValue(object, keys: ["expiresAt", "expiration", "expirationTimestamp", "expiry"])
  guard let payload, let expiresAt = ScaTime.parse(expiryValue) else { return nil }
  let token = firstString(nested, keys: ["scaChallengeToken", "token"])
    ?? firstString(object, keys: ["scaChallengeToken", "token"])
  return ScaChallenge(payload: payload, expiresAt: expiresAt, token: token)
}

private func firstString(_ object: [String: Any]?, keys: [String]) -> String? {
  guard let object else { return nil }
  for key in keys {
    if let text = object[key] as? String {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }
  }
  return nil
}

private func firstValue(_ object: [String: Any]?, keys: [String]) -> Any? {
  guard let object else { return nil }
  for key in keys where object[key] != nil {
    return object[key]
  }
  return nil
}

enum ScaTime {
  static func parse(_ value: Any?) -> Date? {
    if value is Bool { return nil }
    if let text = value as? String {
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractional.date(from: text) { return date }
      let basic = ISO8601DateFormatter()
      basic.formatOptions = [.withInternetDateTime]
      return basic.date(from: text)
    }
    if let number = value as? NSNumber {
      let raw = number.doubleValue
      if raw > 10_000_000_000 { return Date(timeIntervalSince1970: raw / 1000) }
      return Date(timeIntervalSince1970: raw)
    }
    return nil
  }
}
