import Foundation

/// Consumer contract for catalog and payment-intent payloads.
/// Legacy documents use integer GBP pence. Newer documents use a money
/// object. Only GBP with minor unit 2 is payable. Card stays Adyen and
/// bank stays Worldpay.
public enum ConsumerContract {
  public static let version = "1"
  public static let acceptedCurrency = "GBP"

  public static func evaluateCatalog(_ data: Data) -> ContractResult {
    guard let root = jsonObject(data) else {
      return rejected("MALFORMED_CATALOG", "invalid_json")
    }
    return evaluateCatalogObject(root)
  }

  public static func evaluatePaymentIntent(_ data: Data) -> ContractResult {
    guard let root = jsonObject(data) else {
      return rejected("MALFORMED_INTENT", "invalid_json")
    }
    return evaluateIntentObject(root)
  }

  public static func evaluateTransaction(_ data: Data) -> ContractResult {
    guard let root = jsonObject(data) else {
      return rejected("MALFORMED_AMOUNT", "invalid_json")
    }
    guard let amount = root["amount"] else {
      return rejected("MALFORMED_AMOUNT", "missing_amount")
    }
    switch parseMoneyJSON(amount) {
    case let .success(money):
      let provider = root["provider"] as? String
      let method = root["method"] as? String
      return accepted(
        currency: money.currency,
        minorUnit: 2,
        amountMinor: money.minor,
        legacyShape: money.legacyShape,
        method: method,
        provider: provider
      )
    case let .failure(error):
      return rejected(error.code, error.message)
    }
  }

  /// Outbound payments stay on the legacy integer field so the Java API
  /// contract is unchanged.
  public static func encodeLegacyPaymentIntent(
    recipientId: String,
    amountMinor: Int,
    method: String,
    note: String,
    scenario: String
  ) throws -> Data {
    let payload: [String: Any] = [
      "recipientId": recipientId,
      "amountMinor": amountMinor,
      "method": method,
      "note": note,
      "scenario": scenario,
    ]
    return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
  }
}

public struct ContractResult: Equatable {
  public let accepted: Bool
  public let code: String
  public let detail: String
  public let currency: String?
  public let minorUnit: Int?
  public let amountMinor: Int?
  public let legacyShape: Bool?
  public let providerIds: [String]
  public let recipientIds: [String]
  public let method: String?
  public let provider: String?
}

public struct ContractRejection: Error, Equatable {
  public let code: String
  public let message: String
  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

struct ParsedMoney: Equatable {
  let minor: Int
  let currency: String
  let legacyShape: Bool
}

struct FlexibleMoney: Decodable {
  let minor: Int
  let currency: String
  let legacyShape: Bool

  private enum CodingKeys: String, CodingKey { case minor, currency, minorUnit }

