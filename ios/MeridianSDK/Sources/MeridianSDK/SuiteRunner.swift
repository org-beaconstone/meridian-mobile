import Foundation

public enum MeridianSuites {
  public static func contractFailures(json: String) -> [String] {
    var failures: [String] = []
    if let live = liveCatalogRoundTripFailure() { failures.append(live) }
    guard let items = caseList(json) else { return failures + ["contract has no cases"] }
    if items.isEmpty { failures.append("contract has no cases") }
    for item in items {
      let id = Json.string(item["id"]) ?? "missing-id"
      switch Json.string(item["type"]) {
      case "money": checkMoney(id, item, &failures)
      case "catalog": checkCatalog(id, item, &failures)
      case "payment-intent": checkIntent(id, item, &failures)
      default: failures.append("\(id) unknown contract type")
      }
    }
    return failures
  }

  public static func scenarioFailures(json: String) -> [String] {
    var failures: [String] = []
    guard let items = caseList(json) else { return ["scenarios have no cases"] }
    if items.isEmpty { failures.append("scenarios have no cases") }
    for item in items {
      let id = Json.string(item["id"]) ?? "missing-id"
      switch Json.string(item["type"]) {
      case "format":
        let display = formatMoney(currency: Json.string(item["currency"]) ?? "", minor: Json.int(item["minor"]) ?? 0, exponent: Json.int(item["exponent"]) ?? 0)
        if display != Json.string(item["display"]) { failures.append("\(id) display \(display)") }
      case "parse-amount": checkParse(id, item, &failures)
      case "cache": checkCache(id, item, &failures)
      case "idempotency": checkIdempotency(id, item, &failures)
      case "deep-link": checkDeepLink(id, item, &failures)
      case "catalog": checkCatalog(id, item, &failures)
      case "accessibility": checkAccessibility(id, item, &failures)
      case "font-scale": checkFont(id, item, &failures)
      case "rtl": checkRtl(id, item, &failures)
      default: failures.append("\(id) unknown scenario type")
      }
    }
    return failures
  }
}

private func caseList(_ json: String) -> [[String: Any]]? {
  guard let data = json.data(using: .utf8),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let raw = Json.array(root["cases"]) else { return nil }
  let items = raw.compactMap { Json.object($0) }
  return items.count == raw.count ? items : nil
}

private func checkMoney(_ id: String, _ item: [String: Any], _ failures: inout [String]) {
  guard let expect = Json.object(item["expect"]) else { failures.append("\(id) missing expect"); return }
  switch decodeMoney(item["value"] ?? NSNull()) {
  case let .failure(error):
    if Json.bool(expect["ok"]) == true { failures.append("\(id) unexpected \(error.code)") }
    else if error.code != Json.string(expect["code"]) { failures.append("\(id) code \(error.code)") }
  case let .success(money):
    guard Json.bool(expect["ok"]) == true else { failures.append("\(id) expected \(Json.string(expect["code"]) ?? "rejection")"); return }
    if money.currency != Json.string(expect["currency"]) { failures.append("\(id) currency") }
    if money.minor != Json.int(expect["minor"]) { failures.append("\(id) minor") }
    if money.exponent != Json.int(expect["exponent"]) { failures.append("\(id) exponent") }
    if let display = Json.string(expect["display"]), money.display != display { failures.append("\(id) display \(money.display)") }
    if !optionalIntEquals(money.gbpPence, expect["gbpPence"]) { failures.append("\(id) gbpPence") }
  }
}

