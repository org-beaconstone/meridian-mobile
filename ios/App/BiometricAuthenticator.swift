import Foundation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Device biometric gate. A failure or missing sensor falls back to the in-app passcode.
/// Biometric data stays in LocalAuthentication and is never added to the payment request.
struct DeviceBiometricAuthenticator {
  func authenticate(reason: String) async -> Bool {
    #if canImport(LocalAuthentication)
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      return false
    }
    return await withCheckedContinuation { continuation in
      context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
        continuation.resume(returning: success)
      }
    }
    #else
    _ = reason
    return false
    #endif
  }
}
