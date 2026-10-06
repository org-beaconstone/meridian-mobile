import Foundation
import MeridianSDK
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Opens a bank URL only after the allowlist accepts it. A refusal does not
/// substitute another host or provider.
enum BankHandoffOpener {
  static func openIfAllowlisted(_ urlString: String) -> Bool {
    guard case .allowed(let url) = BankHandoffPolicy.inspectBankHandoff(urlString) else {
      return false
    }
    guard let link = URL(string: url) else { return false }
    #if canImport(UIKit)
    guard UIApplication.shared.canOpenURL(link) else { return false }
    UIApplication.shared.open(link)
    return true
    #elseif canImport(AppKit)
    return NSWorkspace.shared.open(link)
    #else
    return false
    #endif
  }
}
