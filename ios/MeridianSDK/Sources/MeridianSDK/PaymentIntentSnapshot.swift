import CryptoKit
import Foundation
import Security

/// How long a snapshot is kept after it reaches a terminal status.
/// Active intents are not expired by this window so a restarted process can resume them.
public enum PaymentIntentRetention {
  public static let terminalWindowMillis: Int64 = 24 * 60 * 60 * 1000
}

public enum PaymentIntentStatus: String, Codable, Equatable {
  case created
  case submitted
  case pending
  case requiresAction
  case unknown
  case completed
  case declined
  case failed
  case cancelled

  public var isTerminal: Bool {
    switch self {
    case .completed, .declined, .failed, .cancelled:
      return true
    case .created, .submitted, .pending, .requiresAction, .unknown:
      return false
    }
  }

  public var isActive: Bool { !isTerminal }
}

public enum PaymentIntentError: LocalizedError, Equatable {
  case invalidAccount
  case invalidAmount(String)
  case invalidNote
  case invalidRecipient
  case notFound
  case activeIntentInProgress(String)
  case terminal(String)
  case storage(String)

  public var errorDescription: String? {
    switch self {
    case .invalidAccount:
      return "Customer account must be 3-64 characters of letters, numbers, _ or -"
    case let .invalidAmount(message):
      return message
    case .invalidNote:
      return "Reference is too long"
    case .invalidRecipient:
      return "Recipient is required"
    case .notFound:
      return "Payment intent snapshot was not found"
    case let .activeIntentInProgress(id):
      return "Active payment intent \(id) is still in progress"
    case let .terminal(id):
      return "Payment intent \(id) is already finished"
    case let .storage(message):
      return message
    }
  }
}

public enum PaymentIntentIds {
  public static func isValidCustomerAccountId(_ value: String) -> Bool {
    value.range(of: "^[A-Za-z0-9_-]{3,64}$", options: .regularExpression) != nil
  }

  public static func isValidPaymentIntentId(_ value: String) -> Bool {
    value.range(of: "^[A-Za-z0-9_-]{8,80}$", options: .regularExpression) != nil
  }

  public static func newPaymentIntentId() -> String {
    "pi_" + UUID().uuidString.lowercased()
  }

  public static func newIdempotencyKey() -> String {
    UUID().uuidString.lowercased()
  }
}

public enum PaymentIntentStorageKeys {
  public static let lastAccountKey = "__last_customer_account__"

  public static func snapshotKey(customerAccountId: String, paymentIntentId: String) throws -> String {
    guard PaymentIntentIds.isValidCustomerAccountId(customerAccountId) else {
      throw PaymentIntentError.invalidAccount
    }
    guard PaymentIntentIds.isValidPaymentIntentId(paymentIntentId) else {
      throw PaymentIntentError.storage("Invalid payment intent id")
    }
    return "\(customerAccountId)|\(paymentIntentId)"
  }

  public static func belongsToAccount(_ key: String, customerAccountId: String) -> Bool {
    key.hasPrefix("\(customerAccountId)|")
  }
}

public enum PaymentIntentHash {
  public static func sha256Hex(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  public static func escape(_ value: String) -> String {
    var out = "\""
    for character in value {
      switch character {
      case "\\":
        out += "\\\\"
      case "\"":
        out += "\\\""
      case "\n":
        out += "\\n"
      case "\r":
        out += "\\r"
      case "\t":
        out += "\\t"
      default:
        out.append(character)
      }
    }
    out += "\""
    return out
  }

  /// Canonical business payload. Amount is integer GBP pence. Key order is fixed.
  public static func canonicalBusinessPayload(
    customerAccountId: String,
    recipientId: String,
    amountMinor: Int,
    method: String,
    note: String,
    scenario: String
  ) -> String {
    "{\"v\":1,\"customerAccountId\":\(escape(customerAccountId)),\"recipientId\":\(escape(recipientId)),\"amountMinor\":\(amountMinor),\"method\":\(escape(method)),\"note\":\(escape(note)),\"scenario\":\(escape(scenario))}"
  }

  public static func businessPayloadHash(
    customerAccountId: String,
    recipientId: String,
    amountMinor: Int,
    method: String,
    note: String,
    scenario: String
  ) -> String {
    sha256Hex(
      canonicalBusinessPayload(
        customerAccountId: customerAccountId,
        recipientId: recipientId,
        amountMinor: amountMinor,
        method: method,
        note: note,
        scenario: scenario
      )
    )
  }

  public static func returnStateHash(_ returnState: String) -> String {
    sha256Hex(returnState)
  }

  public static func newReturnState() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    if status != errSecSuccess {
      for index in bytes.indices {
        bytes[index] = UInt8.random(in: UInt8.min...UInt8.max)
      }
    }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }
}

