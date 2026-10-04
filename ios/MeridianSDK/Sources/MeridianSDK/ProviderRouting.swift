import Foundation

/// Card stays on Adyen and bank stays on Worldpay. Uncertain retries must not move a payment.
public func providerFor(method: PaymentMethod) -> ProviderId {
  switch method {
  case .card:
    return .adyen
  case .bank:
    return .worldpay
  }
}

public func refuseProviderSwitch(from original: ProviderId, to attempted: ProviderId) throws {
  if original != attempted {
    throw MeridianError.validationError("Refusing to switch provider after an uncertain outcome")
  }
}
