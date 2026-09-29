import Foundation
import MeridianSDK

@main struct LiveChecks {
  static func main() async throws {
    let base = ProcessInfo.processInfo.environment["MERIDIAN_TEST_API"] ?? "http://127.0.0.1:8080/api/v1"
    let room = "swift-check-" + UUID().uuidString
    let api = try MeridianClient(baseURL: base, sessionId: room)
    try await RehearsalJourney.run(api: api)
    print("PASS: Swift rehearsal journey against the Java contract, catalogue, GBP pence, idempotency, pending, outage retry and reset")
  }
}
