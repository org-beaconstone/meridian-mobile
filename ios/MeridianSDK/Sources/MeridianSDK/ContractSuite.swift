import Foundation

// Consumer contracts and cross-platform scenarios shared with the Kotlin SDK.
// Live rehearsal submits integer GBP pence on Adyen card or Worldpay bank.
// EUR amounts decode for the newer money model and are not posted.

public enum JsonValue: Equatable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([JsonValue])
  case object([String: JsonValue])

  var object: [String: JsonValue]? {
    if case let .object(value) = self { return value }
    return nil
  }

  var array: [JsonValue]? {
    if case let .array(value) = self { return value }
    return nil
  }

  var int: Int? {
    if case let .int(value) = self { return value }
    return nil
  }

  var number: Double? {
    switch self {
    case let .int(value):
      return Double(value)
    case let .double(value):
      return value
    default:
      return nil
    }
  }

  var string: String? {
    if case let .string(value) = self { return value }
    return nil
  }

  var bool: Bool? {
    if case let .bool(value) = self { return value }
    return nil
  }

  func field(_ name: String) -> JsonValue? {
    object?[name]
  }
}

struct ContractParseError: Error, CustomStringConvertible {
  let description: String
}

struct JsonParser {
  private let chars: [Character]
  private var index = 0

  init(_ text: String) {
    chars = Array(text)
  }

  mutating func parse() throws -> JsonValue {
    skip()
    let value = try parseValue()
    skip()
    if index != chars.count {
      throw ContractParseError(description: "Trailing JSON")
    }
    return value
  }

  private mutating func parseValue() throws -> JsonValue {
    skip()
    guard index < chars.count else { throw ContractParseError(description: "Unexpected end of JSON") }
    let char = chars[index]
    switch char {
    case "{":
      return try parseObject()
    case "[":
      return try parseArray()
    case "\"":
      return .string(try parseString())
    case "t":
      try consumeLiteral("true")
      return .bool(true)
    case "f":
      try consumeLiteral("false")
      return .bool(false)
    case "n":
      try consumeLiteral("null")
      return .null
    default:
      return try parseNumber()
    }
  }

  private mutating func parseObject() throws -> JsonValue {
    index += 1
    skip()
    var fields: [String: JsonValue] = [:]
    if peek() == "}" {
      index += 1
      return .object(fields)
    }
    while index < chars.count {
      skip()
      guard peek() == "\"" else { throw ContractParseError(description: "Object key must be a string") }
      let key = try parseString()
      skip()
      guard peek() == ":" else { throw ContractParseError(description: "Expected colon") }
      index += 1
      let value = try parseValue()
      fields[key] = value
      skip()
      if peek() == "," {
        index += 1
        continue
      }
      if peek() == "}" {
        index += 1
        return .object(fields)
      }
      throw ContractParseError(description: "Expected comma or end of object")
    }
    throw ContractParseError(description: "Unclosed object")
  }

  private mutating func parseArray() throws -> JsonValue {
    index += 1
    skip()
    var items: [JsonValue] = []
    if peek() == "]" {
      index += 1
      return .array(items)
    }
    while index < chars.count {
      items.append(try parseValue())
      skip()
      if peek() == "," {
        index += 1
        continue
      }
      if peek() == "]" {
        index += 1
        return .array(items)
      }
      throw ContractParseError(description: "Expected comma or end of array")
    }
    throw ContractParseError(description: "Unclosed array")
  }

  private mutating func parseString() throws -> String {
    index += 1
    var result = ""
    while index < chars.count {
      let char = chars[index]
      index += 1
      if char == "\"" { return result }
      if char == "\\" {
        guard index < chars.count else { throw ContractParseError(description: "Bad escape") }
        let escaped = chars[index]
        index += 1
        switch escaped {
        case "\"": result.append("\"")
        case "\\": result.append("\\")
        case "/": result.append("/")
        case "b": result.append("\u{0008}")
        case "f": result.append("\u{000c}")
        case "n": result.append("\n")
        case "r": result.append("\r")
        case "t": result.append("\t")
        case "u":
          let scalar = try parseHexScalar()
          result.append(Character(scalar))
        default:
          throw ContractParseError(description: "Bad escape")
        }
      } else {
        result.append(char)
      }
    }
    throw ContractParseError(description: "Unclosed string")
  }

  private mutating func parseHexScalar() throws -> Unicode.Scalar {
    guard index + 4 <= chars.count else { throw ContractParseError(description: "Bad unicode escape") }
    let hex = String(chars[index..<(index + 4)])
    index += 4
    guard let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) else {
      throw ContractParseError(description: "Bad unicode escape")
    }
    return scalar
  }

  private mutating func parseNumber() throws -> JsonValue {
    let start = index
    if peek() == "-" { index += 1 }
    while index < chars.count, chars[index].isNumber { index += 1 }
    var fractional = false
    if peek() == "." {
      fractional = true
      index += 1
      while index < chars.count, chars[index].isNumber { index += 1 }
    }
    if peek() == "e" || peek() == "E" {
      fractional = true
      index += 1
      if peek() == "+" || peek() == "-" { index += 1 }
      while index < chars.count, chars[index].isNumber { index += 1 }
    }
    let token = String(chars[start..<index])
    if !fractional, let value = Int(token) { return .int(value) }
    if let value = Double(token) { return .double(value) }
    throw ContractParseError(description: "Bad number")
  }

  private mutating func consumeLiteral(_ literal: String) throws {
    for char in literal {
      guard peek() == char else { throw ContractParseError(description: "Expected \(literal)") }
      index += 1
    }
  }

  private func peek() -> Character? {
    index < chars.count ? chars[index] : nil
  }

  private mutating func skip() {
    while index < chars.count, chars[index] == " " || chars[index] == "\n" || chars[index] == "\r" || chars[index] == "\t" {
      index += 1
    }
  }
}

