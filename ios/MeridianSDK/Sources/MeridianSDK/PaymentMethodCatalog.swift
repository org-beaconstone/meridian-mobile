import Foundation
import CoreFoundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Security)
import Security
#endif

public let liveEligibilityCapability = "live-eligibility"
public let defaultCatalogTtlSeconds: Int64 = 300
public let maxCatalogTtlSeconds: Int64 = 86_400

private let accountScopePattern = "^[A-Za-z0-9_-]{1,64}$"
private let corridorPattern = "^[A-Za-z0-9_-]{1,32}$"
private let catalogFields: Set<String> = ["accountScope", "corridor", "currency", "ttlSeconds", "methods"]
private let descriptorFields: Set<String> = [
  "id", "method", "provider", "displayName", "currency", "corridor",
  "requiresLiveEligibility", "capabilities", "ttlSeconds",
]

public enum CatalogQuery {
  public static func validate(accountScope: String, corridor: String, currency: String) throws {
    guard accountScope.range(of: accountScopePattern, options: .regularExpression) != nil else {
      throw MeridianError.validationError("Invalid account scope")
    }
    guard corridor.range(of: corridorPattern, options: .regularExpression) != nil else {
      throw MeridianError.validationError("Invalid corridor")
    }
    guard currency == "GBP" else {
      throw MeridianError.validationError("Currency must be GBP")
    }
  }
}

public func normalizeCatalogTtl(_ seconds: Int64) -> Int64 {
  if seconds < 0 { return 0 }
  return min(seconds, maxCatalogTtlSeconds)
}

public func buildPaymentMethodsURL(
  baseURL: String,
  accountScope: String,
  corridor: String,
  currency: String = "GBP"
) throws -> URL {
  try CatalogQuery.validate(accountScope: accountScope, corridor: corridor, currency: currency)
  var origin = baseURL
  while origin.hasSuffix("/") { origin.removeLast() }
  if origin.hasSuffix("/api/v1") {
    origin.removeLast("/api/v1".count)
  }
  guard var components = URLComponents(string: origin + "/api/v2/payment-methods") else {
    throw MeridianError.invalidURL
  }
  components.queryItems = [
    URLQueryItem(name: "accountScope", value: accountScope),
    URLQueryItem(name: "corridor", value: corridor),
    URLQueryItem(name: "currency", value: currency),
  ]
  guard let url = components.url else { throw MeridianError.invalidURL }
  return url
}

public func catalogStorageKey(accountScope: String, corridor: String, currency: String) throws -> String {
  try CatalogQuery.validate(accountScope: accountScope, corridor: corridor, currency: currency)
  return [accountScope, corridor, currency].joined(separator: "\u{001f}")
}

public func catalogSessionDirectoryName(sessionId: String) -> String {
  precondition(!sessionId.isEmpty)
  #if canImport(CryptoKit)
  let digest = SHA256.hash(data: Data(sessionId.utf8))
  return digest.map { String(format: "%02x", $0) }.joined()
  #else
  return sessionId
  #endif
}

/// Open payment-method descriptor. Unknown JSON attributes are ignored so an older
/// build keeps working. Checkout still pays only with Adyen card or Worldpay bank.
public struct PaymentMethodDescriptor: Equatable {
  public let id: String
  public let method: String
  public let provider: String
  public let displayName: String
  public let currency: String
  public let corridor: String
  public let requiresLiveEligibility: Bool
  public let capabilities: [String]
  public let ttlSeconds: Int64?
  public let ignoredAttributeNames: [String]

  public init(
    id: String,
    method: String,
    provider: String,
    displayName: String = "",
    currency: String = "GBP",
    corridor: String = "",
    requiresLiveEligibility: Bool = false,
    capabilities: [String] = [],
    ttlSeconds: Int64? = nil,
    ignoredAttributeNames: [String] = []
  ) {
    self.id = id
    self.method = method
    self.provider = provider
    self.displayName = displayName
    self.currency = currency
    self.corridor = corridor
    self.requiresLiveEligibility = requiresLiveEligibility
    self.capabilities = capabilities
    self.ttlSeconds = ttlSeconds
    self.ignoredAttributeNames = ignoredAttributeNames
  }

