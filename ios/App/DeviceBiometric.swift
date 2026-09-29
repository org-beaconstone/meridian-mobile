import Foundation
import MeridianSDK
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Native biometric prompt. When Face ID or Touch ID cannot run, the caller keeps the
/// payment draft and continues with the in-app passcode.
struct DeviceBiometric {
  func authenticate(reason: String) async -> BiometricStatus {
#if canImport(LocalAuthentication)
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
    } catch let failure as LAError {
      switch failure.code {
      case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
        return .unavailable
      case .userCancel, .appCancel, .systemCancel:
        return .cancelled
      default:
        return .failed
      }
    } catch {
      return .failed
    }
#else
    _ = reason
    return .unavailable
#endif
  }
}
