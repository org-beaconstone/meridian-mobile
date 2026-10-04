import Foundation

/// ISO 13616 MOD-97 checksum for rehearsal account numbers. This does not contact a bank.
public func ibanNormalize(_ raw: String) -> String {
  raw.uppercased().filter { !$0.isWhitespace }
}

public func ibanMod97(_ iban: String) -> Int {
  let rearranged = iban.dropFirst(4) + iban.prefix(4)
  var remainder = 0
  for character in rearranged {
    let digits: String
    if character.isNumber {
      digits = String(character)
    } else if let ascii = character.asciiValue, character.isLetter, ascii >= 65, ascii <= 90 {
      digits = String(Int(ascii - 65) + 10)
    } else {
      return -1
    }
    for digit in digits {
      guard let value = digit.wholeNumberValue else { return -1 }
      remainder = (remainder * 10 + value) % 97
    }
  }
  return remainder
}

public func ibanIsValid(_ raw: String) -> Bool {
  let iban = ibanNormalize(raw)
  guard iban.count >= 15 && iban.count <= 34 else { return false }
  let characters = Array(iban)
  guard characters[0].isLetter && characters[1].isLetter else { return false }
  guard characters[2].isNumber && characters[3].isNumber else { return false }
  guard characters.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
  return ibanMod97(iban) == 1
}

public func ibanCheckDigits(country: String, bban: String) -> String {
  let remainder = ibanMod97(country.uppercased() + "00" + bban.uppercased())
  let check = 98 - remainder
  return String(format: "%02d", check)
}

public func ibanCompose(country: String, bban: String) -> String {
  let code = country.uppercased()
  let body = bban.uppercased()
  return code + ibanCheckDigits(country: code, bban: body) + body
}
