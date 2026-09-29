import CryptoKit
import Foundation

public enum CatalogOrigin: String {
  case network
  case cache
  case fallback
  case baseline
}

public struct CatalogLoad {
  public let catalog: CatalogResponse
  public let origin: CatalogOrigin

  public init(catalog: CatalogResponse, origin: CatalogOrigin) {
    self.catalog = catalog
    self.origin = origin
  }
}

public struct StoredCatalog: Codable {
  public let fetchedAtEpochMillis: Int64
  public let catalog: CatalogResponse

  public init(fetchedAtEpochMillis: Int64, catalog: CatalogResponse) {
    self.fetchedAtEpochMillis = fetchedAtEpochMillis
    self.catalog = catalog
  }
}

public protocol CatalogStoring: AnyObject {
  func load() -> StoredCatalog?
  func save(_ stored: StoredCatalog)
}

public final class InMemoryCatalogStore: CatalogStoring {
  private let lock = NSLock()
  private var stored: StoredCatalog?

  public init() {}

  public func load() -> StoredCatalog? {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  public func save(_ stored: StoredCatalog) {
    lock.lock()
    defer { lock.unlock() }
    self.stored = stored
  }
}

/// AES-GCM catalog blob plus a local 256-bit key file. The key stays in the app
/// directory and is never embedded in source.
public final class EncryptedFileCatalogStore: CatalogStoring {
  private let directory: URL
  private let lock = NSLock()
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(directory: URL) {
    self.directory = directory
  }

  public func load() -> StoredCatalog? {
    lock.lock()
    defer { lock.unlock() }
    let dataURL = directory.appendingPathComponent("catalog.bin")
    guard
      let blob = try? Data(contentsOf: dataURL),
      let key = try? readKey(),
      let plain = try? Self.decrypt(blob, key: key)
    else {
      return nil
    }
    return try? decoder.decode(StoredCatalog.self, from: plain)
  }

  public func save(_ stored: StoredCatalog) {
    lock.lock()
    defer { lock.unlock() }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let key = try readOrCreateKey()
      let plain = try encoder.encode(stored)
      let blob = try Self.encrypt(plain, key: key)
      let dataURL = directory.appendingPathComponent("catalog.bin")
      try blob.write(to: dataURL, options: [.atomic])
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dataURL.path)
    } catch {
      // A cache write failure must not take down the payment flow.
    }
  }

  private func readKey() throws -> SymmetricKey {
    let url = directory.appendingPathComponent("catalog.key")
    let data = try Data(contentsOf: url)
    guard data.count == 32 else {
      throw MeridianError.validationError("Invalid catalog key")
    }
    return SymmetricKey(data: data)
  }

  private func readOrCreateKey() throws -> SymmetricKey {
    let url = directory.appendingPathComponent("catalog.key")
    if FileManager.default.fileExists(atPath: url.path) {
      return try readKey()
    }
    let key = SymmetricKey(size: .bits256)
    let raw = key.withUnsafeBytes { Data($0) }
    try raw.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return key
  }

  private static func encrypt(_ plain: Data, key: SymmetricKey) throws -> Data {
    let sealed = try AES.GCM.seal(plain, using: key)
    guard let combined = sealed.combined else {
      throw MeridianError.validationError("Catalog encryption failed")
    }
    return combined
  }

  private static func decrypt(_ blob: Data, key: SymmetricKey) throws -> Data {
    let box = try AES.GCM.SealedBox(combined: blob)
    return try AES.GCM.open(box, using: key)
  }
}

enum CatalogFallback {
  static func load(_ cached: StoredCatalog?) -> CatalogLoad {
    if let cached {
      return CatalogLoad(catalog: cached.catalog, origin: .fallback)
    }
    return CatalogLoad(catalog: ProviderBaseline.fallbackCatalog(), origin: .baseline)
  }

  static func isGateway(_ statusCode: Int) -> Bool {
    statusCode == 500 || statusCode == 502 || statusCode == 503 || statusCode == 504
  }
}
