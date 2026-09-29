import Foundation

/// Remote kill switch read from `GET /config`.
public let mobileEuPaymentsFlag = "enable_mobile_eu_payments"

public enum CurrencyCode: String, Codable, Hashable, CaseIterable {
  case gbp = "GBP"
  case eur = "EUR"
}

/// A customer-facing rail. Only Adyen card and Worldpay bank are constructed.
public struct PaymentRail: Codable, Hashable, Identifiable {
  public let id: String
  public let provider: ProviderId
  public let method: PaymentMethod
  public let currency: CurrencyCode
  public let label: String

  public init(
    id: String,
    provider: ProviderId,
    method: PaymentMethod,
    currency: CurrencyCode,
    label: String
  ) {
    self.id = id
    self.provider = provider
    self.method = method
    self.currency = currency
    self.label = label
  }
}

public struct PaymentSurface: Equatable {
  public let flagEnabled: Bool
  public let dynamicCatalogActive: Bool
  public let usingCachedGbp: Bool
  public let currencies: [CurrencyCode]
  public let rails: [PaymentRail]

  public init(
    flagEnabled: Bool,
    dynamicCatalogActive: Bool,
    usingCachedGbp: Bool,
    currencies: [CurrencyCode],
    rails: [PaymentRail]
  ) {
    self.flagEnabled = flagEnabled
    self.dynamicCatalogActive = dynamicCatalogActive
    self.usingCachedGbp = usingCachedGbp
    self.currencies = currencies
    self.rails = rails
  }
}

public struct ResolvedSurface: Equatable {
  public let surface: PaymentSurface
  public let cachedGbp: [PaymentRail]

  public init(surface: PaymentSurface, cachedGbp: [PaymentRail]) {
    self.surface = surface
    self.cachedGbp = cachedGbp
  }
}

public struct PaymentSelection: Equatable {
  public let currency: CurrencyCode
  public let railId: String
  public let reviewing: Bool

  public init(currency: CurrencyCode, railId: String, reviewing: Bool) {
    self.currency = currency
    self.railId = railId
    self.reviewing = reviewing
  }
}

extension PaymentRail {
  public static let gbpBaseline: [PaymentRail] = [
    PaymentRail(
      id: "adyen-card-gbp",
      provider: .adyen,
      method: .card,
      currency: .gbp,
      label: "Debit card · Adyen"
    ),
    PaymentRail(
      id: "worldpay-bank-gbp",
      provider: .worldpay,
      method: .bank,
      currency: .gbp,
      label: "Bank payment · Worldpay"
    ),
  ]
}

/// Boolean `true` or the string `"true"` enables the flag. Every other payload disables it.
public func evaluateMobileEuPaymentsFlag(_ data: Data) -> Bool {
  guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    return false
  }
  if let direct = json[mobileEuPaymentsFlag] {
    return coerceFlag(direct)
  }
  if let flags = json["flags"] as? [String: Any], let nested = flags[mobileEuPaymentsFlag] {
    return coerceFlag(nested)
  }
  return false
}

private func coerceFlag(_ value: Any) -> Bool {
  if let text = value as? String {
    return text.lowercased() == "true"
  }
  // JSON booleans arrive as NSNumber with objCType "c". Numeric 1 must stay disabled.
  guard let number = value as? NSNumber else { return false }
  let type = String(cString: number.objCType)
  guard type == "c" || type == "B" else { return false }
  return number.boolValue
}

