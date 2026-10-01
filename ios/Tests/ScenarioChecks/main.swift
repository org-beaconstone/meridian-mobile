import Foundation
import MeridianSDK

@main
struct MeridianScenarioChecks {
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

    check("money-formatting", moneyFormatting())
    check("cache-expiry", cacheExpiry())
    check("idempotency-persistence", idempotencyPersistence())
    check("process-death", processDeath())
    check("provider-sticky-on-timeout", providerSticky())
    check("session-preserved", sessionPreserved())
    check("replayed-deep-link", replayedDeepLink())
    check("expired-return-state", expiredReturn())
    check("malformed-catalog", malformedCatalog())
    check("voiceover-label", voiceOver())
    check("talkback-label", talkBack())
    check("large-font-scaling", largeFont())
    check("rtl-layout", rtlLayout())
    check("uncertain-status-codes", uncertainStatus())

    print("Scenario checks passed \(passed) failed \(failed)")
    if failed > 0 { exit(1) }
  }
}

private func model() -> PaymentScreenModel {
  var screen = PaymentScreenModel(endpoint: "http://127.0.0.1:8080/api/v1", room: "room-one")
  var sequence = 0
  screen.keyFactory = {
    sequence += 1
    return "key-\(sequence)"
  }
  return screen
}

private func moneyFormatting() -> Bool {
  money(1) == "£0.01"
    && money(100) == "£1.00"
    && money(1050) == "£10.50"
    && money(1_000_000) == "£10,000.00"
    && money(1_248_050) == "£12,480.50"
    && money(-1050) == "-£10.50"
}

private func cacheExpiry() -> Bool {
  var screen = model()
  let catalog = CachedCatalog(demoDate: "2026-09-18", currency: "GBP", recipientIds: ["northline-studio"], providerIds: ["adyen", "worldpay"])
  screen.rememberCatalog(catalog, nowMillis: 1_000)
  guard screen.cachedCatalog(nowMillis: 1_000, ttlMillis: 5_000) == catalog else { return false }
  guard screen.cachedCatalog(nowMillis: 5_999, ttlMillis: 5_000) == catalog else { return false }
  guard screen.cachedCatalog(nowMillis: 6_000, ttlMillis: 5_000) == nil else { return false }
  guard let restored = PaymentScreenModel.restore(screen.checkpointJSON()) else { return false }
  return restored.cachedCatalog(nowMillis: 2_000, ttlMillis: 5_000) == catalog
    && restored.cachedCatalog(nowMillis: 6_000, ttlMillis: 5_000) == nil
}

private func idempotencyPersistence() -> Bool {
  var screen = model()
  guard screen.connect() else { return false }
  screen.amountInput = "10.50"
  screen.method = .card
  guard screen.review() else { return false }
  let key = screen.submitInstruction()?.idempotencyKey
  screen.markUncertain(reason: "network")
  guard screen.review() else { return false }
  guard screen.submitInstruction()?.idempotencyKey == key else { return false }
  guard screen.requestHeaders(includeIdempotency: true)["Idempotency-Key"] == key else { return false }
  screen.edit()
  return screen.submitInstruction()?.idempotencyKey == key && screen.reviewing
}

private func processDeath() -> Bool {
  var screen = model()
  guard screen.connect() else { return false }
  screen.amountInput = "25.99"
  screen.note = "Desk lamp"
  screen.method = .card
  guard screen.review() else { return false }
  let draft = screen.submitInstruction()
  guard let restored = PaymentScreenModel.restore(screen.checkpointJSON()) else { return false }
  let again = restored.submitInstruction()
  return again?.idempotencyKey == draft?.idempotencyKey
    && again?.outcomeUncertain == true
    && again?.provider == "adyen"
    && again?.method == "card"
    && restored.room == screen.runtime.checkpoint.sessionId
    && restored.requestHeaders(includeIdempotency: true)["X-Rehearsal-Session"] == screen.runtime.checkpoint.sessionId
    && restored.reviewing
}

private func providerSticky() -> Bool {
  var screen = model()
  guard screen.connect() else { return false }
  screen.amountInput = "10.00"
  screen.method = .card
  guard screen.review() else { return false }
  let key = screen.submitInstruction()?.idempotencyKey
  screen.markUncertain(reason: "timeout")
  screen.method = .bank
  let draft = screen.submitInstruction()
  return draft?.idempotencyKey == key && draft?.provider == "adyen" && draft?.method == "card"
}

private func sessionPreserved() -> Bool {
  var screen = model()
  screen.room = "room-two"
  guard screen.connect() else { return false }
  guard screen.requestHeaders(includeIdempotency: false)["X-Rehearsal-Session"] == "room-two" else { return false }
  screen.room = "no"
  let rejected = screen.connect()
  return !rejected
    && screen.requestHeaders(includeIdempotency: false)["X-Rehearsal-Session"] == "room-two"
    && screen.runtime.checkpoint.sessionId == "room-two"
}

