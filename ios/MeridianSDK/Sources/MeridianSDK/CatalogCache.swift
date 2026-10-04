import Crypto
import Foundation
#if canImport(Security)
import Security
#endif

public protocol CatalogCache: AnyObject {
  func load(sessionId: String) -> CatalogResponse?
  func save(sessionId: String, catalog: CatalogResponse)
  func ciphertext(sessionId: String) -> Data?
}

public final class MemoryEncryptedCatalogCache: CatalogCache, @unchecked Sendable {
  private let lock = NSLock()
  private var blobs: [String: Data] = [:]
  private let key: SymmetricKey

  public init() {
    key = SymmetricKey(size: .bits256)
  }

  public func load(sessionId: String) -> CatalogResponse? {
    lock.lock()
    let blob = blobs[sessionId]
    lock.unlock()
    guard let blob else { return nil }
    return CatalogCipher.open(blob, sessionId: sessionId, key: key)
  }

  public func save(sessionId: String, catalog: CatalogResponse) {
    guard let blob = CatalogCipher.seal(catalog, sessionId: sessionId, key: key) else { return }
    lock.lock()
    blobs[sessionId] = blob
    lock.unlock()
  }

  public func ciphertext(sessionId: String) -> Data? {
    lock.lock()
    defer { lock.unlock() }
    return blobs[sessionId]
  }
}

public final class FileEncryptedCatalogCache: CatalogCache, @unchecked Sendable {
  private let directory: URL
  private let key: SymmetricKey
  private let lock = NSLock()

  public init(directory: URL, useKeychain: Bool = true) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    self.directory = directory
    #if canImport(Security)
    if useKeychain, let keychainKey = CatalogKeychain.loadOrCreate() {
      key = keychainKey
    } else {
      key = try FileCatalogKey.loadOrCreate(in: directory)
    }
    #else
    _ = useKeychain
    key = try FileCatalogKey.loadOrCreate(in: directory)
    #endif
  }

  public func load(sessionId: String) -> CatalogResponse? {
    guard let blob = read(sessionId) else { return nil }
    return CatalogCipher.open(blob, sessionId: sessionId, key: key)
  }

  public func save(sessionId: String, catalog: CatalogResponse) {
    guard let blob = CatalogCipher.seal(catalog, sessionId: sessionId, key: key) else { return }
    write(blob, sessionId: sessionId)
  }

  public func ciphertext(sessionId: String) -> Data? {
    read(sessionId)
  }

  private func fileURL(_ sessionId: String) -> URL {
    directory.appendingPathComponent(CatalogCipher.filename(sessionId))
  }

  private func read(_ sessionId: String) -> Data? {
    lock.lock()
    defer { lock.unlock() }
    return try? Data(contentsOf: fileURL(sessionId))
  }

  private func write(_ data: Data, sessionId: String) {
    lock.lock()
    defer { lock.unlock() }
    let url = fileURL(sessionId)
    do {
      try data.write(to: url, options: [.atomic])
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    } catch {
      // A cache write failure leaves the previous good catalog in place.
    }
  }
}

public enum MeridianDeviceCache {
  public static let catalog: CatalogCache = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let directory = base.appendingPathComponent("MeridianCatalog", isDirectory: true)
    if let cache = try? FileEncryptedCatalogCache(directory: directory) {
      return cache
    }
    return MemoryEncryptedCatalogCache()
  }()
}

enum CatalogCipher {
  private static let magic = Data("MCAT".utf8)

  static func filename(_ sessionId: String) -> String {
    let digest = SHA256.hash(data: Data(sessionId.utf8))
    return digest.map { String(format: "%02x", $0) }.joined() + ".bin"
  }

  static func seal(_ catalog: CatalogResponse, sessionId: String, key: SymmetricKey) -> Data? {
    guard let plain = try? JSONEncoder().encode(CatalogEnvelope(sessionId: sessionId, catalog: catalog)) else {
      return nil
    }
    guard let sealed = try? AES.GCM.seal(plain, using: key, authenticating: Data(sessionId.utf8)),
          let combined = sealed.combined else {
      return nil
    }
    var blob = magic
    blob.append(1)
    blob.append(combined)
    return blob
  }

  static func open(_ blob: Data, sessionId: String, key: SymmetricKey) -> CatalogResponse? {
    guard blob.count > 5, blob.prefix(4) == magic, blob[blob.index(blob.startIndex, offsetBy: 4)] == 1 else {
      return nil
    }
    let combined = blob.dropFirst(5)
    guard let box = try? AES.GCM.SealedBox(combined: combined),
          let plain = try? AES.GCM.open(box, using: key, authenticating: Data(sessionId.utf8)),
          let envelope = try? JSONDecoder().decode(CatalogEnvelope.self, from: plain),
          envelope.sessionId == sessionId else {
      return nil
    }
    return envelope.catalog
  }
}

private struct CatalogEnvelope: Codable {
  let sessionId: String
  let catalog: CatalogResponse
}

enum FileCatalogKey {
  static func loadOrCreate(in directory: URL) throws -> SymmetricKey {
    let url = directory.appendingPathComponent("catalog.key")
    if let data = try? Data(contentsOf: url), data.count == 32 {
      return SymmetricKey(data: data)
    }
    let key = SymmetricKey(size: .bits256)
    let data = key.withUnsafeBytes { Data($0) }
    try data.write(to: url, options: [.atomic])
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return key
  }
}

#if canImport(Security)
enum CatalogKeychain {
  private static let service = "com.beaconstone.meridian.catalog"
  private static let account = "catalog-key"

  static func loadOrCreate() -> SymmetricKey? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data, data.count == 32 {
      return SymmetricKey(data: data)
    }
    let key = SymmetricKey(size: .bits256)
    let data = key.withUnsafeBytes { Data($0) }
    let add: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return nil }
    return key
  }
}
#endif
