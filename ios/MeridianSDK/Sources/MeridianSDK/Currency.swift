import Foundation

/// ISO currency codes the mobile SDK can store.
/// Live rehearsal payments remain integer GBP pence. EUR values stay in `EURStore`
/// and are not submitted to the Java API, which still accepts GBP minor units only.
public enum CurrencyCode: String, Codable, Hashable, CaseIterable {
  case gbp = "GBP"
  case eur = "EUR"
}

/// Integer minor units: pence for GBP, cents for EUR.
/// The amount is never stored as a binary floating-point number.
public struct MonetaryAmount: Codable, Hashable {
  public let minorUnits: Int
  public let currency: CurrencyCode

  public init(minorUnits: Int, currency: CurrencyCode) {
    self.minorUnits = minorUnits
    self.currency = currency
  }

  public var formatted: String {
    formatMonetaryAmount(self)
  }
}

/// Baseline provider record. Only Adyen (card) and Worldpay (bank) exist.
/// Currency support on the baseline is GBP; no European provider is contracted.
public struct DynamicProvider: Codable, Hashable {
  public let id: ProviderId
  public let name: String
  public let methods: [PaymentMethod]
  public let currencies: [CurrencyCode]

  public init(
    id: ProviderId,
    name: String,
    methods: [PaymentMethod],
    currencies: [CurrencyCode]
  ) {
    self.id = id
    self.name = name
    self.methods = methods
    self.currencies = currencies
  }

  public static let adyenCard = DynamicProvider(
    id: .adyen,
    name: "Adyen",
    methods: [.card],
    currencies: [.gbp]
  )

  public static let worldpayBank = DynamicProvider(
    id: .worldpay,
    name: "Worldpay",
    methods: [.bank],
    currencies: [.gbp]
  )

  public static let baseline: [DynamicProvider] = [adyenCard, worldpayBank]
}

/// EUR payment record. `EuropeanTransaction` is the same type.
/// Amount currency is EUR. The provider id is still the Adyen/Worldpay baseline.
public struct EuropeanPaymentTransaction: Codable, Hashable {
  public let id: String
  public let reference: String
  public let recipientId: String
  public let amount: MonetaryAmount
  public let provider: DynamicProvider
  public let method: PaymentMethod
  public let status: TransactionStatus
  public let note: String
  public let idempotencyKey: String

  private enum CodingKeys: String, CodingKey {
    case id
    case reference
    case recipientId
    case amount
    case provider
    case method
    case status
    case note
    case idempotencyKey
  }

  public init(
    id: String,
    reference: String,
    recipientId: String,
    amount: MonetaryAmount,
    provider: DynamicProvider,
    method: PaymentMethod,
    status: TransactionStatus,
    note: String = "",
    idempotencyKey: String = ""
  ) throws {
    try Self.validate(amount)
    self.id = id
    self.reference = reference
    self.recipientId = recipientId
    self.amount = amount
    self.provider = provider
    self.method = method
    self.status = status
    self.note = note
    self.idempotencyKey = idempotencyKey
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(String.self, forKey: .id)
    let reference = try container.decode(String.self, forKey: .reference)
    let recipientId = try container.decode(String.self, forKey: .recipientId)
    let amount = try container.decode(MonetaryAmount.self, forKey: .amount)
    try Self.validate(amount)
    let provider = try container.decode(DynamicProvider.self, forKey: .provider)
    let method = try container.decode(PaymentMethod.self, forKey: .method)
    let status = try container.decode(TransactionStatus.self, forKey: .status)
    let note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    let idempotencyKey = try container.decodeIfPresent(String.self, forKey: .idempotencyKey) ?? ""
    self.id = id
    self.reference = reference
    self.recipientId = recipientId
    self.amount = amount
    self.provider = provider
    self.method = method
    self.status = status
    self.note = note
    self.idempotencyKey = idempotencyKey
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(reference, forKey: .reference)
    try container.encode(recipientId, forKey: .recipientId)
    try container.encode(amount, forKey: .amount)
    try container.encode(provider, forKey: .provider)
    try container.encode(method, forKey: .method)
    try container.encode(status, forKey: .status)
    try container.encode(note, forKey: .note)
    try container.encode(idempotencyKey, forKey: .idempotencyKey)
  }

  private static func validate(_ amount: MonetaryAmount) throws {
    guard amount.currency == .eur else {
      throw MeridianError.validationError("EuropeanPaymentTransaction requires EUR")
    }
  }

  public func cachedRecord() -> CachedPaymentRecord {
    CachedPaymentRecord(
      id: id,
      minorUnits: amount.minorUnits,
      currency: amount.currency,
      reference: reference,
      recipientId: recipientId,
      providerId: provider.id,
      method: method,
      status: status,
      note: note,
      idempotencyKey: idempotencyKey
    )
  }
}

public typealias EuropeanTransaction = EuropeanPaymentTransaction

/// Formats minor units with integer arithmetic.
/// 0 -> "£0.00" / "€0.00", 1 -> "£0.01" / "€0.01", 1_000_000 EUR -> "€10,000.00".
public func formatMonetaryAmount(_ amount: MonetaryAmount) -> String {
  let negative = amount.minorUnits < 0
  let units = amount.minorUnits < 0 ? -amount.minorUnits : amount.minorUnits
  let major = units / 100
  let minor = units % 100
  let symbol = amount.currency == .gbp ? "£" : "€"
  let sign = negative ? "-" : ""
  return "\(sign)\(symbol)\(groupedMajorUnits(major)).\(String(format: "%02d", minor))"
}

func groupedMajorUnits(_ value: Int) -> String {
  let digits = String(value)
  var grouped = ""
  for (index, character) in digits.reversed().enumerated() {
    if index != 0 && index % 3 == 0 {
      grouped.append(",")
    }
    grouped.append(character)
  }
  return String(grouped.reversed())
}
