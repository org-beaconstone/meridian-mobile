import Foundation

/// ISO-4217 monetary amount stored as integer minor units.
///
/// `minorUnitExponent` is the number of digits after the decimal separator
/// (2 for GBP and EUR). Arithmetic and JSON conversion never use binary
/// floating point. A bare JSON integer is the legacy GBP pence amount.
public struct Money: Hashable, Sendable {
  public let currencyCode: String
  public let minorUnits: Int64
  public let minorUnitExponent: Int

  /// Exponents required by the currencies this client formats.
  public static let isoExponents: [String: Int] = [
    "GBP": 2,
    "EUR": 2,
  ]

  public init(currencyCode: String, minorUnits: Int64, minorUnitExponent: Int) throws {
    guard currencyCode.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
      throw MoneyError.invalidCurrencyCode(currencyCode)
    }
    guard (0...18).contains(minorUnitExponent) else {
      throw MoneyError.invalidExponent(minorUnitExponent)
    }
    if let expected = Money.isoExponents[currencyCode], expected != minorUnitExponent {
      throw MoneyError.exponentMismatch(
        currency: currencyCode,
        expected: expected,
        actual: minorUnitExponent
      )
    }
    self.currencyCode = currencyCode
    self.minorUnits = minorUnits
    self.minorUnitExponent = minorUnitExponent
  }

  private init(uncheckedCurrencyCode: String, minorUnits: Int64, minorUnitExponent: Int) {
    self.currencyCode = uncheckedCurrencyCode
    self.minorUnits = minorUnits
    self.minorUnitExponent = minorUnitExponent
  }

  /// Adapter from the existing British pound integer-pence fields.
  public static func fromLegacyGbpPence(_ pence: Int) -> Money {
    gbpMinorUnits(Int64(pence))
  }

  fileprivate static func gbpMinorUnits(_ units: Int64) -> Money {
    Money(uncheckedCurrencyCode: "GBP", minorUnits: units, minorUnitExponent: 2)
  }

  /// Legacy wire amount. Fails unless this value is GBP with exponent 2 and fits
  /// a 32-bit signed integer, which is the Java and Kotlin pence field width.
  public func legacyGbpPence() throws -> Int {
    guard currencyCode == "GBP", minorUnitExponent == 2 else {
      throw MoneyError.notLegacyGbp
    }
    guard minorUnits >= Int64(Int32.min), minorUnits <= Int64(Int32.max) else {
      throw MoneyError.overflow
    }
    return Int(minorUnits)
  }

  /// Parse a decimal amount into minor units without floating-point arithmetic.
  public static func parse(
    _ amount: String,
    currencyCode: String,
    minorUnitExponent: Int
  ) throws -> Money {
    let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      throw MoneyError.invalidAmount("Amount is required")
    }
    if trimmed.contains("+") || trimmed.lowercased().contains("e") {
      throw MoneyError.invalidAmount("Amount cannot contain sign or exponent notation")
    }

    var sign: Int64 = 1
    var digits = trimmed
    if digits.hasPrefix("-") {
      sign = -1
      digits.removeFirst()
      if digits.isEmpty {
        throw MoneyError.invalidAmount("Amount must be a valid number")
      }
    }

    guard digits.range(of: #"^\d+(\.\d*)?$"#, options: .regularExpression) != nil else {
      throw MoneyError.invalidAmount("Amount must be a valid number")
    }

    let parts = digits.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let whole = String(parts[0])
    let fractionDigits = parts.count == 2 ? String(parts[1]) : ""
    if fractionDigits.count > minorUnitExponent {
      throw MoneyError.invalidAmount(
        "Amount must have at most \(minorUnitExponent) decimal places"
      )
    }

    guard let major = Int64(whole) else { throw MoneyError.overflow }
    let padded = fractionDigits.padding(
      toLength: minorUnitExponent,
      withPad: "0",
      startingAt: 0
    )
    let fraction = minorUnitExponent == 0 ? 0 : try exactInt64(padded)
    let scaled = try multiplyExact(major, pow10(minorUnitExponent))
    let combined = try addExact(scaled, fraction)
    let signed = try multiplyExact(combined, sign)
    return try Money(
      currencyCode: currencyCode,
      minorUnits: signed,
      minorUnitExponent: minorUnitExponent
    )
  }

  public func adding(_ other: Money) throws -> Money {
    guard currencyCode == other.currencyCode, minorUnitExponent == other.minorUnitExponent else {
      throw MoneyError.currencyMismatch
    }
    return try Money(
      currencyCode: currencyCode,
      minorUnits: addExact(minorUnits, other.minorUnits),
      minorUnitExponent: minorUnitExponent
    )
  }

  /// Exact decimal spelling of the minor units. No grouping and no currency symbol.
  public func plainDecimal() -> String {
    let parts = splitMinorUnits()
    let body = minorUnitExponent == 0 ? parts.major : parts.major + "." + parts.fraction
    return parts.negative ? "-" + body : body
  }

  /// Format EUR or GBP (and any other stored code) for a user locale.
  /// Grouping and separators follow the locale; the exponent comes from this value.
  public func formatted(locale: Locale = Locale(identifier: "en_GB")) -> String {
    let language = locale.identifier
      .replacingOccurrences(of: "-", with: "_")
      .split(separator: "_")
      .first
      .map { String($0).lowercased() } ?? "en"
    let style = Money.localeStyle(language: language)
    let symbol = Money.symbol(for: currencyCode)
    let parts = splitMinorUnits()
    let grouped = groupDigits(parts.major, separator: style.grouping)
    let number = minorUnitExponent == 0
      ? grouped
      : grouped + String(style.decimal) + parts.fraction
    let gap = symbol.count == 3 && style.gap.isEmpty ? " " : style.gap
    let body = style.symbolBefore ? symbol + gap + number : number + gap + symbol
    return parts.negative ? "-" + body : body
  }

  /// Canonical ISO-4217 JSON object. Digits are written from the integer, not a binary float.
  public func toJSON() -> String {
    "{\"currencyCode\":\"\(currencyCode)\",\"minorUnits\":\(minorUnits),\"minorUnitExponent\":\(minorUnitExponent)}"
  }

  /// Decode either a legacy GBP integer or an ISO-4217 object.
  /// The scanner keeps number text intact, including values above 2^53.
  public static func fromJSON(_ json: String) throws -> Money {
    try MoneyMigration.decodeAmount(json)
  }

  private func splitMinorUnits() -> (negative: Bool, major: String, fraction: String) {
    var text = String(minorUnits)
    let negative = text.hasPrefix("-")
    if negative { text.removeFirst() }
    if minorUnitExponent == 0 {
      return (negative, text, "")
    }
    if text.count <= minorUnitExponent {
      let fraction = String(repeating: "0", count: minorUnitExponent - text.count) + text
      return (negative, "0", fraction)
    }
    let split = text.index(text.endIndex, offsetBy: -minorUnitExponent)
    return (negative, String(text[..<split]), String(text[split...]))
  }
}

