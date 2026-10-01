import CryptoKit
import Foundation
#if canImport(Security)
import Security
#endif

/// Terminal snapshots stay available for this window, then storage deletes them.
public enum PaymentIntentRetention {
  public static let terminalWindowMs: Int64 = 24 * 60 * 60 * 1000
}

public enum PaymentIntentStatus: String, Codable, Hashable, Sendable {
  case created
  case pending
  case processing
  case succeeded
  case declined
  case failed
  case cancelled

  public var isTerminal: Bool {
    switch self {
    case .succeeded, .declined, .failed, .cancelled:
      return true
    case .created, .pending, .processing:
      return false
    }
  }
}

public struct PaymentReturnState: Codable, Hashable, Sendable {
  public let ok: Bool
  public let paymentId: String?
  public let code: String?
  public let error: String?
  public let stateVersion: Int?
  public let balancePence: Int?

  public init(
    ok: Bool,
    paymentId: String?,
    code: String?,
    error: String?,
    stateVersion: Int?,
    balancePence: Int?
  ) {
    self.ok = ok
    self.paymentId = paymentId
    self.code = code
    self.error = error
    self.stateVersion = stateVersion
    self.balancePence = balancePence
  }
}

public struct PaymentIntentSnapshot: Codable, Hashable, Sendable {
  public let paymentIntentId: String
  public let customerAccountId: String
  public let idempotencyKey: String
  public let businessPayloadHash: String
  public var status: PaymentIntentStatus
  public var returnState: PaymentReturnState?
  public var returnStateHash: String?
  public let recipientId: String
  public let amountMinor: Int
  public let method: PaymentMethod
  public let note: String
  public let createdAtEpochMs: Int64
  public var updatedAtEpochMs: Int64
  public var terminalAtEpochMs: Int64?

  public init(
    paymentIntentId: String,
    customerAccountId: String,
    idempotencyKey: String,
    businessPayloadHash: String,
    status: PaymentIntentStatus,
    returnState: PaymentReturnState?,
    returnStateHash: String?,
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String,
    createdAtEpochMs: Int64,
    updatedAtEpochMs: Int64,
    terminalAtEpochMs: Int64?
  ) {
    self.paymentIntentId = paymentIntentId
    self.customerAccountId = customerAccountId
    self.idempotencyKey = idempotencyKey
    self.businessPayloadHash = businessPayloadHash
    self.status = status
    self.returnState = returnState
    self.returnStateHash = returnStateHash
    self.recipientId = recipientId
    self.amountMinor = amountMinor
    self.method = method
    self.note = note
    self.createdAtEpochMs = createdAtEpochMs
    self.updatedAtEpochMs = updatedAtEpochMs
    self.terminalAtEpochMs = terminalAtEpochMs
  }

  public func isExpired(at nowEpochMs: Int64) -> Bool {
    guard status.isTerminal else { return false }
    let terminalAt = terminalAtEpochMs ?? updatedAtEpochMs
    return nowEpochMs >= terminalAt + PaymentIntentRetention.terminalWindowMs
  }
}

public struct PaymentIntentDraft: Hashable, Sendable {
  public let customerAccountId: String
  public let paymentIntentId: String
  public let idempotencyKey: String
  public let recipientId: String
  public let amountMinor: Int
  public let method: PaymentMethod
  public let note: String

  public init(
    customerAccountId: String,
    paymentIntentId: String,
    idempotencyKey: String,
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String
  ) {
    self.customerAccountId = customerAccountId
    self.paymentIntentId = paymentIntentId
    self.idempotencyKey = idempotencyKey
    self.recipientId = recipientId
    self.amountMinor = amountMinor
    self.method = method
    self.note = note
  }
}

public struct BeginPaymentIntent: Hashable, Sendable {
  public let snapshot: PaymentIntentSnapshot
  public let created: Bool
  public let payloadMatches: Bool

  public init(snapshot: PaymentIntentSnapshot, created: Bool, payloadMatches: Bool) {
    self.snapshot = snapshot
    self.created = created
    self.payloadMatches = payloadMatches
  }
}

public enum PaymentIntentSnapshotError: Error, Equatable, LocalizedError, CustomStringConvertible {
  case invalidCustomerAccount
  case invalidIntent(String)
  case notFound
  case accountMismatch
  case storageFailed(String)

