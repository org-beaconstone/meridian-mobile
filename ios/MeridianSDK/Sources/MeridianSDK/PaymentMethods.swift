import Foundation

public enum PaymentRailCopy {
  /// Spoken and shown when a baseline rail is missing from the resolved catalog.
  public static let regionUnavailable = "This payment method is temporarily unavailable in your region."
}

public struct PaymentMethodOption: Equatable, Identifiable {
  public let method: PaymentMethod
  public let providerId: ProviderId
  public let title: String
  public let badge: String
  public let available: Bool
  public let warning: String?
  public var id: PaymentMethod { method }

  public func accessibilityAnnouncement(position: Int, total: Int) -> String {
    let base = "Select \(title), radio button, \(position) of \(total)"
    guard available, warning == nil else {
      return "\(base). \(warning ?? PaymentRailCopy.regionUnavailable)"
    }
    return base
  }
}

private struct BaselineRail {
  let providerId: ProviderId
  let method: PaymentMethod
  let title: String
  let fallbackName: String
}

/// Adyen card and Worldpay bank are the only rails this client will offer.
private let baselineRails: [BaselineRail] = [
  BaselineRail(providerId: .adyen, method: .card, title: "Debit card", fallbackName: "Adyen"),
  BaselineRail(providerId: .worldpay, method: .bank, title: "Bank payment", fallbackName: "Worldpay"),
]

/// Builds the payment sheet from a resolved catalog. Rails outside the baseline pair are ignored.
/// A baseline rail that is absent, or present without its method, is shown disabled.
public func resolvePaymentRails(from providers: [Provider]) -> [PaymentMethodOption] {
  baselineRails.map { rail in
    let named = providers.first { $0.id == rail.providerId }
    let name = named?.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? rail.fallbackName
    guard let match = named, match.methods.contains(rail.method) else {
      return PaymentMethodOption(
        method: rail.method,
        providerId: rail.providerId,
        title: rail.title,
        badge: "\(rail.title) · \(name)",
        available: false,
        warning: PaymentRailCopy.regionUnavailable
      )
    }
    return PaymentMethodOption(
      method: rail.method,
      providerId: rail.providerId,
      title: rail.title,
      badge: paymentBadge(title: rail.title, name: match.name, description: match.description),
      available: true,
      warning: nil
    )
  }
}

private func paymentBadge(title: String, name: String, description: String) -> String {
  let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? title
  let detail = description.trimmingCharacters(in: .whitespacesAndNewlines)
  if detail.isEmpty {
    return "\(title) · \(trimmedName)"
  }
  return "\(title) · \(trimmedName) (\(detail))"
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
