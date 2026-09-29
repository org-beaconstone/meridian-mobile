import Foundation
import LocalAuthentication

// MARK: - Protocols

/// Abstraction over native biometric authentication (Face ID / Touch ID).
/// Inject a test double in unit tests; use `LocalAuthenticationBiometricAuthenticator`
/// in production.
public protocol ScaBiometricAuthenticator: Sendable {
  /// Returns `true` when the device can evaluate biometric policy right now.
  func canAuthenticate() -> Bool
  /// Presents the native biometric prompt. Returns `true` on success,
  /// `false` on denial; throws on a hard error (e.g. biometrics locked out).
  func authenticate(reason: String) async throws -> Bool
}

/// Abstraction over in-app passcode verification, presented when biometrics
/// are unavailable or the customer's biometric attempt fails.
public protocol ScaPasscodeVerifier: Sendable {
  /// Presents the in-app passcode challenge UI. Returns `true` on success.
  func verifyPasscode() async -> Bool
}

// MARK: - Default LAContext-backed biometric authenticator

/// Default `ScaBiometricAuthenticator` backed by `LocalAuthentication`.
/// Uses `.deviceOwnerAuthenticationWithBiometrics` so only Face ID / Touch ID
/// is attempted; passcode fallback is handled separately via `ScaPasscodeVerifier`.
public final class LocalAuthenticationBiometricAuthenticator: ScaBiometricAuthenticator,
  @unchecked Sendable
{
  private let context: LAContext

  public init(context: LAContext = LAContext()) {
    self.context = context
  }

  public func canAuthenticate() -> Bool {
    var error: NSError?
    return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
  }

  public func authenticate(reason: String) async throws -> Bool {
    return try await withCheckedThrowingContinuation { continuation in
      context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: reason
      ) { success, error in
        if let error = error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: success)
        }
      }
    }
  }
}

// MARK: - SCA Challenge Handler

/// Handles PSD2 SCA step-up authentication invoked when the payment gateway
/// returns HTTP 202 with `SCA_STEP_UP_REQUIRED`.
///
/// Flow:
/// 1. Check the challenge has not expired.
/// 2. Attempt native biometric authentication (Face ID / Touch ID).
/// 3. On biometric failure or unavailability, fall back to in-app passcode.
/// 4. On successful authentication, re-dispatch the original payment payload
///    with `scaChallengeToken` under the original idempotency key.
public actor ScaChallengeHandler {
  private let client: MeridianClient
  private let biometricAuthenticator: ScaBiometricAuthenticator
  private let passcodeVerifier: ScaPasscodeVerifier

  static let biometricPrompt =
    "Confirm with Face ID / Fingerprint to authorize European payment"
  static let failureMessage =
    "Authentication challenge failed. Please verify with your passcode."

  public init(
    client: MeridianClient,
    biometricAuthenticator: ScaBiometricAuthenticator =
      LocalAuthenticationBiometricAuthenticator(),
    passcodeVerifier: ScaPasscodeVerifier
  ) {
    self.client = client
    self.biometricAuthenticator = biometricAuthenticator
    self.passcodeVerifier = passcodeVerifier
  }

  /// Handle an `SCA_STEP_UP_REQUIRED` response and complete the payment.
  ///
  /// - Parameters:
  ///   - scaChallengeToken: Token extracted from the gateway `SCA_STEP_UP_REQUIRED` response.
  ///   - challengeExpiresAt: ISO 8601 expiration timestamp from the challenge response.
  ///   - recipientId: Original payment recipient ID.
  ///   - amountMinor: Original payment amount in GBP pence.
  ///   - method: Original payment method.
  ///   - note: Original payment note / reference.
  ///   - scenario: Original simulation scenario.
  ///   - idempotencyKey: Original idempotency key – reused so the gateway
  ///     can correlate the re-dispatch with the initial attempt.
  public func handle(
    scaChallengeToken: String,
    challengeExpiresAt: String,
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String,
    scenario: Scenario,
    idempotencyKey: String
  ) async -> ScaOutcome {
    let formatter = ISO8601DateFormatter()

    // 1. Guard: challenge must not already be expired
    if isExpired(expiresAt: challengeExpiresAt, formatter: formatter) {
      return .challengeExpired(Self.failureMessage)
    }

    // 2. Authenticate – biometrics first, passcode fallback
    let authenticated = await attemptAuthentication()

    guard authenticated else {
      return .authenticationFailed(Self.failureMessage)
    }

    // 3. Re-check expiry: authentication may have taken time
    if isExpired(expiresAt: challengeExpiresAt, formatter: formatter) {
      return .challengeExpired(Self.failureMessage)
    }

    // 4. Re-dispatch payment with scaChallengeToken under the original idempotency key
    do {
      let response = try await client.submitScaPayment(
        recipientId: recipientId,
        amountMinor: amountMinor,
        method: method,
        note: note,
        scenario: scenario,
        idempotencyKey: idempotencyKey,
        scaChallengeToken: scaChallengeToken
      )
      return .success(response)
    } catch {
      return .authenticationFailed(Self.failureMessage)
    }
  }

  // MARK: - Helpers

  private func isExpired(expiresAt: String, formatter: ISO8601DateFormatter) -> Bool {
    guard let expiryDate = formatter.date(from: expiresAt) else { return false }
    return expiryDate <= Date()
  }

  private func attemptAuthentication() async -> Bool {
    if biometricAuthenticator.canAuthenticate() {
      do {
        if try await biometricAuthenticator.authenticate(reason: Self.biometricPrompt) {
          return true
        }
      } catch {
        // Biometric attempt failed; fall through to passcode verifier
      }
    }
    return await passcodeVerifier.verifyPasscode()
  }
}