  public var description: String {
    switch self {
    case .invalidCustomerAccount:
      return "Customer account id is required"
    case let .invalidIntent(message):
      return message
    case .notFound:
      return "Payment intent was not found"
    case .accountMismatch:
      return "Payment intent belongs to a different customer account"
    case let .storageFailed(message):
      return message
    }
  }

  public var errorDescription: String? { description }
}

public enum PaymentIntentAccounts {
  private static let accountPattern = "^[A-Za-z0-9._-]{1,128}$"
  private static let idPattern = "^[A-Za-z0-9_-]{8,80}$"
  private static let recipientPattern = "^[A-Za-z0-9_-]{1,128}$"

  public static func isValidAccount(_ id: String) -> Bool {
    id.range(of: accountPattern, options: .regularExpression) != nil
  }

  public static func requireAccount(_ id: String) throws {
    guard isValidAccount(id) else { throw PaymentIntentSnapshotError.invalidCustomerAccount }
  }

  public static func requireDraft(_ draft: PaymentIntentDraft) throws {
    try requireAccount(draft.customerAccountId)
    guard draft.paymentIntentId.range(of: idPattern, options: .regularExpression) != nil else {
      throw PaymentIntentSnapshotError.invalidIntent("Payment intent id is invalid")
    }
    guard draft.idempotencyKey.range(of: idPattern, options: .regularExpression) != nil else {
      throw PaymentIntentSnapshotError.invalidIntent("Idempotency key is invalid")
    }
    guard draft.recipientId.range(of: recipientPattern, options: .regularExpression) != nil else {
      throw PaymentIntentSnapshotError.invalidIntent("Recipient id is invalid")
    }
    guard draft.amountMinor >= 1 && draft.amountMinor <= 1_000_000 else {
      throw PaymentIntentSnapshotError.invalidIntent("Amount must be between 1 and 1000000 pence")
    }
    guard draft.note.count <= 200, draft.note.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) else {
      throw PaymentIntentSnapshotError.invalidIntent("Reference is too long")
    }
  }
}

enum PaymentIntentHashing {
  static func sha256Hex(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  static func jsonString(_ value: String) -> String {
    var encoded = "\""
    for scalar in value.unicodeScalars {
      switch scalar.value {
      case 0x5C:
        encoded += "\\\\"
      case 0x22:
        encoded += "\\\""
      case 0x0A:
        encoded += "\\n"
      case 0x0D:
        encoded += "\\r"
      case 0x09:
        encoded += "\\t"
      default:
        if scalar.value < 0x20 {
          encoded += String(format: "\\u%04x", scalar.value)
        } else {
          encoded.append(Character(scalar))
        }
      }
    }
    encoded += "\""
    return encoded
  }
}

public func businessPayloadHash(
  customerAccountId: String,
  recipientId: String,
  amountMinor: Int,
  method: PaymentMethod,
  note: String
) -> String {
  let canonical = "{\"amountMinor\":\(amountMinor),\"customerAccountId\":\(PaymentIntentHashing.jsonString(customerAccountId)),\"method\":\(PaymentIntentHashing.jsonString(method.rawValue)),\"note\":\(PaymentIntentHashing.jsonString(note)),\"recipientId\":\(PaymentIntentHashing.jsonString(recipientId))}"
  return PaymentIntentHashing.sha256Hex(canonical)
}

public func returnStateHash(_ state: PaymentReturnState) -> String {
  let balance = state.balancePence.map(String.init) ?? "null"
  let code = state.code.map(PaymentIntentHashing.jsonString) ?? "null"
  let error = state.error.map(PaymentIntentHashing.jsonString) ?? "null"
  let ok = state.ok ? "true" : "false"
  let paymentId = state.paymentId.map(PaymentIntentHashing.jsonString) ?? "null"
  let version = state.stateVersion.map(String.init) ?? "null"
  let canonical = "{\"balancePence\":\(balance),\"code\":\(code),\"error\":\(error),\"ok\":\(ok),\"paymentId\":\(paymentId),\"stateVersion\":\(version)}"
  return PaymentIntentHashing.sha256Hex(canonical)
}

public func paymentIntentStatus(for response: PaymentResponse) -> PaymentIntentStatus {
  if response.ok { return .succeeded }
  let code = response.code?.uppercased() ?? ""
  if code.contains("PENDING") || response.transaction?.status == .pending {
    return .pending
  }
  if code.contains("DECLIN") || response.transaction?.status == .declined {
    return .declined
  }
  if code.contains("UNAVAILABLE") || code.contains("TIMEOUT") {
    return .processing
  }
  if code.isEmpty { return .processing }
  return .failed
}

public func paymentReturnState(from response: PaymentResponse) -> PaymentReturnState {
  PaymentReturnState(
    ok: response.ok,
    paymentId: response.paymentId ?? response.transaction?.id,
    code: response.code,
    error: response.error,
    stateVersion: response.state?.version,
    balancePence: response.state?.balance
  )
}

func accountStorageKey(_ customerAccountId: String) -> String {
  PaymentIntentHashing.sha256Hex(customerAccountId)
}

public protocol PaymentIntentSnapshotStoring: Sendable {
  func save(_ snapshot: PaymentIntentSnapshot) throws
  func load(customerAccountId: String, paymentIntentId: String) throws -> PaymentIntentSnapshot?
  func loadAll(customerAccountId: String) throws -> [PaymentIntentSnapshot]
  func delete(customerAccountId: String, paymentIntentId: String) throws
}

public final class InMemoryPaymentIntentSnapshotStore: PaymentIntentSnapshotStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var records: [String: [String: PaymentIntentSnapshot]] = [:]

