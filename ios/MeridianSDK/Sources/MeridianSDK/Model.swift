import Foundation

// MARK: - Domain Types

public enum Category: String, Codable, Hashable, CaseIterable {
  case shopping = "Shopping"
  case foodDrink = "Food & drink"
  case transport = "Transport"
  case bills = "Bills"
  case lifestyle = "Lifestyle"
}

public enum PaymentMethod: String, Codable, Hashable {
  case card
  case bank
}

public enum ProviderId: String, Codable, Hashable {
  case adyen
  case worldpay
}

public enum Scenario: String, Codable {
  case success
  case declined
  case unavailable
  case pending
}

/// Account currency is always GBP. EUR selects a locked conversion for the recipient.
public enum PayCurrency: String, Codable, Hashable {
  case gbp = "GBP"
  case eur = "EUR"
}

public enum TransactionStatus: String, Codable {
  case completed
  case declined
  case pending
}

// MARK: - Models

public struct Recipient: Codable, Hashable {
  public let id: String
  public let name: String
  public let initials: String
  public let detail: String
  public let category: Category
  public let color: String

  public init(
    id: String,
    name: String,
    initials: String,
    detail: String,
    category: Category,
    color: String
  ) {
    self.id = id
    self.name = name
    self.initials = initials
    self.detail = detail
    self.category = category
    self.color = color
  }
}

public struct Transaction: Codable, Hashable {
  public let id: String
  public let reference: String
  public let recipientId: String
  public let name: String
  public let category: Category
  public let amount: Int // integer GBP pence, positive (outgoing)
  public let date: String // ISO 8601
  public let provider: ProviderId
  public let method: PaymentMethod
  public let status: TransactionStatus
  public let note: String

  public init(
    id: String,
    reference: String,
    recipientId: String,
    name: String,
    category: Category,
    amount: Int,
    date: String,
    provider: ProviderId,
    method: PaymentMethod,
    status: TransactionStatus,
    note: String
  ) {
    self.id = id
    self.reference = reference
    self.recipientId = recipientId
    self.name = name
    self.category = category
    self.amount = amount
    self.date = date
    self.provider = provider
    self.method = method
    self.status = status
    self.note = note
  }
}

public struct Budget: Codable, Hashable {
  public let category: Category
  public let limit: Int // integer GBP pence

  public init(category: Category, limit: Int) {
    self.category = category
    self.limit = limit
  }
}

public struct BankState: Codable, Hashable {
  public let version: Int
  public let balance: Int // integer GBP pence
  public let transactions: [Transaction]
  public let budgets: [Budget]

  public init(
    version: Int,
    balance: Int,
    transactions: [Transaction],
    budgets: [Budget]
  ) {
    self.version = version
    self.balance = balance
    self.transactions = transactions
    self.budgets = budgets
  }
}

public struct Provider: Codable, Hashable {
  public let id: ProviderId
  public let name: String
  public let description: String
  public let methods: [PaymentMethod]

  public init(
    id: ProviderId,
    name: String,
    description: String,
    methods: [PaymentMethod]
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.methods = methods
  }
}

// MARK: - API Response Types

public struct HealthResponse: Codable {
  public let status: String
  public let service: String
  public let simulation: Bool
}

public struct CatalogResponse: Codable {
  public let demoDate: String
  public let recipients: [Recipient]
  public let providers: [Provider]
}

public struct PaymentResponse: Codable {
  public let ok: Bool
  public let state: BankState?
  public let transaction: Transaction?
  public let error: String?
  public let code: String?
  public let paymentId: String?

  enum CodingKeys: String, CodingKey {
    case ok
    case state
    case transaction
    case error
    case code
    case paymentId
  }
}

public struct BudgetResponse: Codable {
  public let ok: Bool
  public let state: BankState?
  public let error: String?
}

public struct ResetResponse: Codable {
  public let ok: Bool
  public let state: BankState?
  public let error: String?
}

public struct EventsResponse: Codable {
  public let events: [AuditEvent]
}

public struct AuditEvent: Codable {
  public let timestamp: String
  public let action: String
  public let details: String?
}

// MARK: - Request Payloads

public struct PaymentRequest: Codable {
  public let recipientId: String
  public let amountMinor: Int
  public let method: PaymentMethod
  public let note: String
  public let scenario: Scenario

  public init(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String,
    scenario: Scenario
  ) {
    self.recipientId = recipientId
    self.amountMinor = amountMinor
    self.method = method
    self.note = note
    self.scenario = scenario
  }
}

public struct BudgetRequest: Codable {
  public let category: Category
  public let limitMinor: Int

  public init(category: Category, limitMinor: Int) {
    self.category = category
    self.limitMinor = limitMinor
  }
}

/// GBP pence in, EUR cents out. The ledger debit stays `amountMinor` on the payment call.
public struct FxQuoteRequest: Encodable, Equatable {
  public let sourceCurrency: String
  public let targetCurrency: String
  public let amountMinor: Int

  public init(sourceCurrency: String, targetCurrency: String, amountMinor: Int) {
    self.sourceCurrency = sourceCurrency
    self.targetCurrency = targetCurrency
    self.amountMinor = amountMinor
  }
}

public struct FxQuote: Decodable, Equatable {
  public let quoteId: String
  public let sourceCurrency: String
  public let targetCurrency: String
  public let sourceAmountMinor: Int
  public let targetAmountMinor: Int
  public let rate: String
  public let expiresInSeconds: Int
  public let serverExpiresAt: Date?