  public var requiresFreshEligibility: Bool {
    if requiresLiveEligibility { return true }
    return capabilities.contains { $0.caseInsensitiveCompare(liveEligibilityCapability) == .orderedSame }
  }

  public var isHardcodedBaseline: Bool {
    (provider == "adyen" && method == "card") || (provider == "worldpay" && method == "bank")
  }

  var cacheObject: [String: Any] {
    var object: [String: Any] = [
      "id": id,
      "method": method,
      "provider": provider,
      "displayName": displayName,
      "currency": currency,
      "corridor": corridor,
      "requiresLiveEligibility": requiresLiveEligibility,
      "capabilities": capabilities,
    ]
    if let ttlSeconds {
      object["ttlSeconds"] = NSNumber(value: ttlSeconds)
    }
    return object
  }
}

public struct PaymentMethodsCatalog: Equatable {
  public let accountScope: String
  public let corridor: String
  public let currency: String
  public let ttlSeconds: Int64
  public let methods: [PaymentMethodDescriptor]
  public let ignoredAttributeNames: [String]

  public init(
    accountScope: String,
    corridor: String,
    currency: String,
    ttlSeconds: Int64,
    methods: [PaymentMethodDescriptor],
    ignoredAttributeNames: [String] = []
  ) {
    self.accountScope = accountScope
    self.corridor = corridor
    self.currency = currency
    self.ttlSeconds = ttlSeconds
    self.methods = methods
    self.ignoredAttributeNames = ignoredAttributeNames
  }

  public func forRequest(accountScope: String, corridor: String, currency: String) throws -> PaymentMethodsCatalog {
    guard self.accountScope == accountScope, self.corridor == corridor else {
      throw MeridianError.validationError("Catalog scope does not match the request")
    }
    guard self.currency == "GBP", currency == "GBP" else {
      throw MeridianError.validationError("Currency must be GBP")
    }
    let kept = methods.compactMap { method -> PaymentMethodDescriptor? in
      let methodCurrency = method.currency.isEmpty ? "GBP" : method.currency
      let methodCorridor = method.corridor.isEmpty ? corridor : method.corridor
      guard methodCurrency == "GBP", methodCorridor == corridor else { return nil }
      return PaymentMethodDescriptor(
        id: method.id,
        method: method.method,
        provider: method.provider,
        displayName: method.displayName,
        currency: "GBP",
        corridor: methodCorridor,
        requiresLiveEligibility: method.requiresLiveEligibility,
        capabilities: method.capabilities,
        ttlSeconds: method.ttlSeconds,
        ignoredAttributeNames: method.ignoredAttributeNames
      )
    }
    return PaymentMethodsCatalog(
      accountScope: accountScope,
      corridor: corridor,
      currency: "GBP",
      ttlSeconds: normalizeCatalogTtl(ttlSeconds),
      methods: kept,
      ignoredAttributeNames: ignoredAttributeNames
    )
  }
}

public struct ResolvedPaymentCatalog: Equatable {
  public let accountScope: String
  public let corridor: String
  public let currency: String
  public let available: [PaymentMethodDescriptor]
  public let withheld: [PaymentMethodDescriptor]
  public let stale: Bool
  public let fromCache: Bool

  public var payableBaseline: [PaymentMethodDescriptor] {
    available.filter(\.isHardcodedBaseline)
  }

  public var failClosed: Bool { !withheld.isEmpty }
}

