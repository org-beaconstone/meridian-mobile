import Foundation

public struct CatalogRecipient: Equatable {
  public let id: String
  public let name: String
  public let initials: String
  public let detail: String
  public let category: String
  public let color: String
  public let price: Money?

  public init(id: String, name: String, initials: String, detail: String, category: String, color: String, price: Money?) {
    self.id = id
    self.name = name
    self.initials = initials
    self.detail = detail
    self.category = category
    self.color = color
    self.price = price
  }
}

public struct CatalogProvider: Equatable {
  public let id: String
  public let name: String
  public let description: String
  public let methods: [String]

  public init(id: String, name: String, description: String, methods: [String]) {
    self.id = id
    self.name = name
    self.description = description
    self.methods = methods
  }
}

public struct CatalogDocument: Equatable {
  public let demoDate: String
  public let recipients: [CatalogRecipient]
  public let providers: [CatalogProvider]

  public init(demoDate: String, recipients: [CatalogRecipient], providers: [CatalogProvider]) {
    self.demoDate = demoDate
    self.recipients = recipients
    self.providers = providers
  }
}

public struct PaymentIntent: Equatable {
  public let recipientId: String
  public let money: Money
  public let method: String
  public let note: String
  public let scenario: String

  public init(recipientId: String, money: Money, method: String, note: String, scenario: String) {
    self.recipientId = recipientId
    self.money = money
    self.method = method
    self.note = note
    self.scenario = scenario
  }

  public var submittable: Bool {
    if let pence = money.gbpPence { return (1...1_000_000).contains(pence) }
    return false
  }

  public var wireAmountMinor: Int? {
    submittable ? money.gbpPence : nil
  }
}

private let catalogCategories: Set<String> = ["Shopping", "Food & drink", "Transport", "Bills", "Lifestyle"]
private let providerMethods = ["adyen": ["card"], "worldpay": ["bank"]]
private let providerNames = ["adyen": "Adyen", "worldpay": "Worldpay"]
private let knownScenarios: Set<String> = ["success", "declined", "unavailable", "pending"]