private func checkCatalog(_ id: String, _ item: [String: Any], _ failures: inout [String]) {
  guard let expect = Json.object(item["expect"]) else { failures.append("\(id) missing expect"); return }
  switch decodeCatalog(item["payload"] ?? NSNull()) {
  case let .failure(error):
    if Json.bool(expect["ok"]) == true { failures.append("\(id) unexpected \(error.code)") }
    else if error.code != Json.string(expect["code"]) { failures.append("\(id) code \(error.code)") }
  case let .success(document):
    guard Json.bool(expect["ok"]) == true else { failures.append("\(id) expected rejection"); return }
    if let demoDate = Json.string(expect["demoDate"]), document.demoDate != demoDate { failures.append("\(id) demoDate") }
    if let count = Json.int(expect["recipientCount"]), document.recipients.count != count { failures.append("\(id) recipientCount") }
    if let raw = Json.array(expect["providerIds"]) {
      let ids = raw.compactMap { Json.string($0) }
      if document.providers.map(\.id) != ids { failures.append("\(id) providers \(document.providers.map(\.id))") }
    }
    if let prices = Json.array(expect["prices"]) {
      for priceValue in prices {
        guard let price = Json.object(priceValue) else { continue }
        let recipientId = Json.string(price["id"]) ?? ""
        guard let recipient = document.recipients.first(where: { $0.id == recipientId }) else {
          failures.append("\(id) missing recipient")
          continue
        }
        if Json.bool(price["absent"]) == true {
          if recipient.price != nil { failures.append("\(id) price present") }
          continue
        }
        guard let money = recipient.price else { failures.append("\(id) price missing"); continue }
        if money.currency != Json.string(price["currency"]) || money.minor != Json.int(price["minor"]) || money.exponent != Json.int(price["exponent"]) {
          failures.append("\(id) price fields")
        }
        if let display = Json.string(price["display"]), money.display != display { failures.append("\(id) price display") }
        if price["gbpPence"] != nil && !optionalIntEquals(money.gbpPence, price["gbpPence"]) { failures.append("\(id) price gbp") }
      }
    }
  }
}

private func checkIntent(_ id: String, _ item: [String: Any], _ failures: inout [String]) {
  guard let expect = Json.object(item["expect"]) else { failures.append("\(id) missing expect"); return }
  switch decodePaymentIntent(item["payload"] ?? NSNull()) {
  case let .failure(error):
    if Json.bool(expect["ok"]) == true { failures.append("\(id) unexpected \(error.code)") }
    else if error.code != Json.string(expect["code"]) { failures.append("\(id) code \(error.code)") }
  case let .success(intent):
    guard Json.bool(expect["ok"]) == true else { failures.append("\(id) expected rejection"); return }
    if let currency = Json.string(expect["currency"]), intent.money.currency != currency { failures.append("\(id) currency") }
    if let minor = Json.int(expect["minor"]), intent.money.minor != minor { failures.append("\(id) minor") }
    if let exponent = Json.int(expect["exponent"]), intent.money.exponent != exponent { failures.append("\(id) exponent") }
    if let display = Json.string(expect["display"]), intent.money.display != display { failures.append("\(id) display") }
    if expect["gbpPence"] != nil && !optionalIntEquals(intent.money.gbpPence, expect["gbpPence"]) { failures.append("\(id) gbpPence") }
    if let method = Json.string(expect["method"]), intent.method != method { failures.append("\(id) method") }
    if let note = Json.string(expect["note"]), intent.note != note { failures.append("\(id) note") }
    if let scenario = Json.string(expect["scenario"]), intent.scenario != scenario { failures.append("\(id) scenario") }
    if let submittable = Json.bool(expect["submittable"]), intent.submittable != submittable { failures.append("\(id) submittable") }
    if expect["wireAmountMinor"] != nil && !optionalIntEquals(intent.wireAmountMinor, expect["wireAmountMinor"]) { failures.append("\(id) wire") }
  }
}

private func checkParse(_ id: String, _ item: [String: Any], _ failures: inout [String]) {
  let (pence, error) = parseAmount(Json.string(item["input"]) ?? "")
  if let expected = Json.string(item["error"]) {
    if pence != nil || error != expected { failures.append("\(id) parse \(pence.map(String.init) ?? "null") \(error ?? "null")") }
  } else if pence != Json.int(item["pence"]) || error != nil {
    failures.append("\(id) parse \(pence.map(String.init) ?? "null") \(error ?? "null")")
  }
}

private func checkCache(_ id: String, _ item: [String: Any], _ failures: inout [String]) {
  switch decodeCatalog(item["catalog"] ?? NSNull()) {
  case let .failure(error): failures.append("\(id) catalog \(error.code)")
  case let .success(document):
    var cache = CatalogCache()
    let ttl = Json.int64(item["ttl"]) ?? 0
    for stepValue in Json.array(item["steps"]) ?? [] {
      guard let step = Json.object(stepValue) else { continue }
      switch Json.string(step["op"]) {
      case "store":
        cache.store(session: Json.string(step["session"]) ?? "", document: document, at: Json.int64(step["at"]) ?? 0, ttlMillis: ttl)
      case "read":
        let actual = cache.read(session: Json.string(step["session"]) ?? "", at: Json.int64(step["at"]) ?? 0)
        if actual != Json.string(step["expect"]) { failures.append("\(id) read@\(actual)") }
      default:
        failures.append("\(id) unknown cache op")
      }
    }
  }
}

