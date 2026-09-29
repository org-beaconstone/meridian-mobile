import Foundation

/// One cached payment row. Legacy rows that omit `currency` are read as GBP.
public struct CachedPaymentRecord: Codable, Hashable {
  public let id: String
  public let minorUnits: Int
  public let currency: CurrencyCode
  public let reference: String
  public let recipientId: String
  public let providerId: ProviderId
  public let method: PaymentMethod
  public let status: TransactionStatus
  public let note: String
  public let idempotencyKey: String

  public init(
    id: String,
    minorUnits: Int,
    currency: CurrencyCode,
    reference: String,
    recipientId: String,
    providerId: ProviderId,
    method: PaymentMethod,
    status: TransactionStatus,
    note: String = "",
    idempotencyKey: String = ""
  ) {
    self.id = id
    self.minorUnits = minorUnits
    self.currency = currency
    self.reference = reference
    self.recipientId = recipientId
    self.providerId = providerId
    self.method = method
    self.status = status
    self.note = note
    self.idempotencyKey = idempotencyKey
  }

  public func replacingIdempotencyKey(_ key: String) -> CachedPaymentRecord {
    CachedPaymentRecord(
      id: id,
      minorUnits: minorUnits,
      currency: currency,
      reference: reference,
      recipientId: recipientId,
      providerId: providerId,
      method: method,
      status: status,
      note: note,
      idempotencyKey: key
    )
  }
}

public struct RoutedPaymentRecords {
  public var gbp: [CachedPaymentRecord]
  public var eur: [CachedPaymentRecord]
}

enum CachePayloadDecoder {
  static func route(_ data: Data) throws -> RoutedPaymentRecords {
    let json: Any
    do {
      json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    } catch {
      throw MeridianError.decodingError("Payment cache JSON could not be read")
    }
    var routed = RoutedPaymentRecords(gbp: [], eur: [])
    if let object = json as? [String: Any],
      object["GBPStore"] != nil || object["EURStore"] != nil
    {
      if let gbp = object["GBPStore"] {
        append(contentsOf: try arrayRecords(gbp), to: &routed)
      }
      if let eur = object["EURStore"] {
        append(contentsOf: try arrayRecords(eur), to: &routed)
      }
      return routed
    }
    if let object = json as? [String: Any], let transactions = object["transactions"] {
      append(contentsOf: try arrayRecords(transactions), to: &routed)
      return routed
    }
    if let object = json as? [String: Any], let records = object["records"] {
      append(contentsOf: try arrayRecords(records), to: &routed)
      return routed
    }
    if let array = json as? [Any] {
      append(contentsOf: try array.map(parseRecord), to: &routed)
      return routed
    }
    if json is [String: Any] {
      append(contentsOf: [try parseRecord(json)], to: &routed)
      return routed
    }
    throw MeridianError.decodingError("Unrecognised payment cache payload")
  }

  private static func arrayRecords(_ value: Any) throws -> [CachedPaymentRecord] {
    guard let array = value as? [Any] else {
      throw MeridianError.decodingError("Payment cache partition must be an array")
    }
    return try array.map(parseRecord)
  }

  private static func append(
    contentsOf records: [CachedPaymentRecord],
    to routed: inout RoutedPaymentRecords
  ) {
    for record in records {
      if record.currency == .eur {
        routed.eur.append(record)
      } else {
        routed.gbp.append(record)
      }
    }
  }

  static func parseRecord(_ value: Any) throws -> CachedPaymentRecord {
    guard let object = value as? [String: Any] else {
      throw MeridianError.decodingError("Payment record must be an object")
    }
    guard let id = object["id"] as? String, !id.isEmpty else {
      throw MeridianError.decodingError("Payment record id is required")
    }
    let minorUnits = try integerMinorUnits(object)
    let currency = try currencyCode(object["currency"])
    let providerRaw: String
    if let providerId = object["providerId"] as? String {
      providerRaw = providerId
    } else if let provider = object["provider"] as? String {
      providerRaw = provider
    } else {
      throw MeridianError.decodingError("Payment record provider is required")
    }
    guard let providerId = ProviderId(rawValue: providerRaw) else {
      throw MeridianError.validationError("Unknown provider id")
    }
    guard let methodRaw = object["method"] as? String, let method = PaymentMethod(rawValue: methodRaw) else {
      throw MeridianError.decodingError("Payment record method is required")
    }
    guard let statusRaw = object["status"] as? String, let status = TransactionStatus(rawValue: statusRaw) else {
      throw MeridianError.decodingError("Payment record status is required")
    }
    return CachedPaymentRecord(
      id: id,
      minorUnits: minorUnits,
      currency: currency,
      reference: object["reference"] as? String ?? "",
      recipientId: object["recipientId"] as? String ?? "",
      providerId: providerId,
      method: method,
      status: status,
      note: object["note"] as? String ?? "",
      idempotencyKey: object["idempotencyKey"] as? String ?? ""
    )
  }

  private static func currencyCode(_ value: Any?) throws -> CurrencyCode {
    guard let value else { return .gbp }
    guard let raw = value as? String, let code = CurrencyCode(rawValue: raw) else {
      throw MeridianError.validationError("Unknown currency code")
    }
    return code
  }

