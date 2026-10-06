import Foundation

public struct ContractError: Error, Equatable {
  public let code: String
  public let message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

public struct Money: Equatable {
  public let currency: String
  public let minor: Int
  public let exponent: Int

  public init(currency: String, minor: Int, exponent: Int) {
    self.currency = currency
    self.minor = minor
    self.exponent = exponent
  }

  public var gbpPence: Int? {
    currency == "GBP" && exponent == 2 ? minor : nil
  }

  public var display: String {
    formatMoney(currency: currency, minor: minor, exponent: exponent)
  }
}

public func formatMoney(currency: String, minor: Int, exponent: Int) -> String {
  let symbol: String
  switch currency {
  case "GBP": symbol = "£"
  case "EUR": symbol = "€"
  case "USD": symbol = "$"
  case "JPY": symbol = "¥"
  default: symbol = "\(currency) "
  }
  let negative = minor < 0
  let absolute = negative ? -minor : minor
  let sign = negative ? "-" : ""
  if exponent <= 0 { return sign + symbol + String(absolute) }
  var scale = 1
  for _ in 0..<exponent { scale *= 10 }
  let whole = absolute / scale
  let fraction = String(absolute % scale)
  let padded = String(repeating: "0", count: max(0, exponent - fraction.count)) + fraction
  return sign + symbol + String(whole) + "." + padded
}

public func isCalendarDate(_ value: String) -> Bool {
  guard Json.matches(#"^\d{4}-\d{2}-\d{2}$"#, value) else { return false }
  let parts = value.split(separator: "-")
  guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]), (1...12).contains(month) else {
    return false
  }
  let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  return (1...lengths[month - 1]).contains(day)
}

public func decodeMoney(_ value: Any) -> Result<Money, ContractError> {
  if let _ = value as? String {
    return .failure(ContractError(code: "MALFORMED_AMOUNT", message: "Amount must be an integer or money object"))
  }
  if let minor = Json.int(value), Json.object(value) == nil {
    return legacyPence(minor)
  }
  guard let object = Json.object(value) else {
    return .failure(ContractError(code: "MALFORMED_AMOUNT", message: "Amount must be an integer or money object"))
  }
  guard let currency = Json.string(object["currency"]), let minor = Json.int(object["minor"]), let exponent = Json.int(object["exponent"]) else {
    return .failure(ContractError(code: "MALFORMED_AMOUNT", message: "Money object fields are invalid"))
  }
  guard Json.matches("^[A-Z]{3}$", currency) else {
    return .failure(ContractError(code: "MALFORMED_AMOUNT", message: "Currency must be an ISO code"))
  }
  if minor < 0 { return .failure(ContractError(code: "INVALID_AMOUNT", message: "Amount must be greater than zero")) }
  if exponent < 0 || exponent > 4 {
    return .failure(ContractError(code: "MALFORMED_AMOUNT", message: "Exponent is out of range"))
  }
  if minor == 0 { return .failure(ContractError(code: "INVALID_AMOUNT", message: "Amount must be greater than zero")) }
  if minor > 100_000_000 { return .failure(ContractError(code: "INVALID_AMOUNT", message: "Amount is too large")) }
  if currency == "GBP" && exponent == 2 && minor > 1_000_000 {
    return .failure(ContractError(code: "INVALID_AMOUNT", message: "Amount cannot exceed £10,000"))
  }
  return .success(Money(currency: currency, minor: minor, exponent: exponent))
}

private func legacyPence(_ minor: Int) -> Result<Money, ContractError> {
  if minor <= 0 { return .failure(ContractError(code: "INVALID_AMOUNT", message: "Amount must be greater than zero")) }
  if minor > 1_000_000 { return .failure(ContractError(code: "INVALID_AMOUNT", message: "Amount cannot exceed £10,000")) }
  return .success(Money(currency: "GBP", minor: minor, exponent: 2))
}

public func buttonHeight(platform: String, fontScale: Double) -> Double {
  let minimum = platform == "android" ? 48.0 : 44.0
  return max(minimum, 20.0 * fontScale + 24.0)
}

public func wrappedLines(text: String, fontScale: Double, containerWidth: Double, baseSize: Double) -> Int {
  if containerWidth <= 0 { return 1 }
  let width = Double(text.count) * baseSize * 0.55 * fontScale
  return max(1, Int(ceil(width / containerWidth)))
}

public func horizontalEdges(direction: String) -> (start: String, end: String) {
  direction == "rtl" ? ("right", "left") : ("left", "right")
}