public enum CatalogExpiryPolicy {
  public static func resolve(
    catalog: PaymentMethodsCatalog,
    storedAtEpochMs: Int64,
    nowEpochMs: Int64,
    fromCache: Bool
  ) -> ResolvedPaymentCatalog {
    var available: [PaymentMethodDescriptor] = []
    var withheld: [PaymentMethodDescriptor] = []
    var anyStale = false
    let catalogTtl = normalizeCatalogTtl(catalog.ttlSeconds)
    for method in catalog.methods {
      let methodTtl = method.ttlSeconds.map(normalizeCatalogTtl)
      let ttl = methodTtl.map { min($0, catalogTtl) } ?? catalogTtl
      let stale = nowEpochMs >= storedAtEpochMs + ttl * 1000
      if stale { anyStale = true }
      if stale && method.requiresFreshEligibility {
        withheld.append(method)
      } else {
        available.append(method)
      }
    }
    return ResolvedPaymentCatalog(
      accountScope: catalog.accountScope,
      corridor: catalog.corridor,
      currency: catalog.currency,
      available: available,
      withheld: withheld,
      stale: anyStale,
      fromCache: fromCache
    )
  }
}

public func parsePaymentMethodsCatalog(data: Data) throws -> PaymentMethodsCatalog {
  let root: Any
  do {
    root = try JSONSerialization.jsonObject(with: data)
  } catch {
    throw MeridianError.decodingError("Failed to parse payment method catalog: \(error.localizedDescription)")
  }
  guard let object = root as? [String: Any] else {
    throw MeridianError.decodingError("Catalog must be a JSON object")
  }
  guard let accountScope = jsonString(object["accountScope"]), !accountScope.isEmpty else {
    throw MeridianError.decodingError("Catalog accountScope is required")
  }
  guard let corridor = jsonString(object["corridor"]), !corridor.isEmpty else {
    throw MeridianError.decodingError("Catalog corridor is required")
  }
  guard let currency = jsonString(object["currency"]), !currency.isEmpty else {
    throw MeridianError.decodingError("Catalog currency is required")
  }
  let ttlSeconds = jsonInt(object["ttlSeconds"]) ?? defaultCatalogTtlSeconds
  let methods: [PaymentMethodDescriptor]
  if let methodsValue = object["methods"] {
    if methodsValue is NSNull {
      methods = []
    } else if let array = methodsValue as? [Any] {
      methods = array.compactMap(parseDescriptor)
    } else {
      throw MeridianError.decodingError("methods must be an array")
    }
  } else {
    methods = []
  }
  let ignored = object.keys.filter { !catalogFields.contains($0) }.sorted()
  return PaymentMethodsCatalog(
    accountScope: accountScope,
    corridor: corridor,
    currency: currency,
    ttlSeconds: ttlSeconds,
    methods: methods,
    ignoredAttributeNames: ignored
  )
}

public func parsePaymentMethodsCatalog(json: String) throws -> PaymentMethodsCatalog {
  guard let data = json.data(using: .utf8) else {
    throw MeridianError.decodingError("Catalog must be UTF-8")
  }
  return try parsePaymentMethodsCatalog(data: data)
}

public protocol CatalogSealer {
  func seal(_ plaintext: Data) throws -> Data
  func open(_ sealed: Data) throws -> Data
}

public enum CatalogBlob {
  public static let magic = Data("MRC1".utf8)
  public static let nonceLength = 12
  public static let tagLength = 16

  public static func frame(nonce: Data, cipherTextAndTag: Data) throws -> Data {
    guard nonce.count == nonceLength else {
      throw MeridianError.validationError("Catalog nonce must be 96 bits")
    }
    var framed = magic
    framed.append(nonce)
    framed.append(cipherTextAndTag)
    return framed
  }

  public static func split(_ sealed: Data) throws -> (nonce: Data, body: Data) {
    let header = magic.count + nonceLength
    guard sealed.count >= header + tagLength else {
      throw MeridianError.decodingError("Catalog blob is truncated")
    }
    guard sealed.prefix(magic.count) == magic else {
      throw MeridianError.decodingError("Catalog blob magic mismatch")
    }
    let nonce = sealed.subdata(in: magic.count..<header)
    let body = sealed.subdata(in: header..<sealed.count)
    return (nonce, body)
  }
}

