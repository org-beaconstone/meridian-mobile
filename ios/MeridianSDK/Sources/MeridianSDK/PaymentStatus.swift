import Foundation

/// Authoritative payment-intent phase from GET /api/v2/payment-intents/{id}.
/// Processing, pending, and unknown keep being checked. Declined is terminal.
public enum IntentPhase: String, Codable, Equatable {
  case processing
  case pending
  case unknown
  case succeeded
  case declined

  public var needsStatusCheck: Bool {
    switch self {
    case .processing, .pending, .unknown:
      return true
    case .succeeded, .declined:
      return false
    }
  }

  public static func classify(_ raw: String?) -> IntentPhase {
    let value = (raw ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "_", with: "-")
    switch value {
    case "processing", "submitting", "prepared", "created", "in-progress", "authorizing":
      return .processing
    case "pending", "payment-pending", "requires-action":
      return .pending
    case "succeeded", "success", "completed", "complete":
      return .succeeded
    case "declined", "declined-final", "payment-declined", "hard-decline":
      return .declined
    default:
      return .unknown
    }
  }
}

/// What a stored snapshot should do after a restart or process eviction.
/// Status checks are GET lookups. A declined snapshot never submits again.
public enum RecoveryAction: Equatable {
  case poll(intentId: String)
  case showReceipt
  case showDecline
  case holdUnknown
}

public func recoveryAction(for snapshot: IntentSnapshot) -> RecoveryAction {
  switch snapshot.phase {
  case .succeeded:
    return .showReceipt
  case .declined:
    return .showDecline
  case .processing, .pending, .unknown:
    if let intentId = snapshot.intentId, !intentId.isEmpty {
      return .poll(intentId: intentId)
    }
    return .holdUnknown
  }
}

public func phase(for response: PaymentResponse) -> IntentPhase {
  if response.ok {
    return .succeeded
  }
  switch response.code {
  case "PAYMENT_DECLINED":
    return .declined
  case "PAYMENT_PENDING":
    return .pending
  case "PAYMENT_PROCESSING":
    return .processing
  default:
    return .unknown
  }
}

public func recoveryFeedback(for phase: IntentPhase) -> String {
  switch phase {
  case .succeeded:
    return "Payment complete."
  case .declined:
    return "This payment was declined. No money was taken. It will not be submitted again automatically."
  case .pending:
    return "This payment is pending confirmation. Status checks continue without submitting it again."
  case .processing:
    return "Checking payment status. This does not start a new payment."
  case .unknown:
    return "The payment status is still unknown. Status checks resume after a restart. A new payment was not created."
  }
}

public func providerLabel(_ provider: String?) -> String {
  switch provider {
  case "adyen":
    return "Adyen"
  case "worldpay":
    return "Worldpay"
  default:
    return "Simulated provider"
  }
}

public func baselineProvider(method: String) -> String {
  method == "bank" ? "worldpay" : "adyen"
}

/// Equal-jitter backoff capped at `maxMs`. The delay stays inside half the step and the cap.
public enum StatusBackoff {
  public static let initialMs: UInt64 = 500
  public static let maxMs: UInt64 = 4_000
  public static let maxAttempts = 5
  public static let maxElapsedMs: UInt64 = 15_000

  public static func backoffMillis(
    attemptIndex: Int,
    randomUnit: Double,
    initialMs: UInt64 = StatusBackoff.initialMs,
    maxMs: UInt64 = StatusBackoff.maxMs
  ) -> UInt64 {
    precondition(attemptIndex >= 0, "attemptIndex must be >= 0")
    var delay = initialMs
    var steps = attemptIndex
    while steps > 0 {
      if delay >= maxMs / 2 {
        delay = maxMs
        break
      }
      delay *= 2
      steps -= 1
    }
    if delay > maxMs {
      delay = maxMs
    }
    let unit = min(1, max(0, randomUnit))
    let half = delay / 2
    let jitter = UInt64(unit * Double(delay - half))
    return half + jitter
  }
}

public struct PaymentIntent: Decodable, Equatable {
  public var id: String
  public var status: String
  public var amountMinor: Int?
  public var currency: String?
  public var recipientId: String?
  public var recipientName: String?
  public var method: String?
  public var provider: String?
  public var note: String?
  public var supportReference: String?
  public var transaction: Transaction?
  public var error: String?
  public var code: String?