public enum MoneyMigration {
  /// Decode a JSON amount that is either a legacy integer or an ISO-4217 money object.
  public static func decodeAmount(_ json: String) throws -> Money {
    try value(JsonParser.parse(json))
  }

  /// Read one amount field from a JSON object, leaving sibling fields untouched.
  public static func decodeAmountField(_ field: String, in json: String) throws -> Money {
    let root = try JsonParser.parse(json)
    guard case .object(let object) = root, let amount = object[field] else {
      throw MoneyError.invalidAmount("Missing \(field)")
    }
    return try value(amount)
  }

  fileprivate static func value(_ json: JsonValue) throws -> Money {
    switch json {
    case .number(let literal):
      guard literal.range(of: #"^-?\d+$"#, options: .regularExpression) != nil else {
        throw MoneyError.invalidAmount("Legacy amount must be an integer number of GBP pence")
      }
      return Money.gbpMinorUnits(try exactInt64(literal))
    case .object(let fields):
      guard case .string(let code)? = fields["currencyCode"] else {
        throw MoneyError.invalidAmount("currencyCode must be a string")
      }
      guard case .number(let unitsLiteral)? = fields["minorUnits"] else {
        throw MoneyError.invalidAmount("minorUnits must be an integer")
      }
      guard unitsLiteral.range(of: #"^-?\d+$"#, options: .regularExpression) != nil else {
        throw MoneyError.invalidAmount("minorUnits must be an integer")
      }
      guard case .number(let exponentLiteral)? = fields["minorUnitExponent"] else {
        throw MoneyError.invalidAmount("minorUnitExponent must be an integer")
      }
      guard exponentLiteral.range(of: #"^\d+$"#, options: .regularExpression) != nil else {
        throw MoneyError.invalidAmount("minorUnitExponent must be an integer")
      }
      guard let exponent = Int(exponentLiteral) else {
        throw MoneyError.invalidExponent(-1)
      }
      return try Money(
        currencyCode: code,
        minorUnits: exactInt64(unitsLiteral),
        minorUnitExponent: exponent
      )
    default:
      throw MoneyError.invalidAmount("Money JSON must be an integer or an ISO-4217 object")
    }
  }
}

