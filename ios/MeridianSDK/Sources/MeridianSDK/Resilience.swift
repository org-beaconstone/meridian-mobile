import Foundation

/// Bounded retry for transient gateway failures on a payment that already has an idempotency key.
/// HTTP 502 and 504 are retried. Business outcomes (including simulated 503) are not.
/// The client never selects a different provider while retrying.
public struct RetryPolicy: Sendable {
  public let maxAttempts: Int
  public let initialDelayMillis: Int
  public let maxDelayMillis: Int
  public let jitter: @Sendable (Int) -> Int

  public init(
    maxAttempts: Int = 3,
    initialDelayMillis: Int = 200,
    maxDelayMillis: Int = 1_600,
    jitter: @escaping @Sendable (Int) -> Int = { base in
      guard base > 0 else { return 0 }
      return Int.random(in: 0...max(base / 5, 0))
    }
  ) {
    self.maxAttempts = max(1, maxAttempts)
    self.initialDelayMillis = initialDelayMillis
    self.maxDelayMillis = maxDelayMillis
    self.jitter = jitter
  }

  public func retriesHTTPStatus(_ statusCode: Int) -> Bool {
    statusCode == 502 || statusCode == 504
  }

  /// Delay before starting `attempt` (2 is the second try).
  public func delayMillis(beforeAttempt attempt: Int) -> Int {
    let exponent = min(8, max(0, attempt - 2))
    var scaled = initialDelayMillis
    if exponent > 0 {
      for _ in 0..<exponent {
        if scaled > maxDelayMillis { return maxDelayMillis + jitter(maxDelayMillis) }
        scaled *= 2
      }
    }
    let capped = min(scaled, maxDelayMillis)
    return capped + jitter(capped)
  }
}

public struct RailHealth: Decodable, Hashable, Sendable {
  public let method: String
  public let provider: String
  public let status: String

  public init(method: String, provider: String, status: String) {
    self.method = method
    self.provider = provider
    self.status = status
  }
}

public struct CorridorHealth: Decodable, Hashable, Sendable {
  public let id: String
  public let status: String
  public let currency: String?
  public let rails: [RailHealth]

  public init(id: String, status: String, currency: String? = nil, rails: [RailHealth] = []) {
    self.id = id
    self.status = status
    self.currency = currency
    self.rails = rails
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    status = try container.decodeIfPresent(String.self, forKey: .status) ?? "healthy"
    currency = try container.decodeIfPresent(String.self, forKey: .currency)
    rails = try container.decodeIfPresent([RailHealth].self, forKey: .rails) ?? []
  }

  private enum CodingKeys: String, CodingKey {
    case id, status, currency, rails
  }
}

public struct SessionHealth: Decodable, Hashable, Sendable {
  public let status: String
  public let simulation: Bool?
  public let corridors: [CorridorHealth]

  public init(status: String, simulation: Bool? = nil, corridors: [CorridorHealth] = []) {
    self.status = status
    self.simulation = simulation
    self.corridors = corridors
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    status = try container.decodeIfPresent(String.self, forKey: .status) ?? "UP"
    simulation = try container.decodeIfPresent(Bool.self, forKey: .simulation)
    corridors = try container.decodeIfPresent([CorridorHealth].self, forKey: .corridors) ?? []
  }

  private enum CodingKeys: String, CodingKey {
    case status, simulation, corridors
  }
}

public struct SessionHealthSnapshot: Hashable, Sendable {
  public let health: SessionHealth?
  public let reachable: Bool
  public let detail: String?

  public init(health: SessionHealth?, reachable: Bool, detail: String?) {
    self.health = health
    self.reachable = reachable
    self.detail = detail
  }

  public static let unknown = SessionHealthSnapshot(health: nil, reachable: false, detail: nil)
}

public struct RailPrompt: Hashable, Sendable {
  public let corridorId: String
  public let selectedMethod: PaymentMethod
  public let alternateMethod: PaymentMethod
  public let reason: String

  public init(corridorId: String, selectedMethod: PaymentMethod, alternateMethod: PaymentMethod, reason: String) {
    self.corridorId = corridorId
    self.selectedMethod = selectedMethod
    self.alternateMethod = alternateMethod
    self.reason = reason
  }
}

public enum CorridorNotice: Hashable, Sendable {
  case switchRail(RailPrompt)
  case unavailable(corridorId: String, message: String)
}

public func baselineProvider(for method: PaymentMethod) -> ProviderId {
  switch method {
  case .card: return .adyen
  case .bank: return .worldpay
  }
}

public func railLabel(_ method: PaymentMethod) -> String {
  switch method {
  case .card: return "Debit card · Adyen"
  case .bank: return "Bank payment · Worldpay"
  }
}

/// GBP rehearsal only. A rail is eligible when it is the hardcoded Adyen card or Worldpay bank
/// pairing and the corridor reports it healthy. Any other provider id is ignored.
public func corridorNotice(for health: SessionHealth, selected: PaymentMethod) -> CorridorNotice? {
  guard let corridor = gbpCorridor(health) else { return nil }
  let baseline = corridor.rails.filter(isBaselineRail)
  let selectedRail = baseline.first { $0.method.lowercased() == selected.rawValue }
  let selectedStatus: String
  if let selectedRail {
    selectedStatus = normalizeStatus(selectedRail.status)
  } else if normalizeStatus(corridor.status) == "outage" {
    selectedStatus = "outage"
  } else {
    selectedStatus = "healthy"
  }
  guard selectedStatus == "degraded" || selectedStatus == "outage" else { return nil }

  if let alternate = baseline.first(where: {
    $0.method.lowercased() != selected.rawValue && normalizeStatus($0.status) == "healthy"
  }), let method = PaymentMethod(rawValue: alternate.method.lowercased()) {
    return .switchRail(
      RailPrompt(
        corridorId: corridor.id.isEmpty ? "GB" : corridor.id,
        selectedMethod: selected,
        alternateMethod: method,
        reason: selectedStatus
      )
    )
  }
  let corridorId = corridor.id.isEmpty ? "GB" : corridor.id
  return .unavailable(
    corridorId: corridorId,
    message: "Corridor \(corridorId) is unavailable. No other rehearsed rail is healthy. Your payment details are unchanged."
  )
}

func gbpCorridor(_ health: SessionHealth) -> CorridorHealth? {
  health.corridors.first { corridor in
    corridor.currency?.caseInsensitiveCompare("GBP") == .orderedSame
      || corridor.id.caseInsensitiveCompare("GB") == .orderedSame
      || corridor.id.caseInsensitiveCompare("GBP") == .orderedSame
  }
}

func isBaselineRail(_ rail: RailHealth) -> Bool {
  let method = rail.method.lowercased()
  let provider = rail.provider.lowercased()
  return (method == "card" && provider == "adyen") || (method == "bank" && provider == "worldpay")
}

func normalizeStatus(_ raw: String) -> String {
  switch raw.lowercased() {
  case "healthy", "up", "ok", "available": return "healthy"
  case "degraded", "degradation": return "degraded"
  case "outage", "down", "unavailable": return "outage"
  default: return "unknown"
  }
}
