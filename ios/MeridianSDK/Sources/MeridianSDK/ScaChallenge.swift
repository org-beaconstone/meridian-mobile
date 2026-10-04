import Foundation
import CryptoKit

/// In-app PSD2 strong customer authentication for the rehearsal.
/// Possession is the in-app device binding. The second factor is inherence
/// (biometrics) or knowledge (the security passcode). The signed
/// `scaChallengeToken` never includes the passcode and is not a provider credential.
public enum ScaFactor: String, Codable, Hashable, CaseIterable {
  case possession
  case knowledge
  case inherence
}

public enum BiometricOutcome: String, Codable, Hashable {
  case succeeded
  case rejected
  case bypassed
  case unavailable
}

public enum ScaPhase: Equatable {
  case biometric
  case passcode
  case verified
}

public struct ScaPaymentBinding: Equatable {
  public let recipientId: String
  public let amountMinor: Int
  public let method: PaymentMethod
  public let idempotencyKey: String

  public init(recipientId: String, amountMinor: Int, method: PaymentMethod, idempotencyKey: String) {
    self.recipientId = recipientId
    self.amountMinor = amountMinor
    self.method = method
    self.idempotencyKey = idempotencyKey
  }
}

public struct ScaVerification: Equatable {
  public let scaChallengeToken: String
  public let factors: [ScaFactor]
  public let biometric: BiometricOutcome

  public init(scaChallengeToken: String, factors: [ScaFactor], biometric: BiometricOutcome) {
    self.scaChallengeToken = scaChallengeToken
    self.factors = factors
    self.biometric = biometric
  }
}

public enum ScaChallenge {
  public static let rejectionBanner = "Authentication challenge failed. Please verify with your passcode."
  public static let biometricsUnavailableNote = "Biometrics are unavailable on this device."
  public static let incorrectPasscode = "Incorrect passcode."
  public static let tooManyAttempts = "Too many attempts. Try again shortly."
  public static let pinLength = 6
  public static let maxAttempts = 5
  public static let lockoutSeconds: TimeInterval = 30
  /// Fictional rehearsal knowledge factor. It is never sent to the API or a provider.
  public static let rehearsalPin = "135790"
  public static let inAppBinding = "meridian-in-app"
  public static let salt = "meridian-sca-rehearsal-salt-v1"
  public static let deviceKeyMaterial = "meridian-sca-rehearsal-device-v1"

  static func hashPin(_ pin: String) -> Data {
    var material = Data(salt.utf8)
    material.append(Data("\n".utf8))
    material.append(Data(pin.utf8))
    return Data(SHA256.hash(data: material))
  }

  static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
    guard lhs.count == rhs.count else { return false }
    var diff: UInt8 = 0
    for index in 0..<lhs.count {
      diff |= lhs[index] ^ rhs[index]
    }
    return diff == 0
  }
}

public struct ScaSigner {
  private let key: Data

  public init(key: Data) {
    self.key = key
  }

  public static func rehearsal() -> ScaSigner {
    ScaSigner(key: Data(SHA256.hash(data: Data(ScaChallenge.deviceKeyMaterial.utf8))))
  }