/// Local record of an in-progress or recently finished payment.
/// The raw return-state token is not stored; only its hash is.
public struct PaymentIntentSnapshot: Codable, Equatable {
  public var paymentIntentId: String
  public var idempotencyKey: String
  public var businessPayloadHash: String
  public var status: PaymentIntentStatus
  /// SHA-256 hex of the return-state token presented when the app is resumed.
  public var returnStateHash: String
  public var customerAccountId: String
  public var recipientId: String
  public var amountMinor: Int
  public var method: PaymentMethod
  public var note: String
  public var scenario: Scenario
  public var createdAtEpochMillis: Int64
  public var updatedAtEpochMillis: Int64
  public var terminalAtEpochMillis: Int64?

  public init(
    paymentIntentId: String,
    idempotencyKey: String,
    businessPayloadHash: String,
    status: PaymentIntentStatus,
    returnStateHash: String,
    customerAccountId: String,
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String,
    scenario: Scenario,
    createdAtEpochMillis: Int64,
    updatedAtEpochMillis: Int64,
    terminalAtEpochMillis: Int64? = nil
  ) {
    self.paymentIntentId = paymentIntentId
    self.idempotencyKey = idempotencyKey
    self.businessPayloadHash = businessPayloadHash
    self.status = status
    self.returnStateHash = returnStateHash
    self.customerAccountId = customerAccountId
    self.recipientId = recipientId
    self.amountMinor = amountMinor
    self.method = method
    self.note = note
    self.scenario = scenario
    self.createdAtEpochMillis = createdAtEpochMillis
    self.updatedAtEpochMillis = updatedAtEpochMillis
    self.terminalAtEpochMillis = terminalAtEpochMillis
  }
}

public struct PreparedPaymentIntent: Equatable {
  public let snapshot: PaymentIntentSnapshot
  /// Present only when this call created the snapshot. Resume does not reveal the original token.
  public let returnState: String?

  public init(snapshot: PaymentIntentSnapshot, returnState: String?) {
    self.snapshot = snapshot
    self.returnState = returnState
  }
}

public protocol PaymentIntentSnapshotStore: AnyObject {
  func load(customerAccountId: String) throws -> [PaymentIntentSnapshot]
  func save(_ snapshot: PaymentIntentSnapshot) throws
  func delete(customerAccountId: String, paymentIntentId: String) throws
  func lastCustomerAccountId() throws -> String?
  func rememberCustomerAccountId(_ customerAccountId: String) throws
}

public final class InMemoryPaymentIntentStore: PaymentIntentSnapshotStore, @unchecked Sendable {
  private let lock = NSLock()
  private var snapshots: [String: PaymentIntentSnapshot] = [:]
  private var lastAccount: String?

  public init() {}

  public func load(customerAccountId: String) throws -> [PaymentIntentSnapshot] {
    guard PaymentIntentIds.isValidCustomerAccountId(customerAccountId) else {
      throw PaymentIntentError.invalidAccount
    }
    lock.lock()
    defer { lock.unlock() }
    return snapshots.compactMap { key, snapshot in
      guard PaymentIntentStorageKeys.belongsToAccount(key, customerAccountId: customerAccountId) else {
        return nil
      }
      guard snapshot.customerAccountId == customerAccountId else { return nil }
      return snapshot
    }
  }