  public init(
    id: String,
    status: String,
    amountMinor: Int? = nil,
    currency: String? = nil,
    recipientId: String? = nil,
    recipientName: String? = nil,
    method: String? = nil,
    provider: String? = nil,
    note: String? = nil,
    supportReference: String? = nil,
    transaction: Transaction? = nil,
    error: String? = nil,
    code: String? = nil
  ) {
    self.id = id
    self.status = status
    self.amountMinor = amountMinor
    self.currency = currency
    self.recipientId = recipientId
    self.recipientName = recipientName
    self.method = method
    self.provider = provider
    self.note = note
    self.supportReference = supportReference
    self.transaction = transaction
    self.error = error
    self.code = code
  }

  enum CodingKeys: String, CodingKey {
    case id
    case status
    case phase
    case amountMinor
    case currency
    case recipientId
    case recipientName
    case method
    case provider
    case note
    case supportReference
    case transaction
    case error
    case code
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    if let status = try container.decodeIfPresent(String.self, forKey: .status) {
      self.status = status
    } else if let phase = try container.decodeIfPresent(String.self, forKey: .phase) {
      self.status = phase
    } else {
      self.status = "unknown"
    }
    amountMinor = try container.decodeIfPresent(Int.self, forKey: .amountMinor)
    currency = try container.decodeIfPresent(String.self, forKey: .currency)
    recipientId = try container.decodeIfPresent(String.self, forKey: .recipientId)
    recipientName = try container.decodeIfPresent(String.self, forKey: .recipientName)
    method = try container.decodeIfPresent(String.self, forKey: .method)
    provider = try container.decodeIfPresent(String.self, forKey: .provider)
    note = try container.decodeIfPresent(String.self, forKey: .note)
    supportReference = try container.decodeIfPresent(String.self, forKey: .supportReference)
    transaction = try container.decodeIfPresent(Transaction.self, forKey: .transaction)
    error = try container.decodeIfPresent(String.self, forKey: .error)
    code = try container.decodeIfPresent(String.self, forKey: .code)
  }
}

/// GBP-only view of an intent. A non-GBP currency is not treated as success.
public func presentationPhase(_ intent: PaymentIntent) -> IntentPhase {
  if let currency = intent.currency?.trimmingCharacters(in: .whitespacesAndNewlines),
    !currency.isEmpty,
    currency.uppercased() != "GBP",
    IntentPhase.classify(intent.status) != .declined
  {
    return .unknown
  }
  return IntentPhase.classify(intent.status)
}

public struct IntentSnapshot: Codable, Equatable {
  public var intentId: String?
  public var sessionId: String
  public var baseURL: String
  public var idempotencyKey: String
  public var recipientId: String
  public var recipientName: String
  public var amountMinor: Int
  public var method: String
  public var note: String
  public var phase: IntentPhase
  public var supportReference: String?
  public var transaction: Transaction?
  public var provider: String?
  public var detail: String?
  public var updatedAt: String

  public init(
    intentId: String?,
    sessionId: String,
    baseURL: String,
    idempotencyKey: String,
    recipientId: String,
    recipientName: String,
    amountMinor: Int,
    method: String,
    note: String,
    phase: IntentPhase,
    supportReference: String? = nil,
    transaction: Transaction? = nil,
    provider: String? = nil,
    detail: String? = nil,
    updatedAt: String
  ) {
    self.intentId = intentId
    self.sessionId = sessionId
    self.baseURL = baseURL
    self.idempotencyKey = idempotencyKey
    self.recipientId = recipientId
    self.recipientName = recipientName
    self.amountMinor = amountMinor
    self.method = method
    self.note = note
    self.phase = phase
    self.supportReference = supportReference
    self.transaction = transaction
    self.provider = provider
    self.detail = detail
    self.updatedAt = updatedAt
  }

  public var needsStatusCheck: Bool {
    phase.needsStatusCheck
  }
}

public func isoTimestamp(_ date: Date = Date()) -> String {
  ISO8601DateFormatter().string(from: date)
}

public struct PaymentReceipt: Equatable {
  public var recipientName: String
  public var amountMinor: Int
  public var supportReference: String
  public var transactionId: String?
  public var transactionDate: String?
  public var method: String?
  public var provider: String?
  public var note: String?
  public var status: String?
}

