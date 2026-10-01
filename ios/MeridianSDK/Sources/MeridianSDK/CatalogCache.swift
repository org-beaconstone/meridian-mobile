import CryptoKit
import Foundation
import Security

/// Encrypted catalog cache keyed by account scope, corridor, and currency.
///
/// Blobs are AES-256-GCM with the cache key as additional authenticated data, so a blob
/// cannot be replayed under a different scope. The AES key and ciphertext live in the
/// Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
///
/// Stale methods that require live eligibility are withheld. A timeout reads this same key
/// and does not send the caller to a different provider.
public final class CatalogCache: @unchecked Sendable {
  private let store: CatalogBlobStore
  private let keys: CatalogKeyProviding
  private let lock = NSLock()

  public init(store: CatalogBlobStore, keys: CatalogKeyProviding) {
    self.store = store
    self.keys = keys
  }

  public static func platformProtected() -> CatalogCache {
    CatalogCache(store: KeychainCatalogBlobStore(), keys: KeychainCatalogKeyProvider())
  }

  public func store(scope: CatalogScope, rawJSON: Data, nowEpochMs: Int64) throws {
    _ = try parsePaymentMethodsCatalog(rawJSON, expected: scope)
    let plaintext = try envelope(scope: scope, storedAtEpochMs: nowEpochMs, rawJSON: rawJSON)
    let secret = try keys.loadOrCreateKey()
    let blob = try CatalogCipher.encrypt(key: secret, aad: Data(scope.storageKey.utf8), plaintext: plaintext)
    try withStoreLock { try store.write(key: scope.storageKey, data: blob) }
  }

  private func withStoreLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  public func read(scope: CatalogScope, nowEpochMs: Int64) throws -> CatalogResolution? {
    let blob = try withStoreLock { try store.read(key: scope.storageKey) }
    guard let blob else { return nil }
    let plaintext: Data
    do {
      plaintext = try CatalogCipher.decrypt(
        key: keys.loadOrCreateKey(),
        aad: Data(scope.storageKey.utf8),
        blob: blob
      )
    } catch let error as MeridianError {
      throw error
    } catch {
      throw MeridianError.catalogUnavailable("Catalog cache blob failed authentication")
    }
    let opened = try openEnvelope(plaintext, expected: scope)
    return eligibility(
      catalog: opened.catalog,
      storedAtEpochMs: opened.storedAtEpochMs,
      nowEpochMs: nowEpochMs,
      fromCache: true
    )
  }

  /// Fetch the catalog, encrypt it, and return methods that pass the expiry policy.
  /// On a transport or HTTP failure, read the same cache key. Never requests another corridor or provider.
  public func resolve(
    client: MeridianClient,
    accountScope: String,
    corridor: String,
    currency: String = "GBP",
    nowEpochMs: Int64
  ) async throws -> CatalogResolution {
    let scope = try CatalogScope.parse(accountScope: accountScope, corridor: corridor, currency: currency)
    do {
      let fetched = try await client.fetchPaymentMethods(
        accountScope: scope.accountScope,
        corridor: scope.corridor,
        currency: scope.currency
      )
      try store(scope: scope, rawJSON: fetched.rawJSON, nowEpochMs: nowEpochMs)
      return eligibility(
        catalog: fetched.catalog,
        storedAtEpochMs: nowEpochMs,
        nowEpochMs: nowEpochMs,
        fromCache: false
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      let cached: CatalogResolution?
      do {
        cached = try read(scope: scope, nowEpochMs: nowEpochMs)
      } catch {
        throw MeridianError.catalogUnavailable("Cached payment methods failed validation")
      }
      if let cached { return cached }
      throw error
    }
  }
}

public struct CatalogResolution: Hashable {
  public let scope: CatalogScope
  public let methods: [PaymentMethodDescriptor]
  public let fromCache: Bool
  public let stale: Bool
  public let withheldLiveEligibility: Int

  public init(
    scope: CatalogScope,
    methods: [PaymentMethodDescriptor],
    fromCache: Bool,
    stale: Bool,
    withheldLiveEligibility: Int
  ) {
    self.scope = scope
    self.methods = methods
    self.fromCache = fromCache
    self.stale = stale
    self.withheldLiveEligibility = withheldLiveEligibility
  }
}

func eligibility(
  catalog: PaymentMethodsCatalog,
  storedAtEpochMs: Int64,
  nowEpochMs: Int64,
  fromCache: Bool
) -> CatalogResolution {
  let ageMillis = nowEpochMs - storedAtEpochMs
  let ageSeconds = ageMillis <= 0 ? Int64(0) : ageMillis / 1000
  var kept: [PaymentMethodDescriptor] = []
  var withheld = 0
  for method in catalog.methods {
    if !method.enabled { continue }
    let ttl = min(catalog.ttlSeconds, method.ttlSeconds)
    let staleMethod = ageSeconds >= Int64(ttl)
    if staleMethod && method.requiresLiveEligibility {
      withheld += 1
      continue
    }
    kept.append(method)
  }
  return CatalogResolution(
    scope: CatalogScope(
      accountScope: catalog.accountScope,
      corridor: catalog.corridor,
      currency: catalog.currency
    ),
    methods: kept,
    fromCache: fromCache,
    stale: ageSeconds >= Int64(catalog.ttlSeconds),
    withheldLiveEligibility: withheld
  )
}

public protocol CatalogBlobStore: AnyObject {
  func read(key: String) throws -> Data?
  func write(key: String, data: Data) throws
}

public protocol CatalogKeyProviding: AnyObject {
  func loadOrCreateKey() throws -> SymmetricKey
}

public final class MemoryCatalogBlobStore: CatalogBlobStore {
  private var values: [String: Data] = [:]