  public init(
    quoteId: String,
    sourceCurrency: String = "GBP",
    targetCurrency: String = "EUR",
    sourceAmountMinor: Int,
    targetAmountMinor: Int,
    rate: String,
    expiresInSeconds: Int = 60,
    serverExpiresAt: Date? = nil
  ) {
    self.quoteId = quoteId
    self.sourceCurrency = sourceCurrency
    self.targetCurrency = targetCurrency
    self.sourceAmountMinor = sourceAmountMinor
    self.targetAmountMinor = targetAmountMinor
    self.rate = rate
    self.expiresInSeconds = expiresInSeconds
    self.serverExpiresAt = serverExpiresAt
  }

  private enum CodingKeys: String, CodingKey {
    case quoteId
    case id
    case sourceCurrency
    case targetCurrency
    case sourceAmountMinor
    case amountMinor
    case targetAmountMinor
    case rate
    case expiresInSeconds
    case expiresAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let quoteId = try container.decodeIfPresent(String.self, forKey: .quoteId), !quoteId.isEmpty {
      self.quoteId = quoteId
    } else if let quoteId = try container.decodeIfPresent(String.self, forKey: .id), !quoteId.isEmpty {
      self.quoteId = quoteId
    } else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "FX quote id missing")
      )
    }
    sourceCurrency = try container.decodeIfPresent(String.self, forKey: .sourceCurrency) ?? "GBP"
    targetCurrency = try container.decodeIfPresent(String.self, forKey: .targetCurrency) ?? "EUR"
    if let source = try container.decodeIfPresent(Int.self, forKey: .sourceAmountMinor) {
      sourceAmountMinor = source
    } else if let source = try container.decodeIfPresent(Int.self, forKey: .amountMinor) {
      sourceAmountMinor = source
    } else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "FX quote amount missing")
      )
    }
    guard let target = try container.decodeIfPresent(Int.self, forKey: .targetAmountMinor) else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "FX quote target amount missing")
      )
    }
    targetAmountMinor = target
    if let text = try? container.decode(String.self, forKey: .rate) {
      rate = text
    } else if let number = try? container.decode(Double.self, forKey: .rate) {
      rate = String(number)
    } else {
      rate = ""
    }
    expiresInSeconds = try container.decodeIfPresent(Int.self, forKey: .expiresInSeconds) ?? 60
    if let raw = try container.decodeIfPresent(String.self, forKey: .expiresAt) {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      serverExpiresAt = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    } else {
      serverExpiresAt = nil
    }
  }
}

// MARK: - Error Types

public enum MeridianError: LocalizedError {
  case networkError(String)
  case invalidURL
  case decodingError(String)
  case httpError(statusCode: Int, message: String)
  case missingSession
  case invalidAmount(String)
  case validationError(String)
  case quoteExpired(String)
  case invalidIban(String)

  public var errorDescription: String? {
    switch self {
    case let .networkError(msg):
      return "Network error: \(msg)"
    case .invalidURL:
      return "Invalid URL"
    case let .decodingError(msg):
      return "Decoding error: \(msg)"
    case let .httpError(code, msg):
      return "HTTP \(code): \(msg)"
    case .missingSession:
      return "Session ID is required"
    case let .invalidAmount(msg):
      return "Invalid amount: \(msg)"
    case let .validationError(msg):
      return "Validation error: \(msg)"
    case let .quoteExpired(msg):
      return msg
    case let .invalidIban(msg):
      return msg
    }
  }
}

public func moneyEur(_ cents: Int) -> String {
  let negative = cents < 0
  let absolute = abs(cents)
  return "\(negative ? "-" : "")€\(absolute / 100).\(String(format: "%02d", absolute % 100))"
}

// MARK: - Amount Formatting

public func money(_ pence: Int) -> String {
  let pounds = Double(pence) / 100.0
  let formatter = NumberFormatter()
  formatter.numberStyle = .currency
  formatter.locale = Locale(identifier: "en_GB")
  return formatter.string(from: NSNumber(value: pounds)) ?? "£\(String(format: "%.2f", pounds))"
}

/// Parse amount string to integer pence
/// - Parameter input: Amount string (e.g., "10.50", "10", "10.5")
/// - Returns: Tuple of (pence: Int?, error: String?)
public func parseAmount(_ input: String) -> (Int?, String?) {
  let trimmed = input.trimmingCharacters(in: .whitespaces)

  // Empty or whitespace only
  if trimmed.isEmpty {
    return (nil, "Amount is required")
  }

  // Check for sign, exponent, or invalid characters
  if trimmed.contains("-") || trimmed.contains("+") || trimmed.lowercased().contains("e") {
    return (nil, "Amount cannot contain sign or exponent notation")
  }

  // Must be numeric with optional decimal point
  let pattern = "^\\d+(\\.\\d*)?$"
  let regex = try? NSRegularExpression(pattern: pattern)
  let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
  guard regex?.firstMatch(in: trimmed, range: range) != nil else {
    return (nil, "Amount must be a valid number")
  }

  // Check decimal places and parse
  let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
  if parts.count == 2 && parts[1].count > 2 {
    return (nil, "Amount must have at most 2 decimal places")
  }

  let poundsStr = String(parts[0])
  let penceStr = parts.count == 2
    ? String(parts[1]).padding(toLength: 2, withPad: "0", startingAt: 0)
    : "00"

  guard let pounds = Int(poundsStr), let pence = Int(penceStr) else {
    return (nil, "Amount is not a valid integer")
  }

  guard pounds <= 10000 else { return (nil, "Amount cannot exceed £10,000") }
  let totalPence = pounds * 100 + pence

  // Validate range: 1 to 1,000,000 pence (£10,000)
  if totalPence <= 0 {
    return (nil, "Amount must be greater than zero")
  }

  if totalPence > 1_000_000 {
    return (nil, "Amount cannot exceed £10,000")
  }

  return (totalPence, nil)
}
