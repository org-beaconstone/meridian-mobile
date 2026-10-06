import Foundation
import LocalAuthentication

/// Invokes the platform biometric or device-PIN prompt. This is a local rehearsal
/// confirmation, not a provider challenge and not a stored bank credential.
enum DeviceOwnerConfirmation {
  static func evaluate(reason: String, completion: @escaping @MainActor (Bool) -> Void) {
    let context = LAContext()
    context.localizedCancelTitle = "Use PIN"
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      Task { @MainActor in completion(false) }
      return
    }
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
      Task { @MainActor in completion(success) }
    }
  }
}
