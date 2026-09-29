import CoreFoundation
import Foundation

/// Hard cap so a catalog response cannot be cached unbounded.
let maxCatalogBytes = 256 * 1024

/// Capability token that forces fail-closed expiry even when the boolean is absent or false.
let liveEligibilityCapability = "live_eligibility"

/// Cache and request key. Currency is GBP only; amounts elsewhere stay integer pence.
/// Provider ids are open strings. The native baseline remains Adyen card and Worldpay bank.
public struct CatalogScope: Hashable {
  public let accountScope: String
  public let corridor: String
  public let currency: String

  public var storageKey: String { "\(accountScope)|\(corridor)|\(currency)" }

  public init(accountScope: String, corridor: String, currency: String) {
    self.accountScope = accountScope
    self.corridor = corridor
    self.currency = currency
  }

  public static func parse(accountScope: String, corridor: String, currency: String) throws -> CatalogScope {
    let scope = accountScope.trimmingCharacters(in: .whitespacesAndNewlines)
    let corridorNorm = asciiUppercased(corridor.trimmingCharacters(in: .whitespacesAndNewlines))
    let currencyNorm = asciiUppercased(currency.trimmingCharacters(in: .whitespacesAndNewlines))
    guard wholeMatch(scope, pattern: "^[A-Za-z0-9._:-]{1,64}$") else {
      throw MeridianError.validationError("Account scope is invalid")
    }
    guard wholeMatch(corridorNorm, pattern: "^[A-Z0-9_-]{2,16}$") else {
      throw MeridianError.validationError("Corridor is invalid")
    }
    guard currencyNorm == "GBP" else {
      throw MeridianError.validationError("Only GBP payment catalogs are supported")
    }
    return CatalogScope(accountScope: scope, corridor: corridorNorm, currency: currencyNorm)
  }
}

/// Open payment-method record. Unknown JSON attributes are ignored so older builds keep decoding.
/// Method and provider stay strings so a new value does not crash a closed enum.
public struct PaymentMethodDescriptor: Hashable {
  public let id: String
  public let method: String
  public let provider: String
  public let displayName: String
  public let currency: String
  public let corridor: String
  public let accountScope: String
  public let capabilities: [String]
  public let requiresLiveEligibility: Bool
  public let ttlSeconds: Int
  public let enabled: Bool

  public init(
    id: String,
    method: String,
    provider: String,
    displayName: String,
    currency: String,
    corridor: String,
    accountScope: String,
    capabilities: [String],
    requiresLiveEligibility: Bool,
    ttlSeconds: Int,
    enabled: Bool
  ) {
    self.id = id
    self.method = method
    self.provider = provider
    self.displayName = displayName
    self.currency = currency
    self.corridor = corridor
    self.accountScope = accountScope
    self.capabilities = capabilities
    self.requiresLiveEligibility = requiresLiveEligibility
    self.ttlSeconds = ttlSeconds
    self.enabled = enabled
  }
}

public struct PaymentMethodsCatalog: Hashable {
  public let accountScope: String
  public let corridor: String
  public let currency: String
  public let ttlSeconds: Int
  public let methods: [PaymentMethodDescriptor]

  public init(
    accountScope: String,
    corridor: String,
    currency: String,
    ttlSeconds: Int,
    methods: [PaymentMethodDescriptor]
  ) {
    self.accountScope = accountScope
    self.corridor = corridor
    self.currency = currency
    self.ttlSeconds = ttlSeconds
    self.methods = methods
  }
}

public struct PaymentMethodsFetch {
  public let catalog: PaymentMethodsCatalog
  public let rawJSON: Data

  public init(catalog: PaymentMethodsCatalog, rawJSON: Data) {
    self.catalog = catalog
    self.rawJSON = rawJSON
  }
}

/// `GET /api/v2/payment-methods` against the same origin as an `/api/v1` base URL.
func paymentMethodsURL(baseURL: String, scope: CatalogScope) throws -> URL {
  var normalized = baseURL
  while normalized.hasSuffix("/") {
    normalized.removeLast()
  }
  if normalized.hasSuffix("/api/v1") {
    normalized.removeLast("/api/v1".count)
  } else if normalized.hasSuffix("/api/v2") {
    normalized.removeLast("/api/v2".count)
  }
  while normalized.hasSuffix("/") {
    normalized.removeLast()
  }
  guard normalized.hasPrefix("http://") || normalized.hasPrefix("https://") else {
    throw MeridianError.invalidURL
  }
  guard var components = URLComponents(string: normalized + "/api/v2/payment-methods") else {
    throw MeridianError.invalidURL
  }
  components.queryItems = [
    URLQueryItem(name: "accountScope", value: scope.accountScope),
    URLQueryItem(name: "corridor", value: scope.corridor),
    URLQueryItem(name: "currency", value: scope.currency),
  ]
  guard let url = components.url else {
    throw MeridianError.invalidURL
  }
  return url
}

