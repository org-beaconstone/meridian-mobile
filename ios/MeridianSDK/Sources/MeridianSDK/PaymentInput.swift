import Foundation

// Payment amounts stay integer GBP pence (£0.01...£10,000.00). The IBAN check is a
// client-side format check for the existing Worldpay bank method. It does not add a
// provider and it is not sent to the payment API.

public struct AmountEvaluation: Equatable {
  public let minorUnits: Int?
  public let isValid: Bool
  public let helper: String
  public let spoken: String
  public let prefix: String

  public init(minorUnits: Int?, isValid: Bool, helper: String, spoken: String, prefix: String) {
    self.minorUnits = minorUnits
    self.isValid = isValid
    self.helper = helper
    self.spoken = spoken
    self.prefix = prefix
  }
}

public struct IbanCheck: Equatable {
  public let normalized: String
  public let isValid: Bool
  public let helper: String

  public init(normalized: String, isValid: Bool, helper: String) {
    self.normalized = normalized
    self.isValid = isValid
    self.helper = helper
  }
}

public struct PaymentEntry: Equatable, Codable {
  public var amount: String
  public var iban: String
  public var reference: String
  public var recipientId: String
  public var method: String
  public var idempotencyKey: String
  public var reviewing: Bool

  public init(
    amount: String = "",
    iban: String = "",
    reference: String = "",
    recipientId: String = "",
    method: String = "card",
    idempotencyKey: String = "",
    reviewing: Bool = false
  ) {
    self.amount = amount
    self.iban = iban
    self.reference = reference
    self.recipientId = recipientId
    self.method = method
    self.idempotencyKey = idempotencyKey
    self.reviewing = reviewing
  }
}

public enum PaymentEntryEvent: Equatable {
  case review(newKey: String)
  case edit(newKey: String)
  case completed(newKey: String)
  case sessionChanged(newKey: String)
  case pending
  case networkFailure
  case rejected
}

private struct IbanCountry {
  let name: String
  let length: Int
}

private let europeanIbans: [String: IbanCountry] = [
  "AD": IbanCountry(name: "Andorra", length: 24),
  "AT": IbanCountry(name: "Austria", length: 20),
  "BE": IbanCountry(name: "Belgium", length: 16),
  "BG": IbanCountry(name: "Bulgaria", length: 22),
  "CH": IbanCountry(name: "Switzerland", length: 21),
  "CY": IbanCountry(name: "Cyprus", length: 28),
  "CZ": IbanCountry(name: "Czechia", length: 24),
  "DE": IbanCountry(name: "Germany", length: 22),
  "DK": IbanCountry(name: "Denmark", length: 18),
  "EE": IbanCountry(name: "Estonia", length: 20),
  "ES": IbanCountry(name: "Spain", length: 24),
  "FI": IbanCountry(name: "Finland", length: 18),
  "FR": IbanCountry(name: "France", length: 27),
  "GB": IbanCountry(name: "the United Kingdom", length: 22),
  "GI": IbanCountry(name: "Gibraltar", length: 23),
  "GR": IbanCountry(name: "Greece", length: 27),
  "HR": IbanCountry(name: "Croatia", length: 21),
  "HU": IbanCountry(name: "Hungary", length: 28),
  "IE": IbanCountry(name: "Ireland", length: 22),
  "IS": IbanCountry(name: "Iceland", length: 26),
  "IT": IbanCountry(name: "Italy", length: 27),
  "LI": IbanCountry(name: "Liechtenstein", length: 21),
  "LT": IbanCountry(name: "Lithuania", length: 20),
  "LU": IbanCountry(name: "Luxembourg", length: 20),
  "LV": IbanCountry(name: "Latvia", length: 21),
  "MC": IbanCountry(name: "Monaco", length: 27),
  "MT": IbanCountry(name: "Malta", length: 31),
  "NL": IbanCountry(name: "the Netherlands", length: 18),
  "NO": IbanCountry(name: "Norway", length: 15),
  "PL": IbanCountry(name: "Poland", length: 28),
  "PT": IbanCountry(name: "Portugal", length: 25),
  "RO": IbanCountry(name: "Romania", length: 24),
  "SE": IbanCountry(name: "Sweden", length: 24),
  "SI": IbanCountry(name: "Slovenia", length: 19),
  "SK": IbanCountry(name: "Slovakia", length: 24),
  "SM": IbanCountry(name: "San Marino", length: 27),
  "VA": IbanCountry(name: "Vatican City", length: 22),
  "XK": IbanCountry(name: "Kosovo", length: 20),
]

/// en_GB currency prefix for the amount field. The rehearsal ledger is GBP.
public func currencyPrefixSymbol() -> String {
  "£"
}

/// VoiceOver phrase for an amount in integer pence, for example "10 pounds and 50 pence".
public func amountSpokenLabel(_ minorUnits: Int) -> String {
  let pounds = minorUnits / 100
  let pence = abs(minorUnits % 100)
  let poundUnit = pounds == 1 ? "pound" : "pounds"
  let penceUnit = pence == 1 ? "penny" : "pence"
  return "\(pounds) \(poundUnit) and \(pence) \(penceUnit)"
}

