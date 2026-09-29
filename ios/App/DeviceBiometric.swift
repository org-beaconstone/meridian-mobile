import Foundation
import MeridianSDK

#if canImport(LocalAuthentication)
import LocalAuthentication

/// Face ID / Touch ID via LocalAuthentication.
/// The system passcode is not accepted here. Failure or unavailability keeps the
/// same payment on screen and opens the in-app passcode challenge.
struct LocalAuthenticationBiometric {
  func authenticate(reason: String) async -> BiometricStatus {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      return .unavailable
    }
    do {
      let accepted = try await context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: reason
      )
      return accepted ? .success : .failed
    } catch let laError as LAError {
      switch laError.code {
      case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout, .passcodeNotSet:
        return .unavailable
      case .userCancel, .appCancel, .systemCancel:
        return .cancelled
      default:
        return .failed
      }
    } catch {
      return .failed
    }
  }
}
#else
struct LocalAuthenticationBiometric {
  func authenticate(reason: String) async -> BiometricStatus { .unavailable }
}
#endif
