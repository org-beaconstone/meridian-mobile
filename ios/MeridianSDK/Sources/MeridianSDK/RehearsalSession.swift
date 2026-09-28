import Foundation

/// Client rehearsal against the shared Java mock.
/// Amounts stay integer GBP pence. Card stays Adyen and bank stays Worldpay.
/// A gateway timeout or provider-unavailable response retries the same idempotency key and method.
/// HTTP 202 is pending confirmation: the payment is not settled and the key is kept.
public actor RehearsalSession {
  private let client: MeridianClient
  private var lastCatalog: CatalogResponse?

  public init(client: MeridianClient) {
    self.client = client
  }

  public func hydrateCatalog() async -> CatalogHydration {
    do {
      let fresh = try await client.getCatalog()
      lastCatalog = fresh
      return CatalogHydration(catalog: fresh, source: .live, degraded: false)
    } catch {
      if let cached = lastCatalog {
        return CatalogHydration(catalog: cached, source: .lastKnownGood, degraded: true)
      }
      return CatalogHydration(catalog: nil, source: .empty, degraded: true)
    }
  }

  public func submit(_ attempt: PaymentAttempt) async -> PaymentOutcome {
    if let problem = validate(attempt) {
      return .rejected(message: problem, attempt: attempt)
    }
    // Provider is fixed by the selected method and is not sent as a switchable field.
    _ = baselineProvider(for: attempt.method)
    do {
      let submission = try await client.submitPaymentDetailed(
        recipientId: attempt.recipientId,
        amountMinor: attempt.amountMinor,
        method: attempt.method,
        note: attempt.note,
        scenario: attempt.scenario,
        idempotencyKey: attempt.idempotencyKey
      )
      return classify(submission, attempt: attempt)
    } catch let error as MeridianError {
      switch error {
      case let .networkError(message), let .decodingError(message):
        return .retryable(message: message, attempt: attempt)
      case let .httpError(status, message) where (status == 408 || status >= 500):
        return .retryable(message: message, attempt: attempt)
      case let .httpError(_, message):
        return .rejected(message: message, attempt: attempt)
      default:
        return .rejected(message: error.localizedDescription, attempt: attempt)
      }
    } catch {
      return .retryable(message: String(describing: error), attempt: attempt)
    }
  }

  private func validate(_ attempt: PaymentAttempt) -> String? {
    let keyPattern = "^[A-Za-z0-9_-]{1,100}$"
    guard attempt.idempotencyKey.range(of: keyPattern, options: .regularExpression) != nil else {
      return "Invalid Idempotency-Key"
    }
    guard attempt.amountMinor >= 1 && attempt.amountMinor <= 1_000_000 else {
      return "Amount must be integer pence from 1 to 1000000"
    }
    guard attempt.note.count <= 200 else {
      return "Reference exceeds 200 characters"
    }
    return nil
  }

  private func classify(_ submission: PaymentSubmission, attempt: PaymentAttempt) -> PaymentOutcome {
    let status = submission.statusCode
    let code = submission.body.code
    if status == 202 || code == "PAYMENT_PENDING" {
      return .pending(response: submission.body, attempt: attempt)
    }
    if status == 503 || code == "PROVIDER_UNAVAILABLE" {
      return .retryable(
        message: submission.body.error ?? "Provider unavailable. Retry the same payment.",
        attempt: attempt
      )
    }
    if status == 422 || code == "PAYMENT_DECLINED" {
      return .declined(response: submission.body, attempt: attempt)
    }
    if status == 409 {
      return .rejected(
        message: submission.body.error ?? "Idempotency key belongs to a different payment",
        attempt: attempt
      )
    }
    if submission.body.ok && (200..<300).contains(status) {
      return .settled(response: submission.body, attempt: attempt)
    }
    if status >= 500 {
      return .retryable(message: submission.body.error ?? "HTTP \(status)", attempt: attempt)
    }
    return .rejected(message: submission.body.error ?? "HTTP \(status)", attempt: attempt)
  }
}

public enum CatalogSource: String {
  case live
  case lastKnownGood
  case empty
}

public struct CatalogHydration {
  public let catalog: CatalogResponse?
  public let source: CatalogSource
  public let degraded: Bool

  public init(catalog: CatalogResponse?, source: CatalogSource, degraded: Bool) {
    self.catalog = catalog
    self.source = source
    self.degraded = degraded
  }
}

public struct PaymentAttempt: Equatable {
  public let recipientId: String
  public let amountMinor: Int
  public let method: PaymentMethod
  public let note: String
  public let scenario: Scenario
  public let idempotencyKey: String

  public var provider: ProviderId { baselineProvider(for: method) }

  public init(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String,
    scenario: Scenario,
    idempotencyKey: String
  ) {
    self.recipientId = recipientId
    self.amountMinor = amountMinor
    self.method = method
    self.note = note
    self.scenario = scenario
    self.idempotencyKey = idempotencyKey
  }
}

public enum PaymentOutcome {
  case settled(response: PaymentResponse, attempt: PaymentAttempt)
  case pending(response: PaymentResponse, attempt: PaymentAttempt)
  case declined(response: PaymentResponse, attempt: PaymentAttempt)
  case retryable(message: String, attempt: PaymentAttempt)
  case rejected(message: String, attempt: PaymentAttempt)
}