public protocol ProtectedBlobStore: AnyObject {
  func write(storageKey: String, blob: Data) throws
  func read(storageKey: String) -> Data?
  func delete(storageKey: String)
}

public final class MemoryProtectedBlobStore: ProtectedBlobStore {
  private let lock = NSLock()
  private var blobs: [String: Data] = [:]

  public init() {}

  public var keys: Set<String> {
    lock.lock()
    defer { lock.unlock() }
    return Set(blobs.keys)
  }

  public func write(storageKey: String, blob: Data) {
    lock.lock()
    blobs[storageKey] = blob
    lock.unlock()
  }

  public func read(storageKey: String) -> Data? {
    lock.lock()
    defer { lock.unlock() }
    return blobs[storageKey]
  }

  public func delete(storageKey: String) {
    lock.lock()
    blobs.removeValue(forKey: storageKey)
    lock.unlock()
  }
}

public final class CatalogCache {
  private let store: ProtectedBlobStore
  private let sealer: CatalogSealer
  private let lock = NSLock()

  public init(store: ProtectedBlobStore, sealer: CatalogSealer) {
    self.store = store
    self.sealer = sealer
  }

  public func storageKey(accountScope: String, corridor: String, currency: String) throws -> String {
    try catalogStorageKey(accountScope: accountScope, corridor: corridor, currency: currency)
  }

  public func write(catalog: PaymentMethodsCatalog, storedAtEpochMs: Int64) throws {
    let methods = catalog.methods.map { method -> [String: Any] in
      var object = method.cacheObject
      object.removeValue(forKey: "ignoredAttributeNames")
      return object
    }
    let envelope: [String: Any] = [
      "schema": 1,
      "accountScope": catalog.accountScope,
      "corridor": catalog.corridor,
      "currency": catalog.currency,
      "storedAtEpochMs": NSNumber(value: storedAtEpochMs),
      "ttlSeconds": NSNumber(value: normalizeCatalogTtl(catalog.ttlSeconds)),
      "methods": methods,
    ]
    let plaintext = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    let sealed = try sealer.seal(plaintext)
    let key = try storageKey(accountScope: catalog.accountScope, corridor: catalog.corridor, currency: catalog.currency)
    lock.lock()
    defer { lock.unlock() }
    try store.write(storageKey: key, blob: sealed)
  }

  public func read(
    accountScope: String,
    corridor: String,
    currency: String,
    nowEpochMs: Int64
  ) -> ResolvedPaymentCatalog? {
    let key: String
    do {
      key = try storageKey(accountScope: accountScope, corridor: corridor, currency: currency)
    } catch {
      return nil
    }
    lock.lock()
    defer { lock.unlock() }
    guard let blob = store.read(storageKey: key) else { return nil }
    let plaintext: Data
    do {
      plaintext = try sealer.open(blob)
    } catch {
      store.delete(storageKey: key)
      return nil
    }
    guard let envelope = parseCachedEnvelope(plaintext),
          envelope.accountScope == accountScope,
          envelope.corridor == corridor,
          envelope.currency == currency,
          envelope.currency == "GBP"
    else {
      store.delete(storageKey: key)
      return nil
    }
    let catalog = PaymentMethodsCatalog(
      accountScope: envelope.accountScope,
      corridor: envelope.corridor,
      currency: envelope.currency,
      ttlSeconds: envelope.ttlSeconds,
      methods: envelope.methods
    )
    return CatalogExpiryPolicy.resolve(
      catalog: catalog,
      storedAtEpochMs: envelope.storedAtEpochMs,
      nowEpochMs: nowEpochMs,
      fromCache: true
    )
  }
}

public struct PaymentMethodCatalogService {
  public let client: MeridianClient
  public let cache: CatalogCache
  public var clock: () -> Int64