  init(from decoder: Decoder) throws {
    if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
       keyed.contains(.minor) || keyed.contains(.currency) {
      let minor = try keyed.decode(Int.self, forKey: .minor)
      let currency = try keyed.decode(String.self, forKey: .currency)
      if let minorUnit = try keyed.decodeIfPresent(Int.self, forKey: .minorUnit), minorUnit != 2 {
        throw DecodingError.dataCorruptedError(forKey: .minorUnit, in: keyed, debugDescription: "INVALID_MINOR_UNIT")
      }
      guard currency == ConsumerContract.acceptedCurrency else {
        throw DecodingError.dataCorruptedError(forKey: .currency, in: keyed, debugDescription: "UNSUPPORTED_CURRENCY")
      }
      self.minor = minor
      self.currency = currency
      legacyShape = false
      return
    }
    let container = try decoder.singleValueContainer()
    if let minor = try? container.decode(Int.self) {
      self.minor = minor
      currency = ConsumerContract.acceptedCurrency
      legacyShape = true
      return
    }
    throw DecodingError.dataCorruptedError(in: container, debugDescription: "MALFORMED_AMOUNT")
  }
}

extension CatalogResponse {
  public func assertConsumerContract() throws {
    let result = validateCatalogFields(
      demoDate: demoDate,
      currency: currency,
      minorUnit: minorUnit,
      legacyShape: false,
      recipients: recipients.map {
        RecipientDraft(id: $0.id, name: $0.name, initials: $0.initials, detail: $0.detail, category: $0.category.rawValue, color: $0.color)
      },
      providers: providers.map {
        ProviderDraft(id: $0.id.rawValue, name: $0.name, description: $0.description, methods: $0.methods.map(\.rawValue))
      }
    )
    guard result.accepted else {
      throw ContractRejection(code: result.code, message: result.detail)
    }
  }
}

struct RecipientDraft {
  let id: String
  let name: String
  let initials: String
  let detail: String
  let category: String
  let color: String
}

struct ProviderDraft {
  let id: String
  let name: String
  let description: String
  let methods: [String]
}

func formatGbp(_ minor: Int64) -> String {
  let negative = minor < 0
  let absMinor = negative ? -minor : minor
  let units = absMinor / 100
  let frac = Int(absMinor % 100)
  let digits = String(units)
  var grouped = ""
  for (index, character) in digits.enumerated() {
    if index > 0 && (digits.count - index) % 3 == 0 {
      grouped.append(",")
    }
    grouped.append(character)
  }
  let fracText = String(format: "%02d", frac)
  let body = "£\(grouped).\(fracText)"
  return negative ? "-" + body : body
}

private func jsonObject(_ data: Data) -> [String: Any]? {
  (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

private func rejected(_ code: String, _ detail: String) -> ContractResult {
  ContractResult(
    accepted: false,
    code: code,
    detail: detail,
    currency: nil,
    minorUnit: nil,
    amountMinor: nil,
    legacyShape: nil,
    providerIds: [],
    recipientIds: [],
    method: nil,
    provider: nil
  )
}

private func accepted(
  currency: String,
  minorUnit: Int,
  amountMinor: Int?,
  legacyShape: Bool,
  providerIds: [String] = [],
  recipientIds: [String] = [],
  method: String? = nil,
  provider: String? = nil
) -> ContractResult {
  ContractResult(
    accepted: true,
    code: "OK",
    detail: "",
    currency: currency,
    minorUnit: minorUnit,
    amountMinor: amountMinor,
    legacyShape: legacyShape,
    providerIds: providerIds,
    recipientIds: recipientIds,
    method: method,
    provider: provider
  )
}

private func evaluateCatalogObject(_ root: [String: Any]) -> ContractResult {
  let legacyShape = root["currency"] == nil && root["minorUnit"] == nil
  let currency = (root["currency"] as? String) ?? "GBP"
  if root["currency"] != nil && currency != "GBP" {
    return rejected("UNSUPPORTED_CURRENCY", currency)
  }
  let minorUnit: Int
  if let rawMinor = root["minorUnit"] {
    guard let parsed = integralValue(rawMinor), parsed == 2 else {
      return rejected("INVALID_MINOR_UNIT", "minor_unit")
    }
    minorUnit = parsed
  } else {
    minorUnit = 2
  }
  guard let recipientRows = root["recipients"] as? [[String: Any]] else {
    return rejected("MALFORMED_CATALOG", "missing_recipients")
  }
  guard let providerRows = root["providers"] as? [[String: Any]] else {
    return rejected("MALFORMED_CATALOG", "missing_providers")
  }
  let recipients = recipientRows.map { row in
    RecipientDraft(
      id: row["id"] as? String ?? "",
      name: row["name"] as? String ?? "",
      initials: row["initials"] as? String ?? "",
      detail: row["detail"] as? String ?? "",
      category: row["category"] as? String ?? "",
      color: row["color"] as? String ?? ""
    )
  }
  let providers = providerRows.map { row in
    ProviderDraft(
      id: row["id"] as? String ?? "",
      name: row["name"] as? String ?? "",
      description: row["description"] as? String ?? "",
      methods: stringArray(row["methods"])
    )
  }
  return validateCatalogFields(
    demoDate: root["demoDate"] as? String ?? "",
    currency: currency,
    minorUnit: minorUnit,
    legacyShape: legacyShape,
    recipients: recipients,
    providers: providers
  )
}

func validateCatalogFields(
  demoDate: String,
  currency: String,
  minorUnit: Int,
  legacyShape: Bool,
  recipients: [RecipientDraft],
  providers: [ProviderDraft]
) -> ContractResult {
  if currency != "GBP" {
    return rejected("UNSUPPORTED_CURRENCY", currency)
  }
  if minorUnit != 2 {
    return rejected("INVALID_MINOR_UNIT", "minor_unit")
  }
  var issues: [String] = []
  if demoDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    issues.append("missing_demo_date")
  }
  if recipients.isEmpty {
    issues.append("empty_recipients")
  }
  let categories: Set<String> = ["Shopping", "Food & drink", "Transport", "Bills", "Lifestyle"]
  var seenRecipients: [String] = []
  for recipient in recipients {
    let id = recipient.id.trimmingCharacters(in: .whitespacesAndNewlines)
    if id.isEmpty {
      issues.append("empty_recipient_id")
    } else if seenRecipients.contains(id) {
      issues.append("duplicate_recipient")
    } else {
      seenRecipients.append(id)
    }
    if recipient.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("missing_name") }
    if recipient.initials.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("missing_initials") }
    if recipient.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("missing_detail") }
    if recipient.color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("missing_color") }
    if !categories.contains(recipient.category) { issues.append("unknown_category") }
  }
  let baseline = ["adyen": ["card"], "worldpay": ["bank"]]
  var seenProviders: [String] = []
  for provider in providers {
    if let expected = baseline[provider.id] {
      if provider.methods != expected { issues.append("provider_method_mismatch") }
      if provider.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("missing_provider_name") }
      if provider.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("missing_provider_description") }
      if seenProviders.contains(provider.id) {
        issues.append("duplicate_provider")
      } else {
        seenProviders.append(provider.id)
      }
    } else {
      issues.append("unknown_provider")
    }
  }
  if !seenProviders.contains("adyen") || !seenProviders.contains("worldpay") {
    issues.append("missing_baseline_provider")
  }
  if !issues.isEmpty {
    return rejected("MALFORMED_CATALOG", issues.joined(separator: ","))
  }
  return accepted(
    currency: "GBP",
    minorUnit: 2,
    amountMinor: nil,
    legacyShape: legacyShape,
    providerIds: seenProviders.sorted(),
    recipientIds: seenRecipients
  )
}