func jsonText(_ value: JsonValue) -> String {
  switch value {
  case .null:
    return "null"
  case let .bool(flag):
    return flag ? "true" : "false"
  case let .int(number):
    return String(number)
  case let .double(number):
    return String(number)
  case let .string(text):
    return "\"\(escapeJson(text))\""
  case let .array(items):
    return "[" + items.map(jsonText).joined(separator: ",") + "]"
  case let .object(fields):
    let body = fields.keys.sorted().map { key in
      "\(jsonText(.string(key))):\(jsonText(fields[key] ?? .null))"
    }.joined(separator: ",")
    return "{\(body)}"
  }
}

private func escapeJson(_ text: String) -> String {
  var escaped = ""
  for char in text {
    switch char {
    case "\\": escaped += "\\\\"
    case "\"": escaped += "\\\""
    case "\n": escaped += "\\n"
    case "\r": escaped += "\\r"
    case "\t": escaped += "\\t"
    default: escaped.append(char)
    }
  }
  return escaped
}

func nestedURL(_ base: URL, _ relative: String) -> URL {
  relative.split(separator: "/").reduce(base) { partial, part in
    partial.appendingPathComponent(String(part))
  }
}

func readJsonFile(_ url: URL) throws -> JsonValue {
  let text = try String(contentsOf: url, encoding: .utf8)
  var parser = JsonParser(text)
  return try parser.parse()
}

public func formatMinorUnits(_ minorUnits: Int, currency: String) -> String {
  let negative = minorUnits < 0
  let units = negative ? -Int64(minorUnits) : Int64(minorUnits)
  let major = Int(units / 100)
  let minor = Int(units % 100)
  let symbol: String
  switch currency {
  case "GBP": symbol = "£"
  case "EUR": symbol = "€"
  default: symbol = currency
  }
  let sign = negative ? "-" : ""
  return "\(sign)\(symbol)\(groupedMajorUnits(major)).\(String(format: "%02d", minor))"
}

func groupedMajorUnits(_ value: Int) -> String {
  let digits = Array(String(value))
  var grouped = ""
  for (index, character) in digits.reversed().enumerated() {
    if index != 0 && index % 3 == 0 { grouped.append(",") }
    grouped.append(character)
  }
  return String(grouped.reversed())
}

public enum AccessibilityCopy {
  public static let balanceBaseSp = 38.0
  public static let confirmLabel = "Confirm payment"
  public static let confirmHint = "Submits the reviewed GBP payment. No real money moves."
  public static let confirmTalkBack = "\(confirmLabel). \(confirmHint)"
  public static let arrangement = "start"

  public static func balanceLabel(_ formatted: String) -> String {
    "Everyday account balance, \(formatted)"
  }

  public static func scaledBalanceSp(_ fontScale: Double) -> Double {
    balanceBaseSp * fontScale
  }

  public static func minimumTouchTargetDp(_ fontScale: Double) -> Double {
    48.0 * max(fontScale, 1.0)
  }

  public static func startEdge(_ direction: String) -> String {
    direction == "rtl" ? "right" : "left"
  }
}

public struct BalanceAccessibility: Equatable {
  public let voiceOverLabel: String
  public let talkBackDescription: String
  public let scaledSp: Double
  public let minimumTouchTargetDp: Double
  public let startEdge: String
  public let arrangement: String
  public let amountText: String
  public let amountDirection: String
}

public func balanceAccessibility(minorUnits: Int, currency: String, fontScale: Double, direction: String) -> BalanceAccessibility {
  let amount = formatMinorUnits(minorUnits, currency: currency)
  let label = AccessibilityCopy.balanceLabel(amount)
  return BalanceAccessibility(
    voiceOverLabel: label,
    talkBackDescription: label,
    scaledSp: AccessibilityCopy.scaledBalanceSp(fontScale),
    minimumTouchTargetDp: AccessibilityCopy.minimumTouchTargetDp(fontScale),
    startEdge: AccessibilityCopy.startEdge(direction),
    arrangement: AccessibilityCopy.arrangement,
    amountText: amount,
    amountDirection: "ltr"
  )
}

public struct DecodedIntent: Equatable {
  public let recipientId: String
  public let minorUnits: Int
  public let currency: String
  public let method: String
  public let note: String
  public let scenario: String
  public let providerId: String
  public let submittable: Bool
}

public struct MoneySample: Equatable {
  public let providerId: String
  public let minorUnits: Int
  public let currency: String
}

public struct CatalogView: Equatable {
  public let recipientIds: [String]
  public let providerIds: [String]
  public let currencies: [String: [String]]
  public let samples: [MoneySample]
  public let rejections: [String]
  public var accepted: Bool { rejections.isEmpty }
}

public enum Decode<T> {
  case ok(T)
  case reject(String)
}