  public static func randomNonce() -> String {
    (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
  }

  public func sign(
    binding: ScaPaymentBinding,
    factors: [ScaFactor],
    biometric: BiometricOutcome,
    challengeId: String,
    issuedAt: Date,
    nonce: String
  ) -> String? {
    guard let canonical = canonical(
      binding: binding,
      factors: factors,
      biometric: biometric,
      challengeId: challengeId,
      issuedAt: issuedAt,
      nonce: nonce
    ) else { return nil }
    let payload = Data(canonical.utf8)
    let mac = hmac(payload)
    return base64UrlEncode(payload) + "." + base64UrlEncode(mac)
  }

  /// Returns the signed canonical payload when the MAC matches.
  public func authenticatedPayload(_ token: String) -> String? {
    let parts = token.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2,
          let payload = base64UrlDecode(String(parts[0])),
          let provided = base64UrlDecode(String(parts[1])),
          ScaChallenge.constantTimeEquals(hmac(payload), provided),
          let text = String(data: payload, encoding: .utf8) else { return nil }
    return text
  }

  public func verify(token: String, binding: ScaPaymentBinding) -> Bool {
    guard let payload = authenticatedPayload(token) else { return false }
    let lines = payload.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard lines.count == 11, lines[0] == "v1" else { return false }
    guard !lines[1].isEmpty, !lines[9].isEmpty else { return false }
    let factors = Set(lines[2].split(separator: "+").map(String.init))
    guard factors.contains(ScaFactor.possession.rawValue),
          factors.contains(ScaFactor.knowledge.rawValue) || factors.contains(ScaFactor.inherence.rawValue) else {
      return false
    }
    guard BiometricOutcome(rawValue: lines[3]) != nil else { return false }
    guard lines[4] == String(binding.amountMinor),
          lines[5] == binding.recipientId,
          lines[6] == binding.method.rawValue,
          lines[7] == binding.idempotencyKey,
          lines[10] == ScaChallenge.inAppBinding else { return false }
    return true
  }

  private func canonical(
    binding: ScaPaymentBinding,
    factors: [ScaFactor],
    biometric: BiometricOutcome,
    challengeId: String,
    issuedAt: Date,
    nonce: String
  ) -> String? {
    let fields = [
      challengeId,
      binding.recipientId,
      binding.method.rawValue,
      binding.idempotencyKey,
      nonce,
    ]
    guard fields.allSatisfy({ !$0.isEmpty && !$0.contains("\n") && !$0.contains("\r") }) else { return nil }
    guard binding.amountMinor > 0 else { return nil }
    let factorList = factors.map(\.rawValue).sorted().joined(separator: "+")
    guard !factorList.isEmpty else { return nil }
    let issued = String(Int64(issuedAt.timeIntervalSince1970))
    return [
      "v1",
      challengeId,
      factorList,
      biometric.rawValue,
      String(binding.amountMinor),
      binding.recipientId,
      binding.method.rawValue,
      binding.idempotencyKey,
      issued,
      nonce,
      ScaChallenge.inAppBinding,
    ].joined(separator: "\n")
  }

  private func hmac(_ message: Data) -> Data {
    let code = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key))
    return Data(code)
  }
}

struct ScaPasscodeVerifier {
  private let expected: Data

  static func rehearsal() -> ScaPasscodeVerifier {
    ScaPasscodeVerifier(expected: ScaChallenge.hashPin(ScaChallenge.rehearsalPin))
  }

  init(expected: Data) {
    self.expected = expected
  }

  func matches(_ pin: String) -> Bool {
    guard pin.count == ScaChallenge.pinLength, pin.allSatisfy(\.isNumber) else { return false }
    return ScaChallenge.constantTimeEquals(ScaChallenge.hashPin(pin), expected)
  }
}

public struct ScaChallengeSession: CustomStringConvertible {
  public let binding: ScaPaymentBinding
  public private(set) var phase: ScaPhase
  public private(set) var rejectionBanner: String?
  public private(set) var biometric: BiometricOutcome?
  public private(set) var enteredCount: Int
  public private(set) var failures: Int
  public private(set) var lockedUntil: Date?
  public private(set) var passcodeMessage: String?
  public private(set) var verification: ScaVerification?

  private var entered: String
  private let signer: ScaSigner
  private let verifier: ScaPasscodeVerifier
  private let challengeId: String
  private let nonce: () -> String

  public var description: String {
    "ScaChallengeSession(phase=\(phase), failures=\(failures), entered=\(enteredCount))"
  }

  public init(
    binding: ScaPaymentBinding,
    signer: ScaSigner = .rehearsal(),
    challengeId: String = UUID().uuidString,
    nonce: @escaping () -> String = { ScaSigner.randomNonce() }
  ) {
    self.binding = binding
    self.signer = signer
    self.verifier = .rehearsal()
    self.challengeId = challengeId
    self.nonce = nonce
    self.phase = .biometric
    self.entered = ""
    self.enteredCount = 0
    self.failures = 0
  }

