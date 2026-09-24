import Foundation

/// One selectable payment method resolved from `GET /catalog`.
///
/// The id is the client-side method id (`adyen_card`, `worldpay_bank`).
/// `POST /payments` still receives `wireMethod` (`card` or `bank`), which is the
/// meridian-api contract. Only the Adyen card and Worldpay bank baseline is recognized.
public struct PaymentMethodOption: Hashable, Identifiable {
  public let id: String
  public let displayLabel: String
  public let providerName: String
  public let wireMethod: PaymentMethod

  public init(id: String, displayLabel: String, providerName: String, wireMethod: PaymentMethod) {
    self.id = id
    self.displayLabel = displayLabel
    self.providerName = providerName
    self.wireMethod = wireMethod
  }
}

/// Runtime switch for the config-driven method picker.
/// Off (the default) keeps the hardcoded Adyen card / Worldpay bank picker.
public struct MeridianFeatureFlags: Equatable, Sendable {
  public var configDrivenProviderCatalog: Bool

  public init(configDrivenProviderCatalog: Bool = false) {
    self.configDrivenProviderCatalog = configDrivenProviderCatalog
  }

  /// `MERIDIAN_CONFIG_DRIVEN_CATALOG=1` or `true` enables the catalog picker.
  public static func fromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> MeridianFeatureFlags {
    let raw = environment["MERIDIAN_CONFIG_DRIVEN_CATALOG"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let enabled = raw == "1" || raw == "true"
    return MeridianFeatureFlags(configDrivenProviderCatalog: enabled)
  }
}

public enum MethodPickerSource: Equatable {
  case hardcodedBaseline
  case catalog([PaymentMethodOption])

  /// Flag off always selects the hardcoded picker, even if catalog options exist.
  public static func resolve(
    flags: MeridianFeatureFlags,
    configuration: [PaymentMethodOption]
  ) -> MethodPickerSource {
    guard flags.configDrivenProviderCatalog else { return .hardcodedBaseline }
    let options = configuration.isEmpty ? PaymentMethodCatalog.safeDefault : configuration
    return .catalog(options)
  }
}

public enum ProviderConfigurationSource: Equatable, Sendable {
  /// A successful fetch, or a cached configuration still inside its time-to-live.
  case current
  /// The fetch failed, timed out, or was malformed. Last-known-good options are in use.
  case lastKnownGood
  /// Nothing usable has been cached. Built-in Adyen card and Worldpay bank list.
  case safeDefault
}

public struct ProviderConfiguration {
  public let options: [PaymentMethodOption]
  public let catalog: CatalogResponse?
  public let source: ProviderConfigurationSource

  public init(
    options: [PaymentMethodOption],
    catalog: CatalogResponse?,
    source: ProviderConfigurationSource
  ) {
    self.options = options
    self.catalog = catalog
    self.source = source
  }
}

public enum PaymentMethodCatalog {
  public static let cardMethodId = "adyen_card"
  public static let bankMethodId = "worldpay_bank"

  /// Built-in pair used when no catalog has been cached yet.
  public static let safeDefault: [PaymentMethodOption] = [
    PaymentMethodOption(
      id: cardMethodId,
      displayLabel: "Debit card",
      providerName: "Adyen",
      wireMethod: .card
    ),
    PaymentMethodOption(
      id: bankMethodId,
      displayLabel: "Bank payment",
      providerName: "Worldpay",
      wireMethod: .bank
    )
  ]

  /// Maps a catalog provider list to method options.
  /// Returns nil when the payload has none of the baseline Adyen-card / Worldpay-bank pairs.
  public static func options(from catalog: CatalogResponse) -> [PaymentMethodOption]? {
    var resolved: [PaymentMethodOption] = []
    var seen = Set<String>()
    for provider in catalog.providers {
      let providerName = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !providerName.isEmpty else { continue }
      for method in provider.methods {
        guard let option = option(providerId: provider.id, providerName: providerName, method: method) else {
          continue
        }
        if seen.insert(option.id).inserted {
          resolved.append(option)
        }
      }
    }
    return resolved.isEmpty ? nil : resolved
  }

  /// Client method id to the `card` / `bank` value meridian-api accepts.
  /// Unknown ids return nil so the client does not substitute another provider.
  public static func wireMethod(forMethodId methodId: String) -> PaymentMethod? {
    switch methodId {
    case "card", cardMethodId:
      return .card
    case "bank", bankMethodId:
      return .bank
    default:
      return nil
    }
  }

  private static func option(
    providerId: ProviderId,
    providerName: String,
    method: PaymentMethod
  ) -> PaymentMethodOption? {
    switch (providerId, method) {
    case (.adyen, .card):
      return PaymentMethodOption(
        id: cardMethodId,
        displayLabel: "Debit card",
        providerName: providerName,
        wireMethod: .card
      )
    case (.worldpay, .bank):
      return PaymentMethodOption(
        id: bankMethodId,
        displayLabel: "Bank payment",
        providerName: providerName,
        wireMethod: .bank
      )
    default:
      return nil
    }
  }
}

public enum PaymentSubmission {
  public static let idempotencyHeader = "Idempotency-Key"

  /// The idempotency key is sent unchanged. It is not derived from the method id.
  public static func headers(idempotencyKey: String) -> [String: String] {
    [idempotencyHeader: idempotencyKey]
  }

