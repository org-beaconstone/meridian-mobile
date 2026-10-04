import Foundation

/// Account ledger currency. Cross-currency review converts from this into the recipient currency.
public let accountCurrency = "GBP"

/// Customers see this countdown on the review sheet. The client never extends it.
public let quoteLockSeconds = 60

public enum FxCopy {
  public static let unavailable = "We couldn't lock an exchange rate. Try again."
  public static let expired =
    "This rate lock has expired. Refresh the rate to continue. Your payment details are unchanged."
  public static let retry = "Try again"
  public static let refresh = "Refresh rate"
  public static let locked = "Rate locked"
}

public func isCrossCurrency(source: String, target: String) -> Bool {
  source.uppercased() != target.uppercased()
}

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
  public let sourceAmountMinor: Int?
  public let targetAmountMinor: Int?
  public let rate: String
  public let expiresInSeconds: Int
  public let serverExpiresAt: Date?

  public init(
    quoteId: String,
    sourceCurrency: String = "",
    targetCurrency: String = "",
    sourceAmountMinor: Int? = nil,
    targetAmountMinor: Int? = nil,
    rate: String,
    expiresInSeconds: Int = quoteLockSeconds,
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
    let primary = try container.decodeIfPresent(String.self, forKey: .quoteId) ?? ""
    let alternate = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    let resolvedId = primary.isEmpty ? alternate : primary
    guard !resolvedId.isEmpty else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "FX quote id missing")
      )
    }
    quoteId = resolvedId
    sourceCurrency = try container.decodeIfPresent(String.self, forKey: .sourceCurrency) ?? ""
    targetCurrency = try container.decodeIfPresent(String.self, forKey: .targetCurrency) ?? ""
    if let source = try container.decodeIfPresent(Int.self, forKey: .sourceAmountMinor) {
      sourceAmountMinor = source
    } else {
      sourceAmountMinor = try container.decodeIfPresent(Int.self, forKey: .amountMinor)
    }
    targetAmountMinor = try container.decodeIfPresent(Int.self, forKey: .targetAmountMinor)
    if let text = try? container.decode(String.self, forKey: .rate), !text.isEmpty {
      rate = text
    } else if let number = try? container.decode(Double.self, forKey: .rate), number.isFinite {
      rate = FxQuote.formatRate(number)
    } else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "FX rate missing")
      )
    }
    expiresInSeconds = try container.decodeIfPresent(Int.self, forKey: .expiresInSeconds) ?? quoteLockSeconds
    if let raw = try container.decodeIfPresent(String.self, forKey: .expiresAt) {
      serverExpiresAt = FxQuote.parseServerDate(raw)
    } else {
      serverExpiresAt = nil
    }
  }

  private static func formatRate(_ number: Double) -> String {
    var text = String(format: "%.6f", number)
    while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
      text.removeLast()
    }
    return text
  }

  private static func parseServerDate(_ raw: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: raw) { return date }
    let basic = ISO8601DateFormatter()
    basic.formatOptions = [.withInternetDateTime]
    return basic.date(from: raw)
  }
}

public struct FxQuoteLock: Equatable {
  public let quoteId: String
  public let sourceCurrency: String
  public let targetCurrency: String
  public let sourceAmountMinor: Int
  public let targetAmountMinor: Int?
  public let rate: String
  public let expiresAt: Date

  public func remainingSeconds(at now: Date) -> Int {
    let left = expiresAt.timeIntervalSince(now)
    if left <= 0 { return 0 }
    return min(quoteLockSeconds, max(0, Int(left.rounded(.up))))
  }

  public func isExpired(at now: Date) -> Bool {
    now >= expiresAt
  }
}

public func lockQuote(
  _ quote: FxQuote,
  sourceCurrency: String,
  targetCurrency: String,
  amountMinor: Int,
  lockedAt: Date = Date()
) -> FxQuoteLock {
  let requestedWindow = max(0, quote.expiresInSeconds)
  let window = TimeInterval(min(requestedWindow, quoteLockSeconds))
  var expiry = lockedAt.addingTimeInterval(window)
  if let server = quote.serverExpiresAt {
    expiry = min(expiry, server)
  }
  let cap = lockedAt.addingTimeInterval(TimeInterval(quoteLockSeconds))
  if expiry > cap { expiry = cap }
  let resolvedSource = quote.sourceCurrency.isEmpty ? sourceCurrency : quote.sourceCurrency
  let resolvedTarget = quote.targetCurrency.isEmpty ? targetCurrency : quote.targetCurrency
  return FxQuoteLock(
    quoteId: quote.quoteId,
    sourceCurrency: resolvedSource,
    targetCurrency: resolvedTarget,
    sourceAmountMinor: quote.sourceAmountMinor ?? amountMinor,
    targetAmountMinor: quote.targetAmountMinor,
    rate: quote.rate,
    expiresAt: expiry
  )
}

/// Nil when confirmation may proceed. Cross-currency payments need an unexpired matching quote.
public func rateLockBlockReason(
  sourceCurrency: String,
  targetCurrency: String,
  amountMinor: Int,
  quote: FxQuoteLock?,
  now: Date
) -> String? {
  guard isCrossCurrency(source: sourceCurrency, target: targetCurrency) else { return nil }
  guard let quote else { return FxCopy.unavailable }
  let samePair =
    quote.sourceCurrency.uppercased() == sourceCurrency.uppercased()
    && quote.targetCurrency.uppercased() == targetCurrency.uppercased()
    && quote.sourceAmountMinor == amountMinor
    && !quote.quoteId.isEmpty
    && !quote.isExpired(at: now)
  return samePair ? nil : FxCopy.expired
}

public func formatMinor(_ amountMinor: Int, currency: String) -> String {
  if currency.uppercased() == "EUR" {
    return String(format: "€%.2f", Double(amountMinor) / 100.0)
  }
  return money(amountMinor)
}
