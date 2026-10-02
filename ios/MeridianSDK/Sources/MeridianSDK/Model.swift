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

public enum Scenario: String, Codable {
  case success
  case declined
  case unavailable
  case pending
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
  public let provider: String // provider id string from server (e.g. "adyen", "worldpay")
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
    provider: String,
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
  public let id: String // server-assigned provider id string
  public let name: String
  public let description: String
  public let methods: [String]

  public init(
    id: String,
    name: String,
    description: String,
    methods: [String]
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.methods = methods
  }
}

// MARK: - Payment Method Descriptors

/// A server-driven descriptor representing one selectable payment option.
/// Derived from the catalog `/catalog` providers list; each provider × method
/// combination yields one descriptor shown in the method-selector bottom sheet.
public struct PaymentMethodDescriptor: Identifiable, Hashable {
  /// Stable composite key: "\(providerId):\(method.rawValue)"
  public let id: String
  public let providerId: String
  public let providerName: String
  public let method: PaymentMethod
  /// Human-readable label shown in the picker row (e.g. "Debit card").
  public let label: String
  /// SF Symbol name for the leading icon.
  public let logoSymbol: String
  /// Whether the user must also choose a destination bank.
  public let requiresBankChoice: Bool
  /// False when the server marks this combination ineligible.
  public let eligible: Bool

  public init(
    id: String,
    providerId: String,
    providerName: String,
    method: PaymentMethod,
    label: String,
    logoSymbol: String,
    requiresBankChoice: Bool,
    eligible: Bool
  ) {
    self.id = id
    self.providerId = providerId
    self.providerName = providerName
    self.method = method
    self.label = label
    self.logoSymbol = logoSymbol
    self.requiresBankChoice = requiresBankChoice
    self.eligible = eligible
  }
}

/// A selectable destination bank shown in the bank-selector bottom sheet.
public struct BankOption: Identifiable, Hashable {
  public let id: String
  public let name: String
  public let sortCode: String

  public init(id: String, name: String, sortCode: String) {
    self.id = id
    self.name = name
    self.sortCode = sortCode
  }
}

/// Build `PaymentMethodDescriptor` entries from the catalog provider list.
/// Order follows the server-returned provider and method ordering.
public func paymentMethodDescriptors(from providers: [Provider]) -> [PaymentMethodDescriptor] {
  var result: [PaymentMethodDescriptor] = []
  for provider in providers {
    for methodStr in provider.methods {
      guard let method = PaymentMethod(rawValue: methodStr) else { continue }
      let label: String
      let symbol: String
      let requiresBank: Bool
      switch method {
      case .card:
        label = "Debit card"
        symbol = "creditcard.fill"
        requiresBank = false
      case .bank:
        label = "Bank payment"
        symbol = "building.columns.fill"
        requiresBank = true
      }
      result.append(
        PaymentMethodDescriptor(
          id: "\(provider.id):\(methodStr)",
          providerId: provider.id,
          providerName: provider.name,
          method: method,
          label: label,
          logoSymbol: symbol,
          requiresBankChoice: requiresBank,
          eligible: true
        )
      )
    }
  }
  return result
}

/// Simulated UK bank list used for bank-payment demos.
/// Presented in the searchable bank-selector sheet when the chosen method
/// has `requiresBankChoice == true`.
public let demoBanks: [BankOption] = [
  BankOption(id: "barclays",   name: "Barclays",      sortCode: "20-00-00"),
  BankOption(id: "hsbc",       name: "HSBC",          sortCode: "40-00-00"),
  BankOption(id: "lloyds",     name: "Lloyds",        sortCode: "30-00-00"),
  BankOption(id: "natwest",    name: "NatWest",       sortCode: "60-00-00"),
  BankOption(id: "nationwide", name: "Nationwide",    sortCode: "07-00-00"),
  BankOption(id: "santander",  name: "Santander",     sortCode: "09-00-00"),
  BankOption(id: "monzo",      name: "Monzo",         sortCode: "04-00-04"),
  BankOption(id: "starling",   name: "Starling Bank", sortCode: "60-83-71"),
]

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

// MARK: - Error Types

public enum MeridianError: LocalizedError {
  case networkError(String)
  case invalidURL
  case decodingError(String)
  case httpError(statusCode: Int, message: String)
  case missingSession
  case invalidAmount(String)
  case validationError(String)

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
    }
  }
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
