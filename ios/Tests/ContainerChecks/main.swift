import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MeridianSDK

@main
struct MeridianContainerChecks {
  static func main() async {
    guard let base = ProcessInfo.processInfo.environment["MERIDIAN_TEST_API"], !base.isEmpty else {
      fputs("MERIDIAN_TEST_API is required for the Spring Boot mock journey\n", stderr)
      exit(1)
    }
    let session = "swift-journey-" + UUID().uuidString
    do {
      try assertSimulatedScaFlows()
      let client = try MeridianClient(baseURL: base, sessionId: session)
      let health = try await client.getHealth()
      try expect(health.status == "UP" && health.simulation && health.service == "meridian-api", "health")
      let catalog = try await client.getCatalog()
      let ids = Set(catalog.providers.map(\.id))
      try expect(ids == Set([ProviderId.adyen, ProviderId.worldpay]), "providers")
      try expect(catalog.providers.first { $0.id == .adyen }?.methods == [.card], "adyen methods")
      try expect(catalog.providers.first { $0.id == .worldpay }?.methods == [.bank], "worldpay methods")
      try expect(try await client.getState().balance == 1_248_050, "opening balance")

      let minimum = try await client.submitPayment(recipientId: "northline-studio", amountMinor: gbpMinMinor, method: .card, note: "boundary-0.01", scenario: .success, idempotencyKey: "boundary-min")
      try expect(minimum.ok && minimum.state?.balance == 1_248_049, "£0.01 card payment \(minimum.error ?? "")")
      try expect(minimum.transaction?.amount == gbpMinMinor && minimum.transaction?.provider == .adyen && minimum.transaction?.method == .card, "adyen boundary")
      let minimumId = minimum.transaction?.id

      let middle = try await client.submitPayment(recipientId: "northline-studio", amountMinor: 100, method: .card, note: "mid", scenario: .success, idempotencyKey: "mid-100")
      try expect(middle.ok && middle.state?.balance == 1_247_949, "second debit")

      let replay = try await client.submitPayment(recipientId: "northline-studio", amountMinor: gbpMinMinor, method: .card, note: "boundary-0.01", scenario: .success, idempotencyKey: "boundary-min")
      try expect(replay.ok && replay.transaction?.id == minimumId && replay.state?.balance == 1_247_949, "idempotency replay")

      let maximum = try await client.submitPayment(recipientId: "northline-studio", amountMinor: gbpMaxMinor, method: .bank, note: "boundary-10000.00", scenario: .success, idempotencyKey: "boundary-max")
      try expect(maximum.ok && maximum.state?.balance == 247_949, "£10,000.00 bank payment \(maximum.error ?? "") balance \(maximum.state?.balance ?? -1)")
      try expect(maximum.transaction?.amount == gbpMaxMinor && maximum.transaction?.provider == .worldpay && maximum.transaction?.method == .bank, "worldpay boundary")
      let maximumId = maximum.transaction?.id
      let maximumReplay = try await client.submitPayment(recipientId: "northline-studio", amountMinor: gbpMaxMinor, method: .bank, note: "boundary-10000.00", scenario: .success, idempotencyKey: "boundary-max")
      try expect(maximumReplay.ok && maximumReplay.transaction?.id == maximumId && maximumReplay.state?.balance == 247_949, "max replay")

      let pending = try await client.submitPayment(recipientId: "northline-studio", amountMinor: 50, method: .card, note: "pending", scenario: .pending, idempotencyKey: "pending-key")
      try expect(!pending.ok && pending.code == "PAYMENT_PENDING" && pending.paymentId != nil, "pending")
      try expect(try await client.getState().balance == 247_949, "pending balance")

      let declined = try await client.submitPayment(recipientId: "northline-studio", amountMinor: 50, method: .card, note: "declined", scenario: .declined, idempotencyKey: "declined-key")
      try expect(!declined.ok && declined.code == "PAYMENT_DECLINED", "declined")
      try expect(try await client.getState().balance == 247_949, "declined balance")

      let mismatch = try await client.submitPayment(recipientId: "northline-studio", amountMinor: 2, method: .bank, note: "boundary-10000.00", scenario: .success, idempotencyKey: "boundary-max")
      try expect(!mismatch.ok, "idempotency mismatch")
      try expect(try await client.getState().balance == 247_949, "mismatch balance")

      let reset = try await client.reset()
      try expect(reset.ok && reset.state?.balance == 1_248_050, "reset")
      print("PASS: Swift desktop runner against Spring Boot mock, boundaries, idempotency, SCA")
    } catch {
      fputs("FAIL: \(error)\n", stderr)
      exit(1)
    }
  }

  static func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckError.failed(message) }
  }

  enum CheckError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case let .failed(message): return message } }
  }
}