  public init() {}

  public func read(key: String) throws -> Data? { values[key] }

  public func write(key: String, data: Data) throws { values[key] = data }

  func peek(key: String) -> Data? { values[key] }

  func copy(from: String, to: String) {
    values[to] = values[from]
  }
}

public final class MemoryCatalogKeyProvider: CatalogKeyProviding {
  private let key = SymmetricKey(size: .bits256)

  public init() {}

  public func loadOrCreateKey() throws -> SymmetricKey { key }
}

public final class KeychainCatalogBlobStore: CatalogBlobStore {
  private let service = "com.atlassian.meridian.catalog"

  public init() {}

  public func read(key: String) throws -> Data? {
    try KeychainBytes.read(service: service, account: "blob.\(key)")
  }

  public func write(key: String, data: Data) throws {
    try KeychainBytes.write(service: service, account: "blob.\(key)", data: data)
  }
}

public final class KeychainCatalogKeyProvider: CatalogKeyProviding {
  private let service = "com.atlassian.meridian.catalog"
  private let account = "catalog-aes-key"

  public init() {}

  public func loadOrCreateKey() throws -> SymmetricKey {
    if let existing = try KeychainBytes.read(service: service, account: account) {
      guard existing.count == 32 else {
        throw MeridianError.catalogUnavailable("Protected catalog key is unusable")
      }
      return SymmetricKey(data: existing)
    }
    let key = SymmetricKey(size: .bits256)
    let bytes = key.withUnsafeBytes { Data($0) }
    try KeychainBytes.write(service: service, account: account, data: bytes)
    return key
  }
}

enum KeychainBytes {
  static func read(service: String, account: String) throws -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
      throw MeridianError.catalogUnavailable("Keychain read failed (\(status))")
    }
    return data
  }

  static func write(service: String, account: String, data: Data) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if update == errSecSuccess { return }
    if update != errSecItemNotFound {
      throw MeridianError.catalogUnavailable("Keychain update failed (\(update))")
    }
    var insert = query
    insert[kSecValueData as String] = data
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(insert as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw MeridianError.catalogUnavailable("Keychain write failed (\(status))")
    }
  }
}

enum CatalogCipher {
  static let magic = Data("MRC1".utf8)

  static func encrypt(key: SymmetricKey, aad: Data, plaintext: Data) throws -> Data {
    let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
    guard let combined = sealed.combined else {
      throw MeridianError.catalogUnavailable("Encryption failed")
    }
    return magic + combined
  }

  static func decrypt(key: SymmetricKey, aad: Data, blob: Data) throws -> Data {
    guard blob.starts(with: magic), blob.count >= magic.count + 12 + 16 else {
      throw MeridianError.catalogUnavailable("Catalog cache blob is not readable")
    }
    do {
      let combined = Data(blob.dropFirst(magic.count))
      let box = try AES.GCM.SealedBox(combined: combined)
      return try AES.GCM.open(box, using: key, authenticating: aad)
    } catch let error as MeridianError {
      throw error
    } catch {
      throw MeridianError.catalogUnavailable("Catalog cache blob failed authentication")
    }
  }
}

private struct OpenedCatalog {
  let catalog: PaymentMethodsCatalog
  let storedAtEpochMs: Int64
}

private func envelope(scope: CatalogScope, storedAtEpochMs: Int64, rawJSON: Data) throws -> Data {
  guard let body = String(data: rawJSON, encoding: .utf8) else {
    throw MeridianError.decodingError("Payment method catalog is not valid JSON")
  }
  let object: [String: Any] = [
    "v": NSNumber(value: 1),
    "storedAtEpochMs": NSNumber(value: storedAtEpochMs),
    "accountScope": scope.accountScope,
    "corridor": scope.corridor,
    "currency": scope.currency,
    "body": body,
  ]
  return try JSONSerialization.data(withJSONObject: object, options: [])
}

private func openEnvelope(_ plaintext: Data, expected: CatalogScope) throws -> OpenedCatalog {
  let rootAny: Any
  do {
    rootAny = try JSONSerialization.jsonObject(with: plaintext, options: [])
  } catch {
    throw MeridianError.catalogUnavailable("Catalog cache blob is not readable")
  }
  guard let root = rootAny as? [String: Any], jsonInt64(root["v"]) == 1 else {
    throw MeridianError.catalogUnavailable("Catalog cache blob is not readable")
  }
  guard let storedAt = jsonInt64(root["storedAtEpochMs"]) else {
    throw MeridianError.catalogUnavailable("Catalog cache blob is not readable")
  }
  guard
    root["accountScope"] as? String == expected.accountScope,
    root["corridor"] as? String == expected.corridor,
    root["currency"] as? String == expected.currency
  else {
    throw MeridianError.catalogUnavailable("Catalog cache blob does not match the requested scope")
  }
  guard let body = root["body"] as? String, let bodyData = body.data(using: .utf8) else {
    throw MeridianError.catalogUnavailable("Catalog cache blob is not readable")
  }
  return OpenedCatalog(
    catalog: try parsePaymentMethodsCatalog(bodyData, expected: expected),
    storedAtEpochMs: storedAt
  )
}

private func jsonInt64(_ value: Any?) -> Int64? {
  guard let number = value as? NSNumber else { return nil }
  if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
  let double = number.doubleValue
  guard double.rounded() == double, double <= Double(Int64.max), double >= Double(Int64.min) else {
    return nil
  }
  return number.int64Value
}
