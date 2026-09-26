import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Gates the config-driven provider list. The default keeps today's hardcoded picker.
public struct MeridianFeatures: Equatable, Sendable {
  /// When false, provider options stay Adyen card and Worldpay bank with no catalog fetch.
  public var configDrivenProviders: Bool

  public init(configDrivenProviders: Bool = false) {
    self.configDrivenProviders = configDrivenProviders
  }
}

/// Maps the agreed `GET /catalog` payload into payment method options.
///
/// The live contract is `{demoDate, recipients, providers: [{id, name, description, methods}]}`
/// with provider ids `adyen` and `worldpay`. An unconfirmed extension on that payload is ignored.
public enum ProviderConfiguration {
  public static let baseline: [PaymentMethodOption] = [
    PaymentMethodOption(id: "adyen_card", displayLabel: "Debit card", providerName: "Adyen", method: .card),
    PaymentMethodOption(id: "worldpay_bank", displayLabel: "Bank payment", providerName: "Worldpay", method: .bank),
  ]

  /// Returns both live options, or nil when the catalog does not contain that pair.
  /// Unknown provider/method pairs are skipped. A third provider is not synthesized.
  public static func options(from catalog: CatalogResponse) -> [PaymentMethodOption]? {
    var parsed: [PaymentMethodOption] = []
    var seen = Set<String>()
    for provider in catalog.providers {
      for method in provider.methods {
        guard let option = option(provider: provider, method: method) else { continue }
        if seen.insert(option.id).inserted {
          parsed.append(option)
        }
      }
    }
    let ids = Set(parsed.map(\.id))
    guard ids.contains("adyen_card"), ids.contains("worldpay_bank") else { return nil }
    return parsed
  }

  private static func option(provider: Provider, method: PaymentMethod) -> PaymentMethodOption? {
    switch (provider.id, method) {
    case (.adyen, .card):
      return PaymentMethodOption(
        id: "adyen_card",
        displayLabel: "Debit card",
        providerName: displayName(provider.name, fallback: "Adyen"),
        method: .card
      )
    case (.worldpay, .bank):
      return PaymentMethodOption(
        id: "worldpay_bank",
        displayLabel: "Bank payment",
        providerName: displayName(provider.name, fallback: "Worldpay"),
        method: .bank
      )
    default:
      return nil
    }
  }

  private static func displayName(_ name: String, fallback: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
  }
}

public struct ProviderConfigMetricEvent: Equatable, Sendable {
  public enum Kind: String, Sendable {
    case fetchSuccess = "provider_config.fetch.success"
    case fetchFailure = "provider_config.fetch.failure"
    case fallbackToCache = "provider_config.fallback.cache"
    case fallbackToBaseline = "provider_config.fallback.baseline"
  }

  public let kind: Kind
  /// Correlation id from the catalog response when meridian-api sends one.
  public let correlationId: String?
  /// `X-Rehearsal-Session` value that scopes the request in meridian-api.
  public let sessionId: String
  /// Failure detail, including the error `code` from the API body when present.
  public let reason: String?
}

public struct ProviderConfigMetrics: Equatable, Sendable {
  public var fetchSuccess: Int
  public var fetchFailure: Int
  public var fallbackToCache: Int
  public var fallbackToBaseline: Int
  public var events: [ProviderConfigMetricEvent]
}

/// Client-side transaction event recorded when a payment is submitted.
public struct PaymentTransactionLog: Equatable, Sendable {
  public let action: String
  public let idempotencyKey: String
  public let methodId: String
  public let providerName: String
  public let method: PaymentMethod
  public let transactionId: String?
  public let paymentId: String?
  public let reference: String?
  public let sessionId: String
}

protocol MeridianHTTPTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionTransport: MeridianHTTPTransport, @unchecked Sendable {
  let session: URLSession

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await session.data(for: request)
  }
}