public func evaluateAmount(_ input: String) -> AmountEvaluation {
  let prefix = currencyPrefixSymbol()
  let (minor, error) = parseAmount(input)
  if let minor {
    let spoken = amountSpokenLabel(minor)
    return AmountEvaluation(
      minorUnits: minor,
      isValid: true,
      helper: spoken,
      spoken: spoken,
      prefix: prefix
    )
  }
  let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty || trimmed == "£" {
    return AmountEvaluation(
      minorUnits: nil,
      isValid: false,
      helper: "Enter an amount from £0.01 to £10,000.00",
      spoken: "No amount entered",
      prefix: prefix
    )
  }
  return AmountEvaluation(
    minorUnits: nil,
    isValid: false,
    helper: error ?? "Enter an amount from £0.01 to £10,000.00",
    spoken: "Invalid amount",
    prefix: prefix
  )
}

public func formatIbanGroups(_ compact: String) -> String {
  var groups: [String] = []
  var index = compact.startIndex
  while index < compact.endIndex {
    let next = compact.index(index, offsetBy: 4, limitedBy: compact.endIndex) ?? compact.endIndex
    groups.append(String(compact[index..<next]))
    index = next
  }
  return groups.joined(separator: " ")
}

public func validateIban(_ raw: String) -> IbanCheck {
  let compact = String(raw.uppercased().filter { !$0.isWhitespace && $0 != "-" })
  if compact.isEmpty {
    return IbanCheck(normalized: "", isValid: false, helper: "Enter the recipient IBAN")
  }
  if compact.contains(where: { !isAsciiDigit($0) && !isAsciiUppercase($0) }) {
    return IbanCheck(
      normalized: compact,
      isValid: false,
      helper: "IBAN can contain only letters and numbers"
    )
  }
  if compact.count < 2 || !compact.prefix(2).allSatisfy(isAsciiUppercase) {
    return IbanCheck(
      normalized: compact,
      isValid: false,
      helper: "IBAN must start with a two-letter country code"
    )
  }
  let country = String(compact.prefix(2))
  guard let spec = europeanIbans[country] else {
    return IbanCheck(
      normalized: compact,
      isValid: false,
      helper: "Enter a European IBAN. \(country) is not a supported country code"
    )
  }
  if compact.count >= 4 {
    let checkDigits = compact.dropFirst(2).prefix(2)
    if !checkDigits.allSatisfy(isAsciiDigit) {
      return IbanCheck(
        normalized: compact,
        isValid: false,
        helper: "The two characters after the country code must be digits"
      )
    }
  }
  if compact.count < spec.length {
    let missing = spec.length - compact.count
    let noun = missing == 1 ? "character" : "characters"
    return IbanCheck(
      normalized: compact,
      isValid: false,
      helper: "IBANs for \(spec.name) are \(spec.length) characters. Enter \(missing) more \(noun)"
    )
  }
  if compact.count > spec.length {
    return IbanCheck(
      normalized: compact,
      isValid: false,
      helper: "IBANs for \(spec.name) are \(spec.length) characters"
    )
  }
  if !ibanChecksumValid(compact) {
    return IbanCheck(
      normalized: compact,
      isValid: false,
      helper: "IBAN checksum is invalid. Check the account number and try again"
    )
  }
  return IbanCheck(normalized: compact, isValid: true, helper: "IBAN checksum is valid")
}

public func paymentReviewError(_ entry: PaymentEntry) -> String? {
  let amount = evaluateAmount(entry.amount)
  if !amount.isValid {
    return amount.helper
  }
  if entry.reference.count > 200 {
    return "Reference is too long"
  }
  if entry.method == PaymentMethod.bank.rawValue {
    let iban = validateIban(entry.iban)
    if !iban.isValid {
      return iban.helper
    }
  }
  return nil
}

/// Keeps the typed amount, IBAN, and reference unless the payment completed.
/// Network failures, pending responses, and review/edit transitions keep the draft
/// and, except for a fresh review or edit, the same idempotency key.
public func reducePaymentEntry(_ entry: PaymentEntry, _ event: PaymentEntryEvent) -> PaymentEntry {
  var next = entry
  switch event {
  case let .review(newKey):
    next.reviewing = true
    next.idempotencyKey = newKey
  case let .edit(newKey):
    next.reviewing = false
    next.idempotencyKey = newKey
  case let .completed(newKey):
    next.amount = ""
    next.iban = ""
    next.reference = ""
    next.reviewing = false
    next.idempotencyKey = newKey
  case let .sessionChanged(newKey):
    next.reviewing = false
    next.idempotencyKey = newKey
  case .pending, .networkFailure, .rejected:
    break
  }
  return next
}

private func isAsciiUppercase(_ character: Character) -> Bool {
  guard let value = character.asciiValue else { return false }
  return value >= 65 && value <= 90
}

private func isAsciiDigit(_ character: Character) -> Bool {
  guard let value = character.asciiValue else { return false }
  return value >= 48 && value <= 57
}

private func ibanChecksumValid(_ compact: String) -> Bool {
  let rearranged = String(compact.dropFirst(4) + compact.prefix(4))
  var remainder = 0
  for character in rearranged {
    let value: String
    if character.isNumber {
      value = String(character)
    } else if character.isLetter, let ascii = character.asciiValue, let a = Character("A").asciiValue {
      value = String(Int(ascii) - Int(a) + 10)
    } else {
      return false
    }
    for digit in value {
      guard let number = digit.wholeNumberValue else { return false }
      remainder = (remainder * 10 + number) % 97
    }
  }
  return remainder == 1
}
