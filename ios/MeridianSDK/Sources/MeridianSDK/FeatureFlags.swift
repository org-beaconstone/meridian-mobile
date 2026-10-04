import Foundation

/// Remote flag that partitions dynamic catalog hydration and Euro display controls.
public enum FeatureFlags {
  public static let mobileEuPayments = "enable_mobile_eu_payments"

  public static func cacheKey(sessionId: String) -> String {
    "\(mobileEuPayments):\(sessionId)"
  }
}

public struct FeatureFlagEvaluation: Codable, Equatable, Sendable {
  public let key: String
  public let enabled: Bool
  public let variant: String
  public let source: String

  public init(key: String, enabled: Bool, variant: String, source: String) {
    self.key = key
    self.enabled = enabled
    self.variant = variant
    self.source = source
  }

  public static func legacy(source: String) -> FeatureFlagEvaluation {
    FeatureFlagEvaluation(
      key: FeatureFlags.mobileEuPayments,
      enabled: false,
      variant: "legacy",
      source: source
    )
  }
}

public struct PaymentTelemetryEvent: Codable, Equatable, Sendable {
  public let action: String
  public let flagKey: String
  public let variant: String
  public let currency: String
  public let idempotencyKey: String
  public let sessionId: String

  public init(
    action: String,
    flagKey: String,
    variant: String,
    currency: String,
    idempotencyKey: String,
    sessionId: String
  ) {
    self.action = action
    self.flagKey = flagKey
    self.variant = variant
    self.currency = currency
    self.idempotencyKey = idempotencyKey
    self.sessionId = sessionId
  }
}

public protocol FeatureFlagCache: Sendable {
  func read(key: String) -> FeatureFlagEvaluation?
  func write(key: String, evaluation: FeatureFlagEvaluation)
}

public final class InMemoryFeatureFlagCache: FeatureFlagCache, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: FeatureFlagEvaluation] = [:]

  public init() {}

  public func read(key: String) -> FeatureFlagEvaluation? {
    lock.lock()
    defer { lock.unlock() }
    return values[key]
  }

  public func write(key: String, evaluation: FeatureFlagEvaluation) {
    lock.lock()
    defer { lock.unlock() }
    values[key] = evaluation
  }
}

public final class UserDefaultsFeatureFlagCache: FeatureFlagCache, @unchecked Sendable {
  private let defaults: UserDefaults
  private let lock = NSLock()

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func read(key: String) -> FeatureFlagEvaluation? {
    lock.lock()
    defer { lock.unlock() }
    guard let data = defaults.data(forKey: storageKey(key)) else { return nil }
    return try? JSONDecoder().decode(FeatureFlagEvaluation.self, from: data)
  }

  public func write(key: String, evaluation: FeatureFlagEvaluation) {
    lock.lock()
    defer { lock.unlock() }
    guard let data = try? JSONEncoder().encode(evaluation) else { return }
    defaults.set(data, forKey: storageKey(key))
  }

  private func storageKey(_ key: String) -> String {
    "meridian.flag.\(key)"
  }
}

public enum FeatureFlagParser {
  /// Parse a remote flag document. A JSON object that omits the flag is the kill switch (legacy).
  /// Returns nil only when the payload is not a JSON object.
  public static func parse(_ data: Data) -> (enabled: Bool, variant: String)? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    if let value = lookup(root, key: FeatureFlags.mobileEuPayments) {
      return interpret(value)
    }
    return (false, "legacy")
  }

  static func interpret(_ value: Any) -> (enabled: Bool, variant: String) {
    if let enabled = value as? Bool {
      return enabled ? (true, "dynamic") : (false, "legacy")
    }
    if let number = value as? NSNumber, !(value is Bool) {
      // JSON true/false arrives as Bool. Numeric 0/1 is an explicit switch.
      return number.intValue == 0 ? (false, "legacy") : (true, "dynamic")
    }
    if let text = value as? String {
      return interpretText(text)
    }
    if let object = value as? [String: Any] {
      if (object["killSwitch"] as? Bool) == true || (object["kill_switch"] as? Bool) == true {
        return (false, "legacy")
      }
      let rawEnabled = object["enabled"] ?? object["value"] ?? object["on"]
      let enabled = rawEnabled.map(isEnabled) ?? false
      if !enabled {
        return (false, "legacy")
      }
      let variant = sanitize(object["variant"] as? String) ?? "dynamic"
      return (true, variant)
    }
    return (false, "legacy")
  }

  private static func lookup(_ root: [String: Any], key: String) -> Any? {
    if let direct = root[key] { return direct }
    if let flags = root["flags"] as? [String: Any], let value = flags[key] { return value }
    if let flags = root["featureFlags"] as? [String: Any], let value = flags[key] { return value }
    let collections = [root["flags"], root["featureFlags"]].compactMap { $0 as? [[String: Any]] }
    for rows in collections {
      if let match = rows.first(where: { ($0["key"] as? String) == key || ($0["name"] as? String) == key }) {
        return match
      }
    }
    return nil
  }

  private static func interpretText(_ text: String) -> (enabled: Bool, variant: String) {
    switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "on", "enabled", "dynamic", "treatment":
      return (true, "dynamic")
    default:
      return (false, "legacy")
    }
  }

  private static func isEnabled(_ value: Any) -> Bool {
    interpret(value).enabled
  }

  static func sanitize(_ variant: String?) -> String? {
    guard let variant else { return nil }
    let trimmed = variant.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 64 else { return nil }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
    guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
    return trimmed
  }
}

public enum PaymentTelemetry {
  public static func event(
    evaluation: FeatureFlagEvaluation,
    idempotencyKey: String,
    sessionId: String,
    displayCurrency: String
  ) -> PaymentTelemetryEvent {
    let enabled = evaluation.enabled && evaluation.key == FeatureFlags.mobileEuPayments
    let variant = enabled ? (FeatureFlagParser.sanitize(evaluation.variant) ?? "dynamic") : "legacy"
    let currency = enabled && displayCurrency == "EUR" ? "EUR" : "GBP"
    return PaymentTelemetryEvent(
      action: "payment.submit",
      flagKey: FeatureFlags.mobileEuPayments,
      variant: variant,
      currency: currency,
      idempotencyKey: idempotencyKey,
      sessionId: sessionId
    )
  }

  public static func headerValue(_ event: PaymentTelemetryEvent) -> String {
    "\(event.flagKey)=\(event.variant)"
  }
}
