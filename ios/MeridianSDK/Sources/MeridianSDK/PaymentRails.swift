import Foundation

public enum RailAvailability: String, Hashable {
  case available
  case degraded
  case unavailable
}

/// Copy shown when a catalog rail is degraded, unavailable, or offline.
public let regionalUnavailabilityWarning = "This payment method is temporarily unavailable in your region."

public let adyenCardTitle = "Debit card"
public let adyenCardBadge = "Adyen card (UK debit, usually instant)"
public let worldpayBankTitle = "Bank payment"
public let worldpayBankBadge = "Worldpay bank transfer (Free, arrives next working day)"

public struct PaymentRail: Identifiable, Hashable {
  public let id: String
  public let provider: ProviderId
  public let method: PaymentMethod
  public let title: String
  public let badge: String
  public let availability: RailAvailability
  public let warning: String?
  public let position: Int
  public let total: Int

  public var selectable: Bool { availability == .available }

  public var announcement: String {
    paymentOptionAnnouncement(title: title, index: position, total: total)
  }

  public init(
    id: String,
    provider: ProviderId,
    method: PaymentMethod,
    title: String,
    badge: String,
    availability: RailAvailability,
    warning: String?,
    position: Int,
    total: Int
  ) {
    self.id = id
    self.provider = provider
    self.method = method
    self.title = title
    self.badge = badge
    self.availability = availability
    self.warning = warning
    self.position = position
    self.total = total
  }
}

public func paymentOptionAnnouncement(title: String, index: Int, total: Int) -> String {
  "Select \(title), radio button, \(index) of \(total)"
}

/// Payment options for the native bottom sheet.
/// Only the Adyen card and Worldpay bank baseline is offered. Any other catalog provider is ignored
/// and is not named in the resolved options.
public func resolvePaymentRails(from providers: [Provider]) -> [PaymentRail] {
  struct Draft {
    let provider: ProviderId
    let method: PaymentMethod
    let title: String
    let badge: String
    let availability: RailAvailability
  }

  var drafts: [Draft] = []
  var seen: Set<String> = []
  for provider in providers {
    for methodName in provider.methods {
      guard let baseline = baselineRail(providerId: provider.id, methodName: methodName) else { continue }
      let key = "\(baseline.provider.rawValue):\(baseline.method.rawValue)"
      guard seen.insert(key).inserted else { continue }
      drafts.append(
        Draft(
          provider: baseline.provider,
          method: baseline.method,
          title: baseline.title,
          badge: baseline.badge,
          availability: parseRailAvailability(provider.status)
        )
      )
    }
  }

  let total = drafts.count
  return drafts.enumerated().map { offset, draft in
    let warning = draft.availability == .available ? nil : regionalUnavailabilityWarning
    return PaymentRail(
      id: "\(draft.provider.rawValue)-\(draft.method.rawValue)",
      provider: draft.provider,
      method: draft.method,
      title: draft.title,
      badge: draft.badge,
      availability: draft.availability,
      warning: warning,
      position: offset + 1,
      total: total
    )
  }
}

private struct BaselineRail {
  let provider: ProviderId
  let method: PaymentMethod
  let title: String
  let badge: String
}

private func baselineRail(providerId: String, methodName: String) -> BaselineRail? {
  switch (providerId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          methodName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
  case ("adyen", "card"):
    return BaselineRail(provider: .adyen, method: .card, title: adyenCardTitle, badge: adyenCardBadge)
  case ("worldpay", "bank"):
    return BaselineRail(provider: .worldpay, method: .bank, title: worldpayBankTitle, badge: worldpayBankBadge)
  default:
    return nil
  }
}

private func parseRailAvailability(_ status: String?) -> RailAvailability {
  switch status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
  case nil, "", "available", "online":
    return .available
  case "degraded":
    return .degraded
  default:
    return .unavailable
  }
}
