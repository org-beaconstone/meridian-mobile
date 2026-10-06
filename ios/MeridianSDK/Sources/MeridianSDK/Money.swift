import Foundation

/// ISO-4217 amount stored as integer minor units.
///
/// A legacy JSON number is a British pound amount in pence (exponent 2).
/// Object payloads carry `currencyCode`, `minorUnits`, and `minorUnitExponent`.
/// Parsing, scaling, and overflow checks use integer arithmetic only.
public struct Money: Hashable, Codable {
  public let currencyCode: String
  public let minorUnits: Int64
  public let minorUnitExponent: Int

  public init(currencyCode: String, minorUnits: Int64, minorUnitExponent: Int) throws {
    let expected = try Money.isoExponent(for: currencyCode)
    guard minorUnitExponent == expected else {
      throw MoneyError.exponentMismatch(
        currency: currencyCode,
        exponent: minorUnitExponent,
        expected: expected
      )
    }
    self.currencyCode = currencyCode
    self.minorUnits = minorUnits
    self.minorUnitExponent = minorUnitExponent
  }

  /// Existing rehearsal amounts are GBP integer pence.
  public static func gbpPence(_ pence: Int64) -> Money {
    // GBP exponent 2 is a fixed ISO-4217 fact, so this cannot fail validation.
    try! Money(currencyCode: "GBP", minorUnits: pence, minorUnitExponent: 2)
  }

  public static func gbpPence(_ pence: Int) -> Money {
    gbpPence(Int64(pence))
  }

  /// Integer pence for the current payment request. Refuses other currencies.
  public func requireLegacyGbpPence() throws -> Int {
    guard currencyCode == "GBP", minorUnitExponent == 2 else {
      throw MoneyError.notLegacyGbp
    }
    guard minorUnits <= Int64(Int.max), minorUnits >= Int64(Int.min) else {
      throw MoneyError.overflow
    }
    return Int(minorUnits)
  }

  public func adding(_ other: Money) throws -> Money {
    guard currencyCode == other.currencyCode, minorUnitExponent == other.minorUnitExponent else {
      throw MoneyError.currencyMismatch
    }
    let (sum, overflow) = minorUnits.addingReportingOverflow(other.minorUnits)
    if overflow { throw MoneyError.overflow }
    return try Money(currencyCode: currencyCode, minorUnits: sum, minorUnitExponent: minorUnitExponent)
  }

  /// Parse a major-unit decimal string such as "10.50" into minor units.
  public static func parseMajor(_ input: String, currencyCode: String) throws -> Money {
    let exponent = try isoExponent(for: currencyCode)
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      throw MoneyError.invalidMajorAmount("Amount is required")
    }
    if trimmed.contains("-") || trimmed.contains("+") || trimmed.lowercased().contains("e") {
      throw MoneyError.invalidMajorAmount("Amount cannot contain sign or exponent notation")
    }
    let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
    guard wholeNumberPattern.firstMatch(in: trimmed, range: range) != nil else {
      throw MoneyError.invalidMajorAmount("Amount must be a valid number")
    }