  public init(
    client: MeridianClient,
    cache: CatalogCache,
    clock: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }
  ) {
    self.client = client
    self.cache = cache
    self.clock = clock
  }

  public func load(
    accountScope: String,
    corridor: String,
    currency: String = "GBP"
  ) async throws -> ResolvedPaymentCatalog {
    try CatalogQuery.validate(accountScope: accountScope, corridor: corridor, currency: currency)
    let cached = cache.read(accountScope: accountScope, corridor: corridor, currency: currency, nowEpochMs: clock())
    if let cached, !cached.stale { return cached }
    do {
      let fresh = try await client.fetchPaymentMethods(accountScope: accountScope, corridor: corridor, currency: currency)
      let storedAt = clock()
      try cache.write(catalog: fresh, storedAtEpochMs: storedAt)
      return CatalogExpiryPolicy.resolve(catalog: fresh, storedAtEpochMs: storedAt, nowEpochMs: storedAt, fromCache: false)
    } catch {
      if let cached { return cached }
      throw error
    }
  }
}

#if canImport(CryptoKit)
public struct AesGcmCatalogSealer: CatalogSealer {
  private let key: SymmetricKey

  public init(key: Data) throws {
    guard key.count == 32 else {
      throw MeridianError.validationError("Catalog key must be 256 bits")
    }
    self.key = SymmetricKey(data: key)
  }

  public func seal(_ plaintext: Data) throws -> Data {
    let nonce = AES.GCM.Nonce()
    let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
    let nonceData = nonce.withUnsafeBytes { Data($0) }
    return try CatalogBlob.frame(nonce: nonceData, cipherTextAndTag: sealed.ciphertext + sealed.tag)
  }

  public func open(_ sealedBlob: Data) throws -> Data {
    let parts = try CatalogBlob.split(sealedBlob)
    guard parts.body.count >= CatalogBlob.tagLength else {
      throw MeridianError.decodingError("Catalog blob is truncated")
    }
    let cipherText = parts.body.prefix(parts.body.count - CatalogBlob.tagLength)
    let tag = parts.body.suffix(CatalogBlob.tagLength)
    do {
      let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: parts.nonce), ciphertext: cipherText, tag: tag)
      return try AES.GCM.open(box, using: key)
    } catch let error as MeridianError {
      throw error
    } catch {
      throw MeridianError.decodingError("Catalog blob failed authentication")
    }
  }
}

public final class FileProtectedBlobStore: ProtectedBlobStore {
  private let directory: URL

  public init(directory: URL) throws {
    self.directory = directory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  }

