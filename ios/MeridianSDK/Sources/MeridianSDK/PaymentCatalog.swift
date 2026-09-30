import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// Customer-facing rails for the Adyen card / Worldpay bank baseline.
// Vendor names stay off the UI. No further provider is recognized.

public let paymentWideBreakpoint: Double = 600

public enum PaymentCorridor: String, CaseIterable, Identifiable, Hashable {
  case unitedKingdom = "GB"
  case eurozone = "EU"
  case other = "XX"

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .unitedKingdom: return "United Kingdom"
    case .eurozone: return "Eurozone"
    case .other: return "Other destinations"
    }
  }

  public var summary: String {
    switch self {
    case .unitedKingdom: return "Domestic debit and credit cards in GBP"
    case .eurozone: return "Cards and SEPA Instant Transfer in GBP"
    case .other: return "Destinations outside the supported rails"
    }
  }

  /// Methods this corridor can settle. Intersected with the server catalog.
  public var eligibleMethods: Set<PaymentMethod> {
    switch self {
    case .unitedKingdom: return [.card]
    case .eurozone: return [.card, .bank]
    case .other: return []
    }
  }
}

public struct PaymentOption: Identifiable, Hashable {
  public let method: PaymentMethod
  public let railLabel: String
  public let accessibilityLabel: String

  public var id: PaymentMethod { method }

  public init(method: PaymentMethod, railLabel: String, accessibilityLabel: String) {
    self.method = method
    self.railLabel = railLabel
    self.accessibilityLabel = accessibilityLabel
  }
}

public enum PaymentMethodPhase: Equatable {
  case loading
  case unavailable(String)
  case empty(PaymentCorridor)
  case ready([PaymentOption])
}

public struct ContrastColor: Hashable {
  public let red: Double
  public let green: Double
  public let blue: Double

  public init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  public init(hex: Int) {
    self.red = Double((hex >> 16) & 0xFF) / 255
    self.green = Double((hex >> 8) & 0xFF) / 255
    self.blue = Double(hex & 0xFF) / 255
  }
}

public enum PaymentTextColors {
  public static let ink = ContrastColor(hex: 0x142C35)
  public static let canvas = ContrastColor(hex: 0xF8F9F6)
  public static let surface = ContrastColor(hex: 0xFFFFFF)
  public static let secondary = ContrastColor(hex: 0x31464F)
  public static let onInk = ContrastColor(hex: 0xFFFFFF)
  public static let onInkMuted = ContrastColor(hex: 0xD5DFD7)
  public static let action = ContrastColor(hex: 0x1868DB)
  public static let selectedFill = ContrastColor(hex: 0xE7EEE8)
  public static let border = ContrastColor(hex: 0x3E5248)
  public static let shimmer = ContrastColor(hex: 0xE3E8E1)

  public static let textPairs: [(ContrastColor, ContrastColor)] = [
    (ink, surface),
    (ink, canvas),
    (secondary, surface),
    (secondary, canvas),
    (onInk, ink),
    (onInkMuted, ink),
    (onInk, action),
    (ink, selectedFill),
    (secondary, selectedFill),
  ]

  public static let controlPairs: [(ContrastColor, ContrastColor)] = [
    (border, surface),
    (action, surface),
    (ink, surface),
  ]
}

public let paymentMethodsLoadingLabel = "Loading payment methods"
public let paymentMethodsUnavailableLabel =
  "Payment methods couldn't be loaded. Check the connection and try again. Amounts stay in British pounds (GBP)."

public func railLabel(for method: PaymentMethod) -> String {
  switch method {
  case .card: return "Debit / Credit Card"
  case .bank: return "SEPA Instant Transfer"
  }
}

public func railAccessibilityLabel(for method: PaymentMethod) -> String {
  switch method {
  case .card:
    return "Debit or credit card. Currency British pounds, GBP."
  case .bank:
    return "SEPA Instant Transfer. Currency British pounds, GBP."
  }
}

public func corridorAccessibilityLabel(_ corridor: PaymentCorridor) -> String {
  "\(corridor.title). \(corridor.summary). Currency British pounds, GBP."
}

public func railLabel(forMethodName name: String) -> String {
  switch name.lowercased() {
  case PaymentMethod.card.rawValue: return railLabel(for: .card)
  case PaymentMethod.bank.rawValue: return railLabel(for: .bank)
  default: return "Payment"
  }
}

/// Recognized baseline only: Adyen settles card, Worldpay settles bank.
public func baselineMethod(providerId: String) -> PaymentMethod? {
  switch providerId.lowercased() {
  case ProviderId.adyen.rawValue: return .card
  case ProviderId.worldpay.rawValue: return .bank
  default: return nil
  }
}

public func paymentOptions(in catalog: CatalogResponse, corridor: PaymentCorridor) -> [PaymentOption] {
  let eligible = corridor.eligibleMethods
  var seen = Set<PaymentMethod>()
  var options: [PaymentOption] = []
  for provider in catalog.providers {
    guard let method = baselineMethod(providerId: provider.id.rawValue),
      eligible.contains(method),
      provider.methods.contains(method),
      seen.insert(method).inserted
    else { continue }
    options.append(
      PaymentOption(
        method: method,
        railLabel: railLabel(for: method),
        accessibilityLabel: railAccessibilityLabel(for: method)
      )
    )
  }
  return options
}

public func paymentMethodPhase(
  catalog: CatalogResponse?,
  retrieving: Bool,
  failed: Bool,
  corridor: PaymentCorridor
) -> PaymentMethodPhase {
  guard let catalog else {
    if retrieving { return .loading }
    if failed { return .unavailable(paymentMethodsUnavailableLabel) }
    return .loading
  }
  let options = paymentOptions(in: catalog, corridor: corridor)
  if options.isEmpty { return .empty(corridor) }
  return .ready(options)
}

public func emptyPaymentMethodsMessage(corridor: PaymentCorridor) -> String {
  "No payment methods are available for \(corridor.title). None of the catalogued rails can be used for this corridor. Amounts stay in British pounds (GBP)."
}

public func containsVendorMark(_ text: String) -> Bool {
  let folded = text.lowercased()
  return folded.contains("adyen") || folded.contains("worldpay")
}

/// Side-by-side rails only when the width still fits after font scaling.
/// At 200% a tablet falls back to a single column so labels are not clipped.
public func usesSideBySideRails(widthPoints: Double, fontScale: Double) -> Bool {
  guard widthPoints > 0, fontScale > 0 else { return false }
  return widthPoints / fontScale >= paymentWideBreakpoint
}

public func contrastRatio(_ foreground: ContrastColor, _ background: ContrastColor) -> Double {
  let lighter = max(relativeLuminance(foreground), relativeLuminance(background))
  let darker = min(relativeLuminance(foreground), relativeLuminance(background))
  return (lighter + 0.05) / (darker + 0.05)
}

private func relativeLuminance(_ color: ContrastColor) -> Double {
  func channel(_ value: Double) -> Double {
    if value <= 0.04045 { return value / 12.92 }
    return pow((value + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
}
