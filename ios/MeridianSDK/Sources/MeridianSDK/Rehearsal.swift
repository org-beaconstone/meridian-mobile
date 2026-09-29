import Foundation

/// Outcome of one rehearsal payment attempt.
/// The idempotency key and method are the ones actually sent. Retries do not change either.
public enum Submission {
  case settled(PaymentResponse, idempotencyKey: String, method: PaymentMethod)
  case pending(PaymentResponse, idempotencyKey: String, method: PaymentMethod)
  case declined(PaymentResponse, idempotencyKey: String, method: PaymentMethod)
  case unavailable(PaymentResponse, idempotencyKey: String, method: PaymentMethod)
  case uncertain(idempotencyKey: String, method: PaymentMethod, message: String)
  case rejected(PaymentResponse?, idempotencyKey: String, method: PaymentMethod, message: String)

  public var idempotencyKey: String {
    switch self {
    case let .settled(_, idempotencyKey, _),
      let .pending(_, idempotencyKey, _),
      let .declined(_, idempotencyKey, _),
      let .unavailable(_, idempotencyKey, _),
      let .uncertain(idempotencyKey, _, _),
      let .rejected(_, idempotencyKey, _, _):
      return idempotencyKey
    }
  }

  public var method: PaymentMethod {
    switch self {
    case let .settled(_, _, method),
      let .pending(_, _, method),
      let .declined(_, _, method),
      let .unavailable(_, _, method),
      let .uncertain(_, method, _),
      let .rejected(_, _, method, _):
      return method
    }
  }
}

/// Client-side rehearsal session: last-known catalogue and same-provider retries.
/// Fictional GBP ledger client. It does not collect credentials or call a live provider.
public actor RehearsalClient {
  private let api: MeridianClient
  private var cachedCatalog: CatalogResponse?
  public private(set) var usingCatalogFallback = false

  public init(api: MeridianClient) {
    self.api = api
  }

  public func hasCatalog() -> Bool {
    cachedCatalog != nil
  }

  public func hydrateCatalog() async throws -> CatalogResponse {
    do {
      let fresh = try await api.getCatalog()
      try validateBaseline(fresh)
      cachedCatalog = fresh
      usingCatalogFallback = false
      return fresh
    } catch let error as MeridianError {
      if case .validationError = error {
        throw error
      }
      if let cachedCatalog {
        usingCatalogFallback = true
        return cachedCatalog
      }
      throw error
    } catch {
      if let cachedCatalog {
        usingCatalogFallback = true
        return cachedCatalog
      }
      throw error
    }
  }

  /// Submit a payment. Provider-unavailable and transport failures retry the same key and method.
  /// HTTP 202 pending is returned immediately so the caller keeps that payment instead of starting another.
  public func submit(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = .success,
    idempotencyKey: String,
    maxAttempts: Int = 2
  ) async throws -> Submission {
    guard maxAttempts >= 1 else { throw MeridianError.validationError("At least one attempt is required") }
    guard !idempotencyKey.isEmpty else { throw MeridianError.validationError("Idempotency key is required") }
    var networkMessage = "Outcome unknown"
    for attempt in 1...maxAttempts {
      do {
        let response: PaymentResponse = try await api.submitPayment(
          recipientId: recipientId,
          amountMinor: amountMinor,
          method: method,
          note: note,
          scenario: scenario,
          idempotencyKey: idempotencyKey
        )
        if response.ok {
          return .settled(response, idempotencyKey: idempotencyKey, method: method)
        }
        switch response.code {
        case "PAYMENT_PENDING":
          return .pending(response, idempotencyKey: idempotencyKey, method: method)
        case "PAYMENT_DECLINED":
          return .declined(response, idempotencyKey: idempotencyKey, method: method)
        case "PROVIDER_UNAVAILABLE":
          if attempt == maxAttempts {
            return .unavailable(response, idempotencyKey: idempotencyKey, method: method)
          }
        default:
          return .rejected(
            response,
            idempotencyKey: idempotencyKey,
            method: method,
            message: response.error ?? "Payment rejected"
          )
        }
      } catch let error as MeridianError {
        switch error {
        case let .networkError(message):
          networkMessage = message
          if attempt == maxAttempts {
            return .uncertain(idempotencyKey: idempotencyKey, method: method, message: networkMessage)
          }
        case let .httpError(statusCode, message) where statusCode == 408 || statusCode == 503 || statusCode == 504:
          networkMessage = message
          if attempt == maxAttempts {
            return .uncertain(idempotencyKey: idempotencyKey, method: method, message: networkMessage)
          }
        case let .httpError(_, message):
          return .rejected(nil, idempotencyKey: idempotencyKey, method: method, message: message)
        default:
          throw error
        }
      }
    }
    return .uncertain(idempotencyKey: idempotencyKey, method: method, message: networkMessage)
  }

  private func validateBaseline(_ catalog: CatalogResponse) throws {
    let ids = Set(catalog.providers.map(\.id))
    guard ids == [.adyen, .worldpay], catalog.providers.count == 2 else {
      throw MeridianError.validationError("Catalogue must contain only Adyen card and Worldpay bank")
    }
    let adyen = catalog.providers.first { $0.id == .adyen }
    let worldpay = catalog.providers.first { $0.id == .worldpay }
    guard adyen?.methods == [.card], worldpay?.methods == [.bank] else {
      throw MeridianError.validationError("Provider methods must stay Adyen/card and Worldpay/bank")
    }
  }
}

