import Foundation

/// PSD2 Strong Customer Authentication copy and the fictional in-app passcode.
/// The passcode is checked on device only and is never sent to the API or a provider.
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

public protocol BiometricAuthenticating: Sendable {
  func authenticate(reason: String) async -> BiometricStatus
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

  /// Token echoed on the original payment after local verification succeeds.
  public var resubmitToken: String {
    if let token, !token.isEmpty { return token }
    return payload
  }

  public func isExpired(at now: Date = Date()) -> Bool {
    now >= expiresAt
  }

  static func extract(from object: [String: Any]) -> ScaChallenge? {
    let nested = (object["challenge"] as? [String: Any]) ?? (object["scaChallenge"] as? [String: Any])
    let payload = firstString(nested, keys: ["payload", "challengePayload"])
      ?? firstString(object, keys: ["challengePayload", "payload"])
    let expiryValue = firstValue(nested, keys: ["expiresAt", "expiration", "expiry"])
      ?? firstValue(object, keys: ["expiresAt", "expiration"])
    guard let payload, let expiresAt = ScaTime.parse(expiryValue) else { return nil }
    let token = firstString(nested, keys: ["token", "scaChallengeToken"])
      ?? firstString(object, keys: ["scaChallengeToken"])
    return ScaChallenge(payload: payload, expiresAt: expiresAt, token: token)
  }

  private static func firstString(_ object: [String: Any]?, keys: [String]) -> String? {
    guard let object else { return nil }
    for key in keys {
      if let text = string(object[key]) { return text }
    }
    return nil
  }

  private static func firstValue(_ object: [String: Any]?, keys: [String]) -> Any? {
    guard let object else { return nil }
    for key in keys where object[key] != nil {
      return object[key]
    }
    return nil
  }

  private static func string(_ value: Any?) -> String? {
    guard let text = value as? String, !text.isEmpty else { return nil }
    return text
  }
}

public enum ScaIntercept: Equatable {
  case notStepUp
  case invalid
  case expired(ScaChallenge)
  case required(ScaChallenge)
}

public enum ScaInterpreter {
  /// HTTP 202 plus `SCA_STEP_UP_REQUIRED` is the only step-up signal.
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
  case readyToResubmit(token: String)
  case failed(message: String)
}

public struct ScaSession: Equatable {
  public let draft: PaymentDraft
  public let challenge: ScaChallenge
  public private(set) var phase: ScaPhase

  public init(draft: PaymentDraft, challenge: ScaChallenge, now: Date = Date()) {
    self.draft = draft
    self.challenge = challenge
    self.phase = challenge.isExpired(at: now)
      ? .failed(message: ScaCopy.failureMessage)
      : .biometric
  }

  public var resubmitToken: String? {
    if case .readyToResubmit(let token) = phase { return token }
    return nil
  }

  public var showsPasscode: Bool {
    switch phase {
    case .passcode, .failed: return true
    case .biometric, .readyToResubmit: return false
    }
  }

  public mutating func completeBiometric(_ status: BiometricStatus, now: Date = Date()) {
    guard case .biometric = phase else { return }
    if challenge.isExpired(at: now) {
      phase = .failed(message: ScaCopy.failureMessage)
      return
    }
    if status == .success {
      phase = .readyToResubmit(token: challenge.resubmitToken)
    } else {
      phase = .passcode
    }
  }

  public mutating func submitPasscode(
    _ entered: String,
    now: Date = Date(),
    expected: String = ScaCopy.rehearsalPasscode
  ) {
    switch phase {
    case .passcode, .failed:
      break
    case .biometric, .readyToResubmit:
      return
    }
    if challenge.isExpired(at: now) {
      phase = .failed(message: ScaCopy.failureMessage)
      return
    }
    if entered == expected {
      phase = .readyToResubmit(token: challenge.resubmitToken)
    } else {
      phase = .failed(message: ScaCopy.failureMessage)
    }
  }
}

enum ScaTime {
  static func parse(_ value: Any?) -> Date? {
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
