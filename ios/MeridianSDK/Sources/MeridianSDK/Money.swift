import Foundation

/// GBP minor-unit bounds. £0.01 is 1 pence and £10,000.00 is 1_000_000 pence.
public let gbpMinMinor = 1
public let gbpMaxMinor = 1_000_000

/// Canonical major-unit text for an integer pence amount, without grouping separators.
public func formatMinorUnits(_ pence: Int) -> String {
  let negative = pence < 0
  let absolute = abs(pence)
  let text = "\(absolute / 100)." + String(format: "%02d", absolute % 100)
  return negative ? "-" + text : text
}

/// Convert a major-unit decimal string to integer pence.
/// At most two fractional digits are kept as-is. Further digits round half up, including exact halves.
/// Values that round to 0 or above £10,000.00 are rejected. Signs and exponents are rejected.
public func roundMajorToMinor(_ input: String) -> (Int?, String?) {
  let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty {
    return (nil, "Amount is required")
  }
  if trimmed.contains("-") || trimmed.contains("+") || trimmed.lowercased().contains("e") {
    return (nil, "Amount cannot contain sign or exponent notation")
  }
  let pattern = "^\\d+(\\.\\d*)?$"
  let regex = try? NSRegularExpression(pattern: pattern)
  let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
  guard regex?.firstMatch(in: trimmed, range: range) != nil else {
    return (nil, "Amount must be a valid number")
  }

  let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
  let poundsStr = String(parts[0])
  if poundsStr.count > 5 {
    return (nil, "Amount cannot exceed £10,000")
  }
  let fraction = parts.count == 2 ? String(parts[1]) : ""
  if fraction.count > 12 {
    return (nil, "Amount has too many decimal places")
  }
  guard let pounds = Int(poundsStr) else {
    return (nil, "Amount is not a valid integer")
  }
  if pounds > 10_000 {
    return (nil, "Amount cannot exceed £10,000")
  }

  let padded = fraction + String(repeating: "0", count: max(0, 2 - fraction.count))
  let penceText = padded.prefix(2)
  guard var pence = Int(penceText) else {
    return (nil, "Amount is not a valid integer")
  }
  let rest = padded.dropFirst(2)
  if let first = rest.first, first >= "5" {
    pence += 1
  }
  var poundsTotal = pounds
  if pence >= 100 {
    poundsTotal += pence / 100
    pence %= 100
  }
  if poundsTotal > 10_000 || (poundsTotal == 10_000 && pence > 0) {
    return (nil, "Amount cannot exceed £10,000")
  }
  let total = poundsTotal * 100 + pence
  if total <= 0 {
    return (nil, "Amount must be greater than zero")
  }
  if total > gbpMaxMinor {
    return (nil, "Amount cannot exceed £10,000")
  }
  return (total, nil)
}
