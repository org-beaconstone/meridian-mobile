import Foundation
import MeridianSDK

@main
struct MeridianContractChecks {
  static func main() {
    var passed = 0
    var failed = 0

    func check(_ name: String, _ condition: Bool, _ detail: String = "") {
      if condition {
        print("PASS \(name)")
        passed += 1
      } else {
        print("FAIL \(name) \(detail)")
        failed += 1
      }
    }

    let root = contractsDirectory()
    let expectationsURL = root.appendingPathComponent("consumer-expectations.json")
    guard let expectationData = try? Data(contentsOf: expectationsURL),
          let document = try? JSONDecoder().decode(ExpectationFile.self, from: expectationData) else {
      print("FAIL load-expectations missing \(expectationsURL.path)")
      exit(1)
    }
    check("consumer-name", document.consumer == "meridian-mobile")

    for item in document.cases {
      let url = root.appendingPathComponent(item.fixture)
      guard let data = try? Data(contentsOf: url) else {
        check(item.fixture, false, "missing file")
        continue
      }
      let result: ContractResult
      switch item.kind {
      case "catalog":
        result = ConsumerContract.evaluateCatalog(data)
      case "intent":
        result = ConsumerContract.evaluatePaymentIntent(data)
      case "transaction":
        result = ConsumerContract.evaluateTransaction(data)
      default:
        check(item.fixture, false, "unknown kind")
        continue
      }
      if item.expect == "accepted" {
        var ok = result.accepted && result.code == "OK"
        if let currency = item.currency { ok = ok && result.currency == currency }
        if let legacy = item.legacy { ok = ok && result.legacyShape == legacy }
        if let amount = item.amountMinor { ok = ok && result.amountMinor == amount }
        if let provider = item.provider {
          ok = ok && (result.provider == provider || result.providerIds.contains(provider))
        }
        check(item.fixture, ok, "code=\(result.code) detail=\(result.detail) amount=\(result.amountMinor ?? -1)")
      } else {
        let detailOK = item.detailContains.map { result.detail.contains($0) } ?? true
        check(item.fixture, !result.accepted && result.code == item.expect && detailOK, "code=\(result.code) detail=\(result.detail)")
      }
    }

    check("legacy-and-object-amounts-match", amountsMatch(root))
    check("outbound-stays-integer-pence", outboundIsLegacyInteger())
    check("codable-legacy-catalog", codableCatalog(root, "catalog-legacy.json", shouldValidate: true))
    check("codable-gbp-catalog", codableCatalog(root, "catalog-gbp-object.json", shouldValidate: true))
    check("codable-eur-catalog-rejected", codableCatalogRejected(root, "catalog-eur.json"))
    check("codable-empty-id-rejected", codableCatalog(root, "catalog-empty-id.json", shouldValidate: false))
    check("codable-legacy-transaction", codableTransaction(root, "transaction-legacy.json", expected: 3500))
    check("codable-gbp-transaction", codableTransaction(root, "transaction-gbp-object.json", expected: 3500))
    check("codable-eur-transaction-rejected", eurTransactionRejected())
    check("note-too-long", noteTooLong())

    print("Contract checks passed \(passed) failed \(failed)")
    if failed > 0 { exit(1) }
  }
}

private struct ExpectationFile: Decodable {
  let consumer: String
  let cases: [ExpectationCase]
}

private struct ExpectationCase: Decodable {
  let fixture: String
  let kind: String
  let expect: String
  let currency: String?
  let legacy: Bool?
  let amountMinor: Int?
  let provider: String?
  let detailContains: String?
}

private func contractsDirectory() -> URL {
  var url = URL(fileURLWithPath: #filePath)
  for _ in 0..<4 { url.deleteLastPathComponent() }
  return url.appendingPathComponent("contracts")
}

private func amountsMatch(_ root: URL) -> Bool {
  guard let legacy = try? Data(contentsOf: root.appendingPathComponent("payment-intent-legacy.json")),
        let object = try? Data(contentsOf: root.appendingPathComponent("payment-intent-gbp-object.json")) else { return false }
  let left = ConsumerContract.evaluatePaymentIntent(legacy)
  let right = ConsumerContract.evaluatePaymentIntent(object)
  return left.accepted && right.accepted && left.amountMinor == 2599 && right.amountMinor == 2599 && left.legacyShape == true && right.legacyShape == false
}

private func outboundIsLegacyInteger() -> Bool {
  guard let data = try? ConsumerContract.encodeLegacyPaymentIntent(
    recipientId: "northline-studio",
    amountMinor: 2599,
    method: "card",
    note: "Desk lamp",
    scenario: "success"
  ),
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
  return object["amountMinor"] as? Int == 2599 && object["amount"] == nil && object["method"] as? String == "card"
}

private func codableCatalog(_ root: URL, _ name: String, shouldValidate: Bool) -> Bool {
  guard let data = try? Data(contentsOf: root.appendingPathComponent(name)) else { return false }
  do {
    let catalog = try JSONDecoder().decode(CatalogResponse.self, from: data)
    if shouldValidate {
      try catalog.assertConsumerContract()
      return catalog.currency == "GBP" && catalog.minorUnit == 2
    }
    do {
      try catalog.assertConsumerContract()
      return false
    } catch {
      return true
    }
  } catch {
    return false
  }
}

private func codableCatalogRejected(_ root: URL, _ name: String) -> Bool {
  guard let data = try? Data(contentsOf: root.appendingPathComponent(name)) else { return false }
  do {
    _ = try JSONDecoder().decode(CatalogResponse.self, from: data)
    return false
  } catch {
    return String(describing: error).contains("UNSUPPORTED_CURRENCY")
  }
}

private func codableTransaction(_ root: URL, _ name: String, expected: Int) -> Bool {
  guard let data = try? Data(contentsOf: root.appendingPathComponent(name)) else { return false }
  guard let transaction = try? JSONDecoder().decode(Transaction.self, from: data) else { return false }
  return transaction.amount == expected
}

private func eurTransactionRejected() -> Bool {
  let json = """
  {"id":"txn","reference":"R","recipientId":"northline-studio","name":"Northline Studio","category":"Shopping","amount":{"minor":3500,"currency":"EUR"},"date":"2026-09-05","provider":"adyen","method":"card","status":"completed","note":"Lamp"}
  """.data(using: .utf8)!
  do {
    _ = try JSONDecoder().decode(Transaction.self, from: json)
    return false
  } catch {
    return String(describing: error).contains("UNSUPPORTED_CURRENCY")
  }
}

private func noteTooLong() -> Bool {
  let note = String(repeating: "a", count: 201)
  let payload: [String: Any] = [
    "recipientId": "northline-studio",
    "amountMinor": 100,
    "method": "card",
    "note": note,
    "scenario": "success",
  ]
  guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return false }
  let result = ConsumerContract.evaluatePaymentIntent(data)
  return !result.accepted && result.code == "MALFORMED_INTENT" && result.detail == "note_too_long"
}
