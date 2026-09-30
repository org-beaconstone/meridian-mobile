import Foundation

/// Customer-facing copy when new payment intents are refused.
public let paymentsPausedMessage = "New payments are paused. Status and receipts stay available."

/// GB is the domestic rehearsal corridor. EU is the European corridor.
/// Both corridors use the hardcoded Adyen card and Worldpay bank rails.
/// Amounts elsewhere stay integer GBP pence. No other provider is constructed.
public enum PaymentCorridor: String, Hashable, CaseIterable {
  case gb = "GB"
  case eu = "EU"

  public init?(raw: String) {
    self.init(rawValue: raw.uppercased())
  }
}

public struct CorridorMethod: Hashable, Identifiable {
  public let id: String
  public let provider: ProviderId
  public let method: PaymentMethod
  public let corridor: PaymentCorridor
  public let label: String

  public init(
    id: String,
    provider: ProviderId,
    method: PaymentMethod,
    corridor: PaymentCorridor,
    label: String
  ) {
    self.id = id
    self.provider = provider
    self.method = method
    self.corridor = corridor
    self.label = label
  }

  public static let baseline: [CorridorMethod] = [
    CorridorMethod(
      id: "adyen-card-gb",
      provider: .adyen,
      method: .card,
      corridor: .gb,
      label: "Debit card · Adyen"
    ),
    CorridorMethod(
      id: "worldpay-bank-gb",
      provider: .worldpay,
      method: .bank,
      corridor: .gb,
      label: "Bank payment · Worldpay"
    ),
    CorridorMethod(
      id: "adyen-card-eu",
      provider: .adyen,
      method: .card,
      corridor: .eu,
      label: "Debit card · Adyen · European corridor"
    ),
    CorridorMethod(
      id: "worldpay-bank-eu",
      provider: .worldpay,
      method: .bank,
      corridor: .eu,
      label: "Bank payment · Worldpay · European corridor"
    ),
  ]

  public static func forCorridors(_ corridors: [PaymentCorridor]) -> [CorridorMethod] {
    baseline.filter { corridors.contains($0.corridor) }
  }
}

public struct CorridorFlags: Equatable {
  public let multiProviderSelection: Bool
  public let europeanCorridorEnabled: Bool
  public let darkLaunch: Bool
  public let killSwitch: Bool
  public let canaryAccounts: [String]

  public init(
    multiProviderSelection: Bool,
    europeanCorridorEnabled: Bool,
    darkLaunch: Bool,
    killSwitch: Bool,
    canaryAccounts: [String]
  ) {
    self.multiProviderSelection = multiProviderSelection
    self.europeanCorridorEnabled = europeanCorridorEnabled
    self.darkLaunch = darkLaunch
    self.killSwitch = killSwitch
    self.canaryAccounts = canaryAccounts
  }

  public static let rehearsalDefault = CorridorFlags(
    multiProviderSelection: true,
    europeanCorridorEnabled: false,
    darkLaunch: false,
    killSwitch: false,
    canaryAccounts: []
  )
}

public struct CatalogSnapshot: Equatable {
  public let version: Int
  public let methods: [CorridorMethod]

  public init(version: Int, methods: [CorridorMethod]) {
    self.version = version
    self.methods = methods
  }
}

public enum IntentStatus: String, Equatable {
  case inFlight
  case completed
  case declined
}

public struct IntentReceipt: Equatable {
  public let reference: String
  public let amountMinor: Int
  public let methodId: String
  public let provider: ProviderId

  public init(reference: String, amountMinor: Int, methodId: String, provider: ProviderId) {
    self.reference = reference
    self.amountMinor = amountMinor
    self.methodId = methodId
    self.provider = provider
  }
}

public struct PaymentIntentRecord: Equatable {
  public let id: String
  public let idempotencyKey: String
  public let accountId: String
  public let recipientId: String
  public let amountMinor: Int
  public let note: String
  public let methodId: String
  public let provider: ProviderId
  public let method: PaymentMethod
  public let corridor: PaymentCorridor
  public let snapshot: CatalogSnapshot
  public var status: IntentStatus
  public var receipt: IntentReceipt?

