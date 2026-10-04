import Foundation

/// Local PSD2 SCA step-up for the rehearsal. The verification token is a device-local
/// proof, not a provider cryptogram, credential, or network call.
public enum ScaCopy {
  public static let code = "SCA_STEP_UP_REQUIRED"
  public static let europeanPayment = "Confirm with Face ID / Fingerprint to authorize European payment"
  public static let expired = "This step-up window expired. Start the payment again."
  public static let cancelled = "Biometric confirmation cancelled. Retry the same payment."
  public static let rejected = "The authentication challenge was not accepted. Start the payment again."
  public static let malformed = "The bank response did not include a usable challenge token. Retry the same payment."
  public static let latency = "Local authentication verification exceeded 300 ms. Retry the same payment."
}

public struct ScaChallenge: Equatable, Sendable {
  public let token: String
  public let expiresAt: Date

  public func isExpired(at now: Date) -> Bool {
    now >= expiresAt
  }
}

public enum ScaAssessment: Equatable {
  case notRequired
  case ready(ScaChallenge)
  case malformed(String)
}

public protocol ScaChallengeHandler: Sendable {
  /// Present the native biometric dialog. Return true when the user authenticates.
  func confirmEuropeanPayment(prompt: String) async -> Bool
}

public enum ScaVerification {
  public static let headerName = "X-Challenge-Verification"
  public static let latencyBudgetMs = 300

  /// Derive the resubmit token. The measured work is the local proof only.
  public static func token(for challengeToken: String) throws -> String {
    if challengeToken.isEmpty {
      throw MeridianError.scaMalformed(ScaCopy.malformed)
    }
    let start = DispatchTime.now().uptimeNanoseconds
    var hash: UInt64 = 14_695_981_039_346_656_037
    let prime: UInt64 = 1_099_511_628_211
    for byte in challengeToken.utf8 {
      hash ^= UInt64(byte)
      hash &*= prime
    }
    let elapsedMs = (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    if elapsedMs >= UInt64(latencyBudgetMs) {
      throw MeridianError.scaLatencyExceeded(ScaCopy.latency)
    }
    return String(format: "sca_v1_%016llx", hash)
  }
}

public func assessSca(statusCode: Int, body: PaymentResponse) -> ScaAssessment {
  guard statusCode == 202, body.code == ScaCopy.code else {
    return .notRequired
  }
  guard
    let token = body.challengeToken,
    !token.isEmpty,
    let rawExpiry = body.challengeExpiresAt,
    let expiry = ScaTimestamps.parse(rawExpiry)
  else {
    return .malformed(ScaCopy.malformed)
  }
  return .ready(ScaChallenge(token: token, expiresAt: expiry))
}

enum ScaTimestamps {
  static func parse(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
      return date
    }
    let basic = ISO8601DateFormatter()
    basic.formatOptions = [.withInternetDateTime]
    return basic.date(from: value)
  }
}
