import Foundation

/// Payment fields bound to one idempotency key.
/// A retry or challenge must carry the same fingerprint as the initial attempt.
public struct PaymentAttempt: Equatable {
  public let recipientId: String
  public let amountMinor: Int
  public let method: String
  public let note: String
  public let scenario: String

  public init(recipientId: String, amountMinor: Int, method: String, note: String, scenario: String) {
    self.recipientId = recipientId
    self.amountMinor = amountMinor
    self.method = method
    self.note = note
    self.scenario = scenario
  }

  public func fingerprint() -> String {
    [recipientId, String(amountMinor), method, note, scenario]
      .map(escapeFingerprintPart)
      .joined(separator: "\u{1f}")
  }

  public static func fromFingerprint(_ value: String) -> PaymentAttempt? {
    let parts = value.components(separatedBy: "\u{1f}")
    guard parts.count == 5, let amount = Int(unescapeFingerprintPart(parts[1])) else { return nil }
    return PaymentAttempt(
      recipientId: unescapeFingerprintPart(parts[0]),
      amountMinor: amount,
      method: unescapeFingerprintPart(parts[2]),
      note: unescapeFingerprintPart(parts[3]),
      scenario: unescapeFingerprintPart(parts[4])
    )
  }
}

func escapeFingerprintPart(_ value: String) -> String {
  value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\u{1f}", with: "\\u001f")
}

func unescapeFingerprintPart(_ value: String) -> String {
  var output = ""
  var index = value.startIndex
  while index < value.endIndex {
    if value[index] == "\\", let next = value.index(index, offsetBy: 1, limitedBy: value.endIndex), next < value.endIndex {
      if value[next] == "\\" {
        output.append("\\")
        index = value.index(after: next)
        continue
      }
      if value[index...].hasPrefix("\\u001f") {
        output.append("\u{1f}")
        index = value.index(index, offsetBy: 6)
        continue
      }
    }
    output.append(value[index])
    index = value.index(after: index)
  }
  return output
}

public struct IdempotencyRecord: Codable, Equatable {
  public let transactionId: String
  public let key: String
  public let createdAtEpochMillis: Int64
  public let fingerprint: String?

  public init(transactionId: String, key: String, createdAtEpochMillis: Int64, fingerprint: String?) {
    self.transactionId = transactionId
    self.key = key
    self.createdAtEpochMillis = createdAtEpochMillis
    self.fingerprint = fingerprint
  }
}

struct IdempotencySnapshot: Codable {
  var version: Int
  var records: [IdempotencyRecord]
}

public protocol IdempotencyStore: Sendable {
  func load() throws -> [IdempotencyRecord]
  func save(_ records: [IdempotencyRecord]) throws
}

public final class MemoryIdempotencyStore: IdempotencyStore, @unchecked Sendable {
  private let lock = NSLock()
  private var records: [IdempotencyRecord] = []

  public init() {}

  public func load() -> [IdempotencyRecord] {
    lock.lock()
    defer { lock.unlock() }
    return records
  }

  public func save(_ records: [IdempotencyRecord]) {
    lock.lock()
    defer { lock.unlock() }
    self.records = records
  }
}

public final class FileIdempotencyStore: IdempotencyStore, @unchecked Sendable {
  public let fileURL: URL
  private let lock = NSLock()
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public static func fileURL(directory: URL, sessionId: String) -> URL {
    let safe = sessionId.replacingOccurrences(
      of: "[^A-Za-z0-9_-]",
      with: "_",
      options: .regularExpression
    )
    return directory.appendingPathComponent("idempotency-\(safe).json")
  }

  public func load() throws -> [IdempotencyRecord] {
    lock.lock()
    defer { lock.unlock() }
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    let data = try Data(contentsOf: fileURL)
    if data.isEmpty { return [] }
    do {
      return try decoder.decode(IdempotencySnapshot.self, from: data).records
    } catch {
      throw MeridianError.validationError("Idempotency store is unreadable at \(fileURL.path)")
    }
  }

  public func save(_ records: [IdempotencyRecord]) throws {
    lock.lock()
    defer { lock.unlock() }
    let parent = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let data = try encoder.encode(IdempotencySnapshot(version: 1, records: records))
    let temporary = parent.appendingPathComponent(fileURL.lastPathComponent + ".tmp")
    try data.write(to: temporary)
    if FileManager.default.fileExists(atPath: fileURL.path) {
      try FileManager.default.removeItem(at: fileURL)
    }
    try FileManager.default.moveItem(at: temporary, to: fileURL)
  }
}

/// Generates, persists, and attaches UUID v4 idempotency keys for one payment lifecycle.
///
/// Keys are cryptographically random UUID v4 strings. The same key is reused for network
/// retries and two-factor challenge submissions. In-flight keys expire after 24 hours so
/// they stay inside the gateway's Redis deduplication window. The cache drops a key after
/// successful terminal settlement or an explicit cancellation.
public final class IdempotencyKeyManager: @unchecked Sendable {
  public static let twentyFourHoursMillis: Int64 = 24 * 60 * 60 * 1000
  public static let header = "Idempotency-Key"
  private static let uuidV4 = try! NSRegularExpression(
    pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
  )

