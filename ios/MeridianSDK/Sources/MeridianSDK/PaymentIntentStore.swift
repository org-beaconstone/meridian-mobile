import CryptoKit
import Foundation
import Security

// MARK: - Business Payload Hash

/// Computes a canonical SHA-256 hex hash of payment business parameters.
///
/// The hash uniquely identifies the business intent of a payment so that
/// resumption logic can verify no parameters changed between attempts.
public func businessPayloadHash(
  recipientId: String,
  amountMinor: Int,
  method: PaymentMethod,
  note: String,
  scenario: Scenario
) -> String {
  let canonical = "\(recipientId)|\(amountMinor)|\(method.rawValue)|\(note)|\(scenario.rawValue)"
  let hash = SHA256.hash(data: Data(canonical.utf8))
  return hash.compactMap { String(format: "%02x", $0) }.joined()
}

// MARK: - PaymentIntentStore

/// Keychain-backed store for ``PaymentIntentSnapshot`` records, isolated by customer account.
///
/// All snapshots for a given account are persisted as a single JSON array under one
/// Keychain generic-password item keyed by the caller-supplied `accountId`. This
/// limits Keychain round-trips while keeping data scoped per account.
///
/// Keychain item attributes:
/// - `kSecAttrService`: `"com.atlassian.meridian.payment-intent"`
/// - `kSecAttrAccount`: the `accountId` string passed by the caller
///
/// Usage:
/// ```swift
/// let store = PaymentIntentStore()
/// try store.save(snapshot, accountId: customerId)
/// if let active = try store.loadActiveIntent(accountId: customerId) {
///     // Resume the in-flight payment
/// }
/// ```
public final class PaymentIntentStore {
  private let keychainService = "com.atlassian.meridian.payment-intent"

  public init() {}

  // MARK: - Public API

  /// Persist or replace a snapshot for the given account.
  ///
  /// If a snapshot with the same `paymentIntentId` already exists it is replaced
  /// in-place; otherwise the new snapshot is appended to the account's list.
  public func save(_ snapshot: PaymentIntentSnapshot, accountId: String) throws {
    var snapshots = (try? loadAll(accountId: accountId)) ?? []
    if let idx = snapshots.firstIndex(where: { $0.paymentIntentId == snapshot.paymentIntentId }) {
      snapshots[idx] = snapshot
    } else {
      snapshots.append(snapshot)
    }
    try persist(snapshots, accountId: accountId)
  }

  /// Return all snapshots for the account (including expired entries).
  public func loadAll(accountId: String) throws -> [PaymentIntentSnapshot] {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: keychainService,
      kSecAttrAccount: accountId,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else {
      if status == errSecItemNotFound { return [] }
      throw PaymentIntentStoreError.keychainError(status)
    }
    return try JSONDecoder().decode([PaymentIntentSnapshot].self, from: data)
  }

  /// Return the first non-expired active (pending) intent for the account, or `nil`.
  ///
  /// Call this on app launch or process recovery to detect an in-flight payment
  /// that requires resumption.
  public func loadActiveIntent(accountId: String) throws -> PaymentIntentSnapshot? {
    let all = try loadAll(accountId: accountId)
    return all.first { $0.isActive && !$0.isExpired }
  }

  /// Remove a specific snapshot by `paymentIntentId`.
  public func delete(paymentIntentId: String, accountId: String) throws {
    var snapshots = (try? loadAll(accountId: accountId)) ?? []
    snapshots.removeAll { $0.paymentIntentId == paymentIntentId }
    try persist(snapshots, accountId: accountId)
  }

  /// Remove all expired snapshots for the account.
  public func purgeExpired(accountId: String) throws {
    var snapshots = (try? loadAll(accountId: accountId)) ?? []
    snapshots.removeAll { $0.isExpired }
    try persist(snapshots, accountId: accountId)
  }

  // MARK: - Private Helpers

  private func persist(_ snapshots: [PaymentIntentSnapshot], accountId: String) throws {
    let data = try JSONEncoder().encode(snapshots)
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: keychainService,
      kSecAttrAccount: accountId,
    ]
    let existingStatus = SecItemCopyMatching(query as CFDictionary, nil)
    if existingStatus == errSecItemNotFound {
      var addQuery = query
      addQuery[kSecValueData] = data
      let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw PaymentIntentStoreError.keychainError(addStatus)
      }
    } else if existingStatus == errSecSuccess {
      let attributes: [CFString: Any] = [kSecValueData: data]
      let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      guard updateStatus == errSecSuccess else {
        throw PaymentIntentStoreError.keychainError(updateStatus)
      }
    } else {
      throw PaymentIntentStoreError.keychainError(existingStatus)
    }
  }
}

// MARK: - Error Type

public enum PaymentIntentStoreError: Error, Equatable {
  case keychainError(OSStatus)
  case encodingError(String)
}