public enum MoneyError: Error, Equatable, CustomStringConvertible {
  case invalidCurrencyCode(String)
  case invalidExponent(Int)
  case exponentMismatch(currency: String, expected: Int, actual: Int)
  case overflow
  case invalidAmount(String)
  case notLegacyGbp
  case currencyMismatch

  public var description: String {
    switch self {
    case let .invalidCurrencyCode(code):
      return "Invalid ISO-4217 currency code: \(code)"
    case let .invalidExponent(exponent):
      return "Minor unit exponent out of range: \(exponent)"
    case let .exponentMismatch(currency, expected, actual):
      return "\(currency) requires minor unit exponent \(expected), got \(actual)"
    case .overflow:
      return "Money amount overflow"
    case let .invalidAmount(message):
      return message
    case .notLegacyGbp:
      return "Amount is not a legacy GBP pence value"
    case .currencyMismatch:
      return "Currency and exponent must match"
    }
  }
}

extension Transaction {
  public var amountMoney: Money { Money.fromLegacyGbpPence(amount) }
}

extension Budget {
  public var limitMoney: Money { Money.fromLegacyGbpPence(limit) }
}

extension BankState {
  public var balanceMoney: Money { Money.fromLegacyGbpPence(balance) }
}

private struct LocaleMoneyStyle {
  let decimal: Character
  let grouping: Character
  let symbolBefore: Bool
  let gap: String
}

private func groupDigits(_ digits: String, separator: Character) -> String {
  guard digits.count > 3 else { return digits }
  var groups: [String] = []
  var end = digits.endIndex
  while end > digits.startIndex {
    let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
    groups.append(String(digits[start..<end]))
    end = start
  }
  return groups.reversed().joined(separator: String(separator))
}

private extension Money {
  static func localeStyle(language: String) -> LocaleMoneyStyle {
    switch language {
    case "de", "nl", "es", "it", "pt":
      return LocaleMoneyStyle(decimal: ",", grouping: ".", symbolBefore: false, gap: " ")
    case "fr":
      return LocaleMoneyStyle(decimal: ",", grouping: "\u{00A0}", symbolBefore: false, gap: "\u{00A0}")
    default:
      return LocaleMoneyStyle(decimal: ".", grouping: ",", symbolBefore: true, gap: "")
    }
  }

  static func symbol(for currencyCode: String) -> String {
    switch currencyCode {
    case "GBP": return "£"
    case "EUR": return "€"
    default: return currencyCode
    }
  }
}

private func pow10(_ exponent: Int) throws -> Int64 {
  var result: Int64 = 1
  for _ in 0..<exponent {
    result = try multiplyExact(result, 10)
  }
  return result
}

private func multiplyExact(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
  let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
  if overflow { throw MoneyError.overflow }
  return value
}

private func addExact(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
  let (value, overflow) = lhs.addingReportingOverflow(rhs)
  if overflow { throw MoneyError.overflow }
  return value
}

private func exactInt64(_ literal: String) throws -> Int64 {
  guard let value = Int64(literal) else { throw MoneyError.overflow }
  return value
}

private enum JsonValue {
  case null
  case bool(Bool)
  case number(String)
  case string(String)
  case array([JsonValue])
  case object([String: JsonValue])
}

private struct JsonParser {
  private let text: String
  private var index: String.Index

  static func parse(_ text: String) throws -> JsonValue {
    var parser = JsonParser(text)
    let value = try parser.parseValue()
    parser.skipWhitespace()
    guard parser.index == parser.text.endIndex else {
      throw MoneyError.invalidAmount("Unexpected trailing JSON")
    }
    return value
  }

  private init(_ text: String) {
    self.text = text
    self.index = text.startIndex
  }

