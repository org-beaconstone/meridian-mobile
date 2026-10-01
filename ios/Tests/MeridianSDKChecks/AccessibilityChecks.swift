import Foundation
@testable import MeridianSDK

// MARK: - Accessibility & Localisation Tests
//
// Verifies:
//   - money() produces VoiceOver-friendly strings (£ prefix, no ambiguity)
//   - Leading-zero pence formatting (£0.01 not £.01)
//   - Large-font / large-amount formatting stays consistent
//   - RTL readiness: currency symbol precedes digits (no digit-first strings)
//   - parseAmount rejects locale-specific separators (commas) as input
//   - Recipient / Provider strings are non-empty and screen-reader safe
//   - Error messages are human-readable (not raw codes)
//   - Category display names map to human-readable strings

func runAccessibilityChecks(passed: inout Int, failed: inout Int) {
  print("\n=== Accessibility & Localisation Tests ===\n")

  // A1: money() output starts with the £ symbol (not a digit) – RTL readiness
  print("A1. money() output begins with currency symbol (RTL-safe)...")
  let amounts = [1, 50, 100, 1_050, 999_999]
  let allPrefixed = amounts.allSatisfy { money($0).hasPrefix("£") }
  if allPrefixed {
    print("  ✓ All amounts begin with £ – currency-symbol-first (RTL-safe)")
    passed += 1
  } else {
    let failures = amounts.filter { !money($0).hasPrefix("£") }.map { money($0) }
    print("  ✗ Some amounts do not begin with £: \(failures)")
    failed += 1
  }

  // A2: money(1) produces leading zero before decimal (£0.01, not £.01)
  print("A2. money(1) leading-zero before decimal...")
  let penny = money(1)
  if penny == "£0.01" {
    print("  ✓ money(1) = \(penny) – leading zero present")
    passed += 1
  } else {
    print("  ✗ Expected £0.01, got: \(penny)")
    failed += 1
  }

  // A3: money() always produces exactly two decimal places
  print("A3. money() always produces exactly two decimal places...")
  let testPences = [0, 1, 10, 100, 1_000, 10_050, 1_000_000]
  let allTwoDecimal = testPences.allSatisfy { pence -> Bool in
    let formatted = money(pence)
    guard let dotIdx = formatted.firstIndex(of: ".") else { return false }
    let afterDot = formatted[formatted.index(after: dotIdx)...]
    return afterDot.count == 2
  }
  if allTwoDecimal {
    print("  ✓ All money() outputs have exactly two decimal places")
    passed += 1
  } else {
    let failures = testPences.map { money($0) }
    print("  ✗ Some money() outputs do not have two decimal places: \(failures)")
    failed += 1
  }

  // A4: money() output contains only £, digits, and a single decimal point
  print("A4. money() output contains only safe characters (VoiceOver-friendly)...")
  let allowedSet = CharacterSet(charactersIn: "£0123456789.")
  let allSafe = testPences.allSatisfy { pence -> Bool in
    let formatted = money(pence)
    return formatted.unicodeScalars.allSatisfy { allowedSet.contains($0) }
  }
  if allSafe {
    print("  ✓ All money() outputs contain only £, digits, and decimal point")
    passed += 1
  } else {
    print("  ✗ money() output contains unexpected characters")
    failed += 1
  }

  // A5: Category rawValues are human-readable (not machine codes)
  print("A5. Category display names are human-readable...")
  let humanReadable = Category.allCases.allSatisfy { cat in
    let raw = cat.rawValue
    return !raw.isEmpty
      && raw.first?.isUppercase == true
      && raw == raw.trimmingCharacters(in: .whitespaces)
  }
  if humanReadable {
    let names = Category.allCases.map { $0.rawValue }
    print("  ✓ Category names: \(names)")
    passed += 1
  } else {
    print("  ✗ Some category names are not human-readable")
    failed += 1
  }

  // A6: Provider names are non-empty and descriptions are non-empty
  print("A6. Provider fields are non-empty (TalkBack/VoiceOver labels)...")
  let providersJson = """
  [
    {"id": "adyen", "name": "Adyen", "description": "Card payment processor", "methods": ["card"]},
    {"id": "worldpay", "name": "Worldpay", "description": "Bank transfer processor", "methods": ["bank"]}
  ]
  """
  do {
    let providers = try JSONDecoder().decode([Provider].self, from: providersJson.data(using: .utf8)!)
    let allValid = providers.allSatisfy { !$0.name.isEmpty && !$0.description.isEmpty && !$0.methods.isEmpty }
    if allValid {
      print("  ✓ All provider names and descriptions are non-empty")
      passed += 1
    } else {
      print("  ✗ Some provider fields are empty")
      failed += 1
    }
  } catch {
    print("  ✗ Provider decoding failed: \(error)")
    failed += 1
  }

  // A7: parseAmount rejects locale-specific comma separator (en-DE style)
  print("A7. parseAmount rejects comma decimal separator (locale-independence)...")
  let commaInputs = ["10,50", "1,000", "10,5"]
  let allRejected = commaInputs.allSatisfy { input in
    let (pence, _) = parseAmount(input)
    return pence == nil
  }
  if allRejected {
    print("  ✓ Comma-separated amounts rejected – input is locale-independent")
    passed += 1
  } else {
    let accepted = commaInputs.filter { parseAmount($0).0 != nil }
    print("  ✗ Some comma-separated amounts were accepted: \(accepted)")
    failed += 1
  }

  // A8: MeridianError descriptions are human-readable sentences
  print("A8. MeridianError descriptions are human-readable...")
  let errors: [MeridianError] = [
    .networkError("timeout"),
    .invalidURL,
    .decodingError("field missing"),
    .httpError(statusCode: 503, message: "Service unavailable"),
    .missingSession,
    .invalidAmount("negative not allowed"),
    .validationError("note too long")
  ]
  let allDescribed = errors.allSatisfy { err in
    guard let desc = err.errorDescription else { return false }
    return !desc.isEmpty && desc.count > 5
  }
  if allDescribed {
    print("  ✓ All MeridianError cases have non-trivial human-readable descriptions")
    passed += 1
  } else {
    print("  ✗ Some MeridianError descriptions are missing or too short")
    failed += 1
  }

  // A9: Recipient initials are 1-3 characters (safe for avatar labels)
  print("A9. Recipient initials are 1-3 characters (avatar accessibility)...")
  let recipientsJson = """
  [
    {"id": "r1", "name": "Alice", "initials": "A", "detail": "d", "category": "Shopping", "color": "#FFF"},
    {"id": "r2", "name": "Birch & Bloom", "initials": "BB", "detail": "d", "category": "Food & drink", "color": "#FFF"},
    {"id": "r3", "name": "Northline Studio", "initials": "NS", "detail": "d", "category": "Lifestyle", "color": "#FFF"}
  ]
  """
  do {
    let recipients = try JSONDecoder().decode([Recipient].self, from: recipientsJson.data(using: .utf8)!)
    let allValidInitials = recipients.allSatisfy { r in
      !r.initials.isEmpty && r.initials.count <= 3
    }
    if allValidInitials {
      print("  ✓ All recipient initials are 1-3 characters")
      passed += 1
    } else {
      print("  ✗ Some initials are outside the 1-3 character range")
      failed += 1
    }
  } catch {
    print("  ✗ Recipient decoding failed: \(error)")
    failed += 1
  }

  // A10: Large-amount money() formatting is consistent (no truncation or scientific notation)
  print("A10. Large amounts formatted consistently (no scientific notation)...")
  let largeAmounts = [100_000, 500_000, 999_999, 1_000_000]
  let allConsistent = largeAmounts.allSatisfy { pence -> Bool in
    let formatted = money(pence)
    // Must not contain 'e' or 'E' (scientific notation)
    // Must start with £
    // Must have exactly one decimal point
    let noScientific = !formatted.lowercased().contains("e")
    let hasPound = formatted.hasPrefix("£")
    let oneDecimal = formatted.filter { $0 == "." }.count == 1
    return noScientific && hasPound && oneDecimal
  }
  if allConsistent {
    let examples = largeAmounts.map { "\(money($0))" }.joined(separator: ", ")
    print("  ✓ Large amounts formatted consistently: \(examples)")
    passed += 1
  } else {
    print("  ✗ Some large amounts formatted inconsistently")
    failed += 1
  }
}