private func evaluateIntentObject(_ root: [String: Any]) -> ContractResult {
  let recipientId = root["recipientId"] as? String ?? ""
  if recipientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    return rejected("MALFORMED_INTENT", "missing_recipient")
  }
  let method = root["method"] as? String ?? ""
  guard let provider = providerForMethod(method) else {
    return rejected("MALFORMED_INTENT", "unknown_method")
  }
  let scenario = root["scenario"] as? String ?? "success"
  let scenarios: Set<String> = ["success", "declined", "unavailable", "pending"]
  if !scenarios.contains(scenario) {
    return rejected("MALFORMED_INTENT", "unknown_scenario")
  }
  let note = root["note"] as? String ?? ""
  if root["note"] != nil && root["note"] as? String == nil {
    return rejected("MALFORMED_INTENT", "note_type")
  }
  if note.count > 200 {
    return rejected("MALFORMED_INTENT", "note_too_long")
  }
  let hasMinor = root["amountMinor"] != nil
  let hasObject = root["amount"] != nil
  if hasMinor && hasObject {
    return rejected("MALFORMED_INTENT", "conflicting_amount")
  }
  if !hasMinor && !hasObject {
    return rejected("MALFORMED_AMOUNT", "missing_amount")
  }
  let parsed: ParsedMoney
  if hasMinor {
    guard let minor = integralValue(root["amountMinor"]!) else {
      return rejected("MALFORMED_AMOUNT", "fractional_minor")
    }
    if minor <= 0 || minor > 1_000_000 {
      return rejected("MALFORMED_AMOUNT", "amount_out_of_range")
    }
    parsed = ParsedMoney(minor: minor, currency: "GBP", legacyShape: true)
  } else {
    switch parseMoneyJSON(root["amount"]!) {
    case let .success(money):
      if money.legacyShape {
        return rejected("MALFORMED_AMOUNT", "amount_shape")
      }
      if money.minor <= 0 || money.minor > 1_000_000 {
        return rejected("MALFORMED_AMOUNT", "amount_out_of_range")
      }
      parsed = money
    case let .failure(error):
      return rejected(error.code, error.message)
    }
  }
  return accepted(
    currency: parsed.currency,
    minorUnit: 2,
    amountMinor: parsed.minor,
    legacyShape: parsed.legacyShape,
    method: method,
    provider: provider
  )
}

