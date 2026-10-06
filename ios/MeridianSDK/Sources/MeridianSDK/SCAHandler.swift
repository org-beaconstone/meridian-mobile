import Foundation

#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

// MARK: - SCA Result

public enum SCAResult: Sendable, Equatable {
    /// Authentication succeeded.
    case success
    /// The user cancelled the prompt.
    case cancelled
    /// Authentication failed or is unavailable; the associated value carries a description.
    case failed(String)
}

// MARK: - SCA Challenge

public enum SCAChallenge: Sendable {
    /// Require biometric authentication only (Face ID / Touch ID).
    case biometric(reason: String)
    /// Require device PIN / passcode only.
    case pin(reason: String)
    /// Accept biometric falling back to device PIN (recommended for most flows).
    case any(reason: String)

    public var reason: String {
        switch self {
        case let .biometric(r), let .pin(r), let .any(r): return r
        }
    }
}

// MARK: - SCA Authenticating Protocol

/// Abstract interface for SCA so that callers remain testable without real hardware.
public protocol SCAAuthenticating: Sendable {
    func authenticate(challenge: SCAChallenge) async -> SCAResult
}

// MARK: - Live SCA Handler

/// Production SCA handler backed by `LocalAuthentication`.
///
/// Falls back gracefully when biometrics are unavailable: `.any` and `.pin` challenges
/// will succeed via device passcode; a pure `.biometric` challenge will fail if no enrolled
/// biometrics are present.
public struct SCAHandler: SCAAuthenticating {
    public init() {}

    public func authenticate(challenge: SCAChallenge) async -> SCAResult {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var canEvaluateError: NSError?
        let policy: LAPolicy = {
            switch challenge {
            case .biometric: return .deviceOwnerAuthenticationWithBiometrics
            case .pin, .any: return .deviceOwnerAuthentication
            }
        }()

        guard context.canEvaluatePolicy(policy, error: &canEvaluateError) else {
            return .failed(canEvaluateError?.localizedDescription ?? "Authentication not available")
        }

        do {
            let granted = try await context.evaluatePolicy(policy, localizedReason: challenge.reason)
            return granted ? .success : .cancelled
        } catch {
            if let laError = error as? LAError {
                switch laError.code {
                case .userCancel, .appCancel, .systemCancel:
                    return .cancelled
                default:
                    break
                }
            }
            return .failed(error.localizedDescription)
        }
        #else
        return .failed("LocalAuthentication is not available on this platform")
        #endif
    }
}

// MARK: - Test Stubs

/// Always succeeds – use in unit tests that should not depend on hardware.
public struct AlwaysSucceedSCAHandler: SCAAuthenticating {
    public init() {}
    public func authenticate(challenge: SCAChallenge) async -> SCAResult { .success }
}

/// Always fails – use in unit tests that exercise error paths.
public struct AlwaysFailSCAHandler: SCAAuthenticating {
    public let reason: String
    public init(reason: String = "Test-induced failure") { self.reason = reason }
    public func authenticate(challenge: SCAChallenge) async -> SCAResult { .failed(reason) }
}

/// Always cancels – use in unit tests that exercise cancellation paths.
public struct AlwaysCancelSCAHandler: SCAAuthenticating {
    public init() {}
    public func authenticate(challenge: SCAChallenge) async -> SCAResult { .cancelled }
}