public enum RehearsalCheck: Error, CustomStringConvertible {
  case failed(String)
  public var description: String {
    switch self {
    case let .failed(message): return message
    }
  }
}

/// Release-gate journey against the shared Java rehearsal contract.
/// Amounts are GBP pence. Pending confirmation does not debit. Retries keep the original key.
public enum RehearsalJourney {
  public static let openingBalance = 1_248_050

  public static func run(api: MeridianClient) async throws {
    let rehearsal = RehearsalClient(api: api)
    let health = try await api.getHealth()
    try expect(health.status == "UP" && health.service == "meridian-api" && health.simulation, "health")

    let catalog = try await rehearsal.hydrateCatalog()
    try expect(catalog.demoDate == "2026-09-18", "demo date")
    try expect(catalog.recipients.count == 5, "recipient count")
    try expect(catalog.recipients.contains { $0.id == "northline-studio" }, "recipient")
    try expect(Set(catalog.providers.map(\.id)) == [.adyen, .worldpay], "providers")
    let adyen = catalog.providers.first { $0.id == .adyen }
    let worldpay = catalog.providers.first { $0.id == .worldpay }
    try expect(adyen?.methods == [.card], "adyen method")
    try expect(worldpay?.methods == [.bank], "worldpay method")

    let state = try await api.getState()
    try expect(state.balance == openingBalance, "opening balance \(state.balance)")

    let (pence, penceError) = minorUnits(currency: "GBP", input: "0.01")
    try expect(pence == 1 && penceError == nil, "minimum pence")
    let (pounds, poundsError) = minorUnits(currency: "GBP", input: "10000.00")
    try expect(pounds == 1_000_000 && poundsError == nil, "maximum pounds")
    try expect(minorUnits(currency: "GBP", input: "10000.01").0 == nil, "over maximum")
    try expect(minorUnits(currency: "EUR", input: "10.00").0 == nil, "non-GBP currency")
    try expect(baselineProvider(.card) == .adyen, "card provider")
    try expect(baselineProvider(.bank) == .worldpay, "bank provider")

    let settlementKey = UUID().uuidString
    let paid = try await rehearsal.submit(
      recipientId: "northline-studio",
      amountMinor: 2599,
      method: .card,
      note: "rehearsal settlement",
      idempotencyKey: settlementKey
    )
    guard case let .settled(paidResponse, paidKey, paidMethod) = paid else {
      throw RehearsalCheck.failed("expected settlement")
    }
    try expect(paidKey == settlementKey && paidMethod == .card, "settlement identity")
    try expect(paidResponse.state?.balance == openingBalance - 2599, "settlement balance")
    try expect(paidResponse.transaction?.provider == .adyen, "settlement provider")
    try expect(paidResponse.transaction?.method == .card, "settlement method")
    let settledId = paidResponse.transaction?.id ?? ""
    try expect(!settledId.isEmpty, "missing transaction")

    let replay = try await rehearsal.submit(
      recipientId: "northline-studio",
      amountMinor: 2599,
      method: .card,
      note: "rehearsal settlement",
      idempotencyKey: settlementKey
    )
    guard case let .settled(replayResponse, _, _) = replay else {
      throw RehearsalCheck.failed("expected idempotent replay")
    }
    try expect(replayResponse.transaction?.id == settledId, "idempotent transaction")
    try expect(replayResponse.state?.balance == openingBalance - 2599, "idempotent balance")

    let mismatch = try await rehearsal.submit(
      recipientId: "northline-studio",
      amountMinor: 2600,
      method: .card,
      note: "rehearsal settlement",
      idempotencyKey: settlementKey,
      maxAttempts: 1
    )
    guard case .rejected = mismatch else { throw RehearsalCheck.failed("idempotency mismatch") }
    try expect((try await api.getState()).balance == openingBalance - 2599, "mismatch balance")

    let pendingKey = UUID().uuidString
    let pending = try await rehearsal.submit(
      recipientId: "northline-studio",
      amountMinor: 100,
      method: .card,
      note: "pending confirmation",
      scenario: .pending,
      idempotencyKey: pendingKey
    )
    guard case let .pending(pendingResponse, retainedKey, _) = pending else {
      throw RehearsalCheck.failed("expected pending")
    }
    try expect(pendingResponse.code == "PAYMENT_PENDING" && pendingResponse.paymentId != nil, "pending payload")
    try expect(retainedKey == pendingKey, "pending key retained")
    try expect(!pendingResponse.ok, "pending is not settled")
    try expect((try await api.getState()).balance == openingBalance - 2599, "pending balance")

    let pendingAgain = try await rehearsal.submit(
      recipientId: "northline-studio",
      amountMinor: 100,
      method: .card,
      note: "pending confirmation",
      scenario: .pending,
      idempotencyKey: pendingKey
    )
    guard case let .pending(pendingAgainResponse, _, _) = pendingAgain else {
      throw RehearsalCheck.failed("pending retry created a new outcome")
    }
    try expect(pendingAgainResponse.paymentId == pendingResponse.paymentId, "pending identity")
    try expect((try await api.getState()).balance == openingBalance - 2599, "pending retry balance")

    let outageKey = UUID().uuidString
    let unavailable = try await rehearsal.submit(
      recipientId: "northline-studio",
      amountMinor: 500,
      method: .bank,
      note: "provider outage",
      scenario: .unavailable,
      idempotencyKey: outageKey,
      maxAttempts: 1
    )
    guard case let .unavailable(_, _, outageMethod) = unavailable else {
      throw RehearsalCheck.failed("expected unavailable")
    }
    try expect(outageMethod == .bank, "outage kept bank method")
    try expect((try await api.getState()).balance == openingBalance - 2599, "outage balance")

    let recovered = try await rehearsal.submit(
      recipientId: "northline-studio",
      amountMinor: 500,
      method: .bank,
      note: "provider outage",
      scenario: .success,
      idempotencyKey: outageKey,
      maxAttempts: 1
    )
    guard case let .settled(recoveredResponse, _, recoveredMethod) = recovered else {
      throw RehearsalCheck.failed("expected recovery with the same key")
    }
    try expect(recoveredMethod == .bank, "recovery method")
    try expect(recoveredResponse.transaction?.provider == .worldpay, "recovery provider")
    try expect(recoveredResponse.transaction?.method == .bank, "recovery rail")
    try expect((try await api.getState()).balance == openingBalance - 2599 - 500, "recovery balance")

    let declined = try await rehearsal.submit(
      recipientId: "birch-bloom",
      amountMinor: 125,
      method: .card,
      note: "declined",
      scenario: .declined,
      idempotencyKey: UUID().uuidString,
      maxAttempts: 1
    )
    guard case let .declined(declinedResponse, _, _) = declined else {
      throw RehearsalCheck.failed("expected decline")
    }
    try expect(declinedResponse.code == "PAYMENT_DECLINED", "decline code")
    try expect((try await api.getState()).balance == openingBalance - 2599 - 500, "decline balance")

    let reset = try await api.reset()
    try expect(reset.ok && reset.state?.balance == openingBalance, "reset")
  }

  private static func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw RehearsalCheck.failed(message) }
  }
}
