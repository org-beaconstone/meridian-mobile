import CryptoKit
import Foundation

public let defaultCatalogTtl: TimeInterval = 15 * 60

public struct CachedCatalog: Codable, Sendable {
  public let catalog: CatalogResponse
  public let fetchedAtEpochMs: Int64

  public init(catalog: CatalogResponse, fetchedAtEpochMs: Int64) {
    self.catalog = catalog
    self.fetchedAtEpochMs = fetchedAtEpochMs
  }
}

public protocol CatalogStore: AnyObject {
  func read(cacheKey: String) -> CachedCatalog?
  func write(cacheKey: String, entry: CachedCatalog) throws
}

public final class MemoryCatalogStore: CatalogStore, @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [String: CachedCatalog] = [:]

  public init() {}

  public func read(cacheKey: String) -> CachedCatalog? {
    lock.lock()
    defer { lock.unlock() }
    return entries[cacheKey]
  }

  public func write(cacheKey: String, entry: CachedCatalog) throws {
    lock.lock()
    defer { lock.unlock() }
    entries[cacheKey] = entry
  }
}

/// AES-GCM file cache. The key stays beside the ciphertext in an app-private directory.
public final class EncryptedFileCatalogStore: CatalogStore, @unchecked Sendable {
  private let directory: URL
  private let key: SymmetricKey
  private let lock = NSLock()
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(directory: URL) throws {
    self.directory = directory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let keyURL = directory.appendingPathComponent("catalog.key")
    if FileManager.default.fileExists(atPath: keyURL.path) {
      let data = try Data(contentsOf: keyURL)
      guard data.count == 32 else {
        throw MeridianError.decodingError("Catalog key is unreadable")
      }
      key = SymmetricKey(data: data)
    } else {
      let newKey = SymmetricKey(size: .bits256)
      let data = newKey.withUnsafeBytes { Data($0) }
      try data.write(to: keyURL, options: .atomic)
      try? FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o600)],
        ofItemAtPath: keyURL.path
      )
      key = newKey
    }
  }

  public static func defaultDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return base.appendingPathComponent("MeridianCatalog", isDirectory: true)
  }

  public func read(cacheKey: String) -> CachedCatalog? {
    lock.lock()
    defer { lock.unlock() }
    let url = fileURL(for: cacheKey)
    guard let payload = try? Data(contentsOf: url) else { return nil }
    guard let sealed = try? AES.GCM.SealedBox(combined: payload),
          let plain = try? AES.GCM.open(sealed, using: key) else {
      return nil
    }
    return try? decoder.decode(CachedCatalog.self, from: plain)
  }

  public func write(cacheKey: String, entry: CachedCatalog) throws {
    lock.lock()
    defer { lock.unlock() }
    let plain = try encoder.encode(entry)
    let sealed = try AES.GCM.seal(plain, using: key)
    guard let combined = sealed.combined else {
      throw MeridianError.decodingError("Catalog cache could not be sealed")
    }
    try combined.write(to: fileURL(for: cacheKey), options: .atomic)
  }

  private func fileURL(for cacheKey: String) -> URL {
    let digest = SHA256.hash(data: Data(cacheKey.utf8))
    let name = digest.map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(name + ".catalog")
  }
}

/// Loads GET /catalog and keeps the last accepted Adyen/Worldpay snapshot.
final class CatalogClient {
  private let cacheKey: String
  private let store: any CatalogStore
  private let ttlMs: Int64
  private let now: @Sendable () -> Date
  private(set) var usingFallback = false

  init(
    cacheKey: String,
    store: any CatalogStore,
    ttl: TimeInterval,
    now: @escaping @Sendable () -> Date
  ) {
    precondition(ttl >= 0, "Catalog TTL must be zero or positive")
    self.cacheKey = cacheKey
    self.store = store
    self.ttlMs = Int64(ttl * 1000)
    self.now = now
  }

  /// Returns a saved catalog that is still inside the TTL, when one exists.
  func freshCachedCatalog() -> CatalogResponse? {
    guard let cached = store.read(cacheKey: cacheKey) else { return nil }
    let nowMs = Int64(now().timeIntervalSince1970 * 1000)
    guard nowMs - cached.fetchedAtEpochMs < ttlMs else { return nil }
    usingFallback = false
    return presentCatalog(cached.catalog)
  }

  /// Stores a recognized catalog. An unrecognized provider id keeps the previous snapshot.
  func accept(_ fresh: CatalogResponse) throws -> CatalogResponse {
    let cached = store.read(cacheKey: cacheKey)
    guard let accepted = acceptCatalog(fresh) else {
      usingFallback = true
      return presentCatalog(cached?.catalog ?? baselineCatalog())
    }
    let nowMs = Int64(now().timeIntervalSince1970 * 1000)
    try store.write(cacheKey: cacheKey, entry: CachedCatalog(catalog: accepted, fetchedAtEpochMs: nowMs))
    usingFallback = false
    return presentCatalog(accepted)
  }

  func fallback() -> CatalogResponse {
    usingFallback = true
    let cached = store.read(cacheKey: cacheKey)
    return presentCatalog(cached?.catalog ?? baselineCatalog())
  }
}

func acceptCatalog(_ catalog: CatalogResponse) -> CatalogResponse? {
  let known: Set<String> = [ProviderId.adyen.rawValue, ProviderId.worldpay.rawValue]
  guard catalog.providers.allSatisfy({ known.contains($0.id) }) else { return nil }
  return catalog
}

func presentCatalog(_ catalog: CatalogResponse) -> CatalogResponse {
  CatalogResponse(
    demoDate: catalog.demoDate,
    recipients: catalog.recipients,
    providers: catalog.providers.filter(\.available),
    corridors: catalog.corridors.filter(\.available)
  )
}

func shouldFallbackCatalog(_ error: MeridianError) -> Bool {
  switch error {
  case let .httpError(statusCode, _):
    return statusCode == 500 || statusCode == 502 || statusCode == 504
  case .networkError, .decodingError:
    return true
  default:
    return false
  }
}
