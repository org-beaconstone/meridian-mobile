import Foundation
import MeridianSDK

@main
struct MeridianContractChecks {
  static func main() {
    run(file: "consumer-contract.json", label: "consumer contract") { text in
      MeridianSuites.contractFailures(json: text)
    }
  }
}

func run(file: String, label: String, suite: (String) -> [String]) {
  do {
    let text = try String(contentsOf: fixture(file), encoding: .utf8)
    let failures = suite(text)
    if failures.isEmpty {
      print("PASS: \(label)")
    } else {
      for failure in failures { print("FAIL: \(failure)") }
      exit(1)
    }
  } catch {
    print("FAIL: \(error)")
    exit(1)
  }
}

func fixture(_ name: String) -> URL {
  var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  for _ in 0..<8 {
    let candidate = dir.appendingPathComponent("shared").appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
    dir.deleteLastPathComponent()
  }
  return dir.appendingPathComponent("shared").appendingPathComponent(name)
}