  public init(
    id: String,
    idempotencyKey: String,
    accountId: String,
    recipientId: String,
    amountMinor: Int,
    note: String,
    methodId: String,
    provider: ProviderId,
    method: PaymentMethod,
    corridor: PaymentCorridor,
    snapshot: CatalogSnapshot,
    status: IntentStatus,
    receipt: IntentReceipt?
  ) {
    self.id = id
    self.idempotencyKey = idempotencyKey
    self.accountId = accountId
    self.recipientId = recipientId
    self.amountMinor = amountMinor
    self.note = note
    self.methodId = methodId
    self.provider = provider
    self.method = method
    self.corridor = corridor
    self.snapshot = snapshot
    self.status = status
    self.receipt = receipt
  }
}

public struct DarkLaunchEvent: Equatable {
  public let generation: Int
  public let accountId: String
  public let catalogVersion: Int
  public let corridor: String
  public let europeanMethodsHidden: Bool

  public init(
    generation: Int,
    accountId: String,
    catalogVersion: Int,
    corridor: String,
    europeanMethodsHidden: Bool
  ) {
    self.generation = generation
    self.accountId = accountId
    self.catalogVersion = catalogVersion
    self.corridor = corridor
    self.europeanMethodsHidden = europeanMethodsHidden
  }
}

public enum IntentError: Error, Equatable {
  case killSwitch
  case methodUnavailable
  case invalidAmount
  case missingIdempotencyKey

  public var message: String {
    switch self {
    case .killSwitch:
      return paymentsPausedMessage
    case .methodUnavailable:
      return "That payment method is not available."
    case .invalidAmount:
      return "Amount must be from 1 to 1000000 pence."
    case .missingIdempotencyKey:
      return "Idempotency key is required."
    }
  }
}

/// Server-driven corridor flags, dark launch telemetry, the operational kill switch,
/// and catalog rollback. Applying a payload replaces the previous flags immediately.
/// In-flight intents keep the catalog snapshot copied at creation.
public final class CorridorControls {
  public private(set) var flags: CorridorFlags
  public private(set) var activeCatalog: CatalogSnapshot
  public private(set) var telemetry: [DarkLaunchEvent]
  private var history: [Int: CatalogSnapshot]
  private var intentsById: [String: PaymentIntentRecord]
  private var intentIdByKey: [String: String]
  private var generation: Int

  public init() {
    let initial = CatalogSnapshot(version: 1, methods: CorridorMethod.forCorridors([.gb]))
    flags = .rehearsalDefault
    activeCatalog = initial
    history = [1: initial]
    telemetry = []
    intentsById = [:]
    intentIdByKey = [:]
    generation = 0
  }

  public func reset() {
    let fresh = CorridorControls()
    flags = fresh.flags
    activeCatalog = fresh.activeCatalog
    history = fresh.history
    telemetry = []
    intentsById = [:]
    intentIdByKey = [:]
    generation = 0
  }

  /// Returns false when the payload is not a config object. State is left unchanged.
  @discardableResult
  public func applyServerPayload(_ data: Data) -> Bool {
    let decoder = JSONDecoder()
    guard let payload = try? decoder.decode(FlagPayload.self, from: data) else {
      return false
    }
    let canary: [String]
    if let object = try? JSONSerialization.jsonObject(with: data),
      let raw = object as? [String: Any]
    {
      canary = stringList(raw)
    } else {
      canary = []
    }
    flags = CorridorFlags(
      multiProviderSelection: flag(
        payload,
        key: "multi_provider_selection",
        topLevel: payload.multiProviderSelection,
        default: true
      ),
      europeanCorridorEnabled: flag(
        payload,
        key: "european_corridor",
        topLevel: payload.europeanCorridor,
        default: false
      ),
      darkLaunch: flag(payload, key: "dark_launch", topLevel: payload.darkLaunch, default: false),
      killSwitch: flag(
        payload,
        key: "payments_kill_switch",
        topLevel: payload.paymentsKillSwitch,
        default: false
      ),
      canaryAccounts: canary
    )
    generation += 1
    if let envelope = try? decoder.decode(CatalogEnvelope.self, from: data),
      let catalogs = envelope.catalogs
    {
      install(catalogs)
    }
    if let version = payload.catalogVersion {
      _ = activate(version: version)
    }
    return true
  }

