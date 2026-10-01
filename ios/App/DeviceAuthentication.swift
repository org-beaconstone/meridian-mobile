import Foundation
import LocalAuthentication
import MeridianSDK

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Invokes the platform biometric prompt for an in-app SCA challenge.
struct DeviceOwnerConfirmation {
  func confirmBiometric() async -> Bool {
    let context = LAContext()
    context.localizedCancelTitle = "Use PIN"
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      return false
    }
    return await withCheckedContinuation { continuation in
      context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: "Approve this rehearsal payment"
      ) { success, _ in
        continuation.resume(returning: success)
      }
    }
  }
}

/// Opens an allowlisted bank HTTPS URL. The return is completed by the universal-link listener.
enum BankLinkOpener {
  static func open(_ url: URL) -> Bool {
    guard BankAllowlist.permitsHandoff(url) else { return false }
    #if canImport(UIKit)
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
    return true
    #elseif canImport(AppKit)
    return NSWorkspace.shared.open(url)
    #else
    return false
    #endif
  }
}