private func replayedDeepLink() -> Bool {
  var screen = model()
  let now: Int64 = 1_700_000_000_000
  let url = "meridian://return?paymentId=pay-1&nonce=n1&exp=\(now + 10_000)"
  guard case .accepted(let paymentId) = screen.openReturn(url: url, nowMillis: now), paymentId == "pay-1" else { return false }
  guard case .rejected(let reason) = screen.openReturn(url: url, nowMillis: now + 1), reason == "replayed" else { return false }
  guard let restored = PaymentScreenModel.restore(screen.checkpointJSON()) else { return false }
  var revived = restored
  guard case .rejected(let again) = revived.openReturn(url: url, nowMillis: now + 2), again == "replayed" else { return false }
  return true
}

private func expiredReturn() -> Bool {
  var screen = model()
  let now: Int64 = 1_700_000_000_000
  let expired = "meridian://return?paymentId=pay-2&nonce=n2&exp=\(now)"
  guard case .rejected(let reason) = screen.openReturn(url: expired, nowMillis: now), reason == "expired" else { return false }
  let malformed = "https://example.invalid/return?paymentId=pay-3&nonce=n3&exp=\(now + 10)"
  guard case .rejected(let bad) = screen.openReturn(url: malformed, nowMillis: now), bad == "malformed" else { return false }
  let missing = "meridian://return?paymentId=pay-4&exp=\(now + 10)"
  guard case .rejected(let missingReason) = screen.openReturn(url: missing, nowMillis: now), missingReason == "malformed" else { return false }
  return screen.runtime.checkpoint.consumedReturnNonces.isEmpty
}

private func malformedCatalog() -> Bool {
  let root = contractsDirectory()
  guard let data = try? Data(contentsOf: root.appendingPathComponent("catalog-malformed.json")) else { return false }
  let result = ConsumerContract.evaluateCatalog(data)
  return !result.accepted && result.code == "MALFORMED_CATALOG" && result.detail.contains("unknown_provider") && result.detail.contains("unknown_category") && result.providerIds.isEmpty
}

private func voiceOver() -> Bool {
  let descriptor = paymentConfirmationAccessibility(
    amountLabel: "£10.50",
    recipientName: "Northline Studio",
    method: "card",
    language: "en",
    fontScale: 1,
    platform: "voiceover"
  )
  return descriptor.label == "Confirm payment of £10.50 to Northline Studio using debit card, Adyen"
    && descriptor.hint == "Submits the fictional rehearsal payment. No real money moves."
    && descriptor.role == "button"
    && descriptor.minimumTouchTargetPt >= 44
    && descriptor.layoutDirection == "ltr"
    && descriptor.mirrorsInRightToLeft
}

private func talkBack() -> Bool {
  let voice = paymentConfirmationAccessibility(
    amountLabel: "£10.50",
    recipientName: "Northline Studio",
    method: "card",
    language: "en",
    fontScale: 1,
    platform: "voiceover"
  )
  let talk = paymentConfirmationAccessibility(
    amountLabel: "£10.50",
    recipientName: "Northline Studio",
    method: "bank",
    language: "en-GB",
    fontScale: 1,
    platform: "talkback"
  )
  return talk.label == "Confirm payment of £10.50 to Northline Studio using bank payment, Worldpay"
    && talk.hint == voice.hint
    && talk.minimumTouchTargetPt >= 48
    && talk.role == "button"
}

private func largeFont() -> Bool {
  let standard = scaledFontSize(base: 38, fontScale: fontScaleFor(bucket: "standard"))
  let large = scaledFontSize(base: 38, fontScale: fontScaleFor(bucket: "large"))
  let accessibility = scaledFontSize(base: 38, fontScale: fontScaleFor(bucket: "accessibility"))
  return fontScaleFor(bucket: "large") == 1.3
    && large > standard
    && accessibility == 76
    && large == 49.4
}

private func rtlLayout() -> Bool {
  layoutDirectionForLanguage("en") == "ltr"
    && layoutDirectionForLanguage("en-GB") == "ltr"
    && layoutDirectionForLanguage("ar") == "rtl"
    && layoutDirectionForLanguage("he") == "rtl"
    && paymentConfirmationAccessibility(
      amountLabel: "£1.00",
      recipientName: "Northline Studio",
      method: "card",
      language: "ar",
      fontScale: fontScaleFor(bucket: "large"),
      platform: "voiceover"
    ).layoutDirection == "rtl"
}

private func uncertainStatus() -> Bool {
  PaymentScreenModel.failureIsUncertain(statusCode: nil)
    && PaymentScreenModel.failureIsUncertain(statusCode: 202)
    && PaymentScreenModel.failureIsUncertain(statusCode: 503)
    && !PaymentScreenModel.failureIsUncertain(statusCode: 400)
    && !PaymentScreenModel.failureIsUncertain(statusCode: 422)
    && !PaymentScreenModel.failureIsUncertain(statusCode: 409)
}

private func contractsDirectory() -> URL {
  var url = URL(fileURLWithPath: #filePath)
  for _ in 0..<4 { url.deleteLastPathComponent() }
  return url.appendingPathComponent("contracts")
}