/// Deserialize a catalog. Extra attributes are ignored. A single bad descriptor is skipped.
func parsePaymentMethodsCatalog(_ data: Data, expected: CatalogScope) throws -> PaymentMethodsCatalog {
  guard data.count <= maxCatalogBytes else {
    throw MeridianError.validationError("Payment method catalog is too large")
  }
  let rootAny: Any
  do {
    rootAny = try JSONSerialization.jsonObject(with: data, options: [])
  } catch {
    throw MeridianError.decodingError("Payment method catalog is not valid JSON")
  }
  guard let root = rootAny as? [String: Any] else {
    throw MeridianError.decodingError("Payment method catalog must be an object")
  }

  guard let accountScope = requiredText(root["accountScope"]) else {
    throw MeridianError.decodingError("Payment method catalog is missing account scope")
  }
  guard accountScope == expected.accountScope else {
    throw MeridianError.validationError("Payment method catalog account scope does not match the request")
  }

  guard let corridor = requiredText(root["corridor"]).map(asciiUppercased) else {
    throw MeridianError.decodingError("Payment method catalog is missing corridor")
  }
  guard corridor == expected.corridor else {
    throw MeridianError.validationError("Payment method catalog corridor does not match the request")
  }

  guard let currency = requiredText(root["currency"]).map(asciiUppercased) else {
    throw MeridianError.decodingError("Payment method catalog is missing currency")
  }
  guard currency == expected.currency else {
    throw MeridianError.validationError("Only GBP payment catalogs are supported")
  }

  guard let ttlSeconds = positiveInt(root["ttlSeconds"]) else {
    throw MeridianError.decodingError("Payment method catalog TTL is invalid")
  }

  guard let methodsNode = root["methods"] as? [Any] else {
    throw MeridianError.decodingError("Payment method catalog is missing methods")
  }

  var methods: [PaymentMethodDescriptor] = []
  for item in methodsNode {
    if let descriptor = parseDescriptor(item, expected: expected, catalogTtl: ttlSeconds) {
      methods.append(descriptor)
    }
  }

  return PaymentMethodsCatalog(
    accountScope: accountScope,
    corridor: corridor,
    currency: currency,
    ttlSeconds: ttlSeconds,
    methods: methods
  )
}

private func parseDescriptor(
  _ item: Any,
  expected: CatalogScope,
  catalogTtl: Int
) -> PaymentMethodDescriptor? {
  guard let object = item as? [String: Any] else { return nil }
  guard
    let id = requiredText(object["id"]),
    let method = requiredText(object["method"]),
    let provider = requiredText(object["provider"]),
    let displayName = requiredText(object["displayName"])
  else { return nil }

  let currency: String
  if object.keys.contains("currency") {
    guard let value = requiredText(object["currency"]).map(asciiUppercased), value == expected.currency else {
      return nil
    }
    currency = value
  } else {
    currency = expected.currency
  }

  let corridor: String
  if object.keys.contains("corridor") {
    guard let value = requiredText(object["corridor"]).map(asciiUppercased), value == expected.corridor else {
      return nil
    }
    corridor = value
  } else {
    corridor = expected.corridor
  }

  let accountScope: String
  if object.keys.contains("accountScope") {
    guard let value = requiredText(object["accountScope"]), value == expected.accountScope else {
      return nil
    }
    accountScope = value
  } else {
    accountScope = expected.accountScope
  }

  let capabilities: [String]
  if object.keys.contains("capabilities") {
    guard let raw = object["capabilities"] as? [Any] else { return nil }
    capabilities = raw.compactMap { requiredText($0) }
  } else {
    capabilities = []
  }

  let liveFlag: Bool
  if object.keys.contains("requiresLiveEligibility") {
    guard let value = jsonBool(object["requiresLiveEligibility"]) else { return nil }
    liveFlag = value
  } else {
    liveFlag = false
  }
  let requiresLiveEligibility = liveFlag || capabilities.contains(liveEligibilityCapability)

  let ttlSeconds: Int
  if object.keys.contains("ttlSeconds") {
    guard let value = positiveInt(object["ttlSeconds"]) else { return nil }
    ttlSeconds = value
  } else {
    ttlSeconds = catalogTtl
  }

  let enabled: Bool
  if object.keys.contains("enabled") {
    guard let value = jsonBool(object["enabled"]) else { return nil }
    enabled = value
  } else {
    enabled = true
  }

  return PaymentMethodDescriptor(
    id: id,
    method: method,
    provider: provider,
    displayName: displayName,
    currency: currency,
    corridor: corridor,
    accountScope: accountScope,
    capabilities: capabilities,
    requiresLiveEligibility: requiresLiveEligibility,
    ttlSeconds: ttlSeconds,
    enabled: enabled
  )
}

private func requiredText(_ value: Any?) -> String? {
  guard let text = value as? String else { return nil }
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}

private func positiveInt(_ value: Any?) -> Int? {
  guard let value, isJSONNumber(value), let number = value as? NSNumber else { return nil }
  let double = number.doubleValue
  guard double.rounded() == double, double > 0, double <= Double(Int.max) else { return nil }
  return number.intValue
}

private func jsonBool(_ value: Any?) -> Bool? {
  guard let value, isJSONBoolean(value), let number = value as? NSNumber else { return nil }
  return number.boolValue
}

private func isJSONBoolean(_ value: Any) -> Bool {
  guard let number = value as? NSNumber else { return false }
  return CFGetTypeID(number) == CFBooleanGetTypeID()
}

private func isJSONNumber(_ value: Any) -> Bool {
  value is NSNumber && !isJSONBoolean(value)
}

private func asciiUppercased(_ value: String) -> String {
  value.uppercased(with: Locale(identifier: "en_US_POSIX"))
}

private func wholeMatch(_ value: String, pattern: String) -> Bool {
  value.range(of: pattern, options: .regularExpression) != nil
}