  @discardableResult
  public func publishCatalog(version: Int, corridors: [PaymentCorridor]) -> Bool {
    var seen: [PaymentCorridor] = []
    for corridor in corridors where !seen.contains(corridor) {
      seen.append(corridor)
    }
    guard version > 0, !seen.isEmpty else { return false }
    let snapshot = CatalogSnapshot(version: version, methods: CorridorMethod.forCorridors(seen))
    history[version] = snapshot
    activeCatalog = snapshot
    return true
  }

  /// Activates a stored catalog version. Intent snapshots are not rewritten.
  @discardableResult
  public func rollbackCatalog(to version: Int) -> Bool {
    activate(version: version)
  }

  public func visibleMethods(accountId: String) -> [CorridorMethod] {
    let allowEurope = europeanMethodsVisible(accountId: accountId)
    return activeCatalog.methods.filter { method in
      if method.corridor == .eu && !allowEurope { return false }
      if !flags.multiProviderSelection && !(method.provider == .adyen && method.method == .card) {
        return false
      }
      return true
    }
  }

  /// Records one dark-launch telemetry event per flag generation and account.
  @discardableResult
  public func resolve(accountId: String) -> [CorridorMethod] {
    let methods = visibleMethods(accountId: accountId)
    if flags.darkLaunch {
      let already = telemetry.contains { $0.generation == generation && $0.accountId == accountId }
      if !already {
        telemetry.append(
          DarkLaunchEvent(
            generation: generation,
            accountId: accountId,
            catalogVersion: activeCatalog.version,
            corridor: "EU",
            europeanMethodsHidden: !methods.contains { $0.corridor == .eu }
          )
        )
      }
    }
    return methods
  }

  public func blocksNewIntent(idempotencyKey: String) -> Bool {
    if intentIdByKey[idempotencyKey] != nil { return false }
    return flags.killSwitch
  }

  public func createIntent(
    idempotencyKey: String,
    accountId: String,
    recipientId: String,
    amountMinor: Int,
    note: String = "",
    methodId: String
  ) -> Result<PaymentIntentRecord, IntentError> {
    if let existingId = intentIdByKey[idempotencyKey], let existing = intentsById[existingId] {
      return .success(existing)
    }
    if idempotencyKey.isEmpty || idempotencyKey.count > 100 {
      return .failure(.missingIdempotencyKey)
    }
    if flags.killSwitch {
      return .failure(.killSwitch)
    }
    if amountMinor < 1 || amountMinor > 1_000_000 {
      return .failure(.invalidAmount)
    }
    guard let selected = visibleMethods(accountId: accountId).first(where: { $0.id == methodId }) else {
      return .failure(.methodUnavailable)
    }
    let record = PaymentIntentRecord(
      id: UUID().uuidString,
      idempotencyKey: idempotencyKey,
      accountId: accountId,
      recipientId: recipientId,
      amountMinor: amountMinor,
      note: note,
      methodId: selected.id,
      provider: selected.provider,
      method: selected.method,
      corridor: selected.corridor,
      snapshot: activeCatalog,
      status: .inFlight,
      receipt: nil
    )
    intentsById[record.id] = record
    intentIdByKey[idempotencyKey] = record.id
    return .success(record)
  }

  public func intent(id: String) -> PaymentIntentRecord? {
    intentsById[id]
  }