  public func save(_ snapshot: PaymentIntentSnapshot) throws {
    let key = try PaymentIntentStorageKeys.snapshotKey(
      customerAccountId: snapshot.customerAccountId,
      paymentIntentId: snapshot.paymentIntentId
    )
    lock.lock()
    defer { lock.unlock() }
    snapshots[key] = snapshot
  }

  public func delete(customerAccountId: String, paymentIntentId: String) throws {
    let key = try PaymentIntentStorageKeys.snapshotKey(
      customerAccountId: customerAccountId,
      paymentIntentId: paymentIntentId
    )
    lock.lock()
    defer { lock.unlock() }
    if snapshots[key]?.customerAccountId == customerAccountId {
      snapshots.removeValue(forKey: key)
    }
  }

  public func lastCustomerAccountId() throws -> String? {
    lock.lock()
    defer { lock.unlock() }
    guard let lastAccount, PaymentIntentIds.isValidCustomerAccountId(lastAccount) else { return nil }
    return lastAccount
  }

  public func rememberCustomerAccountId(_ customerAccountId: String) throws {
    guard PaymentIntentIds.isValidCustomerAccountId(customerAccountId) else {
      throw PaymentIntentError.invalidAccount
    }
    lock.lock()
    defer { lock.unlock() }
    lastAccount = customerAccountId
  }
}

/// iOS Keychain store. Items are device-local, unlocked after first unlock, and labelled by customer account.
public final class KeychainPaymentIntentStore: PaymentIntentSnapshotStore, @unchecked Sendable {
  private let service = "com.atlassian.meridian.payment-intents"
  private let lock = NSLock()

  public init() {}