  public init() {}

  public func save(_ snapshot: PaymentIntentSnapshot) throws {
    try PaymentIntentAccounts.requireAccount(snapshot.customerAccountId)
    lock.lock()
    defer { lock.unlock() }
    var account = records[snapshot.customerAccountId] ?? [:]
    account[snapshot.paymentIntentId] = snapshot
    records[snapshot.customerAccountId] = account
  }

  public func load(customerAccountId: String, paymentIntentId: String) throws -> PaymentIntentSnapshot? {
    lock.lock()
    defer { lock.unlock() }
    guard let snapshot = records[customerAccountId]?[paymentIntentId] else { return nil }
    return snapshot.customerAccountId == customerAccountId ? snapshot : nil
  }

  public func loadAll(customerAccountId: String) throws -> [PaymentIntentSnapshot] {
    lock.lock()
    defer { lock.unlock() }
    return Array(records[customerAccountId]?.values.filter { $0.customerAccountId == customerAccountId } ?? [])
  }

  public func delete(customerAccountId: String, paymentIntentId: String) throws {
    lock.lock()
    defer { lock.unlock() }
    records[customerAccountId]?.removeValue(forKey: paymentIntentId)
  }
}

public final class PaymentIntentSnapshotRepository: @unchecked Sendable {
  private let store: any PaymentIntentSnapshotStoring
  private let lock = NSLock()

  public init(store: any PaymentIntentSnapshotStoring) {
    self.store = store
  }

  public func begin(_ draft: PaymentIntentDraft, nowEpochMs: Int64) throws -> BeginPaymentIntent {
    lock.lock()
    defer { lock.unlock() }
    try PaymentIntentAccounts.requireDraft(draft)
    _ = try purgeExpiredLocked(customerAccountId: draft.customerAccountId, nowEpochMs: nowEpochMs)
    let hash = businessPayloadHash(
      customerAccountId: draft.customerAccountId,
      recipientId: draft.recipientId,
      amountMinor: draft.amountMinor,
      method: draft.method,
      note: draft.note
    )
    let active = try store.loadAll(customerAccountId: draft.customerAccountId).filter { !$0.status.isTerminal }
    if let samePayload = active.first(where: { $0.businessPayloadHash == hash }) {
      return BeginPaymentIntent(snapshot: samePayload, created: false, payloadMatches: true)
    }
    if let other = active.first {
      return BeginPaymentIntent(snapshot: other, created: false, payloadMatches: false)
    }
    let snapshot = PaymentIntentSnapshot(
      paymentIntentId: draft.paymentIntentId,
      customerAccountId: draft.customerAccountId,
      idempotencyKey: draft.idempotencyKey,
      businessPayloadHash: hash,
      status: .processing,
      returnState: nil,
      returnStateHash: nil,
      recipientId: draft.recipientId,
      amountMinor: draft.amountMinor,
      method: draft.method,
      note: draft.note,
      createdAtEpochMs: nowEpochMs,
      updatedAtEpochMs: nowEpochMs,
      terminalAtEpochMs: nil
    )
    try store.save(snapshot)
    return BeginPaymentIntent(snapshot: snapshot, created: true, payloadMatches: true)
  }