func stringArray(_ value: Any?) -> [String] {
  if let strings = value as? [String] { return strings }
  if let items = value as? [Any] { return items.compactMap { $0 as? String } }
  return []
}

func providerForMethod(_ method: String) -> String? {
  switch method {
  case "card":
    return "adyen"
  case "bank":
    return "worldpay"
  default:
    return nil
  }
}

func parseMoneyJSON(_ value: Any) -> Result<ParsedMoney, ContractRejection> {
  if let object = value as? [String: Any] {
    guard let minor = object["minor"].flatMap(integralValue) else {
      return .failure(ContractRejection(code: "MALFORMED_AMOUNT", message: "fractional_minor"))
    }
    guard let currency = object["currency"] as? String else {
      return .failure(ContractRejection(code: "MALFORMED_AMOUNT", message: "missing_currency"))
    }
    if currency != "GBP" {
      return .failure(ContractRejection(code: "UNSUPPORTED_CURRENCY", message: currency))
    }
    if let rawUnit = object["minorUnit"] {
      guard let unit = integralValue(rawUnit), unit == 2 else {
        return .failure(ContractRejection(code: "INVALID_MINOR_UNIT", message: "minor_unit"))
      }
    }
    return .success(ParsedMoney(minor: minor, currency: "GBP", legacyShape: false))
  }
  if let minor = integralValue(value) {
    return .success(ParsedMoney(minor: minor, currency: "GBP", legacyShape: true))
  }
  return .failure(ContractRejection(code: "MALFORMED_AMOUNT", message: "fractional_minor"))
}

func integralValue(_ value: Any) -> Int? {
  if value is Bool { return nil }
  guard let number = value as? NSNumber else { return nil }
  let double = number.doubleValue
  guard double.isFinite, double.rounded() == double else { return nil }
  guard double <= Double(Int.max), double >= Double(Int.min) else { return nil }
  let text = number.stringValue.lowercased()
  if text.contains("e") { return nil }
  if text.contains(".") {
    let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    if parts.count == 2 && parts[1].contains(where: { $0 != "0" }) { return nil }
  }
  return Int(double)
}

public func layoutDirectionForLanguage(_ language: String) -> String {
  let code = language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? language.lowercased()
  switch code {
  case "ar", "he", "fa", "ur", "dv", "ps":
    return "rtl"
  default:
    return "ltr"
  }
}

public func fontScaleFor(bucket: String) -> Double {
  switch bucket {
  case "large":
    return 1.3
  case "accessibility":
    return 2.0
  default:
    return 1.0
  }
}

public func scaledFontSize(base: Double, fontScale: Double) -> Double {
  let clamped = min(3.0, max(1.0, fontScale))
  return (base * clamped * 10).rounded() / 10
}

public struct AccessibilityDescriptor: Equatable {
  public let platform: String
  public let label: String
  public let hint: String
  public let role: String
  public let fontScale: Double
  public let scaledFontPt: Double
  public let layoutDirection: String
  public let minimumTouchTargetPt: Int
  public let mirrorsInRightToLeft: Bool
}

public func paymentConfirmationAccessibility(
  amountLabel: String,
  recipientName: String,
  method: String,
  language: String,
  fontScale: Double,
  platform: String
) -> AccessibilityDescriptor {
  let methodPhrase = method == "bank" ? "bank payment, Worldpay" : "debit card, Adyen"
  let minimum = platform == "talkback" ? 48 : 44
  return AccessibilityDescriptor(
    platform: platform,
    label: "Confirm payment of \(amountLabel) to \(recipientName) using \(methodPhrase)",
    hint: "Submits the fictional rehearsal payment. No real money moves.",
    role: "button",
    fontScale: fontScale,
    scaledFontPt: scaledFontSize(base: 38, fontScale: fontScale),
    layoutDirection: layoutDirectionForLanguage(language),
    minimumTouchTargetPt: minimum,
    mirrorsInRightToLeft: true
  )
}