  public func load(customerAccountId: String) throws -> [PaymentIntentSnapshot] {
    guard PaymentIntentIds.isValidCustomerAccountId(customerAccountId) else {
      throw PaymentIntentError.invalidAccount
    }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecMatchLimit as String: kSecMatchLimitAll,
      kSecReturnData as String: true,
      kSecReturnAttributes as String: true,
      kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
    ]
    return try lock.performLocked {
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      if status == errSecItemNotFound { return [] }
      guard status == errSecSuccess else {
        throw PaymentIntentError.storage("Keychain read failed (\(status))")
      }
      let rows = dictionaries(from: result)
      var snapshots: [PaymentIntentSnapshot] = []
      for row in rows {
        guard let account = row[kSecAttrAccount as String] as? String,
          PaymentIntentStorageKeys.belongsToAccount(account, customerAccountId: customerAccountId)
        else { continue }
        guard let data = row[kSecValueData as String] as? Data else { continue }
        guard let snapshot = try? JSONDecoder().decode(PaymentIntentSnapshot.self, from: data) else { continue }
        guard snapshot.customerAccountId == customerAccountId else { continue }
        snapshots.append(snapshot)
      }
      return snapshots
    }
  }

  public func save(_ snapshot: PaymentIntentSnapshot) throws {
    let account = try PaymentIntentStorageKeys.snapshotKey(
      customerAccountId: snapshot.customerAccountId,
      paymentIntentId: snapshot.paymentIntentId
    )
    let data = try JSONEncoder().encode(snapshot)
    try lock.performLocked {
      let found = try copyStatus(account: account)
      if found == errSecSuccess {
        let update: [String: Any] = [
          kSecValueData as String: data,
          kSecAttrLabel as String: snapshotLabel(snapshot.customerAccountId),
          kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, update as CFDictionary)
        guard status == errSecSuccess else {
          throw PaymentIntentError.storage("Keychain update failed (\(status))")
        }
      } else if found == errSecItemNotFound {
        var add = baseQuery(account: account)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = snapshotLabel(snapshot.customerAccountId)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
          throw PaymentIntentError.storage("Keychain save failed (\(status))")
        }
      } else {
        throw PaymentIntentError.storage("Keychain lookup failed (\(found))")
      }
    }
  }

  public func delete(customerAccountId: String, paymentIntentId: String) throws {
    let account = try PaymentIntentStorageKeys.snapshotKey(
      customerAccountId: customerAccountId,
      paymentIntentId: paymentIntentId
    )
    try lock.performLocked {
      let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw PaymentIntentError.storage("Keychain delete failed (\(status))")
      }
    }
  }

  public func lastCustomerAccountId() throws -> String? {
    try lock.performLocked {
      var result: CFTypeRef?
      let status = SecItemCopyMatching(baseQuery(account: PaymentIntentStorageKeys.lastAccountKey, returnData: true) as CFDictionary, &result)
      if status == errSecItemNotFound { return nil }
      guard status == errSecSuccess, let row = result as? [String: Any], let data = row[kSecValueData as String] as? Data,
        let value = String(data: data, encoding: .utf8),
        PaymentIntentIds.isValidCustomerAccountId(value)
      else {
        if status != errSecSuccess {
          throw PaymentIntentError.storage("Keychain account read failed (\(status))")
        }
        return nil
      }
      return value
    }
  }

  public func rememberCustomerAccountId(_ customerAccountId: String) throws {
    guard PaymentIntentIds.isValidCustomerAccountId(customerAccountId) else {
      throw PaymentIntentError.invalidAccount
    }
    let data = Data(customerAccountId.utf8)
    try lock.performLocked {
      let found = try copyStatus(account: PaymentIntentStorageKeys.lastAccountKey)
      if found == errSecSuccess {
        let update: [String: Any] = [
          kSecValueData as String: data,
          kSecAttrLabel as String: "index",
          kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery(account: PaymentIntentStorageKeys.lastAccountKey) as CFDictionary, update as CFDictionary)
        guard status == errSecSuccess else {
          throw PaymentIntentError.storage("Keychain account update failed (\(status))")
        }
      } else if found == errSecItemNotFound {
        var add = baseQuery(account: PaymentIntentStorageKeys.lastAccountKey)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "index"
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
          throw PaymentIntentError.storage("Keychain account save failed (\(status))")
        }
      } else {
        throw PaymentIntentError.storage("Keychain account lookup failed (\(found))")
      }
    }
  }

  private func snapshotLabel(_ customerAccountId: String) -> String {
    "acct:\(customerAccountId)"
  }

  private func baseQuery(account: String, returnData: Bool = false) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
    ]
    if returnData {
      query[kSecReturnData as String] = true
      query[kSecReturnAttributes as String] = true
    }
    return query
  }

  private func copyStatus(account: String) throws -> OSStatus {
    SecItemCopyMatching(baseQuery(account: account) as CFDictionary, nil)
  }

  private func dictionaries(from result: CFTypeRef?) -> [[String: Any]] {
    if let rows = result as? [[String: Any]] { return rows }
    if let row = result as? [String: Any] { return [row] }
    if let rows = result as? [NSDictionary] {
      return rows.compactMap { $0 as? [String: Any] }
    }
    if let row = result as? NSDictionary, let typed = row as? [String: Any] { return [typed] }
    return []
  }
}

private extension NSLock {
  func performLocked<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}

public final class PaymentIntentLedger {
  private let store: PaymentIntentSnapshotStore
  private let nowMillis: () -> Int64
  private let retentionMillis: Int64
  private let lock = NSRecursiveLock()

  public init(
    store: PaymentIntentSnapshotStore,
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
    retentionMillis: Int64 = PaymentIntentRetention.terminalWindowMillis
  ) {
    self.store = store
    self.nowMillis = nowMillis
    self.retentionMillis = retentionMillis
  }

  public func rememberCustomerAccount(_ customerAccountId: String) throws {
    try lock.performLocked {
      guard PaymentIntentIds.isValidCustomerAccountId(customerAccountId) else {
        throw PaymentIntentError.invalidAccount
      }
      try store.rememberCustomerAccountId(customerAccountId)
    }
  }

  public func lastCustomerAccountId() throws -> String? {
    try lock.performLocked { try store.lastCustomerAccountId() }
  }