  public let ttlMillis: Int64
  private let store: IdempotencyStore
  private let clock: () -> Int64
  private let uuidGenerator: () -> String
  private let lock = NSLock()
  private var entries: [String: IdempotencyRecord] = [:]

  public init(
    store: IdempotencyStore = MemoryIdempotencyStore(),
    clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
    uuidGenerator: @escaping () -> String = { IdempotencyKeyManager.secureUuidV4() },
    ttlMillis: Int64 = IdempotencyKeyManager.twentyFourHoursMillis
  ) throws {
    precondition(ttlMillis > 0, "Idempotency TTL must be positive")
    self.store = store
    self.clock = clock
    self.uuidGenerator = uuidGenerator
    self.ttlMillis = ttlMillis
    let loaded = try store.load()
    for record in loaded {
      entries[record.transactionId] = record
    }
  }

  public static func isUuidV4(_ value: String) -> Bool {
    let lowered = value.lowercased()
    let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
    return uuidV4.firstMatch(in: lowered, range: range) != nil
  }

  public static func secureUuidV4() -> String {
    var generator = SystemRandomNumberGenerator()
    var bytes = [UInt8](repeating: 0, count: 16)
    for index in bytes.indices {
      bytes[index] = UInt8.random(in: .min ... .max, using: &generator)
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    let uuid = UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11],
      bytes[12], bytes[13], bytes[14], bytes[15]
    ))
    return uuid.uuidString.lowercased()
  }

  @discardableResult
  public func begin(transactionId: String, fingerprint: String? = nil) throws -> String {
    try locked {
      guard !transactionId.isEmpty else {
        throw MeridianError.validationError("transactionId is required")
      }
      if let existing = entries[transactionId], !isExpired(existing) {
        try bindFingerprint(existing, fingerprint)
        return existing.key
      }
      let key = uuidGenerator()
      guard IdempotencyKeyManager.isUuidV4(key) else {
        throw MeridianError.validationError("Idempotency key generator must return a UUID v4")
      }
      let record = IdempotencyRecord(
        transactionId: transactionId,
        key: key,
        createdAtEpochMillis: clock(),
        fingerprint: fingerprint
      )
      try write(transactionId, record)
      return record.key
    }
  }

  public func keyForRetry(transactionId: String, fingerprint: String? = nil) throws -> String {
    try requireActive(transactionId, fingerprint)
  }

  public func keyForChallenge(transactionId: String, fingerprint: String? = nil) throws -> String {
    try requireActive(transactionId, fingerprint)
  }

  public func activeKey(transactionId: String) -> String? {
    lockedValue {
      guard let record = entries[transactionId], !isExpired(record) else { return nil }
      return record.key
    }
  }

  public func activeRecords() -> [IdempotencyRecord] {
    lockedValue { entries.values.filter { !isExpired($0) } }
  }

  public func storedRecords() -> [IdempotencyRecord] {
    lockedValue { Array(entries.values) }
  }

  public func settle(transactionId: String) throws {
    try purge(transactionId)
  }

  public func cancel(transactionId: String) throws {
    try purge(transactionId)
  }

  private func requireActive(_ transactionId: String, _ fingerprint: String?) throws -> String {
    try locked {
      guard let existing = entries[transactionId] else {
        throw MeridianError.missingIdempotencyKey(transactionId)
      }
      if isExpired(existing) {
        throw MeridianError.idempotencyKeyExpired(transactionId)
      }
      try bindFingerprint(existing, fingerprint)
      return existing.key
    }
  }

  private func bindFingerprint(_ existing: IdempotencyRecord, _ fingerprint: String?) throws {
    guard let fingerprint else { return }
    if existing.fingerprint == nil {
      try write(
        existing.transactionId,
        IdempotencyRecord(
          transactionId: existing.transactionId,
          key: existing.key,
          createdAtEpochMillis: existing.createdAtEpochMillis,
          fingerprint: fingerprint
        )
      )
      return
    }
    if existing.fingerprint != fingerprint {
      throw MeridianError.validationError("Idempotency key is bound to a different payment")
    }
  }

  private func purge(_ transactionId: String) throws {
    try locked {
      try write(transactionId, nil)
    }
  }

  private func write(_ transactionId: String, _ record: IdempotencyRecord?) throws {
    let previous = entries[transactionId]
    if let record {
      entries[transactionId] = record
    } else {
      entries.removeValue(forKey: transactionId)
    }
    do {
      try persist()
    } catch {
      if let previous {
        entries[transactionId] = previous
      } else {
        entries.removeValue(forKey: transactionId)
      }
      throw error
    }
  }

  private func isExpired(_ record: IdempotencyRecord) -> Bool {
    clock() - record.createdAtEpochMillis >= ttlMillis
  }

  private func persist() throws {
    try store.save(Array(entries.values))
  }

  private func locked<T>(_ body: () throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private func lockedValue<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
