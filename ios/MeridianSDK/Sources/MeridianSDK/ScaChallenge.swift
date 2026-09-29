import Foundation

/// PSD2 Strong Customer Authentication for a European payment.
/// The rehearsal passcode is compared on device and is never sent to the API or a provider.
public enum ScaCopy {
  public static let stepUpCode = "SCA_STEP_UP_REQUIRED"
  public static let biometricPrompt = "Confirm with Face ID / Fingerprint to authorize European payment"
  public static let failureMessage = "Authentication challenge failed. Please verify with your passcode."
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
  /// Gateway token echoed after local verification. Nil when the payload itself is the token.
  public let token: String?

  public init(payload: String, expiresAt: Date, token: String? = nil) {
    self.payload = payload
    self.expiresAt = expiresAt
    self.token = token
  }

  public var resubmitToken: String {
    if let token, !token.isEmpty { return token }
    return payload
  }

  public func isExpired(at now: Date = Date()) -> Bool {
    now >= expiresAt
  }
}

public enum ScaIntercept: Equatable {
  case notStepUp
  case invalid
  case expired(ScaChallenge)
  case required(ScaChallenge)
}

public enum ScaInterpreter {
  /// HTTP 202 with `SCA_STEP_UP_REQUIRED` is the only step-up signal.
  /// Pending payments use the same status with a different code and stay on the normal path.
  public static func intercept(statusCode: Int, body: Data, now: Date = Date()) -> ScaIntercept {
    guard statusCode == 202,
      let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
      (object["code"] as? String) == ScaCopy.stepUpCode
    else { return .notStepUp }
    guard let challenge = ScaChallenge.extract(from: object) else { return .invalid }
    if challenge.isExpired(at: now) { return .expired(challenge) }
    return .required(challenge)
  }
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
  public private(set) var token: String?
  public private(set) var message: String?

  public init(draft: PaymentDraft, challenge: ScaChallenge, now: Date = Date()) {
    self.draft = draft
    self.challenge = challenge
    if challenge.isExpired(at: now) {
      self.phase = .failed
      self.token = nil
      self.message = ScaCopy.failureMessage
    } else {
      self.phase = .biometric
      self.token = nil
      self.message = nil
    }
  }

  public var showsPasscode: Bool {
    phase == .passcode || phase == .failed
  }

  /// Values for the original payment, plus the token, after verification.
  public func resubmit() -> (
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String,
    scenario: Scenario,
    idempotencyKey: String,
    scaChallengeToken: String
  )? {
    guard phase == .ready, let token, !token.isEmpty else { return nil }
    return (
      draft.recipientId,
      draft.amountMinor,
      draft.method,
      draft.note,
      draft.scenario,
      draft.idempotencyKey,
      token
    )
  }

  public mutating func completeBiometric(_ status: BiometricStatus, now: Date = Date()) {
    guard phase == .biometric else { return }
    if challenge.isExpired(at: now) {
      fail()
      return
    }
    if status == .success {
      phase = .ready
      token = challenge.resubmitToken
      message = nil
    } else {
      phase = .passcode
      token = nil
      message = nil
    }
  }

  public mutating func submitPasscode(
    _ entered: String,
    now: Date = Date(),
    expected: String = ScaCopy.rehearsalPasscode
  ) {
    guard phase == .passcode || phase == .failed else { return }
    if challenge.isExpired(at: now) {
      fail()
      return
    }
    if ScaPasscode.matches(entered, expected: expected) {
      phase = .ready
      token = challenge.resubmitToken
      message = nil
    } else {
      fail()
    }
  }

  private mutating func fail() {
    phase = .failed
    token = nil
    message = ScaCopy.failureMessage
  }
}

enum ScaPasscode {
  static func matches(_ entered: String, expected: String) -> Bool {
    let given = Array(entered.utf8)
    let wanted = Array(expected.utf8)
    guard given.count == wanted.count, !wanted.isEmpty else { return false }
    var diff: UInt8 = 0
    for index in wanted.indices {
      diff |= given[index] ^ wanted[index]
    }
    return diff == 0
  }
}

extension ScaChallenge {
  static func extract(from object: [String: Any]) -> ScaChallenge? {
    let nested = dictionary(object["challenge"]) ?? dictionary(object["scaChallenge"])
    let payload = string(nested, keys: ["payload", "challengePayload"])
      ?? string(object, keys: ["challengePayload", "payload"])
      ?? textual(object["challenge"])
    let expiry = value(nested, keys: ["expiresAt", "expirationTimestamp", "expiration", "expiry"])
      ?? value(object, keys: ["expiresAt", "expirationTimestamp", "expiration", "expiry"])
    guard let payload, let expiresAt = ScaTime.parse(expiry) else { return nil }
    let token = string(nested, keys: ["scaChallengeToken", "token"])
      ?? string(object, keys: ["scaChallengeToken", "token"])
    return ScaChallenge(payload: payload, expiresAt: expiresAt, token: token)
  }

  private static func dictionary(_ value: Any?) -> [String: Any]? {
    value as? [String: Any]
  }

  private static func textual(_ value: Any?) -> String? {
    guard let text = value as? String else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func string(_ object: [String: Any]?, keys: [String]) -> String? {
    guard let object else { return nil }
    for key in keys {
      if let text = textual(object[key]) { return text }
    }
    return nil
  }

  private static func value(_ object: [String: Any]?, keys: [String]) -> Any? {
    guard let object else { return nil }
    for key in keys where object[key] != nil { return object[key] }
    return nil
  }
}

enum ScaTime {
  static func parse(_ value: Any?) -> Date? {
    if let text = value as? String {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractional.date(from: trimmed) { return date }
      let basic = ISO8601DateFormatter()
      basic.formatOptions = [.withInternetDateTime]
      return basic.date(from: trimmed)
    }
    if let number = value as? NSNumber, !(value is Bool) {
      let raw = number.doubleValue
      guard raw.isFinite, raw > 0 else { return nil }
      if raw > 10_000_000_000 { return Date(timeIntervalSince1970: raw / 1000) }
      return Date(timeIntervalSince1970: raw)
    }
    return nil
  }
}