  public func purgeExpired(customerAccountId: String) throws {
    try lock.performLocked {
      let now = nowMillis()
      for snapshot in try store.load(customerAccountId: customerAccountId) where snapshot.customerAccountId == customerAccountId {
        guard snapshot.status.isTerminal, let terminalAt = snapshot.terminalAtEpochMillis else { continue }
        if now >= terminalAt + retentionMillis {
          try store.delete(customerAccountId: customerAccountId, paymentIntentId: snapshot.paymentIntentId)
        }
      }
    }
  }

  public func snapshots(customerAccountId: String) throws -> [PaymentIntentSnapshot] {
    try lock.performLocked {
      try purgeExpired(customerAccountId: customerAccountId)
      return try store.load(customerAccountId: customerAccountId)
        .filter { $0.customerAccountId == customerAccountId }
        .sorted { $0.updatedAtEpochMillis > $1.updatedAtEpochMillis }
    }
  }

  public func activeIntents(customerAccountId: String) throws -> [PaymentIntentSnapshot] {
    try snapshots(customerAccountId: customerAccountId).filter { $0.status.isActive }
  }

  public func snapshot(customerAccountId: String, paymentIntentId: String) throws -> PaymentIntentSnapshot {
    try lock.performLocked {
      guard let found = try store.load(customerAccountId: customerAccountId).first(where: {
        $0.paymentIntentId == paymentIntentId && $0.customerAccountId == customerAccountId
      }) else {
        throw PaymentIntentError.notFound
      }
      return found
    }
  }

  public func begin(
    customerAccountId: String,
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String,
    scenario: Scenario
  ) throws -> PreparedPaymentIntent {
    try lock.performLocked {
      try validate(customerAccountId: customerAccountId, recipientId: recipientId, amountMinor: amountMinor, note: note)
      try purgeExpired(customerAccountId: customerAccountId)
      let hash = PaymentIntentHash.businessPayloadHash(
        customerAccountId: customerAccountId,
        recipientId: recipientId,
        amountMinor: amountMinor,
        method: method.rawValue,
        note: note,
        scenario: scenario.rawValue
      )
      let active = try store.load(customerAccountId: customerAccountId)
        .filter { $0.customerAccountId == customerAccountId && $0.status.isActive }
        .sorted { $0.updatedAtEpochMillis > $1.updatedAtEpochMillis }
      if let existing = active.first {
        if existing.businessPayloadHash == hash && existing.recipientId == recipientId && existing.amountMinor == amountMinor
          && existing.method == method && existing.note == note && existing.scenario == scenario
        {
          var touched = existing
          touched.updatedAtEpochMillis = nowMillis()
          try store.save(touched)
          try store.rememberCustomerAccountId(customerAccountId)
          return PreparedPaymentIntent(snapshot: touched, returnState: nil)
        }
        if existing.status == .created {
          _ = try cancel(customerAccountId: customerAccountId, paymentIntentId: existing.paymentIntentId)
        } else {
          throw PaymentIntentError.activeIntentInProgress(existing.paymentIntentId)
        }
      }
      let returnState = PaymentIntentHash.newReturnState()
      let now = nowMillis()
      let snapshot = PaymentIntentSnapshot(
        paymentIntentId: PaymentIntentIds.newPaymentIntentId(),
        idempotencyKey: PaymentIntentIds.newIdempotencyKey(),
        businessPayloadHash: hash,
        status: .created,
        returnStateHash: PaymentIntentHash.returnStateHash(returnState),
        customerAccountId: customerAccountId,
        recipientId: recipientId,
        amountMinor: amountMinor,
        method: method,
        note: note,
        scenario: scenario,
        createdAtEpochMillis: now,
        updatedAtEpochMillis: now
      )
      try store.save(snapshot)
      try store.rememberCustomerAccountId(customerAccountId)
      return PreparedPaymentIntent(snapshot: snapshot, returnState: returnState)
    }
  }