  private static func integerMinorUnits(_ object: [String: Any]) throws -> Int {
    let raw = object["minorUnits"] ?? object["amount"]
    guard let raw else {
      throw MeridianError.decodingError("Payment record amount is required")
    }
    if let number = raw as? NSNumber {
      let whole = number.int64Value
      guard Double(whole) == number.doubleValue else {
        throw MeridianError.validationError("minor units must be an integer")
      }
      return Int(whole)
    }
    throw MeridianError.validationError("minor units must be an integer")
  }
}

/// File-backed partition. Writes stay inside this directory.
public class CurrencySubStore {
  public let name: String
  public let currency: CurrencyCode
  public let paymentsFile: URL
  private let lock = NSLock()

  public init(name: String, currency: CurrencyCode, directory: URL) throws {
    self.name = name
    self.currency = currency
    self.paymentsFile = directory.appendingPathComponent("payments.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  public func load() throws -> [CachedPaymentRecord] {
    lock.lock()
    defer { lock.unlock() }
    return try loadUnlocked()
  }

  public func isEmpty() throws -> Bool {
    try load().isEmpty
  }

  public func readBytes() throws -> Data {
    lock.lock()
    defer { lock.unlock() }
    guard FileManager.default.fileExists(atPath: paymentsFile.path) else { return Data() }
    return try Data(contentsOf: paymentsFile)
  }

  public func save(_ records: [CachedPaymentRecord]) throws {
    lock.lock()
    defer { lock.unlock() }
    for record in records where record.currency != currency {
      throw MeridianError.validationError("\(name) cannot store \(record.currency.rawValue)")
    }
    try writeUnlocked(records)
  }

  /// Inserts or replaces a row. An existing idempotency key is kept.
  public func upsert(_ record: CachedPaymentRecord) throws {
    lock.lock()
    defer { lock.unlock() }
    guard record.currency == currency else {
      throw MeridianError.validationError("\(record.currency.rawValue) records stay out of \(name)")
    }
    var records = try loadUnlocked()
    if let index = records.firstIndex(where: { existing in
      existing.id == record.id
        || (!existing.idempotencyKey.isEmpty && existing.idempotencyKey == record.idempotencyKey)
    }) {
      let retained = records[index].idempotencyKey.isEmpty
        ? record.idempotencyKey
        : records[index].idempotencyKey
      records[index] = record.replacingIdempotencyKey(retained)
    } else {
      records.append(record)
    }
    try writeUnlocked(records)
  }

  private func loadUnlocked() throws -> [CachedPaymentRecord] {
    guard FileManager.default.fileExists(atPath: paymentsFile.path) else { return [] }
    let data = try Data(contentsOf: paymentsFile)
    if data.isEmpty { return [] }
    if let records = try? JSONDecoder().decode([CachedPaymentRecord].self, from: data) {
      if records.contains(where: { $0.currency != currency }) {
        throw MeridianError.validationError("\(name) contains another currency and was left unchanged")
      }
      return records
    }
    do {
      let routed = try CachePayloadDecoder.route(data)
      let mine = currency == .gbp ? routed.gbp : routed.eur
      let other = currency == .gbp ? routed.eur : routed.gbp
      if !other.isEmpty {
        throw MeridianError.validationError("\(name) contains another currency and was left unchanged")
      }
      return mine
    } catch let error as MeridianError {
      throw error
    } catch {
      throw MeridianError.decodingError("\(name) could not be read and was left unchanged")
    }
  }

  private func writeUnlocked(_ records: [CachedPaymentRecord]) throws {
    let data = try JSONEncoder().encode(records)
    try data.write(to: paymentsFile, options: .atomic)
  }
}

public final class GBPStore: CurrencySubStore {
  public init(directory: URL) throws {
    try super.init(name: "GBPStore", currency: .gbp, directory: directory)
  }
}

public final class EURStore: CurrencySubStore {
  public init(directory: URL) throws {
    try super.init(name: "EURStore", currency: .eur, directory: directory)
  }
}

/// Root cache split into `GBPStore` and `EURStore` directories.
/// A legacy file at the root is copied into GBPStore and is not rewritten.
public final class IsolatedPaymentCache {
  public let gbpStore: GBPStore
  public let eurStore: EURStore
  public let rootDirectory: URL

  public init(rootDirectory: URL) throws {
    try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    self.rootDirectory = rootDirectory
    gbpStore = try GBPStore(directory: rootDirectory.appendingPathComponent("GBPStore", isDirectory: true))
    eurStore = try EURStore(directory: rootDirectory.appendingPathComponent("EURStore", isDirectory: true))
    for name in ["payments.json", "cache.json"] {
      let legacy = rootDirectory.appendingPathComponent(name)
      if FileManager.default.fileExists(atPath: legacy.path) {
        try adoptLegacyFile(at: legacy)
      }
    }
  }

  /// Fills an empty domain from `data`. A domain that already has rows is left as-is.
  public func importCached(_ data: Data) throws {
    let routed = try CachePayloadDecoder.route(data)
    if !routed.gbp.isEmpty {
      if try gbpStore.isEmpty() {
        try gbpStore.save(routed.gbp)
      }
    }
    if !routed.eur.isEmpty {
      if try eurStore.isEmpty() {
        try eurStore.save(routed.eur)
      }
    }
  }

  /// Reads a legacy cache without modifying that file.
  public func adoptLegacyFile(at url: URL) throws {
    let before = try Data(contentsOf: url)
    try importCached(before)
    let after = try Data(contentsOf: url)
    guard before == after else {
      throw MeridianError.validationError("Legacy cache was modified")
    }
  }
}