  public func write(storageKey: String, blob: Data) throws {
    let target = fileURL(storageKey)
    let temporary = target.appendingPathExtension("tmp")
    try blob.write(to: temporary, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
    if FileManager.default.fileExists(atPath: target.path) {
      _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
    } else {
      try FileManager.default.moveItem(at: temporary, to: target)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
  }

  public func read(storageKey: String) -> Data? {
    try? Data(contentsOf: fileURL(storageKey))
  }

  public func delete(storageKey: String) {
    try? FileManager.default.removeItem(at: fileURL(storageKey))
  }

  private func fileURL(_ storageKey: String) -> URL {
    let digest = SHA256.hash(data: Data(storageKey.utf8))
    let name = digest.map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(name).appendingPathExtension("bin")
  }
}
#endif

#if canImport(CryptoKit) && canImport(Security)
public enum KeychainCatalogKeyStore {
  public static func loadOrCreateKey(
    service: String = "com.atlassian.meridian.catalog",
    account: String = "cache-aes-key"
  ) throws -> Data {
    if let existing = try read(service: service, account: account) {
      return existing
    }
    var key = Data(count: 32)
    let result = key.withUnsafeMutableBytes { buffer -> Int32 in
      guard let address = buffer.baseAddress else { return errSecAllocate }
      return SecRandomCopyBytes(kSecRandomDefault, 32, address)
    }
    guard result == errSecSuccess else {
      throw MeridianError.validationError("Catalog key generation failed")
    }
    let add: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecValueData as String: key,
    ]
    let added = SecItemAdd(add as CFDictionary, nil)
    if added == errSecDuplicateItem, let existing = try read(service: service, account: account) {
      return existing
    }
    guard added == errSecSuccess else {
      throw MeridianError.validationError("Catalog key could not be stored")
    }
    return key
  }

  private static func read(service: String, account: String) throws -> Data? {
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
    guard status == errSecSuccess, let data = item as? Data, data.count == 32 else {
      throw MeridianError.validationError("Catalog key could not be read")
    }
    return data
  }
}

public enum PlatformCatalogCache {
  public static func open(sessionId: String) throws -> CatalogCache {
    let key = try KeychainCatalogKeyStore.loadOrCreateKey()
    let sealer = try AesGcmCatalogSealer(key: key)
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = base
      .appendingPathComponent("meridian-catalog", isDirectory: true)
      .appendingPathComponent(catalogSessionDirectoryName(sessionId: sessionId), isDirectory: true)
    return CatalogCache(store: try FileProtectedBlobStore(directory: directory), sealer: sealer)
  }
}
#endif

private struct CachedEnvelopeFields {
  let accountScope: String
  let corridor: String
  let currency: String
  let storedAtEpochMs: Int64
  let ttlSeconds: Int64
  let methods: [PaymentMethodDescriptor]
}

private func parseCachedEnvelope(_ plaintext: Data) -> CachedEnvelopeFields? {
  guard let root = try? JSONSerialization.jsonObject(with: plaintext),
        let object = root as? [String: Any]
  else { return nil }
  if let schemaValue = object["schema"] {
    guard let schema = jsonInt(schemaValue), schema == 1 else { return nil }
  }
  guard let accountScope = jsonString(object["accountScope"]),
        let corridor = jsonString(object["corridor"]),
        let currency = jsonString(object["currency"]),
        let storedAt = jsonInt(object["storedAtEpochMs"]),
        let ttlSeconds = jsonInt(object["ttlSeconds"])
  else { return nil }
  let methods: [PaymentMethodDescriptor]
  if let methodsValue = object["methods"] {
    if methodsValue is NSNull {
      methods = []
    } else if let array = methodsValue as? [Any] {
      methods = array.compactMap(parseDescriptor)
    } else {
      return nil
    }
  } else {
    methods = []
  }
  return CachedEnvelopeFields(
    accountScope: accountScope,
    corridor: corridor,
    currency: currency,
    storedAtEpochMs: storedAt,
    ttlSeconds: ttlSeconds,
    methods: methods
  )
}

private func parseDescriptor(_ value: Any) -> PaymentMethodDescriptor? {
  guard let object = value as? [String: Any] else { return nil }
  guard let id = jsonString(object["id"]), !id.isEmpty,
        let method = jsonString(object["method"]), !method.isEmpty,
        let provider = jsonString(object["provider"]), !provider.isEmpty
  else { return nil }
  let ignored = object.keys.filter { !descriptorFields.contains($0) }.sorted()
  return PaymentMethodDescriptor(
    id: id,
    method: method,
    provider: provider,
    displayName: jsonString(object["displayName"]) ?? "",
    currency: jsonString(object["currency"]) ?? "",
    corridor: jsonString(object["corridor"]) ?? "",
    requiresLiveEligibility: jsonBool(object["requiresLiveEligibility"]) ?? false,
    capabilities: jsonStringList(object["capabilities"]),
    ttlSeconds: jsonInt(object["ttlSeconds"]),
    ignoredAttributeNames: ignored
  )
}

private func jsonString(_ value: Any?) -> String? {
  guard let value, !(value is NSNull) else { return nil }
  return value as? String
}

private func jsonBool(_ value: Any?) -> Bool? {
  guard let number = value as? NSNumber else { return nil }
  guard CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
  return number.boolValue
}

private func jsonInt(_ value: Any?) -> Int64? {
  guard let number = value as? NSNumber else { return nil }
  guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
  let text = number.stringValue
  if text.contains(".") || text.contains("e") || text.contains("E") { return nil }
  return Int64(text)
}

private func jsonStringList(_ value: Any?) -> [String] {
  guard let array = value as? [Any] else { return [] }
  return array.compactMap { $0 as? String }
}
