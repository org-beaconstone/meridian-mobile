import Foundation

// MARK: - SCA Challenge Models

/// The authentication method required for an SCA challenge
public enum SCAType: String, Codable, Hashable, Sendable {
  case biometric
  case pin
}

/// An SCA challenge presented before confirming a bank payment
public struct SCAChallenge: Hashable, Sendable {
  public let paymentId: String
  public let amountMinor: Int
  public let recipientName: String
  public let type: SCAType

  public init(
    paymentId: String,
    amountMinor: Int,
    recipientName: String,
    type: SCAType = .biometric
  ) {
    self.paymentId = paymentId
    self.amountMinor = amountMinor
    self.recipientName = recipientName
    self.type = type
  }
}

// MARK: - Return State

/// The decoded payload embedded in a bank handoff return URL's state parameter
public struct ReturnState: Codable, Hashable, Sendable {
  public let paymentId: String
  public let nonce: String
  /// Unix epoch seconds at token creation
  public let issuedAt: Int64

  public init(paymentId: String, nonce: String, issuedAt: Int64) {
    self.paymentId = paymentId
    self.nonce = nonce
    self.issuedAt = issuedAt
  }

  enum CodingKeys: String, CodingKey {
    case paymentId
    case nonce
    case issuedAt = "iat"
  }
}

// MARK: - SCA Authenticator Protocol

/// Protocol for performing a native SCA challenge (biometric or PIN).
/// Implement with LocalAuthentication.LAContext on iOS/macOS.
/// Using a protocol makes the authenticator replaceable with a test stub.
public protocol SCAAuthenticating: Sendable {
  /// Attempt to authenticate the user for the given challenge.
  /// - Parameters:
  ///   - challenge: The SCA challenge describing the payment context
  ///   - localizedReason: Human-readable reason shown in the system prompt
  /// - Returns: `true` if the user authenticated successfully
  func authenticate(
    challenge: SCAChallenge,
    localizedReason: String
  ) async throws -> Bool
}