  public func markSubmitted(customerAccountId: String, paymentIntentId: String) throws -> PaymentIntentSnapshot {
    try lock.performLocked {
      var snapshot = try snapshot(customerAccountId: customerAccountId, paymentIntentId: paymentIntentId)
      if snapshot.status.isTerminal {
        throw PaymentIntentError.terminal(snapshot.paymentIntentId)
      }
      snapshot.status = .submitted
      snapshot.updatedAtEpochMillis = nowMillis()
      snapshot.terminalAtEpochMillis = nil
      try store.save(snapshot)
      return snapshot
    }
  }

  public func record(
    response: PaymentResponse,
    customerAccountId: String,
    paymentIntentId: String
  ) throws -> PaymentIntentSnapshot {
    try lock.performLocked {
      var snapshot = try snapshot(customerAccountId: customerAccountId, paymentIntentId: paymentIntentId)
      if snapshot.status.isTerminal { return snapshot }
      let status = Self.status(for: response)
      let now = nowMillis()
      snapshot.status = status
      snapshot.updatedAtEpochMillis = now
      snapshot.terminalAtEpochMillis = status.isTerminal ? now : nil
      try store.save(snapshot)
      return snapshot
    }
  }

  public func markUncertain(customerAccountId: String, paymentIntentId: String) throws -> PaymentIntentSnapshot {
    try lock.performLocked {
      var snapshot = try snapshot(customerAccountId: customerAccountId, paymentIntentId: paymentIntentId)
      if snapshot.status.isTerminal {
        throw PaymentIntentError.terminal(snapshot.paymentIntentId)
      }
      snapshot.status = .unknown
      snapshot.updatedAtEpochMillis = nowMillis()
      snapshot.terminalAtEpochMillis = nil
      try store.save(snapshot)
      return snapshot
    }
  }

  public func cancel(customerAccountId: String, paymentIntentId: String) throws -> PaymentIntentSnapshot {
    try lock.performLocked {
      var snapshot = try snapshot(customerAccountId: customerAccountId, paymentIntentId: paymentIntentId)
      if snapshot.status.isTerminal { return snapshot }
      let now = nowMillis()
      snapshot.status = .cancelled
      snapshot.updatedAtEpochMillis = now
      snapshot.terminalAtEpochMillis = now
      try store.save(snapshot)
      return snapshot
    }
  }

  public func verifyReturnState(_ snapshot: PaymentIntentSnapshot, returnState: String) -> Bool {
    constantTimeEquals(snapshot.returnStateHash, PaymentIntentHash.returnStateHash(returnState))
  }

  public static func status(for response: PaymentResponse) -> PaymentIntentStatus {
    if response.ok {
      switch response.transaction?.status {
      case .declined:
        return .declined
      case .pending:
        return .pending
      case .completed, .none:
        return .completed
      }
    }
    switch response.code {
    case "PAYMENT_PENDING":
      return .pending
    case "DECLINED", "INSUFFICIENT_BALANCE":
      return .declined
    default:
      return .unknown
    }
  }

  private func validate(customerAccountId: String, recipientId: String, amountMinor: Int, note: String) throws {
    guard PaymentIntentIds.isValidCustomerAccountId(customerAccountId) else {
      throw PaymentIntentError.invalidAccount
    }
    guard !recipientId.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw PaymentIntentError.invalidRecipient
    }
    if amountMinor <= 0 {
      throw PaymentIntentError.invalidAmount("Amount must be greater than zero")
    }
    if amountMinor > 1_000_000 {
      throw PaymentIntentError.invalidAmount("Amount cannot exceed £10,000")
    }
    if note.count > 200 {
      throw PaymentIntentError.invalidNote
    }
  }

  private func constantTimeEquals(_ left: String, _ right: String) -> Bool {
    let a = Array(left.utf8)
    let b = Array(right.utf8)
    if a.count != b.count { return false }
    var diff: UInt8 = 0
    for index in a.indices { diff |= a[index] ^ b[index] }
    return diff == 0
  }
}

private extension NSRecursiveLock {
  func performLocked<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
