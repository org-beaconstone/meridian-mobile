import Foundation

public let paymentMethodUnavailableText = "This payment method is temporarily unavailable in your region."

public struct CorridorContext: Hashable {
  public let region: String
  public let currency: String

  public init(region: String, currency: String) {
    self.region = region
    self.currency = currency
  }

  public static let gbp = CorridorContext(region: "GB", currency: "GBP")
}

public struct SelectablePaymentMethod: Identifiable, Hashable {
  public let id: String
  public let method: PaymentMethod
  public let title: String
  public let selectable: Bool
  public let helperText: String?
  public let accessibilityLabel: String

  public init(
    id: String,
    method: PaymentMethod,
    title: String,
    selectable: Bool,
    helperText: String?,
    accessibilityLabel: String
  ) {
    self.id = id
    self.method = method
    self.title = title
    self.selectable = selectable
    self.helperText = helperText
    self.accessibilityLabel = accessibilityLabel
  }
}

public struct PaymentMethodSheetModel: Hashable {
  public let loading: Bool
  public let options: [SelectablePaymentMethod]

  public var placeholderCount: Int { loading ? 2 : 0 }

  public init(loading: Bool, options: [SelectablePaymentMethod]) {
    self.loading = loading
    self.options = options
  }
}

private struct BaselineMethod {
  let provider: ProviderId
  let method: PaymentMethod
  let title: String
}

private let baselineMethods = [
  BaselineMethod(provider: .adyen, method: .card, title: "Adyen Card"),
  BaselineMethod(provider: .worldpay, method: .bank, title: "Worldpay"),
]

/// Builds the GBP corridor sheet from the catalog. Entries outside the contracted
/// Adyen card and Worldpay bank pairing are omitted. An unavailable selection is
/// not replaced with the other method.
public func paymentMethodSheetModel(
  providers: [Provider]?,
  corridor: CorridorContext = .gbp
) -> PaymentMethodSheetModel {
  guard let providers else {
    return PaymentMethodSheetModel(loading: true, options: [])
  }
  let corridorOpen = corridor.currency == "GBP" && corridor.region == "GB"
  var drafts: [(id: String, method: PaymentMethod, title: String, selectable: Bool)] = []
  var seen = Set<PaymentMethod>()
  for provider in providers {
    guard let baseline = baselineMethods.first(where: { $0.provider == provider.id }) else { continue }
    guard provider.methods.contains(baseline.method) else { continue }
    guard seen.insert(baseline.method).inserted else { continue }
    let selectable = corridorOpen && provider.availability == .available
    drafts.append((provider.id.rawValue, baseline.method, baseline.title, selectable))
  }
  let options = drafts.enumerated().map { offset, draft in
    SelectablePaymentMethod(
      id: draft.id,
      method: draft.method,
      title: draft.title,
      selectable: draft.selectable,
      helperText: draft.selectable ? nil : paymentMethodUnavailableText,
      accessibilityLabel: "Select \(draft.title), radio button, \(offset + 1) of \(drafts.count)"
    )
  }
  return PaymentMethodSheetModel(loading: false, options: options)
}

public func submittablePaymentMethod(
  selected: PaymentMethod,
  model: PaymentMethodSheetModel
) -> PaymentMethod? {
  guard !model.loading else { return nil }
  guard let option = model.options.first(where: { $0.method == selected }), option.selectable else { return nil }
  return selected
}

public func paymentMethodBlockMessage(
  selected: PaymentMethod,
  model: PaymentMethodSheetModel
) -> String? {
  if submittablePaymentMethod(selected: selected, model: model) != nil { return nil }
  if model.loading { return "Payment methods are still loading." }
  return model.options.first { $0.method == selected }?.helperText ?? "Choose an available payment method."
}
