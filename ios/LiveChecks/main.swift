import Foundation
import MeridianSDK

@main struct LiveChecks {
  static func main() async throws {
    let base = ProcessInfo.processInfo.environment["MERIDIAN_TEST_API"] ?? "http://127.0.0.1:8080/api/v1"
    let room = "swift-check-" + UUID().uuidString
    let client = try MeridianClient(baseURL: base, sessionId: room)
    let rehearsal = RehearsalSession(client: client)
    let before = try await client.getState()
    guard before.balance == 1248050 else { throw CheckError.failed("initial state") }
    let hydration = await rehearsal.hydrateCatalog()
    guard !hydration.degraded, hydration.source == .live else { throw CheckError.failed("catalog hydration") }
    let providers = hydration.catalog?.providers ?? []
    guard providers.map(\.id) == [.adyen, .worldpay] else { throw CheckError.failed("provider baseline") }
    guard providers.first?.methods == [.card], providers.last?.methods == [.bank] else { throw CheckError.failed("provider methods") }
    let penceKey = "k-" + UUID().uuidString
    let pence = PaymentAttempt(recipientId: "northline-studio", amountMinor: 1, method: .card, note: "One pence", scenario: .success, idempotencyKey: penceKey)
    guard case let .settled(paid, _) = await rehearsal.submit(pence),
          paid.ok, paid.state?.balance == 1248049, paid.transaction?.provider == .adyen
    else { throw CheckError.failed("one pence settlement") }
    guard case let .settled(replay, _) = await rehearsal.submit(pence),
          replay.transaction?.id == paid.transaction?.id, replay.state?.balance == 1248049
    else { throw CheckError.failed("idempotency") }
    let bankKey = "k-" + UUID().uuidString
    let down = PaymentAttempt(recipientId: "northline-studio", amountMinor: 100, method: .bank, note: "Unavailable", scenario: .unavailable, idempotencyKey: bankKey)
    guard case let .retryable(_, kept) = await rehearsal.submit(down),
          kept.method == .bank, kept.provider == .worldpay, kept.idempotencyKey == bankKey
    else { throw CheckError.failed("unavailable") }
    let unchanged = try await client.getState()
    guard unchanged.balance == 1248049 else { throw CheckError.failed("unavailable balance") }
    let recoveredAttempt = PaymentAttempt(recipientId: "northline-studio", amountMinor: 100, method: .bank, note: "Unavailable", scenario: .success, idempotencyKey: bankKey)
    guard case let .settled(recovered, _) = await rehearsal.submit(recoveredAttempt),
          recovered.ok, recovered.state?.balance == 1247949, recovered.transaction?.provider == .worldpay
    else { throw CheckError.failed("same-key bank retry") }
    let pendingAttempt = PaymentAttempt(recipientId: "northline-studio", amountMinor: 50, method: .card, note: "Pending", scenario: .pending, idempotencyKey: "k-" + UUID().uuidString)
    guard case let .pending(pending, _) = await rehearsal.submit(pendingAttempt),
          !pending.ok, pending.code == "PAYMENT_PENDING", pending.paymentId != nil
    else { throw CheckError.failed("pending") }
    let afterPending = try await client.getState()
    guard afterPending.balance == 1247949 else { throw CheckError.failed("pending balance") }
    let reset = try await client.reset()
    guard reset.ok, reset.state?.balance == 1248050 else { throw CheckError.failed("reset") }
    print("PASS: Swift rehearsal against Java API, catalog, GBP pence, idempotency, unavailable retry, pending and reset")
  }
  enum CheckError: Error { case failed(String) }
}