public func decodeCatalog(_ value: Any) -> Result<CatalogDocument, ContractError> {
  guard let node = Json.object(value) else {
    return .failure(ContractError(code: "MALFORMED_CATALOG", message: "Catalog must be an object"))
  }
  guard let demoDate = Json.string(node["demoDate"]) else {
    return .failure(ContractError(code: "MALFORMED_CATALOG", message: "demoDate is required"))
  }
  guard isCalendarDate(demoDate) else {
    return .failure(ContractError(code: "MALFORMED_CATALOG", message: "demoDate is not a calendar date"))
  }
  guard let recipientNodes = Json.array(node["recipients"]) else {
    return .failure(ContractError(code: "MALFORMED_CATALOG", message: "recipients are required"))
  }
  guard let providerNodes = Json.array(node["providers"]) else {
    return .failure(ContractError(code: "MALFORMED_CATALOG", message: "providers are required"))
  }
  var recipients: [CatalogRecipient] = []
  var seenIds = Set<String>()
  for recipient in recipientNodes {
    switch decodeRecipient(recipient) {
    case let .failure(error): return .failure(error)
    case let .success(value):
      if !seenIds.insert(value.id).inserted {
        return .failure(ContractError(code: "MALFORMED_CATALOG", message: "Duplicate recipient"))
      }
      recipients.append(value)
    }
  }
  var providers: [CatalogProvider] = []
  var seenProviders = Set<String>()
  for provider in providerNodes {
    guard let object = Json.object(provider), let id = Json.string(object["id"]) else {
      return .failure(ContractError(code: "MALFORMED_CATALOG", message: "Provider id is required"))
    }
    guard providerMethods[id] != nil else {
      return .failure(ContractError(code: "UNKNOWN_PROVIDER", message: "Provider is not in the mobile baseline"))
    }
    if !seenProviders.insert(id).inserted {
      return .failure(ContractError(code: "MALFORMED_CATALOG", message: "Duplicate provider"))
    }
    let name = Json.string(object["name"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let description = Json.string(object["description"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let methods = (Json.array(object["methods"]) ?? []).compactMap { Json.string($0) }
    if name != providerNames[id] || description.isEmpty || Json.array(object["methods"]) == nil || methods != providerMethods[id] {
      return .failure(ContractError(code: "MALFORMED_CATALOG", message: "Provider fields are invalid"))
    }
    providers.append(CatalogProvider(id: id, name: name, description: description, methods: methods))
  }
  if seenProviders != Set(providerMethods.keys) {
    return .failure(ContractError(code: "MALFORMED_CATALOG", message: "Catalog must list Adyen and Worldpay"))
  }
  return .success(CatalogDocument(demoDate: demoDate, recipients: recipients, providers: providers))
}

private func decodeRecipient(_ value: Any) -> Result<CatalogRecipient, ContractError> {
  guard let node = Json.object(value) else {
    return .failure(ContractError(code: "MALFORMED_CATALOG", message: "Recipient must be an object"))
  }
  let id = Json.string(node["id"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  let name = Json.string(node["name"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  let initials = Json.string(node["initials"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  let detail = Json.string(node["detail"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  let category = Json.string(node["category"]) ?? ""
  let color = Json.string(node["color"]) ?? ""
  if !Json.matches("^[a-z0-9-]{1,64}$", id) || name.isEmpty || name.count > 80 || name.unicodeScalars.contains(where: { $0.value < 32 }) {
    return .failure(ContractError(code: "MALFORMED_CATALOG", message: "Recipient fields are invalid"))
  }
  if !Json.matches("^[A-Za-z0-9]{1,4}$", initials) || detail.isEmpty || detail.count > 120 || !catalogCategories.contains(category) || !Json.matches("^#[0-9A-Fa-f]{6}$", color) {
    return .failure(ContractError(code: "MALFORMED_CATALOG", message: "Recipient fields are invalid"))
  }
  let price: Money?
  if Json.isNull(node["price"]) {
    price = nil
  } else if let raw = node["price"] {
    switch decodeMoney(raw) {
    case let .failure(error): return .failure(error)
    case let .success(money): price = money
    }
  } else {
    price = nil
  }
  return .success(CatalogRecipient(id: id, name: name, initials: initials, detail: detail, category: category, color: color, price: price))
}

public func decodePaymentIntent(_ value: Any) -> Result<PaymentIntent, ContractError> {
  guard let node = Json.object(value) else {
    return .failure(ContractError(code: "MALFORMED_INTENT", message: "Payment intent must be an object"))
  }
  let recipientId = Json.string(node["recipientId"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  guard Json.matches("^[a-z0-9-]{1,64}$", recipientId) else {
    return .failure(ContractError(code: "MALFORMED_INTENT", message: "Recipient is invalid"))
  }
  guard let method = Json.string(node["method"]), method == "card" || method == "bank" else {
    return .failure(ContractError(code: "MALFORMED_INTENT", message: "Payment method is invalid"))
  }
  let note: String
  if Json.isNull(node["note"]) {
    note = ""
  } else if let text = Json.string(node["note"]) {
    note = text
  } else {
    return .failure(ContractError(code: "MALFORMED_INTENT", message: "Note is invalid"))
  }
  if note.count > 200 { return .failure(ContractError(code: "MALFORMED_INTENT", message: "Note is too long")) }
  let scenario: String
  if Json.isNull(node["scenario"]) {
    scenario = "success"
  } else if let text = Json.string(node["scenario"]) {
    scenario = text
  } else {
    return .failure(ContractError(code: "MALFORMED_INTENT", message: "Scenario is invalid"))
  }
  guard knownScenarios.contains(scenario) else {
    return .failure(ContractError(code: "MALFORMED_INTENT", message: "Scenario is invalid"))
  }
  if Json.isNull(node["amountMinor"]) && Json.isNull(node["money"]) {
    return .failure(ContractError(code: "MISSING_AMOUNT", message: "Amount is required"))
  }
  let legacy: Money?
  if let raw = node["amountMinor"], !(raw is NSNull) {
    switch decodeMoney(raw) {
    case let .failure(error): return .failure(error)
    case let .success(money): legacy = money
    }
  } else {
    legacy = nil
  }
  let modern: Money?
  if let raw = node["money"], !(raw is NSNull) {
    switch decodeMoney(raw) {
    case let .failure(error): return .failure(error)
    case let .success(money): modern = money
    }
  } else {
    modern = nil
  }
  let money: Money
  if let legacy, let modern {
    if modern.currency != "GBP" || modern.exponent != 2 || modern.minor != legacy.minor {
      return .failure(ContractError(code: "CONFLICTING_AMOUNT", message: "Integer amount and money object disagree"))
    }
    money = modern
  } else if let modern {
    money = modern
  } else if let legacy {
    money = legacy
  } else {
    return .failure(ContractError(code: "MISSING_AMOUNT", message: "Amount is required"))
  }
  return .success(PaymentIntent(recipientId: recipientId, money: money, method: method, note: note, scenario: scenario))
}

public func decodeLiveCatalog(_ catalog: CatalogResponse) -> Result<CatalogDocument, ContractError> {
  do {
    let data = try JSONEncoder().encode(catalog)
    let object = try JSONSerialization.jsonObject(with: data)
    return decodeCatalog(object)
  } catch {
    return .failure(ContractError(code: "MALFORMED_CATALOG", message: "Catalog could not be encoded"))
  }
}

public func validateLiveCatalog(_ catalog: CatalogResponse) -> ContractError? {
  if case let .failure(error) = decodeLiveCatalog(catalog) { return error }
  return nil
}

func liveCatalogRoundTripFailure() -> String? {
  let catalog = CatalogResponse(
    demoDate: "2026-09-18",
    recipients: [
      Recipient(id: "northline-studio", name: "Northline Studio", initials: "NS", detail: "Design tools & materials", category: .shopping, color: "#FF6B6B"),
      Recipient(id: "birch-bloom", name: "Birch & Bloom", initials: "BB", detail: "Organic café & bistro", category: .foodDrink, color: "#FFD93D"),
    ],
    providers: [
      Provider(id: .adyen, name: "Adyen", description: "Card payment processor", methods: [.card]),
      Provider(id: .worldpay, name: "Worldpay", description: "Bank transfer processor", methods: [.bank]),
    ]
  )
  if let error = validateLiveCatalog(catalog) {
    return "live-catalog \(error.code): \(error.message)"
  }
  return nil
}