struct MoneyParts: Equatable {
  let minorUnits: Int
  let currency: String
}

public struct CatalogCache: Equatable {
  public let body: String
  public let fetchedAtEpochMs: Int64
  public let ttlMs: Int64

  public func isFresh(nowEpochMs: Int64) -> Bool {
    nowEpochMs >= fetchedAtEpochMs && nowEpochMs - fetchedAtEpochMs < ttlMs
  }
}

public struct PersistedIntent: Equatable {
  public let idempotencyKey: String
  public let recipientId: String
  public let minorUnits: Int
  public let currency: String
  public let method: String
  public let note: String
  public let providerId: String
}

struct IssuedReturn: Equatable {
  let nonce: String
  let paymentId: String
  let expiresAtEpochMs: Int64
  let consumed: Bool
}

public enum ReturnDecision: Equatable {
  case accepted(String)
  case rejected(String)
}

public struct ParsedReturnLink: Equatable {
  public let nonce: String
  public let paymentId: String
}

public func parseReturnLink(_ url: String) -> ParsedReturnLink? {
  let prefix = "meridian://payments/return?"
  guard url.hasPrefix(prefix) else { return nil }
  var params: [String: String] = [:]
  for part in url.dropFirst(prefix.count).split(separator: "&") {
    let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
    if pieces.count == 2, !pieces[0].isEmpty, !pieces[1].isEmpty {
      params[pieces[0]] = pieces[1]
    }
  }
  guard let nonce = params["state"], let paymentId = params["paymentId"] else { return nil }
  return ParsedReturnLink(nonce: nonce, paymentId: paymentId)
}

public final class SessionCheckpoint {
  private let directory: URL
  private let intentURL: URL
  private let returnsURL: URL
  private let cacheURL: URL

