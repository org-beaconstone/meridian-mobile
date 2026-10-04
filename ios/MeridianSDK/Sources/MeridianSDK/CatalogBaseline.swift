import Foundation

public enum CatalogOrigin: String {
  case network
  case cache
}

public struct CatalogLoad {
  public let catalog: CatalogResponse?
  public let origin: CatalogOrigin?

  public init(catalog: CatalogResponse?, origin: CatalogOrigin?) {
    self.catalog = catalog
    self.origin = origin
  }
}

/// Keeps checkout on Adyen card and Worldpay bank, GBP only.
/// Unknown catalog providers are dropped and are not stored.
public func projectBaselineCatalog(_ raw: CatalogResponse) -> CatalogResponse {
  var projected: [DynamicProvider] = []
  for provider in raw.providers {
    guard let baseline = baselineProvider(provider) else { continue }
    if projected.contains(where: { $0.id == baseline.id }) { continue }
    projected.append(baseline)
  }
  projected.sort { lhs, rhs in
    providerRank(lhs.id) < providerRank(rhs.id)
  }
  return CatalogResponse(
    demoDate: raw.demoDate,
    recipients: raw.recipients,
    providers: projected
  )
}

func catalogFailureUsesCache(_ error: Error) -> Bool {
  if let urlError = error as? URLError {
    switch urlError.code {
    case .timedOut,
         .notConnectedToInternet,
         .networkConnectionLost,
         .cannotConnectToHost,
         .cannotFindHost,
         .dnsLookupFailed,
         .dataNotAllowed,
         .internationalRoamingOff,
         .cannotLoadFromNetwork:
      return true
    default:
      return false
    }
  }
  if case let MeridianError.httpError(statusCode, _) = error {
    return statusCode == 408 || (500...599).contains(statusCode)
  }
  if case MeridianError.networkError = error {
    return true
  }
  return false
}

private func providerRank(_ id: String) -> Int {
  switch id {
  case ProviderId.adyen.rawValue: return 0
  case ProviderId.worldpay.rawValue: return 1
  default: return 2
  }
}

private func baselineProvider(_ provider: DynamicProvider) -> DynamicProvider? {
  let id = provider.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  let allowed: String
  let name: String
  let description: String
  switch id {
  case ProviderId.adyen.rawValue:
    allowed = PaymentMethod.card.rawValue
    name = "Adyen"
    description = "Card processor"
  case ProviderId.worldpay.rawValue:
    allowed = PaymentMethod.bank.rawValue
    name = "Worldpay"
    description = "Bank payment processor"
  default:
    return nil
  }

  let parsedMethods = provider.methods.compactMap(normalizeCatalogMethod)
  if !parsedMethods.isEmpty && !parsedMethods.contains(allowed) {
    return nil
  }

  let currencies = gbpCurrencies(provider.currencies)
  guard currencies == ["GBP"] else { return nil }

  let corridors = baselineCorridors(
    provider.corridors,
    providerId: id,
    allowedMethod: allowed
  )
  guard !corridors.isEmpty else { return nil }

  return DynamicProvider(
    id: id,
    name: name,
    description: description,
    methods: [allowed],
    currencies: currencies,
    corridors: corridors
  )
}

private func gbpCurrencies(_ raw: [String]) -> [String] {
  let codes = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty }
  if codes.isEmpty { return ["GBP"] }
  return codes.contains("GBP") ? ["GBP"] : []
}

private func baselineCorridors(
  _ raw: [PaymentCorridor],
  providerId: String,
  allowedMethod: String
) -> [PaymentCorridor] {
  var seen = Set<String>()
  var kept: [PaymentCorridor] = []
  for corridor in raw {
    guard normalizeCatalogMethod(corridor.method) == allowedMethod else { continue }
    let currency = corridor.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if !currency.isEmpty && currency != "GBP" { continue }
    let fallback = "\(providerId)-\(allowedMethod)-gbp"
    let identifier = safeToken(corridor.id, fallback: fallback, seen: &seen)
    let country = corridorCountry(corridor.country)
    kept.append(PaymentCorridor(id: identifier, method: allowedMethod, currency: "GBP", country: country))
  }
  if kept.isEmpty {
    let identifier = safeToken("", fallback: "\(providerId)-\(allowedMethod)-gbp", seen: &seen)
    kept.append(PaymentCorridor(id: identifier, method: allowedMethod, currency: "GBP", country: "GB"))
  }
  return kept
}

private func corridorCountry(_ raw: String) -> String {
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty { return "GB" }
  if trimmed.count == 2 { return trimmed.uppercased() }
  return String(trimmed.prefix(32))
}

private func safeToken(_ raw: String, fallback: String, seen: inout Set<String>) -> String {
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  let scalarsOK = trimmed.unicodeScalars.allSatisfy { scalar in
    CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
  }
  var candidate = trimmed.isEmpty || !scalarsOK || trimmed.count > 64 ? fallback : trimmed
  if candidate.isEmpty { candidate = fallback }
  var suffix = 2
  var unique = candidate
  while seen.contains(unique) {
    unique = "\(candidate)-\(suffix)"
    suffix += 1
  }
  seen.insert(unique)
  return unique
}

private func normalizeCatalogMethod(_ raw: String) -> String? {
  let value = raw
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .lowercased()
    .replacingOccurrences(of: "-", with: "_")
    .replacingOccurrences(of: " ", with: "_")
  switch value {
  case "card", "debit_card":
    return PaymentMethod.card.rawValue
  case "bank", "bank_transfer", "banktransfer":
    return PaymentMethod.bank.rawValue
  default:
    return nil
  }
}