  private mutating func parseValue() throws -> JsonValue {
    skipWhitespace()
    guard let character = peek() else {
      throw MoneyError.invalidAmount("Unexpected end of JSON")
    }
    switch character {
    case "{": return .object(try parseObject())
    case "[": return .array(try parseArray())
    case "\"": return .string(try parseString())
    case "t":
      try consume("true")
      return .bool(true)
    case "f":
      try consume("false")
      return .bool(false)
    case "n":
      try consume("null")
      return .null
    default:
      return .number(try parseNumber())
    }
  }

  private mutating func parseObject() throws -> [String: JsonValue] {
    try consume("{")
    var fields: [String: JsonValue] = [:]
    skipWhitespace()
    if peek() == "}" {
      _ = try pop()
      return fields
    }
    while true {
      skipWhitespace()
      let key = try parseString()
      skipWhitespace()
      try consume(":")
      fields[key] = try parseValue()
      skipWhitespace()
      if peek() == "," {
        _ = try pop()
        continue
      }
      try consume("}")
      return fields
    }
  }

  private mutating func parseArray() throws -> [JsonValue] {
    try consume("[")
    var values: [JsonValue] = []
    skipWhitespace()
    if peek() == "]" {
      _ = try pop()
      return values
    }
    while true {
      values.append(try parseValue())
      skipWhitespace()
      if peek() == "," {
        _ = try pop()
        continue
      }
      try consume("]")
      return values
    }
  }

  private mutating func parseString() throws -> String {
    try consume("\"")
    var result = ""
    while true {
      let character = try pop()
      if character == "\"" { return result }
      if character == "\\" {
        switch try pop() {
        case "\"": result.append("\"")
        case "\\": result.append("\\")
        case "/": result.append("/")
        case "b": result.append("\u{08}")
        case "f": result.append("\u{0C}")
        case "n": result.append("\n")
        case "r": result.append("\r")
        case "t": result.append("\t")
        case "u":
          var hex = ""
          for _ in 0..<4 { hex.append(try pop()) }
          guard let code = UInt32(hex, radix: 16), let scalar = UnicodeScalar(code) else {
            throw MoneyError.invalidAmount("Invalid unicode escape")
          }
          result.append(Character(scalar))
        default:
          throw MoneyError.invalidAmount("Invalid escape")
        }
      } else {
        result.append(character)
      }
    }
  }

  private mutating func parseNumber() throws -> String {
    let start = index
    if peek() == "-" { index = text.index(after: index) }
    guard let first = peek(), isDigit(first) else {
      throw MoneyError.invalidAmount("Invalid JSON number")
    }
    if first == "0" {
      index = text.index(after: index)
      if let next = peek(), isDigit(next) {
        throw MoneyError.invalidAmount("Invalid JSON number")
      }
    } else {
      while let character = peek(), isDigit(character) { index = text.index(after: index) }
    }
    if peek() == "." {
      index = text.index(after: index)
      guard let digit = peek(), isDigit(digit) else {
        throw MoneyError.invalidAmount("Invalid JSON number")
      }
      while let character = peek(), isDigit(character) { index = text.index(after: index) }
    }
    if peek() == "e" || peek() == "E" {
      index = text.index(after: index)
      if peek() == "+" || peek() == "-" { index = text.index(after: index) }
      guard let digit = peek(), isDigit(digit) else {
        throw MoneyError.invalidAmount("Invalid JSON number")
      }
      while let character = peek(), isDigit(character) { index = text.index(after: index) }
    }
    return String(text[start..<index])
  }

  private mutating func skipWhitespace() {
    while let character = peek(), character == " " || character == "\n" || character == "\r" || character == "\t" {
      index = text.index(after: index)
    }
  }

  private func peek() -> Character? {
    index < text.endIndex ? text[index] : nil
  }

  private mutating func pop() throws -> Character {
    guard let character = peek() else {
      throw MoneyError.invalidAmount("Unexpected end of JSON")
    }
    index = text.index(after: index)
    return character
  }

  private mutating func consume(_ token: String) throws {
    for character in token {
      guard try pop() == character else {
        throw MoneyError.invalidAmount("Invalid JSON")
      }
    }
  }

  private func isDigit(_ character: Character) -> Bool {
    character >= "0" && character <= "9"
  }
}