  public init(directory: URL) {
    self.directory = directory
    intentURL = directory.appendingPathComponent("intent.json")
    returnsURL = directory.appendingPathComponent("returns.json")
    cacheURL = directory.appendingPathComponent("catalog-cache.json")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  public func begin(_ intent: PersistedIntent) throws -> PersistedIntent {
    if let existing = try loadIntent() { return existing }
    try write(intentJson(intent), to: intentURL)
    return intent
  }

  public func loadIntent() throws -> PersistedIntent? {
    guard FileManager.default.fileExists(atPath: intentURL.path) else { return nil }
    return try persistedIntent(readJsonFile(intentURL))
  }

  public func issueReturn(nonce: String, paymentId: String, expiresAtEpochMs: Int64) throws {
    var current = try loadReturns().filter { $0.nonce != nonce }
    current.append(IssuedReturn(nonce: nonce, paymentId: paymentId, expiresAtEpochMs: expiresAtEpochMs, consumed: false))
    try write(returnsJson(current), to: returnsURL)
  }

  public func consume(url: String, nowEpochMs: Int64) throws -> ReturnDecision {
    guard let parsed = parseReturnLink(url) else { return .rejected("malformed deep link") }
    let issued = try loadReturns()
    guard let match = issued.first(where: { $0.nonce == parsed.nonce && $0.paymentId == parsed.paymentId }) else {
      return .rejected("unknown return state")
    }
    if nowEpochMs >= match.expiresAtEpochMs { return .rejected("expired return state") }
    if match.consumed { return .rejected("replayed deep link") }
    let updated = issued.map { item -> IssuedReturn in
      item.nonce == match.nonce
        ? IssuedReturn(nonce: item.nonce, paymentId: item.paymentId, expiresAtEpochMs: item.expiresAtEpochMs, consumed: true)
        : item
    }
    try write(returnsJson(updated), to: returnsURL)
    return .accepted(match.paymentId)
  }

  public func writeCache(_ cache: CatalogCache) throws {
    let value = JsonValue.object([
      "body": .string(cache.body),
      "fetchedAtEpochMs": .int(Int(cache.fetchedAtEpochMs)),
      "ttlMs": .int(Int(cache.ttlMs)),
    ])
    try write(value, to: cacheURL)
  }

  public func readCache(nowEpochMs: Int64) throws -> CatalogCache? {
    guard FileManager.default.fileExists(atPath: cacheURL.path) else { return nil }
    let json = try readJsonFile(cacheURL)
    guard
      let body = json.field("body")?.string,
      let fetched = json.field("fetchedAtEpochMs")?.int,
      let ttl = json.field("ttlMs")?.int
    else { return nil }
    let cache = CatalogCache(body: body, fetchedAtEpochMs: Int64(fetched), ttlMs: Int64(ttl))
    return cache.isFresh(nowEpochMs: nowEpochMs) ? cache : nil
  }

  private func loadReturns() throws -> [IssuedReturn] {
    guard FileManager.default.fileExists(atPath: returnsURL.path) else { return [] }
    guard let rows = try readJsonFile(returnsURL).array else { return [] }
    return try rows.map { try issuedReturn($0) }
  }

  private func write(_ value: JsonValue, to url: URL) throws {
    try jsonText(value).data(using: .utf8)?.write(to: url)
  }
}

private func intentJson(_ intent: PersistedIntent) -> JsonValue {
  .object([
    "idempotencyKey": .string(intent.idempotencyKey),
    "recipientId": .string(intent.recipientId),
    "minorUnits": .int(intent.minorUnits),
    "currency": .string(intent.currency),
    "method": .string(intent.method),
    "note": .string(intent.note),
    "providerId": .string(intent.providerId),
  ])
}

private func persistedIntent(_ json: JsonValue) throws -> PersistedIntent {
  guard
    let key = json.field("idempotencyKey")?.string,
    let recipientId = json.field("recipientId")?.string,
    let minorUnits = json.field("minorUnits")?.int,
    let currency = json.field("currency")?.string,
    let method = json.field("method")?.string,
    let note = json.field("note")?.string,
    let providerId = json.field("providerId")?.string
  else { throw ContractParseError(description: "Intent checkpoint is incomplete") }
  return PersistedIntent(
    idempotencyKey: key,
    recipientId: recipientId,
    minorUnits: minorUnits,
    currency: currency,
    method: method,
    note: note,
    providerId: providerId
  )
}

private func returnsJson(_ rows: [IssuedReturn]) -> JsonValue {
  .array(rows.map { row in
    .object([
      "nonce": .string(row.nonce),
      "paymentId": .string(row.paymentId),
      "expiresAtEpochMs": .int(Int(row.expiresAtEpochMs)),
      "consumed": .bool(row.consumed),
    ])
  })
}

private func issuedReturn(_ json: JsonValue) throws -> IssuedReturn {
  guard
    let nonce = json.field("nonce")?.string,
    let paymentId = json.field("paymentId")?.string,
    let expires = json.field("expiresAtEpochMs")?.int,
    let consumed = json.field("consumed")?.bool
  else { throw ContractParseError(description: "Return checkpoint is incomplete") }
  return IssuedReturn(nonce: nonce, paymentId: paymentId, expiresAtEpochMs: Int64(expires), consumed: consumed)
}

public func decodePaymentIntent(_ body: JsonValue) -> Decode<DecodedIntent> {
  guard let recipientId = textOrNil(body, "recipientId"), !recipientId.isEmpty else {
    return .reject("recipient id is required")
  }
  let method = textOrNil(body, "method")
  let providerId: String
  switch method {
  case "card": providerId = "adyen"
  case "bank": providerId = "worldpay"
  default: return .reject("unsupported payment method")
  }
  guard let scenario = textOrNil(body, "scenario"),
        ["success", "declined", "unavailable", "pending"].contains(scenario) else {
    return .reject("unknown scenario")
  }
  let note = body.field("note")?.string ?? ""
  switch decodeMoney(body) {
  case let .reject(reason):
    return .reject(reason)
  case let .ok(amount):
    let submittable = amount.currency == "GBP" && (1...1_000_000).contains(amount.minorUnits)
    return .ok(DecodedIntent(
      recipientId: recipientId,
      minorUnits: amount.minorUnits,
      currency: amount.currency,
      method: method ?? "",
      note: note,
      scenario: scenario,
      providerId: providerId,
      submittable: submittable
    ))
  }
}

private func decodeMoney(_ body: JsonValue) -> Decode<MoneyParts> {
  let amountNode: JsonValue?
  if let amount = body.field("amount"), amount != .null {
    amountNode = amount
  } else {
    amountNode = body.field("amountMinor")
  }
  guard let amountNode, amountNode != .null else { return .reject("minor units must be an integer") }
  return decodeMoneyNode(amountNode)
}

private func decodeMoneyNode(_ node: JsonValue) -> Decode<MoneyParts> {
  if let object = node.object {
    let raw: JsonValue?
    if object["minorUnits"] != nil {
      raw = object["minorUnits"]
    } else if object["amountMinor"] != nil {
      raw = object["amountMinor"]
    } else {
      raw = nil
    }
    guard let raw, let units = integralMinor(raw) else { return .reject("minor units must be an integer") }
    if units <= 0 { return .reject("minor units must be positive") }
    let currency = object["currency"]?.string ?? "GBP"
    if currency != "GBP" && currency != "EUR" { return .reject("unknown currency") }
    return .ok(MoneyParts(minorUnits: units, currency: currency))
  }
  guard let units = integralMinor(node) else { return .reject("minor units must be an integer") }
  if units <= 0 { return .reject("minor units must be positive") }
  return .ok(MoneyParts(minorUnits: units, currency: "GBP"))
}

private func integralMinor(_ node: JsonValue) -> Int? {
  node.int
}

public func encodeLegacyPayment(_ intent: DecodedIntent) -> Decode<JsonValue> {
  if !intent.submittable { return .reject("Only GBP integer pence can be submitted") }
  return .ok(.object([
    "recipientId": .string(intent.recipientId),
    "amountMinor": .int(intent.minorUnits),
    "method": .string(intent.method),
    "note": .string(intent.note),
    "scenario": .string(intent.scenario),
  ]))
}

public func validateCatalog(_ body: JsonValue) -> CatalogView {
  var rejections: [String] = []
  var recipientIds: [String] = []
  if let recipients = body.field("recipients")?.array {
    for recipient in recipients {
      if let id = textOrNil(recipient, "id"), !id.isEmpty {
        recipientIds.append(id)
      } else {
        rejections.append("recipient id is required")
      }
      if textOrNil(recipient, "name")?.isEmpty != false {
        rejections.append("recipient name is required")
      }
      let category = textOrNil(recipient, "category")
      if !["Shopping", "Food & drink", "Transport", "Bills", "Lifestyle"].contains(category ?? "") {
        rejections.append("unknown category")
      }
    }
  } else {
    rejections.append("recipients must be a list")
  }

  var providerIds: [String] = []
  var currencies: [String: [String]] = [:]
  var samples: [MoneySample] = []
  if let providers = body.field("providers")?.array {
    for provider in providers {
      guard let id = textOrNil(provider, "id"), !id.isEmpty else {
        rejections.append("provider id is required")
        continue
      }
      if id != "adyen" && id != "worldpay" {
        rejections.append("unknown provider")
        continue
      }
      providerIds.append(id)
      let methods = provider.field("methods")?.array?.compactMap(\.string) ?? []
      if methods.isEmpty || methods.contains(where: { $0 != "card" && $0 != "bank" }) {
        rejections.append("unsupported payment method")
      } else if id == "adyen" && methods != ["card"] {
        rejections.append("baseline method mismatch")
      } else if id == "worldpay" && methods != ["bank"] {
        rejections.append("baseline method mismatch")
      }
      let codes = provider.field("currencies")?.array?.compactMap(\.string) ?? ["GBP"]
      if codes.contains(where: { $0 != "GBP" && $0 != "EUR" }) {
        rejections.append("unknown currency")
      }
      currencies[id] = codes
      if let sampleNode = provider.field("sampleAmount"), sampleNode != .null {
        switch decodeMoneyNode(sampleNode) {
        case let .reject(reason):
          rejections.append(reason)
        case let .ok(sample):
          samples.append(MoneySample(providerId: id, minorUnits: sample.minorUnits, currency: sample.currency))
        }
      }
    }
  } else {
    rejections.append("providers must be a list")
  }
  if !providerIds.contains("adyen") || !providerIds.contains("worldpay") {
    rejections.append("baseline providers required")
  }
  return CatalogView(
    recipientIds: recipientIds,
    providerIds: providerIds,
    currencies: currencies,
    samples: samples,
    rejections: rejections
  )
}

private func textOrNil(_ node: JsonValue, _ field: String) -> String? {
  guard let value = node.field(field), value != .null else { return nil }
  return value.string
}

public struct SectionResult: Equatable {
  public let name: String
  public let failures: [String]
}

public struct SuiteReport: Equatable {
  public let sections: [SectionResult]
  public var failures: [String] {
    sections.flatMap { section in section.failures.map { "\(section.name): \($0)" } }
  }
}

public func locateContractsDirectory(start: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> URL? {
  var url = start
  for _ in 0..<8 {
    let marker = nestedURL(url, "contracts/scenarios/parity.json")
    if FileManager.default.fileExists(atPath: marker.path) {
      return url.appendingPathComponent("contracts")
    }
    if url.path == "/" { break }
    url.deleteLastPathComponent()
  }
  return nil
}

public func runParitySuiteOrThrow() -> SuiteReport {
  guard let contracts = locateContractsDirectory() else {
    return SuiteReport(sections: [SectionResult(name: "contracts", failures: ["contracts directory not found"])])
  }
  do {
    return try runParitySuite(contracts)
  } catch {
    return SuiteReport(sections: [SectionResult(name: "contracts", failures: [String(describing: error)])])
  }
}

public func runParitySuite(_ contracts: URL) throws -> SuiteReport {
  let parity = try readJsonFile(nestedURL(contracts, "scenarios/parity.json"))
  let repoRoot = contracts.deletingLastPathComponent()
  let sections = [
    try sectionMoney(parity),
    try sectionLegacyIntent(contracts),
    try sectionMultiCurrencyIntent(contracts),
    try sectionCatalog(contracts, path: "consumer/catalog-legacy.json", name: "legacy catalog", samples: false),
    try sectionCatalog(contracts, path: "consumer/catalog-multi-currency.json", name: "multi-currency catalog", samples: true),
    try sectionCache(parity, contracts),
    try sectionProcessDeath(parity),
    try sectionReplayedDeepLink(parity),
    try sectionExpiredReturn(parity),
    try sectionMalformedCatalog(contracts),
    try sectionAccessibility(parity, repoRoot),
  ]
  return SuiteReport(sections: sections)
}

private func sectionMoney(_ parity: JsonValue) throws -> SectionResult {
  var failures: [String] = []
  for row in parity.field("money")?.array ?? [] {
    let minor = row.field("minorUnits")?.int ?? -1
    let currency = row.field("currency")?.string ?? ""
    let formatted = formatMinorUnits(minor, currency: currency)
    let expected = row.field("formatted")?.string ?? ""
    if formatted != expected {
      failures.append("format \(minor) \(currency) -> \(formatted), expected \(expected)")
    }
    if currency == "GBP" && money(minor) != expected {
      failures.append("money() diverged for \(minor)")
    }
  }
  return SectionResult(name: "money formatting", failures: failures)
}

private func sectionLegacyIntent(_ contracts: URL) throws -> SectionResult {
  var failures: [String] = []
  let doc = try readJsonFile(nestedURL(contracts, "consumer/payment-intent-legacy.json"))
  let body = doc.field("request")?.field("body") ?? .null
  let expect = doc.field("expect") ?? .null
  switch decodePaymentIntent(body) {
  case let .reject(reason):
    failures.append(reason)
  case let .ok(intent):
    if intent.minorUnits != expect.field("minorUnits")?.int { failures.append("minor units \(intent.minorUnits)") }
    if intent.currency != expect.field("currency")?.string { failures.append("currency \(intent.currency)") }
    if intent.submittable != expect.field("submittable")?.bool { failures.append("submittable \(intent.submittable)") }
    if intent.providerId != expect.field("providerId")?.string { failures.append("provider \(intent.providerId)") }
    switch encodeLegacyPayment(intent) {
    case let .reject(reason):
      failures.append(reason)
    case let .ok(encoded):
      let keys = encoded.object?.keys.sorted() ?? []
      let expectedKeys = (expect.field("legacyKeys")?.array ?? []).compactMap(\.string).sorted()
      if keys != expectedKeys { failures.append("legacy keys \(keys)") }
      if encoded != body { failures.append("re-encoded legacy body changed") }
    }
    if doc.field("request")?.field("headers")?.field("Idempotency-Key")?.string != "intent-key-144" {
      failures.append("idempotency header drifted")
    }
    if (doc.field("request")?.field("headers")?.field("X-Rehearsal-Session")?.string ?? "").isEmpty {
      failures.append("session header missing")
    }
  }
  return SectionResult(name: "legacy integer payment intent", failures: failures)
}

private func sectionMultiCurrencyIntent(_ contracts: URL) throws -> SectionResult {
  var failures: [String] = []
  let legacyBody = try readJsonFile(nestedURL(contracts, "consumer/payment-intent-legacy.json"))
    .field("request")?.field("body") ?? .null
  let doc = try readJsonFile(nestedURL(contracts, "consumer/payment-intent-multi-currency.json"))
  for row in doc.field("intents")?.array ?? [] {
    let name = row.field("name")?.string ?? "intent"
    let expect = row.field("expect") ?? .null
    switch decodePaymentIntent(row.field("body") ?? .null) {
    case let .reject(reason):
      if let expectedReject = expect.field("reject")?.string {
        if reason != expectedReject { failures.append("\(name) reason \(reason)") }
      } else {
        failures.append("\(name) rejected: \(reason)")
      }
    case let .ok(intent):
      if expect.field("reject") != nil {
        failures.append("\(name) should reject")
        continue
      }
      if intent.minorUnits != expect.field("minorUnits")?.int { failures.append("\(name) minor \(intent.minorUnits)") }
      if intent.currency != expect.field("currency")?.string { failures.append("\(name) currency \(intent.currency)") }
      if intent.submittable != expect.field("submittable")?.bool { failures.append("\(name) submittable \(intent.submittable)") }
      if intent.providerId != expect.field("providerId")?.string { failures.append("\(name) provider \(intent.providerId)") }
      if expect.field("legacyAmountMinor") != nil {
        switch encodeLegacyPayment(intent) {
        case let .reject(reason):
          failures.append("\(name) encode \(reason)")
        case let .ok(encoded):
          if encoded.field("amountMinor")?.int != expect.field("legacyAmountMinor")?.int {
            failures.append("\(name) legacy amount")
          }
          if encoded.field("currency") != nil {
            failures.append("\(name) leaked currency onto the rehearsal body")
          }
          if name.hasPrefix("gbp object"), encoded != legacyBody {
            failures.append("\(name) is not backward compatible with the legacy integer payload")
          }
        }
      } else if !intent.submittable {
        if case let .reject(reason) = encodeLegacyPayment(intent), reason == "Only GBP integer pence can be submitted" {
          continue
        }
        failures.append("\(name) was submitted")
      }
    }
  }
  return SectionResult(name: "multi-currency payment intent", failures: failures)
}

private func sectionCatalog(_ contracts: URL, path: String, name: String, samples: Bool) throws -> SectionResult {
  var failures: [String] = []
  let doc = try readJsonFile(nestedURL(contracts, path))
  let view = validateCatalog(doc.field("response")?.field("body") ?? .null)
  let expect = doc.field("expect") ?? .null
  if view.accepted != expect.field("accepted")?.bool {
    failures.append("accepted \(view.accepted) \(view.rejections)")
  }
  let providerIds = (expect.field("providerIds")?.array ?? []).compactMap(\.string)
  if view.providerIds != providerIds { failures.append("providers \(view.providerIds)") }
  let recipientIds = (expect.field("recipientIds")?.array ?? []).compactMap(\.string)
  if view.recipientIds != recipientIds { failures.append("recipients \(view.recipientIds)") }
  for (id, node) in expect.field("currencies")?.object ?? [:] {
    let got = view.currencies[id] ?? []
    let want = (node.array ?? []).compactMap(\.string)
    if got != want { failures.append("currencies \(id) \(got)") }
  }
  if samples {
    let want = (expect.field("samples")?.array ?? []).compactMap { sample -> MoneySample? in
      guard let providerId = sample.field("providerId")?.string,
            let minorUnits = sample.field("minorUnits")?.int,
            let currency = sample.field("currency")?.string else { return nil }
      return MoneySample(providerId: providerId, minorUnits: minorUnits, currency: currency)
    }
    if view.samples != want { failures.append("samples \(view.samples)") }
  }
  if view.providerIds.contains(where: { $0 != "adyen" && $0 != "worldpay" }) {
    failures.append("third provider accepted")
  }
  return SectionResult(name: name, failures: failures)
}

private func sectionCache(_ parity: JsonValue, _ contracts: URL) throws -> SectionResult {
  var failures: [String] = []
  let fetchedAt: Int64 = 1_000_000
  for row in parity.field("cache")?.array ?? [] {
    let ttl = Int64(row.field("ttlMs")?.int ?? 0)
    let age = Int64(row.field("ageMs")?.int ?? 0)
    let cache = CatalogCache(body: "catalog", fetchedAtEpochMs: fetchedAt, ttlMs: ttl)
    let fresh = cache.isFresh(nowEpochMs: fetchedAt + age)
    if fresh != row.field("fresh")?.bool {
      failures.append("age \(age) fresh=\(fresh)")
    }
  }
  let legacy = try String(contentsOf: nestedURL(contracts, "consumer/catalog-legacy.json"), encoding: .utf8)
  let freshDir = try makeTemp("cache-fresh")
  let freshStore = SessionCheckpoint(directory: freshDir)
  try freshStore.writeCache(CatalogCache(body: legacy, fetchedAtEpochMs: fetchedAt, ttlMs: 300_000))
  let reloaded = try SessionCheckpoint(directory: freshDir).readCache(nowEpochMs: fetchedAt + 1_000)
  if reloaded?.body != legacy { failures.append("fresh catalog cache did not survive reload") }
  let staleDir = try makeTemp("cache-stale")
  try SessionCheckpoint(directory: staleDir).writeCache(CatalogCache(body: legacy, fetchedAtEpochMs: fetchedAt, ttlMs: 300_000))
  if try SessionCheckpoint(directory: staleDir).readCache(nowEpochMs: fetchedAt + 300_000) != nil {
    failures.append("expired catalog cache was served after process reload")
  }
  return SectionResult(name: "cache expiry", failures: failures)
}

private func sectionProcessDeath(_ parity: JsonValue) throws -> SectionResult {
  var failures: [String] = []
  let spec = parity.field("processDeath") ?? .null
  let intent = PersistedIntent(
    idempotencyKey: spec.field("idempotencyKey")?.string ?? "",
    recipientId: spec.field("recipientId")?.string ?? "",
    minorUnits: spec.field("amountMinor")?.int ?? 0,
    currency: spec.field("currency")?.string ?? "",
    method: spec.field("method")?.string ?? "",
    note: spec.field("note")?.string ?? "",
    providerId: spec.field("providerId")?.string ?? ""
  )
  let dir = try makeTemp("process-death")
  let first = try SessionCheckpoint(directory: dir).begin(intent)
  let restored = try SessionCheckpoint(directory: dir).loadIntent()
  if restored != first { failures.append("restored intent \(String(describing: restored))") }
  if restored?.idempotencyKey != intent.idempotencyKey { failures.append("idempotency key was not retained") }
  let conflicting = PersistedIntent(
    idempotencyKey: "rotated-key",
    recipientId: intent.recipientId,
    minorUnits: spec.field("conflictingAmountMinor")?.int ?? 0,
    currency: intent.currency,
    method: intent.method,
    note: intent.note,
    providerId: intent.providerId
  )
  let kept = try SessionCheckpoint(directory: dir).begin(conflicting)
  if kept.idempotencyKey != intent.idempotencyKey || kept.minorUnits != intent.minorUnits {
    failures.append("in-flight intent was replaced after restart")
  }
  if kept.providerId != "adyen" || kept.method != "card" {
    failures.append("provider changed across process death")
  }
  return SectionResult(name: "idempotency persistence and process death", failures: failures)
}

private func sectionReplayedDeepLink(_ parity: JsonValue) throws -> SectionResult {
  var failures: [String] = []
  let spec = parity.field("returns") ?? .null
  let dir = try makeTemp("replay")
  let store = SessionCheckpoint(directory: dir)
  try store.issueReturn(
    nonce: spec.field("nonce")?.string ?? "",
    paymentId: spec.field("paymentId")?.string ?? "",
    expiresAtEpochMs: Int64(spec.field("expiresAtEpochMs")?.int ?? 0)
  )
  let accepted = try store.consume(
    url: spec.field("validUrl")?.string ?? "",
    nowEpochMs: Int64(spec.field("acceptedAtEpochMs")?.int ?? 0)
  )
  if accepted != .accepted(spec.field("paymentId")?.string ?? "") {
    failures.append("first return was not accepted")
  }
  let replay = try SessionCheckpoint(directory: dir).consume(
    url: spec.field("validUrl")?.string ?? "",
    nowEpochMs: Int64(spec.field("acceptedAtEpochMs")?.int ?? 0)
  )
  if replay != .rejected(spec.field("replayReason")?.string ?? "") {
    failures.append("replay reason \(replay)")
  }
  let malformed = try store.consume(
    url: spec.field("malformedUrl")?.string ?? "",
    nowEpochMs: Int64(spec.field("acceptedAtEpochMs")?.int ?? 0)
  )
  if malformed != .rejected(spec.field("malformedReason")?.string ?? "") {
    failures.append("malformed deep link was not rejected")
  }
  let unknown = try store.consume(
    url: spec.field("unknownUrl")?.string ?? "",
    nowEpochMs: Int64(spec.field("acceptedAtEpochMs")?.int ?? 0)
  )
  if unknown != .rejected(spec.field("unknownReason")?.string ?? "") {
    failures.append("unknown return state was not rejected")
  }
  return SectionResult(name: "replayed deep links", failures: failures)
}

private func sectionExpiredReturn(_ parity: JsonValue) throws -> SectionResult {
  var failures: [String] = []
  let spec = parity.field("returns") ?? .null
  let dir = try makeTemp("expired-return")
  let store = SessionCheckpoint(directory: dir)
  try store.issueReturn(
    nonce: spec.field("nonce")?.string ?? "",
    paymentId: spec.field("paymentId")?.string ?? "",
    expiresAtEpochMs: Int64(spec.field("expiresAtEpochMs")?.int ?? 0)
  )
  let expired = try store.consume(
    url: spec.field("validUrl")?.string ?? "",
    nowEpochMs: Int64(spec.field("expiredAtEpochMs")?.int ?? 0)
  )
  if expired != .rejected(spec.field("expiredReason")?.string ?? "") {
    failures.append("expired reason \(expired)")
  }
  let afterRestart = try SessionCheckpoint(directory: dir).consume(
    url: spec.field("validUrl")?.string ?? "",
    nowEpochMs: Int64(spec.field("expiredAtEpochMs")?.int ?? 0)
  )
  if afterRestart != .rejected(spec.field("expiredReason")?.string ?? "") {
    failures.append("expiry was forgotten after process reload")
  }
  return SectionResult(name: "expired return states", failures: failures)
}

private func sectionMalformedCatalog(_ contracts: URL) throws -> SectionResult {
  var failures: [String] = []
  let doc = try readJsonFile(nestedURL(contracts, "consumer/catalog-malformed.json"))
  for row in doc.field("cases")?.array ?? [] {
    let name = row.field("name")?.string ?? "case"
    let view = validateCatalog(row.field("body") ?? .null)
    if view.accepted { failures.append("\(name) was accepted") }
    if view.rejections != [row.field("reason")?.string ?? ""] {
      failures.append("\(name) rejections \(view.rejections)")
    }
  }
  return SectionResult(name: "malformed catalog entries", failures: failures)
}

private func sectionAccessibility(_ parity: JsonValue, _ repoRoot: URL) throws -> SectionResult {
  var failures: [String] = []
  for row in parity.field("accessibility")?.array ?? [] {
    let got = balanceAccessibility(
      minorUnits: row.field("minorUnits")?.int ?? 0,
      currency: row.field("currency")?.string ?? "",
      fontScale: row.field("fontScale")?.number ?? 0,
      direction: row.field("direction")?.string ?? ""
    )
    func check(_ field: String, _ actual: String, _ expected: String?) {
      if actual != expected { failures.append("\(field) \(actual)") }
    }
    check("voiceOver", got.voiceOverLabel, row.field("voiceOverLabel")?.string)
    check("talkBack", got.talkBackDescription, row.field("talkBackDescription")?.string)
    if abs(got.scaledSp - (row.field("scaledSp")?.number ?? -1)) > 0.001 { failures.append("scaledSp \(got.scaledSp)") }
    if abs(got.minimumTouchTargetDp - (row.field("minimumTouchTargetDp")?.number ?? -1)) > 0.001 {
      failures.append("touch target \(got.minimumTouchTargetDp)")
    }
    check("startEdge", got.startEdge, row.field("startEdge")?.string)
    check("arrangement", got.arrangement, row.field("arrangement")?.string)
    check("amount", got.amountText, row.field("amountText")?.string)
    check("amountDirection", got.amountDirection, row.field("amountDirection")?.string)
  }
  let confirm = parity.field("confirm") ?? .null
  if AccessibilityCopy.confirmLabel != confirm.field("voiceOverLabel")?.string { failures.append("confirm label") }
  if AccessibilityCopy.confirmHint != confirm.field("voiceOverHint")?.string { failures.append("confirm hint") }
  if AccessibilityCopy.confirmTalkBack != confirm.field("talkBackDescription")?.string { failures.append("confirm talkback") }
  let manifest = try String(contentsOf: nestedURL(repoRoot, "android/app/src/main/AndroidManifest.xml"), encoding: .utf8)
  if !manifest.contains("android:supportsRtl=\"true\"") { failures.append("Android manifest is missing supportsRtl") }
  let activity = try String(contentsOf: nestedURL(repoRoot, "android/app/src/main/kotlin/com/atlassian/meridian/MainActivity.kt"), encoding: .utf8)
  if !activity.contains("AccessibilityCopy.balanceLabel") || !activity.contains("AccessibilityCopy.confirmTalkBack") {
    failures.append("TalkBack descriptions are not bound in the Compose UI")
  }
  if !activity.contains("minimumTouchTargetDp") || !activity.contains(".sp") {
    failures.append("large font scaling is not bound in the Compose UI")
  }
  let swiftUi = try String(contentsOf: nestedURL(repoRoot, "ios/App/MeridianApp.swift"), encoding: .utf8)
  if !swiftUi.contains("AccessibilityCopy.balanceLabel") || !swiftUi.contains("accessibilityHint") {
    failures.append("VoiceOver labels are not bound in the SwiftUI view")
  }
  if !swiftUi.contains("ScaledMetric") || !swiftUi.contains("alignment: .leading") {
    failures.append("SwiftUI large type or leading-edge layout is missing")
  }
  return SectionResult(name: "accessibility and localisation", failures: failures)
}

private func makeTemp(_ name: String) throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent("meridian-\(name)-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
