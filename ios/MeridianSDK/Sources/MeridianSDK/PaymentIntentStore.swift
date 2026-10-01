import CryptoKit
import Foundation
import Security

// MARK: - PaymentIntentStatus

/// Lifecycle status of a payment intent snapshot.
public enum PaymentIntentStatus: String, Codable, Hashable, CaseIterable {
  case created     // Snapshot recorded; request not yet sent or outcome unknown
  case pending     // Server acknowledged with PAYMENT_PENDING; awaiting confirmation
  case completed   // Server confirmed payment success
  case declined    // Server rejected the payment
  case expired     // Snapshot passed terminal retention window and was invalidated

  /// Terminal statuses are eligible for expiry after the retention window.
  public var isTerminal: Bool {
    switch self {
    case .completed, .declined, .expired: return true
    case .created, .pending: return false
    }
  }
}

// MARK: - PaymentIntentSnapshot

/// Captures the durable state of a single payment intent so it can be resumed
/// after a process crash or app restart.
public struct PaymentIntentSnapshot: Codable, Hashable {
  /// Server-assigned payment intent ID (populated after first server response;
  /// equals idempotencyKey until then).
  public var paymentIntentId: String
  /// Client-generated UUID sent as the Idempotency-Key header.
  public let idempotencyKey: String
  /// SHA-256 hex digest of the canonical payment request payload.
  public let businessPayloadHash: String
  /// Current lifecycle status.
  public var status: PaymentIntentStatus
  /// SHA-256 hex digest of the bank state returned by the server, or nil when
  /// no state has been received yet.
  public var returnStateHash: String?
  /// ISO 8601 timestamp when the snapshot was first created.
  public let createdAt: Date
  /// ISO 8601 timestamp of the most recent status update.
  public var updatedAt: Date

  // Snapshots in a terminal state are purged after this window.
  static let terminalRetentionWindow: TimeInterval = 86_400 // 24 h

  public var isExpired: Bool {
    status.isTerminal && Date().timeIntervalSince(updatedAt) > Self.terminalRetentionWindow
  }

