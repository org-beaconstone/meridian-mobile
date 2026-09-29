import Foundation

private let uuidV4Pattern =
  "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"

/// UUID version 4 idempotency key for one payment attempt.
public func newPaymentIdempotencyKey() -> String {
  UUID().uuidString.lowercased()
}

public func isUuidV4(_ value: String) -> Bool {
  value.range(of: uuidV4Pattern, options: .regularExpression) != nil
}

/// Retry policy for ambiguous gateway responses from POST /payments.
/// The payment method and idempotency key stay on the original attempt.
public enum GatewayRetry {
  public static let maxAttempts = 3
  public static let initialBackoffMs: UInt64 = 200
  public static let maxBackoffMs: UInt64 = 1_600

  public static func isTimeout(_ statusCode: Int) -> Bool {
    statusCode == 502 || statusCode == 504
  }

  public static func backoffMillis(
    retryIndex: Int,
    randomUnit: Double,
    initialMs: UInt64 = initialBackoffMs,
    maxMs: UInt64 = maxBackoffMs
  ) -> UInt64 {
    precondition(retryIndex >= 0, "retryIndex must be >= 0")
    var delayMs = initialMs
    if retryIndex > 0 {
      for _ in 0..<retryIndex {
        delayMs = delayMs > maxMs / 2 ? maxMs : min(delayMs * 2, maxMs)
      }
    }
    let unit = min(1, max(0, randomUnit))
    let jitter = UInt64(unit * Double(initialMs / 2))
    return delayMs + jitter
  }
}

/// Submits one GBP payment to POST /payments.
/// HTTP 502 and 504 retry with exponential backoff. The rehearsal session,
/// idempotency key, amount, and method are the same on every attempt.
public struct PaymentOrchestrator {
  private let client: MeridianClient
  private let maxAttempts: Int
  private let initialBackoffMs: UInt64
  private let sleep: @Sendable (UInt64) async -> Void
  private let randomUnit: @Sendable () -> Double

  public init(
    client: MeridianClient,
    maxAttempts: Int = GatewayRetry.maxAttempts,
    initialBackoffMs: UInt64 = GatewayRetry.initialBackoffMs,
    sleep: @escaping @Sendable (UInt64) async -> Void = { milliseconds in
      try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    },
    randomUnit: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
  ) {
    self.client = client
    self.maxAttempts = maxAttempts
    self.initialBackoffMs = initialBackoffMs
    self.sleep = sleep
    self.randomUnit = randomUnit
  }

  public func submit(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = .success,
    idempotencyKey: String,
    onRetry: @escaping @Sendable (Int, Int) async -> Void = { _, _ in }
  ) async throws -> PaymentResponse {
    guard isUuidV4(idempotencyKey) else {
      throw MeridianError.validationError("Idempotency key must be a UUID v4")
    }
    guard maxAttempts >= 1 else {
      throw MeridianError.validationError("At least one attempt is required")
    }

    var attempt = 1
    while true {
      do {
        return try await client.submitPayment(
          recipientId: recipientId,
          amountMinor: amountMinor,
          method: method,
          note: note,
          scenario: scenario,
          idempotencyKey: idempotencyKey
        )
      } catch MeridianError.httpError(let statusCode, _) where GatewayRetry.isTimeout(statusCode) {
        if attempt >= maxAttempts {
          throw MeridianError.httpError(
            statusCode: statusCode,
            message: "Gateway timed out. Retry keeps this payment on the same method and the same key."
          )
        }
        await onRetry(attempt + 1, statusCode)
        await sleep(
          GatewayRetry.backoffMillis(
            retryIndex: attempt - 1,
            randomUnit: randomUnit(),
            initialMs: initialBackoffMs
          )
        )
        attempt += 1
      }
    }
  }
}