  public func status(intentId: String) -> IntentStatus? {
    intentsById[intentId]?.status
  }

  public func receipt(intentId: String) -> IntentReceipt? {
    intentsById[intentId]?.receipt
  }

  /// True when the intent's own snapshot still contains its method, whatever the live catalog is.
  public func snapshotRemainsValid(intentId: String) -> Bool {
    guard let intent = intentsById[intentId] else { return false }
    return intent.snapshot.version > 0 && intent.snapshot.methods.contains { $0.id == intent.methodId }
  }

  @discardableResult
  public func complete(intentId: String, reference: String) -> IntentReceipt? {
    guard var intent = intentsById[intentId] else { return nil }
    let receipt = IntentReceipt(
      reference: reference,
      amountMinor: intent.amountMinor,
      methodId: intent.methodId,
      provider: intent.provider
    )
    intent.status = .completed
    intent.receipt = receipt
    intentsById[intentId] = intent
    return receipt
  }

  public func markDeclined(intentId: String) {
    guard var intent = intentsById[intentId] else { return }
    intent.status = .declined
    intentsById[intentId] = intent
  }

  private func europeanMethodsVisible(accountId: String) -> Bool {
    if flags.darkLaunch { return false }
    if !flags.europeanCorridorEnabled { return false }
    if flags.canaryAccounts.isEmpty { return true }
    return flags.canaryAccounts.contains(accountId)
  }

  @discardableResult
  private func activate(version: Int) -> Bool {
    guard let snapshot = history[version] else { return false }
    activeCatalog = snapshot
    return true
  }

  private func install(_ catalogs: [CatalogItem]) {
    var next: [Int: CatalogSnapshot] = [:]
    for catalog in catalogs where catalog.version > 0 {
      var corridors: [PaymentCorridor] = []
      for name in catalog.corridors {
        guard let corridor = PaymentCorridor(raw: name), !corridors.contains(corridor) else { continue }
        corridors.append(corridor)
      }
      if corridors.isEmpty { continue }
      next[catalog.version] = CatalogSnapshot(
        version: catalog.version,
        methods: CorridorMethod.forCorridors(corridors)
      )
    }
    if !next.isEmpty {
      history = next
    }
  }

  private func stringList(_ json: [String: Any]) -> [String] {
    let value = json["canaryAccounts"] ?? json["controlledAccounts"]
    guard let items = value as? [Any] else { return [] }
    return items.compactMap { $0 as? String }
  }

  private func flag(
    _ payload: FlagPayload,
    key: String,
    topLevel: FlagValue?,
    default defaultValue: Bool
  ) -> Bool {
    if let nested = payload.flags?[key] {
      return nested.bool ?? false
    }
    if let topLevel {
      return topLevel.bool ?? false
    }
    return defaultValue
  }
}

private struct FlagValue: Decodable {
  let bool: Bool?

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      bool = nil
      return
    }
    if let value = try? container.decode(Bool.self) {
      bool = value
      return
    }
    if let text = try? container.decode(String.self) {
      bool = text.lowercased() == "true"
      return
    }
    if (try? container.decode(Double.self)) != nil {
      bool = nil
      return
    }
    bool = nil
  }
}

private struct FlagPayload: Decodable {
  let flags: [String: FlagValue]?
  let multiProviderSelection: FlagValue?
  let europeanCorridor: FlagValue?
  let darkLaunch: FlagValue?
  let paymentsKillSwitch: FlagValue?
  let catalogVersion: Int?

  enum CodingKeys: String, CodingKey {
    case flags
    case multiProviderSelection = "multi_provider_selection"
    case europeanCorridor = "european_corridor"
    case darkLaunch = "dark_launch"
    case paymentsKillSwitch = "payments_kill_switch"
    case catalogVersion
  }
}

private struct CatalogItem: Decodable {
  let version: Int
  let corridors: [String]
}

private struct CatalogEnvelope: Decodable {
  let catalogs: [CatalogItem]?
}
