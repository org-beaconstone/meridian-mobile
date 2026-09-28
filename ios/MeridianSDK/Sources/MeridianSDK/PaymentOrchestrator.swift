import Foundation

public let quoteExpiredMessage =
  "This conversion rate has expired. Refresh the conversion rate before confirming."
public let invalidIbanMessage = "Enter a valid recipient IBAN before submitting."

public enum QuoteLock {
  /// Customers see this countdown on the review screen. The client never extends it.
  public static let durationSeconds: TimeInterval = 60
  /// Initial attempt plus two gateway retries. The idempotency key stays the same.
  public static let maxPaymentAttempts = 3
}

public struct FxQuoteLock: Equatable {
  public let quoteId: String
  public let sourceAmountMinor: Int
  public let targetAmountMinor: Int
  public let rate: String
  public let sourceCurrency: String
  public let targetCurrency: String
  public let lockedAt: Date
  public let expiresAt: Date

  public func remainingSeconds(at now: Date) -> Int {
    let left = expiresAt.timeIntervalSince(now)
    if left <= 0 { return 0 }
    let seconds = Int(left.rounded(.up))
    return min(Int(QuoteLock.durationSeconds), max(0, seconds))
  }

  public func isExpired(at now: Date) -> Bool {
    now >= expiresAt
  }
}

public func lockQuote(_ quote: FxQuote, lockedAt: Date = Date()) -> FxQuoteLock {
  let localExpiry = lockedAt.addingTimeInterval(QuoteLock.durationSeconds)
  let expiry = quote.serverExpiresAt.map { min($0, localExpiry) } ?? localExpiry
  return FxQuoteLock(
    quoteId: quote.quoteId,
    sourceAmountMinor: quote.sourceAmountMinor,
    targetAmountMinor: quote.targetAmountMinor,
    rate: quote.rate,
    sourceCurrency: quote.sourceCurrency,
    targetCurrency: quote.targetCurrency,
    lockedAt: lockedAt,
    expiresAt: expiry
  )
}

public func normalizeIban(_ raw: String) -> String {
  raw.uppercased().filter { !$0.isWhitespace }
}

/// ISO 13616 MOD-97. Letters expand to A=10 … Z=35. A valid IBAN has remainder 1.
public func isValidIban(_ raw: String) -> Bool {
  let iban = normalizeIban(raw)
  guard (15...34).contains(iban.count) else { return false }
  guard iban.range(of: "^[A-Z]{2}[0-9]{2}[A-Z0-9]+$", options: .regularExpression) != nil else {
    return false
  }
  let rearranged = String(iban.dropFirst(4) + iban.prefix(4))
  var remainder = 0
  for character in rearranged {
    let digits: String
    if let value = character.wholeNumberValue {
      digits = String(value)
    } else if let ascii = character.asciiValue, character >= "A", character <= "Z" {
      digits = String(Int(ascii) - 55)
    } else {
      return false
    }
    for digit in digits {
      guard let value = digit.wholeNumberValue else { return false }
      remainder = (remainder * 10 + value) % 97
    }
  }
  return remainder == 1
}

public func isUuidV4(_ value: String) -> Bool {
  value.range(
    of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$",
    options: .regularExpression
  ) != nil
}

public func makeIdempotencyKey() -> String {
  let key = UUID().uuidString
  precondition(isUuidV4(key), "Platform UUID must be version 4")
  return key
}

public func nextIdempotencyKey(current: String, retain: Bool) -> String {
  retain ? current : makeIdempotencyKey()
}

public func ibanRequired(currency: PayCurrency, method: PaymentMethod) -> Bool {
  currency == .eur || method == .bank
}

public func ibanBlockReason(currency: PayCurrency, method: PaymentMethod, iban: String) -> String? {
  if ibanRequired(currency: currency, method: method) || !normalizeIban(iban).isEmpty {
    if !isValidIban(iban) { return invalidIbanMessage }
  }
  return nil
}

public func submissionBlockReason(
  currency: PayCurrency,
  method: PaymentMethod,
  iban: String,
  quote: FxQuoteLock?,
  amountMinor: Int,
  now: Date
) -> String? {
  if let ibanError = ibanBlockReason(currency: currency, method: method, iban: iban) {
    return ibanError
  }
  if currency == .eur {
    guard let quote, quote.sourceAmountMinor == amountMinor, !quote.isExpired(at: now) else {
      return quoteExpiredMessage
    }
  }
  return nil
}

public func isGatewayTimeout(statusCode: Int) -> Bool {
  statusCode == 502 || statusCode == 504
}

/// Delay before the next attempt. `failedAttempt` is the 1-based count of gateway failures so far.
public func gatewayBackoffMilliseconds(afterFailure failedAttempt: Int) -> Int {
  precondition(failedAttempt >= 1)
  let shift = min(failedAttempt - 1, 8)
  return 200 << shift
}

/// Replays POST /payments on HTTP 502/504. The key and method never change, so a timeout cannot hop providers.
public func submitPaymentWithRetry(
  idempotencyKey: String,
  method: PaymentMethod,
  maxAttempts: Int = QuoteLock.maxPaymentAttempts,
  delayMilliseconds: (Int) -> Int = gatewayBackoffMilliseconds,
  sleepMilliseconds: (Int) async throws -> Void = { milliseconds in
    try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
  },
  send: (String, PaymentMethod) async throws -> PaymentResponse
) async throws -> PaymentResponse {
  var attempt = 1
  while true {
    do {
      return try await send(idempotencyKey, method)
    } catch let error as MeridianError {
      guard case .httpError(let statusCode, _) = error,
        isGatewayTimeout(statusCode: statusCode),
        attempt < maxAttempts
      else {
        throw error
      }
      let wait = delayMilliseconds(attempt)
      attempt += 1
      try await sleepMilliseconds(wait)
    }
  }
}