  public static func request(
    recipientId: String,
    amountMinor: Int,
    methodId: String,
    note: String,
    scenario: Scenario
  ) throws -> PaymentRequest {
    guard let method = PaymentMethodCatalog.wireMethod(forMethodId: methodId) else {
      throw MeridianError.validationError("Unknown payment method")
    }
    return PaymentRequest(
      recipientId: recipientId,
      amountMinor: amountMinor,
      method: method,
      note: note,
      scenario: scenario
    )
  }
}

public enum CatalogMetricEvent: String, Sendable {
  case success
  case failure
  case fallbackToCache = "fallback_to_cache"
}

public struct CatalogFetchMetrics: Sendable, Equatable {
  public var successCount: Int
  public var failureCount: Int
  public var fallbackToCacheCount: Int

  public init(successCount: Int = 0, failureCount: Int = 0, fallbackToCacheCount: Int = 0) {
    self.successCount = successCount
    self.failureCount = failureCount
    self.fallbackToCacheCount = fallbackToCacheCount
  }
}

public protocol CatalogMetricLogging: Sendable {
  func log(
    event: CatalogMetricEvent,
    metrics: CatalogFetchMetrics,
    sessionId: String,
    detail: String
  )
}

public enum CatalogMetricLine {
  public static func format(
    event: CatalogMetricEvent,
    metrics: CatalogFetchMetrics,
    sessionId: String,
    detail: String
  ) -> String {
    let session = sanitize(sessionId)
    let cleanDetail = sanitize(detail)
    return "meridian.catalog event=\(event.rawValue) session=\(session) success=\(metrics.successCount) failure=\(metrics.failureCount) fallback_to_cache=\(metrics.fallbackToCacheCount) detail=\(cleanDetail)"
  }

  private static func sanitize(_ value: String) -> String {
    let singleLine = value
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
    if singleLine.count <= 200 { return singleLine }
    return String(singleLine.prefix(200))
  }
}

public final class StandardCatalogMetricLog: CatalogMetricLogging, @unchecked Sendable {
  public init() {}

  public func log(
    event: CatalogMetricEvent,
    metrics: CatalogFetchMetrics,
    sessionId: String,
    detail: String
  ) {
    let line = CatalogMetricLine.format(
      event: event,
      metrics: metrics,
      sessionId: sessionId,
      detail: detail
    )
    fputs(line + "\n", stderr)
    fflush(stderr)
  }
}

public enum CatalogFailureDetail {
  public static func describe(_ error: Error) -> String {
    if let urlError = error as? URLError, urlError.code == .timedOut {
      return "timeout"
    }
    if let meridian = error as? MeridianError {
      return meridian.errorDescription ?? "failure"
    }
    return String(describing: error)
  }
}

/// In-memory provider catalog. Entries expire after a short time-to-live.
/// A failed or malformed fetch keeps the last-known-good list.
public actor ProviderCatalogCache {
  public static let defaultTTL: TimeInterval = 30
  public static let fetchTimeout: TimeInterval = 5

  private let ttl: TimeInterval
  private let clock: @Sendable () -> Date
  private let logger: any CatalogMetricLogging
  private var cachedAt: Date?
  private var lastKnownGood: [PaymentMethodOption]?
  private var lastKnownGoodCatalog: CatalogResponse?
  private var metrics = CatalogFetchMetrics()

  public init(
    ttl: TimeInterval = ProviderCatalogCache.defaultTTL,
    clock: @escaping @Sendable () -> Date = { Date() },
    logger: any CatalogMetricLogging = StandardCatalogMetricLog()
  ) {
    self.ttl = ttl
    self.clock = clock
    self.logger = logger
  }

  public func currentMetrics() -> CatalogFetchMetrics { metrics }

  /// Returns the cached configuration while it is inside the time-to-live.
  public func freshConfiguration() -> ProviderConfiguration? {
    guard
      let cachedAt,
      let lastKnownGood,
      clock().timeIntervalSince(cachedAt) < ttl
    else { return nil }
    return ProviderConfiguration(
      options: lastKnownGood,
      catalog: lastKnownGoodCatalog,
      source: .current
    )
  }

  /// Records a catalog that was just fetched. A payload with no baseline methods is a failure.
  public func store(catalog: CatalogResponse, sessionId: String) -> ProviderConfiguration {
    guard let options = PaymentMethodCatalog.options(from: catalog) else {
      return fail(detail: "malformed_catalog", sessionId: sessionId)
    }
    lastKnownGood = options
    lastKnownGoodCatalog = catalog
    cachedAt = clock()
    metrics.successCount += 1
    logger.log(
      event: .success,
      metrics: metrics,
      sessionId: sessionId,
      detail: "methods=\(options.count)"
    )
    return ProviderConfiguration(options: options, catalog: catalog, source: .current)
  }

  /// Records a fetch failure, timeout, or malformed response and falls back when possible.
  public func fail(detail: String, sessionId: String) -> ProviderConfiguration {
    metrics.failureCount += 1
    logger.log(event: .failure, metrics: metrics, sessionId: sessionId, detail: detail)
    if let lastKnownGood {
      metrics.fallbackToCacheCount += 1
      logger.log(
        event: .fallbackToCache,
        metrics: metrics,
        sessionId: sessionId,
        detail: "last_known_good"
      )
      return ProviderConfiguration(
        options: lastKnownGood,
        catalog: lastKnownGoodCatalog,
        source: .lastKnownGood
      )
    }
    return ProviderConfiguration(
      options: PaymentMethodCatalog.safeDefault,
      catalog: nil,
      source: .safeDefault
    )
  }
}