public func resolvedSupportReference(snapshot: IntentSnapshot, intent: PaymentIntent?) -> String {
  if let value = intent?.supportReference?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
    return value
  }
  if let value = snapshot.supportReference?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
    return value
  }
  if let value = intent?.transaction?.reference, !value.isEmpty {
    return value
  }
  if let value = snapshot.transaction?.reference, !value.isEmpty {
    return value
  }
  let source: String
  if let intentId = intent?.id, !intentId.isEmpty {
    source = intentId
  } else if let stored = snapshot.intentId, !stored.isEmpty {
    source = stored
  } else {
    source = snapshot.idempotencyKey
  }
  return "MER-\(source.prefix(8).uppercased())"
}

public func applying(_ result: StatusPollResult, to snapshot: IntentSnapshot) -> IntentSnapshot {
  var next = snapshot
  if let intent = result.intent {
    if !intent.id.isEmpty {
      next.intentId = intent.id
    }
    if let amount = intent.amountMinor {
      next.amountMinor = amount
    }
    if let name = intent.recipientName, !name.isEmpty {
      next.recipientName = name
    }
    if let recipientId = intent.recipientId, !recipientId.isEmpty {
      next.recipientId = recipientId
    }
    if let method = intent.method, !method.isEmpty {
      next.method = method
    }
    if let note = intent.note {
      next.note = note
    }
    if let provider = intent.provider, !provider.isEmpty {
      next.provider = provider
    }
    if let transaction = intent.transaction {
      next.transaction = transaction
    }
    if let support = intent.supportReference, !support.isEmpty {
      next.supportReference = support
    }
    if let error = intent.error, !error.isEmpty {
      next.detail = error
    }
  }
  next.phase = result.phase
  next.supportReference = resolvedSupportReference(snapshot: next, intent: result.intent)
  next.updatedAt = isoTimestamp()
  if result.phase == .declined {
    next.detail = recoveryFeedback(for: .declined)
  } else if result.phase == .succeeded {
    next.detail = recoveryFeedback(for: .succeeded)
  } else {
    next.detail = recoveryFeedback(for: result.phase)
  }
  return next
}

public func makeReceipt(snapshot: IntentSnapshot, intent: PaymentIntent?) -> PaymentReceipt {
  let transaction = intent?.transaction ?? snapshot.transaction
  let amount = intent?.amountMinor ?? transaction?.amount ?? snapshot.amountMinor
  return PaymentReceipt(
    recipientName: intent?.recipientName ?? snapshot.recipientName,
    amountMinor: amount,
    supportReference: resolvedSupportReference(snapshot: snapshot, intent: intent),
    transactionId: transaction?.id ?? (intent?.id.isEmpty == false ? intent?.id : snapshot.intentId),
    transactionDate: transaction?.date,
    method: transaction.map { $0.method.rawValue } ?? intent?.method ?? snapshot.method,
    provider: transaction.map { $0.provider.rawValue } ?? intent?.provider ?? snapshot.provider,
    note: transaction?.note ?? intent?.note ?? snapshot.note,
    status: transaction?.status.rawValue ?? (snapshot.phase == .succeeded ? "completed" : snapshot.phase.rawValue)
  )
}

public func paymentIntentURL(baseURL: URL, id: String) throws -> URL {
  guard id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else {
    throw MeridianError.validationError("Invalid payment intent id")
  }
  guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
    let scheme = components.scheme,
    scheme == "http" || scheme == "https"
  else {
    throw MeridianError.invalidURL
  }
  var path = components.percentEncodedPath
  if path.hasSuffix("/") {
    path.removeLast()
  }
  let suffix = "/api/v1"
  guard path.hasSuffix(suffix) else {
    throw MeridianError.invalidURL
  }
  path = String(path.dropLast(suffix.count)) + "/api/v2/payment-intents/" + id
  components.percentEncodedPath = path
  guard let url = components.url else {
    throw MeridianError.invalidURL
  }
  return url
}

public struct StatusPollResult: Equatable {
  public var phase: IntentPhase
  public var intent: PaymentIntent?
  public var attempts: Int

  public init(phase: IntentPhase, intent: PaymentIntent?, attempts: Int) {
    self.phase = phase
    self.intent = intent
    self.attempts = attempts
  }
}

/// Polls GET /api/v2/payment-intents/{id}. It never submits a payment.
public struct PaymentStatusPoller: Sendable {
  public var getIntent: @Sendable (String) async throws -> PaymentIntent
  public var sleep: @Sendable (UInt64) async -> Void
  public var randomUnit: @Sendable () -> Double
  public var maxAttempts: Int
  public var initialBackoffMs: UInt64
  public var maxBackoffMs: UInt64
  public var maxElapsedMs: UInt64