private func checkIdempotency(_ id: String, _ item: [String: Any], _ failures: inout [String]) {
  var journal = IdempotencyJournal()
  for stepValue in Json.array(item["steps"]) ?? [] {
    guard let step = Json.object(stepValue) else { continue }
    switch Json.string(step["op"]) {
    case "begin":
      let error = journal.begin(
        sessionId: Json.string(step["session"]) ?? "",
        key: Json.string(step["key"]) ?? "",
        recipientId: Json.string(step["recipientId"]) ?? "",
        currency: Json.string(step["currency"]) ?? "",
        minor: Json.int(step["minor"]) ?? 0,
        exponent: Json.int(step["exponent"]) ?? 0,
        method: Json.string(step["method"]) ?? "",
        note: Json.string(step["note"]) ?? ""
      )
      expectError(id, step, error, &failures)
    case "markUncertain":
      if let error = journal.markUncertain() { failures.append("\(id) markUncertain \(error.code)") }
    case "markCompleted":
      if let error = journal.markCompleted() { failures.append("\(id) markCompleted \(error.code)") }
    case "discardDraft":
      expectError(id, step, journal.discardDraft(), &failures)
    case "retry":
      let result = journal.retry(
        note: Json.string(step["note"]) ?? "",
        recipientId: Json.string(step["recipientId"]),
        minor: Json.int(step["minor"]),
        method: Json.string(step["method"]),
        currency: Json.string(step["currency"])
      )
      switch result {
      case let .failure(error):
        if Json.string(step["expect"]) != "rejected" || error.code != Json.string(step["code"]) { failures.append("\(id) retry \(error.code)") }
      case let .success(key):
        if Json.string(step["expect"]) != "accepted" || key != Json.string(step["key"]) { failures.append("\(id) retry accepted \(key)") }
      }
    case "kill":
      journal.kill()
    case "restore":
      journal = IdempotencyJournal.restore(Json.string(step["snapshot"]) ?? "")
    case "expect":
      if journal.status != Json.string(step["status"]) { failures.append("\(id) status \(journal.status)") }
      let expectedKey = Json.isNull(step["key"]) ? nil : Json.string(step["key"])
      if journal.key != expectedKey { failures.append("\(id) key \(journal.key ?? "nil")") }
    case "expectSnapshot":
      if journal.snapshot() != Json.string(step["snapshot"]) { failures.append("\(id) snapshot \(journal.snapshot())") }
    default:
      failures.append("\(id) unknown idempotency op")
    }
  }
}

private func checkDeepLink(_ id: String, _ item: [String: Any], _ failures: inout [String]) {
  var guardState = ReturnStateGuard()
  for stepValue in Json.array(item["steps"]) ?? [] {
    guard let step = Json.object(stepValue) else { continue }
    switch Json.string(step["op"]) {
    case "select":
      guardState.select(session: Json.string(step["session"]) ?? "")
    case "arm":
      expectError(id, step, guardState.arm(sessionId: Json.string(step["session"]) ?? "", paymentId: Json.string(step["paymentId"]) ?? "", nonce: Json.string(step["nonce"]) ?? "", exp: Json.int64(step["exp"]) ?? 0, key: Json.string(step["key"]) ?? ""), &failures)
    case "open":
      expectDecoded(id, step, guardState.open(paymentId: Json.string(step["paymentId"]) ?? "", nonce: Json.string(step["nonce"]) ?? "", now: Json.int64(step["now"]) ?? 0), &failures)
    case "openUrl":
      expectDecoded(id, step, guardState.openUrl(Json.string(step["url"]) ?? "", now: Json.int64(step["now"]) ?? 0), &failures)
    case "expectSelected":
      if guardState.selectedSession != Json.string(step["session"]) { failures.append("\(id) selected \(guardState.selectedSession)") }
    default:
      failures.append("\(id) unknown deep-link op")
    }
  }
}

