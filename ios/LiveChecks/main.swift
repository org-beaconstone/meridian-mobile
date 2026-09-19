import Foundation
import MeridianSDK

@main struct LiveChecks {
  static func main() async throws {
    let base=ProcessInfo.processInfo.environment["MERIDIAN_TEST_API"] ?? "http://127.0.0.1:8080/api/v1"
    let room="swift-check-"+UUID().uuidString
    let api=try MeridianClient(baseURL:base,sessionId:room)
    let before=try await api.getState()
    guard before.balance==1248050 else {throw CheckError.failed("initial state")}
    let catalog=try await api.getCatalog()
    guard catalog.providers.count==2 else {throw CheckError.failed("provider count")}
    let key=UUID().uuidString
    let payment=try await api.submitPayment(recipientId:"northline-studio",amountMinor:2599,method:.card,note:"Swift native transport check",idempotencyKey:key)
    guard payment.ok, payment.state?.balance==1245451, payment.transaction != nil else {throw CheckError.failed("payment response")}
    let duplicate=try await api.submitPayment(recipientId:"northline-studio",amountMinor:2599,method:.card,note:"Swift native transport check",idempotencyKey:key)
    guard duplicate.ok, duplicate.state?.balance==1245451 else {throw CheckError.failed("idempotency")}
    let pending=try await api.submitPayment(recipientId:"northline-studio",amountMinor:100,method:.card,note:"pending",scenario:.pending,idempotencyKey:UUID().uuidString)
    guard !pending.ok,pending.code=="PAYMENT_PENDING",pending.paymentId != nil else {throw CheckError.failed("pending")}
    let unchanged=try await api.getState()
    guard unchanged.balance==1245451 else {throw CheckError.failed("pending balance")}
    let reset=try await api.reset()
    guard reset.ok,reset.state?.balance==1248050 else {throw CheckError.failed("reset")}
    print("PASS: Swift SDK real Java transport, shared contract, idempotency, pending, reset")
  }
  enum CheckError: Error {case failed(String)}
}