  public func recordOutcome(
    customerAccountId: String,
    paymentIntentId: String,
    response: PaymentResponse,
    nowEpochMs: Int64
  ) throws -> PaymentIntentSnapshot {
    lock.lock()
    defer { lock.unlock() }
    let current = try requireOwned(customerAccountId: customerAccountId, paymentIntentId: paymentIntentId)
    if current.status.isTerminal { return current }
    let status = paymentIntentStatus(for: response)
    let returnState = paymentReturnState(from: response)
    var updated = current
    updated.status = status
    updated.returnState = returnState
    updated.returnStateHash = returnStateHash(returnState)
    updated.updatedAtEpochMs = nowEpochMs
    updated.terminalAtEpochMs = status.isTerminal ? (current.terminalAtEpochMs ?? nowEpochMs) : nil
    try store.save(updated)
    return updated
  }

  public func markUncertain(
    customerAccountId: String,
    paymentIntentId: String,
    nowEpochMs: Int64
  ) throws -> PaymentIntentSnapshot {
    lock.lock()
    defer { lock.unlock() }
    let current = try requireOwned(customerAccountId: customerAccountId, paymentIntentId: paymentIntentId)
    if current.status.isTerminal { return current }
    var updated = current
    updated.status = .processing
    updated.updatedAtEpochMs = nowEpochMs
    updated.terminalAtEpochMs = nil
    try store.save(updated)
    return updated
  }

  public func cancel(
    customerAccountId: String,
    paymentIntentId: String,
    nowEpochMs: Int64
  ) throws -> PaymentIntentSnapshot? {
    lock.lock()
    defer { lock.unlock() }
    try PaymentIntentAccounts.requireAccount(customerAccountId)
    guard let current = try store.load(customerAccountId: customerAccountId, paymentIntentId: paymentIntentId) else {
      return nil
    }
    guard current.customerAccountId == customerAccountId else {
      throw PaymentIntentSnapshotError.accountMismatch
    }
    if current.status.isTerminal { return current }
    var updated = current
    updated.status = .cancelled
    updated.updatedAtEpochMs = nowEpochMs
    updated.terminalAtEpochMs = nowEpochMs
    try store.save(updated)
    return updated
  }

  public func resumeActive(customerAccountId: String, nowEpochMs: Int64) throws -> [PaymentIntentSnapshot] {
    lock.lock()
    defer { lock.unlock() }
    try PaymentIntentAccounts.requireAccount(customerAccountId)
    _ = try purgeExpiredLocked(customerAccountId: customerAccountId, nowEpochMs: nowEpochMs)
    return try store.loadAll(customerAccountId: customerAccountId).filter { !$0.status.isTerminal && !$0.isExpired(at: nowEpochMs) }
  }

  public func load(
    customerAccountId: String,
    paymentIntentId: String,
    nowEpochMs: Int64
  ) throws -> PaymentIntentSnapshot? {
    lock.lock()
    defer { lock.unlock() }
    try PaymentIntentAccounts.requireAccount(customerAccountId)
    _ = try purgeExpiredLocked(customerAccountId: customerAccountId, nowEpochMs: nowEpochMs)
    guard let snapshot = try store.load(customerAccountId: customerAccountId, paymentIntentId: paymentIntentId) else {
      return nil
    }
    return snapshot.isExpired(at: nowEpochMs) ? nil : snapshot
  }

  public func purgeExpired(customerAccountId: String, nowEpochMs: Int64) throws -> Int {
    lock.lock()
    defer { lock.unlock() }
    try PaymentIntentAccounts.requireAccount(customerAccountId)
    return try purgeExpiredLocked(customerAccountId: customerAccountId, nowEpochMs: nowEpochMs)
  }

  private func purgeExpiredLocked(customerAccountId: String, nowEpochMs: Int64) throws -> Int {
    let expired = try store.loadAll(customerAccountId: customerAccountId).filter { $0.isExpired(at: nowEpochMs) }
    for snapshot in expired {
      try store.delete(customerAccountId: customerAccountId, paymentIntentId: snapshot.paymentIntentId)
    }
    return expired.count
  }

