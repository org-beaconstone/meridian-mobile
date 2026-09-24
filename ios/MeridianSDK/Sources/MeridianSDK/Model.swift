import Foundation

// MARK: - Domain Types

public enum Category: String, Codable, Hashable, CaseIterable {
  case shopping = "Shopping"
  case foodDrink = "Food & drink"
  case transport = "Transport"
  case bills = "Bills"
  case lifestyle = "Lifestyle"
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
  public let provider: String
  public let method: String
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
    method: String,
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
  public let id: String
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

  public init(demoDate: String, recipients: [Recipient], providers: [Provider]) {
    self.demoDate = demoDate
    self.recipients = recipients
    self.providers = providers
  }
}

/// One payable method from GET /catalog. The id is client-side; `methodId` is submitted unchanged.
public struct PaymentMethodOption: Hashable, Identifiable {
  public let id: String
  public let methodId: String
  public let providerId: String
  public let providerName: String
  public let displayLabel: String

  public init(
    id: String,
    methodId: String,
    providerId: String,
    providerName: String,
    displayLabel: String
  ) {
    self.id = id
    self.methodId = methodId
    self.providerId = providerId
    self.providerName = providerName
    self.displayLabel = displayLabel
  }

  public static func label(methodId: String, providerName: String) -> String {
    "\(humanize(methodId)) · \(providerName)"
  }

  /// Present a method id without interpreting which provider it belongs to.
  public static func humanize(_ methodId: String) -> String {
    let separated = methodId
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
    return separated.split(separator: " ").map { part in
      guard let first = part.first else { return "" }
      return String(first).uppercased() + part.dropFirst().lowercased()
    }.joined(separator: " ")
  }
}

extension CatalogResponse {
  /// Flatten every configured provider method. Count follows the payload, not a fixed provider list.
  public var paymentMethodOptions: [PaymentMethodOption] {
    providers.flatMap { provider in
      provider.methods.filter { !$0.isEmpty }.map { methodId in
        PaymentMethodOption(
          id: "\(provider.id)_\(methodId)",
          methodId: methodId,
          providerId: provider.id,
          providerName: provider.name,
          displayLabel: PaymentMethodOption.label(methodId: methodId, providerName: provider.name)
        )
      }
    }
  }

  public func paymentOption(selectedId: String, allowFallback: Bool) -> PaymentMethodOption? {
    if let match = paymentMethodOptions.first(where: { $0.id == selectedId }) {
      return match
    }
    guard allowFallback else { return nil }
    return paymentMethodOptions.first
  }
}

public enum PaymentRouting {
  /// Method id to submit for a selection the user already confirmed. Never substitutes another option.
  public static func methodId(in catalog: CatalogResponse, selectedOptionId: String) -> String? {
    catalog.paymentOption(selectedId: selectedOptionId, allowFallback: false)?.methodId
  }

  /// Keep the current selection when it is still offered. Otherwise use the first catalog option.
  public static func selectionId(in catalog: CatalogResponse, current: String) -> String {
    if catalog.paymentMethodOptions.contains(where: { $0.id == current }) {
      return current
    }
    return catalog.paymentMethodOptions.first?.id ?? ""
  }
}

/// In-memory catalog snapshot. A failed fetch may reuse it until the time-to-live elapses.
public struct CatalogCache {
  public var ttl: TimeInterval
  public private(set) var cached: CatalogResponse?
  public private(set) var fetchedAt: Date?

  public init(ttl: TimeInterval = 60) {
    self.ttl = ttl
  }

  public mutating func store(_ catalog: CatalogResponse, at now: Date) {
    cached = catalog
    fetchedAt = now
  }

  public func fallback(at now: Date) -> CatalogResponse? {
    guard let cached, let fetchedAt, now.timeIntervalSince(fetchedAt) <= ttl else { return nil }
    return cached
  }
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
  public let method: String
  public let note: String
  public let scenario: Scenario

  public init(
    recipientId: String,
    amountMinor: Int,
    method: String,
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