/// Flag off keeps the cached GBP Adyen/Worldpay list and hides EUR.
/// Flag on may relabel those two rails from the catalog and add EUR.
/// The rail list is never empty, and no other provider is shown.
public func resolvePaymentSurface(
  flagEnabled: Bool,
  providers: [Provider]?,
  cachedGbp: [PaymentRail]
) -> ResolvedSurface {
  let cached = sanitizeGbp(cachedGbp)
  guard flagEnabled else {
    return ResolvedSurface(
      surface: PaymentSurface(
        flagEnabled: false,
        dynamicCatalogActive: false,
        usingCachedGbp: true,
        currencies: [.gbp],
        rails: cached
      ),
      cachedGbp: cached
    )
  }

  var gbp = cached
  var eur: [PaymentRail] = []
  var recognized = 0
  var relabelled = false
  var seen = Set<ProviderId>()

  for provider in providers ?? [] {
    guard let pair = recognizedPair(provider), !seen.contains(pair.provider) else { continue }
    seen.insert(pair.provider)
    recognized += 1
    let name = displayName(provider)
    if offers(provider, currency: "GBP") {
      gbp[pair.index] = PaymentRail(
        id: pair.gbpId,
        provider: pair.provider,
        method: pair.method,
        currency: .gbp,
        label: gbpLabel(name: name, method: pair.method)
      )
      relabelled = true
    }
    if offers(provider, currency: "EUR") {
      eur.append(
        PaymentRail(
          id: pair.eurId,
          provider: pair.provider,
          method: pair.method,
          currency: .eur,
          label: eurLabel(name: name, method: pair.method)
        )
      )
    }
  }

  // No catalog, or nothing we recognise, still unlocks EUR from the cached GBP rails.
  if recognized == 0 {
    eur = cached.map { eurVersion(of: $0) }
  }

  let currencies: [CurrencyCode] = eur.isEmpty ? [.gbp] : [.gbp, .eur]
  return ResolvedSurface(
    surface: PaymentSurface(
      flagEnabled: true,
      dynamicCatalogActive: recognized > 0,
      usingCachedGbp: !relabelled,
      currencies: currencies,
      rails: gbp + eur
    ),
    cachedGbp: gbp
  )
}

public func reconcileSelection(
  surface: PaymentSurface,
  currency: CurrencyCode,
  railId: String,
  reviewing: Bool
) -> PaymentSelection {
  let rails = surface.rails.isEmpty ? PaymentRail.gbpBaseline : surface.rails
  let allowed = surface.currencies.contains(currency) ? currency : .gbp
  let pool = rails.filter { $0.currency == allowed }
  let choices = pool.isEmpty ? rails : pool
  let kept = choices.first { $0.id == railId }
  let chosen = kept ?? choices[0]
  let stillReviewing = reviewing && kept != nil && allowed == currency
  return PaymentSelection(currency: allowed, railId: chosen.id, reviewing: stillReviewing)
}

private struct RecognizedPair {
  let provider: ProviderId
  let method: PaymentMethod
  let index: Int
  let gbpId: String
  let eurId: String
}

private func recognizedPair(_ provider: Provider) -> RecognizedPair? {
  switch provider.id {
  case .adyen where provider.methods.contains(.card):
    return RecognizedPair(
      provider: .adyen,
      method: .card,
      index: 0,
      gbpId: "adyen-card-gbp",
      eurId: "adyen-card-eur"
    )
  case .worldpay where provider.methods.contains(.bank):
    return RecognizedPair(
      provider: .worldpay,
      method: .bank,
      index: 1,
      gbpId: "worldpay-bank-gbp",
      eurId: "worldpay-bank-eur"
    )
  default:
    return nil
  }
}

private func sanitizeGbp(_ rails: [PaymentRail]) -> [PaymentRail] {
  let adyen = rails.first { $0.provider == .adyen && $0.method == .card && $0.currency == .gbp }
  let worldpay = rails.first { $0.provider == .worldpay && $0.method == .bank && $0.currency == .gbp }
  return [
    adyen ?? PaymentRail.gbpBaseline[0],
    worldpay ?? PaymentRail.gbpBaseline[1],
  ]
}

private func displayName(_ provider: Provider) -> String {
  let trimmed = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
  if !trimmed.isEmpty { return trimmed }
  return provider.id == .adyen ? "Adyen" : "Worldpay"
}

/// Explicit currency or region lists win. When both are absent, the enabled flag unlocks EUR and keeps GBP.
private func offers(_ provider: Provider, currency: String) -> Bool {
  if let currencies = provider.currencies, !currencies.isEmpty {
    return currencies.contains { $0.uppercased() == currency }
  }
  if currency == "GBP" { return true }
  if let regions = provider.regions, !regions.isEmpty {
    return regions.contains { ["EU", "EEA", "EUR"].contains($0.uppercased()) }
  }
  return true
}

private func gbpLabel(name: String, method: PaymentMethod) -> String {
  method == .card ? "Debit card · \(name)" : "Bank payment · \(name)"
}

private func eurLabel(name: String, method: PaymentMethod) -> String {
  "\(gbpLabel(name: name, method: method)) · EUR"
}

private func eurVersion(of rail: PaymentRail) -> PaymentRail {
  let name = rail.provider == .adyen ? "Adyen" : "Worldpay"
  return PaymentRail(
    id: rail.provider == .adyen ? "adyen-card-eur" : "worldpay-bank-eur",
    provider: rail.provider,
    method: rail.method,
    currency: .eur,
    label: eurLabel(name: name, method: rail.method)
  )
}
