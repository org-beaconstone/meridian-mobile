import Foundation
import MeridianSDK

@main
struct MeridianScenarioChecks {
  static func main() {
    do {
      let text = try String(contentsOf: scenarioFixture("cross-platform-scenarios.json"), encoding: .utf8)
      let failures = MeridianSuites.scenarioFailures(json: text)
      if failures.isEmpty {
        print("PASS: cross-platform scenarios")
      } else {
        for failure in failures { print("FAIL: \(failure)") }
        exit(1)
      }
    } catch {
      print("FAIL: \(error)")
      exit(1)
    }
  }
}

func scenarioFixture(_ name: String) -> URL {
  var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  for _ in 0..<8 {
    let candidate = dir.appendingPathComponent("shared").appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
    dir.deleteLastPathComponent()
  }
  return dir.appendingPathComponent("shared").appendingPathComponent(name)
}