  private func requireOwned(customerAccountId: String, paymentIntentId: String) throws -> PaymentIntentSnapshot {
    try PaymentIntentAccounts.requireAccount(customerAccountId)
    guard let snapshot = try store.load(customerAccountId: customerAccountId, paymentIntentId: paymentIntentId) else {
      throw PaymentIntentSnapshotError.notFound
    }
    guard snapshot.customerAccountId == customerAccountId else {
      throw PaymentIntentSnapshotError.accountMismatch
    }
    return snapshot
  }
}

#if canImport(Security)
/// iOS and macOS Keychain store. Each customer account uses its own service name,
/// and items are device-local (`WhenUnlockedThisDeviceOnly`), not iCloud-synced.
public final class KeychainPaymentIntentSnapshotStore: PaymentIntentSnapshotStoring, @unchecked Sendable {
  private let servicePrefix = "com.beaconstone.meridian.pi."
  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()
  private let decoder = JSONDecoder()

  public init() {}

  public func save(_ snapshot: PaymentIntentSnapshot) throws {
    try PaymentIntentAccounts.requireAccount(snapshot.customerAccountId)
    let data = try encoder.encode(snapshot)
    let query = baseQuery(customerAccountId: snapshot.customerAccountId, paymentIntentId: snapshot.paymentIntentId)
    SecItemDelete(query as CFDictionary)
    var add = query
    add[kSecValueData as String] = data
    add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let status = SecItemAdd(add as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw PaymentIntentSnapshotError.storageFailed("SecItemAdd \(status)")
    }
  }

  public func load(customerAccountId: String, paymentIntentId: String) throws -> PaymentIntentSnapshot? {
    try PaymentIntentAccounts.requireAccount(customerAccountId)
    var query = baseQuery(customerAccountId: customerAccountId, paymentIntentId: paymentIntentId)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
      throw PaymentIntentSnapshotError.storageFailed("SecItemCopyMatching \(status)")
    }
    let snapshot = try decoder.decode(PaymentIntentSnapshot.self, from: data)
    guard snapshot.customerAccountId == customerAccountId, snapshot.paymentIntentId == paymentIntentId else {
      return nil
    }
    return snapshot
  }

  public func loadAll(customerAccountId: String) throws -> [PaymentIntentSnapshot] {
    try PaymentIntentAccounts.requireAccount(customerAccountId)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service(for: customerAccountId),
      kSecMatchLimit as String: kSecMatchLimitAll,
      kSecReturnAttributes as String: true,
      kSecReturnData as String: true,
      kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return [] }
    guard status == errSecSuccess else {
      throw PaymentIntentSnapshotError.storageFailed("SecItemCopyMatching \(status)")
    }
    let rows = keychainRows(item)
    var snapshots: [PaymentIntentSnapshot] = []
    for row in rows {
      guard let data = ((row as? [String: Any])?[kSecValueData as String] as? Data) ?? (row as? Data) else {
        continue
      }
      guard let snapshot = try? decoder.decode(PaymentIntentSnapshot.self, from: data) else { continue }
      if snapshot.customerAccountId == customerAccountId {
        snapshots.append(snapshot)
      }
    }
    return snapshots
  }

  public func delete(customerAccountId: String, paymentIntentId: String) throws {
    try PaymentIntentAccounts.requireAccount(customerAccountId)
    let status = SecItemDelete(baseQuery(customerAccountId: customerAccountId, paymentIntentId: paymentIntentId) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw PaymentIntentSnapshotError.storageFailed("SecItemDelete \(status)")
    }
  }

  private func keychainRows(_ item: CFTypeRef?) -> [Any] {
    if let rows = item as? [Any] { return rows }
    if let row = item as? [String: Any] { return [row] }
    if let data = item as? Data { return [data] }
    return []
  }

  private func service(for customerAccountId: String) -> String {
    servicePrefix + accountStorageKey(customerAccountId)
  }

  private func baseQuery(customerAccountId: String, paymentIntentId: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service(for: customerAccountId),
      kSecAttrAccount as String: paymentIntentId,
      kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
    ]
  }
}
#endif