    let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let fraction = parts.count == 2 ? String(parts[1]) : ""
    if fraction.count > exponent {
      throw MoneyError.invalidMajorAmount("Amount must have at most \(exponent) decimal places")
    }
    let padded = fraction.padding(toLength: exponent, withPad: "0", startingAt: 0)
    let whole = try parseUnsignedDigits(String(parts[0]))
    var scaled = whole
    for _ in 0..<exponent {
      if scaled > UInt64.max / 10 { throw MoneyError.overflow }
      scaled *= 10
    }
    let fractionUnits = padded.isEmpty ? UInt64(0) : try parseUnsignedDigits(padded)
    if scaled > UInt64.max - fractionUnits { throw MoneyError.overflow }
    let total = scaled + fractionUnits
    if total > UInt64(Int64.max) { throw MoneyError.overflow }
    return try Money(
      currencyCode: currencyCode,
      minorUnits: Int64(total),
      minorUnitExponent: exponent
    )
  }

  /// Decimal major units with a dot separator and no currency symbol.
  public func majorDecimal() -> String {
    let negative = minorUnits < 0
    let magnitude = Self.magnitude(of: minorUnits)
    let sign = negative ? "-" : ""
    guard minorUnitExponent > 0 else { return sign + String(magnitude) }
    var scale: UInt64 = 1
    for _ in 0..<minorUnitExponent { scale *= 10 }
    let major = magnitude / scale
    let fraction = magnitude % scale
    let rawFraction = String(fraction)
    let zeros = String(repeating: "0", count: minorUnitExponent - rawFraction.count)
    return "\(sign)\(major).\(zeros)\(rawFraction)"
  }

  /// Locale currency format. The amount is a base-10 decimal, not a binary float.
  public func formatted(locale: Locale = .current) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .currency
    formatter.currencyCode = currencyCode
    formatter.minimumFractionDigits = minorUnitExponent
    formatter.maximumFractionDigits = minorUnitExponent
    formatter.usesGroupingSeparator = true
    formatter.roundingMode = .down
    let negative = minorUnits < 0
    let decimal = NSDecimalNumber(
      mantissa: Self.magnitude(of: minorUnits),
      exponent: Int16(-minorUnitExponent),
      isNegative: negative
    )
    return formatter.string(from: decimal) ?? "\(currencyCode) \(majorDecimal())"
  }

  public static func isoExponent(for currencyCode: String) throws -> Int {
    guard currencyCode.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil,
          Locale.commonISOCurrencyCodes.contains(currencyCode)
    else {
      throw MoneyError.invalidCurrencyCode(currencyCode)
    }
    if zeroDecimalCurrencies.contains(currencyCode) { return 0 }
    if threeDecimalCurrencies.contains(currencyCode) { return 3 }
    return 2
  }

  // MARK: - Codable migration

  public init(from decoder: Decoder) throws {
    if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
       keyed.contains(.currencyCode)
        || keyed.contains(.minorUnits)
        || keyed.contains(.minorUnitExponent)
        || keyed.contains(.amount)
        || keyed.contains(.amountMinor) {
      try self.init(migrating: keyed)
      return
    }

    let single = try decoder.singleValueContainer()
    if single.decodeNil() { throw MoneyError.missingAmount }
    guard let units = try? single.decode(Int64.self) else {
      throw MoneyError.nonIntegralAmount
    }
    self = Money.gbpPence(units)
  }

  private init(migrating container: KeyedDecodingContainer<CodingKeys>) throws {
    let code: String
    if container.contains(.currencyCode) {
      code = try container.decode(String.self, forKey: .currencyCode)
    } else {
      code = "GBP"
    }

    let minor = try Self.readUnits(container, key: .minorUnits)
    let legacy = try Self.readUnits(container, key: .amount) ?? Self.readUnits(container, key: .amountMinor)
    let units: Int64
    switch (minor, legacy) {
    case let (minor?, legacy?) where minor != legacy:
      throw MoneyError.conflictingAmount
    case let (minor?, _):
      units = minor
    case let (nil, legacy?):
      units = legacy
    case (nil, nil):
      throw MoneyError.missingAmount
    }

    let exponent: Int
    if container.contains(.minorUnitExponent) {
      guard let decoded = try? container.decode(Int.self, forKey: .minorUnitExponent) else {
        throw MoneyError.nonIntegralAmount
      }
      exponent = decoded
    } else {
      exponent = try Money.isoExponent(for: code)
    }
    try self.init(currencyCode: code, minorUnits: units, minorUnitExponent: exponent)
  }

  private static func readUnits(
    _ container: KeyedDecodingContainer<CodingKeys>,
    key: CodingKeys
  ) throws -> Int64? {
    guard container.contains(key) else { return nil }
    guard let units = try? container.decode(Int64.self, forKey: key) else {
      throw MoneyError.nonIntegralAmount
    }
    return units
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(currencyCode, forKey: .currencyCode)
    try container.encode(minorUnits, forKey: .minorUnits)
    try container.encode(minorUnitExponent, forKey: .minorUnitExponent)
  }

  private enum CodingKeys: String, CodingKey {
    case currencyCode
    case minorUnits
    case minorUnitExponent
    case amount
    case amountMinor
  }

  private static func magnitude(of units: Int64) -> UInt64 {
    if units < 0 {
      if units == Int64.min { return UInt64(Int64.max) + 1 }
      return UInt64(-units)
    }
    return UInt64(units)
  }

  private static func parseUnsignedDigits(_ digits: String) throws -> UInt64 {
    if digits.isEmpty { throw MoneyError.nonIntegralAmount }
    var result: UInt64 = 0
    for byte in digits.utf8 {
      guard byte >= 48, byte <= 57 else { throw MoneyError.nonIntegralAmount }
      let digit = UInt64(byte - 48)
      if result > (UInt64.max - digit) / 10 { throw MoneyError.overflow }
      result = result * 10 + digit
    }
    return result
  }

  private static let wholeNumberPattern = try! NSRegularExpression(pattern: "^\\d+(\\.\\d+)?$")

  /// Current ISO-4217 currencies whose minor-unit exponent is 0.
  private static let zeroDecimalCurrencies: Set<String> = [
    "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "VND", "VUV",
    "XAF", "XOF", "XPF",
  ]

  /// Current ISO-4217 currencies whose minor-unit exponent is 3.
  private static let threeDecimalCurrencies: Set<String> = [
    "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND",
  ]
}

public enum MoneyError: Error, Equatable {
  case invalidCurrencyCode(String)
  case exponentMismatch(currency: String, exponent: Int, expected: Int)
  case nonIntegralAmount
  case overflow
  case missingAmount
  case conflictingAmount
  case invalidMajorAmount(String)
  case notLegacyGbp
  case currencyMismatch
}