  public init(
    paymentIntentId: String,
    idempotencyKey: String,
    businessPayloadHash: String,
    status: PaymentIntentStatus = .created,
    returnStateHash: String? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.paymentIntentId = paymentIntentId
    self.idempotencyKey = idempotencyKey
    self.businessPayloadHash = businessPayloadHash
    self.status = status
    self.returnStateHash = returnStateHash
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

// MARK: - PaymentIntentStore protocol

/// Durable store for payment intent snapshots, scoped to an authenticated
/// customer account.
public protocol PaymentIntentStore: Sendable {
  /// Persist or replace a snapshot.
  func save(_ snapshot: PaymentIntentSnapshot) async throws
  /// Load a single snapshot by idempotency key. Returns nil when not found or
  /// when the snapshot has passed its retention window.
  func load(idempotencyKey: String) async throws -> PaymentIntentSnapshot?
  /// Return all non-terminal snapshots for the current account. Expired
  /// entries are removed as a side effect.
  func loadActive() async throws -> [PaymentIntentSnapshot]
  /// Remove a snapshot permanently.
  func delete(idempotencyKey: String) async throws
}

// MARK: - Hash helpers

/// Returns a lower-case hex-encoded SHA-256 digest of the UTF-8 string.
func sha256Hex(_ input: String) -> String {
  let digest = SHA256.hash(data: Data(input.utf8))
  return digest.map { String(format: "%02x", $0) }.joined()
}

/// Canonical hash of a payment request payload.
public func paymentPayloadHash(
  recipientId: String,
  amountMinor: Int,
  method: PaymentMethod,
  note: String
) -> String {
  sha256Hex("\(recipientId)|\(amountMinor)|\(method.rawValue)|\(note)")
}

/// Hash of a bank state snapshot for change detection.
public func bankStateHash(version: Int, balance: Int) -> String {
  sha256Hex("\(version)|\(balance)")
}

// MARK: - KeychainPaymentIntentStore

/// Stores payment intent snapshots in the iOS / macOS Keychain, isolated per
/// customer account via a prefixed account attribute.
///
/// Each snapshot is stored as a separate Keychain generic-password item:
///   - service  : `com.atlassian.meridian.payment-intents`
///   - account  : `{customerId}:{idempotencyKey}`
///   - data     : JSON-encoded `PaymentIntentSnapshot`
///   - accessible: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
public final class KeychainPaymentIntentStore: PaymentIntentStore {
  private let service = "com.atlassian.meridian.payment-intents"
  private let customerId: String
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  /// - Parameter customerId: The authenticated session / customer identifier
  ///   used to scope all stored snapshots.
  public init(customerId: String) {
    self.customerId = customerId
    encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  // MARK: PaymentIntentStore

  public func save(_ snapshot: PaymentIntentSnapshot) async throws {
    let data = try encoder.encode(snapshot)
    let account = keychainAccount(for: snapshot.idempotencyKey)

    let updateQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
    let attributes: [CFString: Any] = [
      kSecValueData: data,
      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]

    let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecItemNotFound {
      var addQuery = updateQuery
      addQuery[kSecValueData] = data
      addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw MeridianError.networkError("Keychain write failed: \(addStatus)")
      }
    } else if updateStatus != errSecSuccess {
      throw MeridianError.networkError("Keychain update failed: \(updateStatus)")
    }
  }

  public func load(idempotencyKey: String) async throws -> PaymentIntentSnapshot? {
    let account = keychainAccount(for: idempotencyKey)
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let data = result as? Data else {
      if status == errSecItemNotFound { return nil }
      throw MeridianError.networkError("Keychain read failed: \(status)")
    }

    let snapshot = try decoder.decode(PaymentIntentSnapshot.self, from: data)
    if snapshot.isExpired {
      try await delete(idempotencyKey: idempotencyKey)
      return nil
    }
    return snapshot
  }

  public func loadActive() async throws -> [PaymentIntentSnapshot] {
    // Retrieve all generic-password items for this service.
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecReturnData: true,
      kSecReturnAttributes: true,
      kSecMatchLimit: kSecMatchLimitAll,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let items = result as? [[CFString: Any]] else {
      if status == errSecItemNotFound { return [] }
      throw MeridianError.networkError("Keychain query failed: \(status)")
    }

    let prefix = "\(customerId):"
    var active: [PaymentIntentSnapshot] = []
    var toDelete: [String] = []

    for item in items {
      guard
        let account = item[kSecAttrAccount] as? String,
        account.hasPrefix(prefix),
        let data = item[kSecValueData] as? Data,
        let snapshot = try? decoder.decode(PaymentIntentSnapshot.self, from: data)
      else { continue }

      if snapshot.isExpired {
        toDelete.append(snapshot.idempotencyKey)
      } else if !snapshot.status.isTerminal {
        active.append(snapshot)
      }
    }

    for key in toDelete {
      try? await delete(idempotencyKey: key)
    }

    return active
  }

  public func delete(idempotencyKey: String) async throws {
    let account = keychainAccount(for: idempotencyKey)
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw MeridianError.networkError("Keychain delete failed: \(status)")
    }
  }

  // MARK: Private

  private func keychainAccount(for idempotencyKey: String) -> String {
    "\(customerId):\(idempotencyKey)"
  }
}

// MARK: - InMemoryPaymentIntentStore

/// A non-persistent, in-memory `PaymentIntentStore` suitable for tests,
/// SwiftUI Previews, and simulator environments where Keychain is unavailable.
public final class InMemoryPaymentIntentStore: PaymentIntentStore, @unchecked Sendable {
  private var store: [String: PaymentIntentSnapshot] = [:]
  private let lock = NSLock()

  public init() {}

  public func save(_ snapshot: PaymentIntentSnapshot) async throws {
    lock.withLock { store[snapshot.idempotencyKey] = snapshot }
  }

  public func load(idempotencyKey: String) async throws -> PaymentIntentSnapshot? {
    let snapshot = lock.withLock { store[idempotencyKey] }
    guard let snapshot else { return nil }
    if snapshot.isExpired {
      try await delete(idempotencyKey: idempotencyKey)
      return nil
    }
    return snapshot
  }

  public func loadActive() async throws -> [PaymentIntentSnapshot] {
    let all = lock.withLock { Array(store.values) }
    var active: [PaymentIntentSnapshot] = []
    for snapshot in all {
      if snapshot.isExpired {
        try await delete(idempotencyKey: snapshot.idempotencyKey)
      } else if !snapshot.status.isTerminal {
        active.append(snapshot)
      }
    }
    return active
  }

  public func delete(idempotencyKey: String) async throws {
    lock.withLock { store.removeValue(forKey: idempotencyKey) }
  }
}