  public func maskedPasscode() -> String {
    let filled = min(enteredCount, ScaChallenge.pinLength)
    return String(repeating: "•", count: filled) + String(repeating: "○", count: ScaChallenge.pinLength - filled)
  }

  public func secondsLocked(at date: Date) -> Int {
    guard let lockedUntil else { return 0 }
    let remaining = lockedUntil.timeIntervalSince(date)
    if remaining <= 0 { return 0 }
    return Int(ceil(remaining))
  }

  public mutating func rejectBiometrics() {
    guard phase == .biometric else { return }
    biometric = .rejected
    rejectionBanner = ScaChallenge.rejectionBanner
    phase = .passcode
    clearEntry()
  }

  public mutating func bypassBiometrics() {
    guard phase == .biometric else { return }
    biometric = .bypassed
    rejectionBanner = nil
    phase = .passcode
    clearEntry()
  }

  public mutating func markBiometricsUnavailable() {
    guard phase == .biometric else { return }
    biometric = .unavailable
    rejectionBanner = nil
    phase = .passcode
    clearEntry()
  }

  @discardableResult
  public mutating func succeedBiometrics(at date: Date) -> ScaVerification? {
    guard phase == .biometric else { return nil }
    biometric = .succeeded
    return issue(factors: [.possession, .inherence], biometric: .succeeded, at: date)
  }

  @discardableResult
  public mutating func appendDigit(_ digit: Int, at date: Date) -> ScaVerification? {
    guard phase == .passcode, (0...9).contains(digit) else { return nil }
    if let lockedUntil, date < lockedUntil {
      passcodeMessage = ScaChallenge.tooManyAttempts
      return nil
    }
    if lockedUntil != nil {
      self.lockedUntil = nil
      failures = 0
      passcodeMessage = nil
    }
    entered.append(String(digit))
    enteredCount = entered.count
    guard entered.count >= ScaChallenge.pinLength else {
      passcodeMessage = nil
      return nil
    }
    let attempt = entered
    clearEntry()
    if verifier.matches(attempt) {
      let outcome = biometric ?? .bypassed
      return issue(factors: [.possession, .knowledge], biometric: outcome, at: date)
    }
    failures += 1
    if failures >= ScaChallenge.maxAttempts {
      lockedUntil = date.addingTimeInterval(ScaChallenge.lockoutSeconds)
      passcodeMessage = ScaChallenge.tooManyAttempts
    } else {
      passcodeMessage = ScaChallenge.incorrectPasscode
    }
    return nil
  }

  public mutating func deleteDigit(at date: Date) {
    if let lockedUntil, date >= lockedUntil {
      self.lockedUntil = nil
      failures = 0
      passcodeMessage = nil
    }
    guard phase == .passcode, self.lockedUntil == nil, !entered.isEmpty else { return }
    entered.removeLast()
    enteredCount = entered.count
  }

  private mutating func clearEntry() {
    entered = ""
    enteredCount = 0
  }

  private mutating func issue(factors: [ScaFactor], biometric: BiometricOutcome, at date: Date) -> ScaVerification? {
    guard let token = signer.sign(
      binding: binding,
      factors: factors,
      biometric: biometric,
      challengeId: challengeId,
      issuedAt: date,
      nonce: nonce()
    ) else { return nil }
    let verification = ScaVerification(
      scaChallengeToken: token,
      factors: factors.sorted { $0.rawValue < $1.rawValue },
      biometric: biometric
    )
    self.verification = verification
    phase = .verified
    rejectionBanner = nil
    passcodeMessage = nil
    lockedUntil = nil
    clearEntry()
    return verification
  }
}

private func base64UrlEncode(_ data: Data) -> String {
  data.base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
}

private func base64UrlDecode(_ value: String) -> Data? {
  var padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
  let remainder = padded.count % 4
  if remainder > 0 {
    padded += String(repeating: "=", count: 4 - remainder)
  }
  return Data(base64Encoded: padded)
}