  public init(
    getIntent: @escaping @Sendable (String) async throws -> PaymentIntent,
    sleep: @escaping @Sendable (UInt64) async -> Void = { milliseconds in
      try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    },
    randomUnit: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
    maxAttempts: Int = StatusBackoff.maxAttempts,
    initialBackoffMs: UInt64 = StatusBackoff.initialMs,
    maxBackoffMs: UInt64 = StatusBackoff.maxMs,
    maxElapsedMs: UInt64 = StatusBackoff.maxElapsedMs
  ) {
    self.getIntent = getIntent
    self.sleep = sleep
    self.randomUnit = randomUnit
    self.maxAttempts = maxAttempts
    self.initialBackoffMs = initialBackoffMs
    self.maxBackoffMs = maxBackoffMs
    self.maxElapsedMs = maxElapsedMs
  }

  public func poll(intentId: String) async -> StatusPollResult {
    var attempt = 0
    var elapsed: UInt64 = 0
    var last: PaymentIntent?
    while attempt < maxAttempts {
      if Task.isCancelled {
        break
      }
      attempt += 1
      do {
        let intent = try await getIntent(intentId)
        last = intent
        let phase = presentationPhase(intent)
        if phase == .succeeded || phase == .declined {
          return StatusPollResult(phase: phase, intent: intent, attempts: attempt)
        }
      } catch {
        // A failed lookup stays unknown and does not create another payment.
      }
      if attempt >= maxAttempts {
        break
      }
      let delay = StatusBackoff.backoffMillis(
        attemptIndex: attempt - 1,
        randomUnit: randomUnit(),
        initialMs: initialBackoffMs,
        maxMs: maxBackoffMs
      )
      if elapsed >= maxElapsedMs || delay > maxElapsedMs - elapsed {
        break
      }
      await sleep(delay)
      elapsed += delay
    }
    let phase = last.map(presentationPhase) ?? .unknown
    if phase == .succeeded || phase == .declined {
      return StatusPollResult(phase: phase, intent: last, attempts: attempt)
    }
    return StatusPollResult(
      phase: phase == .pending || phase == .processing ? phase : .unknown,
      intent: last,
      attempts: attempt
    )
  }
}

private struct SnapshotEnvelope: Codable {
  var sessions: [String: IntentSnapshot]
}

/// JSON file of in-flight and terminal intent snapshots, keyed by rehearsal session.
public struct FileIntentSnapshotStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public static func defaultStore() -> FileIntentSnapshotStore {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let directory = base.appendingPathComponent("Meridian", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return FileIntentSnapshotStore(fileURL: directory.appendingPathComponent("intent-snapshots.json"))
  }

  public func load(sessionId: String) -> IntentSnapshot? {
    loadAll()[sessionId]
  }

  public func save(_ snapshot: IntentSnapshot) {
    var sessions = loadAll()
    sessions[snapshot.sessionId] = snapshot
    write(sessions)
  }

  public func remove(sessionId: String) {
    var sessions = loadAll()
    sessions.removeValue(forKey: sessionId)
    write(sessions)
  }

  /// Prefer a snapshot that still needs a status check, otherwise the newest stored outcome.
  public func latestRecoverable() -> IntentSnapshot? {
    let sessions = Array(loadAll().values)
    let open = sessions.filter { recoveryAction(for: $0) == .holdUnknown || isPoll($0) }
    let pool = open.isEmpty ? sessions : open
    return pool.max { $0.updatedAt < $1.updatedAt }
  }

  private func isPoll(_ snapshot: IntentSnapshot) -> Bool {
    if case .poll = recoveryAction(for: snapshot) {
      return true
    }
    return false
  }

  private func loadAll() -> [String: IntentSnapshot] {
    guard let data = try? Data(contentsOf: fileURL) else {
      return [:]
    }
    let decoder = JSONDecoder()
    return (try? decoder.decode(SnapshotEnvelope.self, from: data).sessions) ?? [:]
  }

  private func write(_ sessions: [String: IntentSnapshot]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(SnapshotEnvelope(sessions: sessions)) else {
      return
    }
    let directory = fileURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? data.write(to: fileURL, options: .atomic)
  }
}