private func checkAccessibility(_ id: String, _ item: [String: Any], _ failures: inout [String]) {
  let expected = Json.array(item["elements"]) ?? []
  if AccessibilityCatalog.nodes.count != expected.count { failures.append("\(id) node count") }
  let minPt = Json.int(item["minTouchTargetPt"]) ?? 0
  let minDp = Json.int(item["minTouchTargetDp"]) ?? 0
  for (index, nodeValue) in expected.enumerated() {
    guard let node = Json.object(nodeValue) else { continue }
    guard index < AccessibilityCatalog.nodes.count else { failures.append("\(id) node \(index)"); continue }
    let actual = AccessibilityCatalog.nodes[index]
    if actual.id != Json.string(node["id"]) { failures.append("\(id) node \(index)"); continue }
    if actual.voiceOverLabel != Json.string(node["voiceOverLabel"]) { failures.append("\(id) voiceover \(actual.id)") }
    if actual.talkBackDescription != Json.string(node["talkBackDescription"]) { failures.append("\(id) talkback \(actual.id)") }
    let traits = (Json.array(node["traits"]) ?? []).compactMap { Json.string($0) }
    if actual.traits != traits { failures.append("\(id) traits \(actual.id)") }
    if actual.textDirection != Json.string(node["textDirection"]) { failures.append("\(id) direction \(actual.id)") }
    if actual.scalesWithFont != (Json.bool(node["scalesWithFont"]) == true) { failures.append("\(id) scale \(actual.id)") }
    if actual.mirrorsInRtl != (Json.bool(node["mirrorsInRtl"]) == true) { failures.append("\(id) mirror \(actual.id)") }
    if actual.minTouchTargetPt != minPt || actual.minTouchTargetDp != minDp { failures.append("\(id) target \(actual.id)") }
  }
}

private func checkFont(_ id: String, _ item: [String: Any], _ failures: inout [String]) {
  let height = buttonHeight(platform: Json.string(item["platform"]) ?? "", fontScale: Json.double(item["fontScale"]) ?? 0)
  if abs(height - (Json.double(item["minHeight"]) ?? -1)) > 0.001 { failures.append("\(id) height \(height)") }
  let lines = wrappedLines(text: Json.string(item["text"]) ?? "", fontScale: Json.double(item["fontScale"]) ?? 0, containerWidth: Json.double(item["containerWidth"]) ?? 0, baseSize: Json.double(item["baseSize"]) ?? 0)
  if lines != Json.int(item["lines"]) { failures.append("\(id) lines \(lines)") }
}

private func checkRtl(_ id: String, _ item: [String: Any], _ failures: inout [String]) {
  let direction = Json.string(item["direction"]) ?? ""
  let edges = horizontalEdges(direction: direction)
  if edges.start != Json.string(item["startEdge"]) || edges.end != Json.string(item["endEdge"]) { failures.append("\(id) edges") }
  if AccessibilityCatalog.node("balance")?.textDirection != Json.string(item["amountDirection"]) { failures.append("\(id) amount direction") }
  for nodeId in (Json.array(item["mirrored"]) ?? []).compactMap({ Json.string($0) }) {
    let node = AccessibilityCatalog.node(nodeId)
    if node == nil || !(node!.mirrorsInRtl && direction == "rtl") { failures.append("\(id) mirrored \(nodeId)") }
  }
  for nodeId in (Json.array(item["notMirrored"]) ?? []).compactMap({ Json.string($0) }) {
    let node = AccessibilityCatalog.node(nodeId)
    let active = node?.mirrorsInRtl == true && direction == "rtl"
    if node == nil || active { failures.append("\(id) notMirrored \(nodeId)") }
  }
}

private func expectError(_ id: String, _ step: [String: Any], _ error: ContractError?, _ failures: inout [String]) {
  let expect = Json.string(step["expect"]) ?? "accepted"
  if expect == "accepted" && error != nil { failures.append("\(id) \(Json.string(step["op"]) ?? "op") \(error?.code ?? "")") }
  if expect == "rejected" && error?.code != Json.string(step["code"]) { failures.append("\(id) \(Json.string(step["op"]) ?? "op") \(error?.code ?? "nil")") }
}

private func expectDecoded(_ id: String, _ step: [String: Any], _ result: Result<String, ContractError>, _ failures: inout [String]) {
  switch result {
  case let .failure(error):
    if Json.string(step["expect"]) != "rejected" || error.code != Json.string(step["code"]) {
      failures.append("\(id) \(Json.string(step["op"]) ?? "op") \(error.code)")
    }
  case let .success(key):
    if Json.string(step["expect"]) != "accepted" || key != Json.string(step["key"]) {
      failures.append("\(id) \(Json.string(step["op"]) ?? "op") \(key)")
    }
  }
}

private func optionalIntEquals(_ actual: Int?, _ expected: Any?) -> Bool {
  if Json.isNull(expected) { return actual == nil }
  return actual == Json.int(expected)
}
