import Foundation
@testable import MeridianSDK

enum AuthenticationChecks {
static func run(passed: inout Int, failed: inout Int) {
  func check(_ name: String, _ ok: Bool) {
    if ok {
      print("  ✓ \(name)")
      passed += 1
    } else {
      print("  ✗ \(name)")
      failed += 1
    }
  }

  let payload = "{\"exp\":1700000300,\"nonce\":\"11111111-1111-1111-1111-111111111111\",\"paymentKey\":\"pay-key-1\",\"session\":\"meridian-rehearsal\",\"v\":1}"
  let knownToken = "eyJleHAiOjE3MDAwMDAzMDAsIm5vbmNlIjoiMTExMTExMTEtMTExMS0xMTExLTExMTEtMTExMTExMTExMTExIiwicGF5bWVudEtleSI6InBheS1rZXktMSIsInNlc3Npb24iOiJtZXJpZGlhbi1yZWhlYXJzYWwiLCJ2IjoxfQ.668b20e0e5b693d0d4f4abfe251d61c9616b79941849d3224eb8fc5b17b88acb"
  let testKey = Data("rehearsal-test-key".utf8)

  print("21. HMAC-SHA256 RFC 4231...")
  let rfcKey = Data(repeating: 0x0b, count: 20)
  let rfc = hex(HmacSha256.sign(key: rfcKey, message: Data("Hi There".utf8)))
  check("HMAC-SHA256 matches RFC 4231", rfc == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")

  print("22. Known signed return token...")
  let signed = ReturnStateVault.sign(key: testKey, payload: payload)
  let knownVault = ReturnStateVault(key: testKey, now: { 1_700_000_000 })
  let known = knownVault.intercept(
    url: returnURL(knownToken),
    expectedSession: "meridian-rehearsal",
    expectedPaymentKey: "pay-key-1"
  )
  check(
    "known token signature and acceptance",
    signed == knownToken && known.outcome == .accepted && known.allowsPaymentSubmit && !known.createsPayment && known.idempotencyKey == "pay-key-1"
  )

  print("23. Allowlisted bank handoff only...")
  let handoff = "https://bank.meridian-rehearsal.test/handoff?state=\(knownToken)"
  let allowed = BankHandoffPolicy.inspectBankHandoff(handoff)
  let http = BankHandoffPolicy.inspectBankHandoff("http://bank.meridian-rehearsal.test/handoff?state=\(knownToken)")
  let userinfo = BankHandoffPolicy.inspectBankHandoff("https://user:secret@bank.meridian-rehearsal.test/handoff?state=\(knownToken)")
  let suffix = BankHandoffPolicy.inspectBankHandoff("https://bank.meridian-rehearsal.test.evil.example/handoff?state=\(knownToken)")
  let worldpay = BankHandoffPolicy.inspectBankHandoff("https://online.worldpay.com/handoff?state=\(knownToken)")
  let adyen = BankHandoffPolicy.inspectBankHandoff("https://checkoutshopper-live.adyen.com/checkout?state=\(knownToken)")
  let extra = BankHandoffPolicy.inspectBankHandoff(handoff + "&amountMinor=100")
  check(
    "only the reserved HTTPS handoff host is allowed",
    {
      if case .allowed = allowed { return true }
      return false
    }() && refused(http) && refused(userinfo) && refused(suffix) && refused(worldpay) && refused(adyen) && refused(extra)
  )

  print("24. Issued handoff is opaque and returnable...")
  let issuedVault = ReturnStateVault(key: testKey, now: { 1_700_000_000 })
  let issued = try? issuedVault.issue(sessionId: "meridian-rehearsal", paymentKey: "pay-key-1")
  let issuedReturn = issued.map { issuedVault.intercept(url: $0.returnURL, expectedSession: "meridian-rehearsal", expectedPaymentKey: "pay-key-1") }
  check(
    "handoff URL has only state and accepts its return",
    issued?.handoffURL.hasPrefix("https://bank.meridian-rehearsal.test/handoff?state=") == true
      && issued?.handoffURL.contains("amount") == false
      && issued?.handoffURL.contains("recipient") == false
      && issued?.handoffURL.contains("pay-key-1") == false
      && issued?.idempotencyKey == "pay-key-1"
      && issuedReturn?.outcome == .accepted
  )

  print("25. Tampered return does not submit...")
  let tampered = String(knownToken.dropLast()) + "0"
  let tamperVault = ReturnStateVault(key: testKey, now: { 1_700_000_000 })
  let tamperDecision = tamperVault.intercept(url: returnURL(tampered), expectedSession: "meridian-rehearsal", expectedPaymentKey: "pay-key-1")
  check("tampered token is a safe failure", safeFailure(tamperDecision, key: "pay-key-1", outcome: .invalid))

  print("26. Expired return does not submit...")
  let expiredVault = ReturnStateVault(key: testKey, now: { 1_700_000_300 })
  let expired = expiredVault.intercept(url: returnURL(knownToken), expectedSession: "meridian-rehearsal", expectedPaymentKey: "pay-key-1")
  check("expired token is a safe failure", safeFailure(expired, key: "pay-key-1", outcome: .expired))

  print("27. Replayed return does not submit again...")
  let replayVault = ReturnStateVault(key: testKey, now: { 1_700_000_000 })
  let first = replayVault.intercept(url: returnURL(knownToken), expectedSession: "meridian-rehearsal", expectedPaymentKey: "pay-key-1")
  let second = replayVault.intercept(url: returnURL(knownToken), expectedSession: "meridian-rehearsal", expectedPaymentKey: "pay-key-1")
  check(
    "replay keeps the original key and does not submit",
    first.outcome == .accepted && safeFailure(second, key: "pay-key-1", outcome: .replayed)
  )

  print("28. Foreign payment key is not adopted...")
  let foreignVault = ReturnStateVault(key: testKey, now: { 1_700_000_000 })
  let foreign = foreignVault.intercept(url: returnURL(knownToken), expectedSession: "meridian-rehearsal", expectedPaymentKey: "other-key")
  check("mismatched return keeps the in-progress key", safeFailure(foreign, key: "other-key", outcome: .invalid))

  print("29. Unrelated link is ignored...")
  let ignored = knownVault.intercept(url: "https://example.test/elsewhere", expectedSession: "meridian-rehearsal", expectedPaymentKey: "pay-key-1")
  check(
    "unrelated URL does not create a payment",
    ignored.outcome == .ignored && !ignored.allowsPaymentSubmit && !ignored.createsPayment && ignored.idempotencyKey == "pay-key-1"
  )

  print("30. Cancelled return cannot create a payment...")
  let cancelVault = ReturnStateVault(key: testKey, now: { 1_700_000_000 })
  cancelVault.cancel(state: knownToken)
  let cancelled = cancelVault.intercept(url: returnURL(knownToken), expectedSession: "meridian-rehearsal", expectedPaymentKey: "pay-key-1")
  check("cancelled token is a replay failure", safeFailure(cancelled, key: "pay-key-1", outcome: .replayed))

  print("31. Card PIN and biometric gate...")
  let original = "payment-key-42"
  let attempt = PaymentAttempt(idempotencyKey: original, method: .card)
  let blocked = !attempt.submitIfReady { _ in }
  let (mismatched, mismatch) = attempt.confirmingPin(pin: "1234", repeated: "9999")
  let (_, shortError) = attempt.confirmingPin(pin: "12", repeated: "12")
  let denied = attempt.confirmingBiometric(succeeded: false)
  let (confirmed, pinError) = attempt.confirmingPin(pin: "1234", repeated: "1234")
  var pinKey = ""
  let pinSubmitted = confirmed.submitIfReady { pinKey = $0 }
  let biometric = attempt.confirmingBiometric(succeeded: true)
  var bioKey = ""
  let bioSubmitted = biometric.submitIfReady { bioKey = $0 }
  check(
    "card payment waits for PIN or biometric and keeps its key",
    blocked
      && mismatch == "PIN entries do not match"
      && !mismatched.readyToSubmit
      && shortError == "PIN must be 4 to 6 digits"
      && !denied.submitIfReady { _ in }
      && pinError == nil
      && pinSubmitted
      && pinKey == original
      && bioSubmitted
      && bioKey == original
  )

  print("32. Bank payment waits for a fresh return...")
  let bank = PaymentAttempt(idempotencyKey: "pay-key-1", method: .bank)
  let bankVault = ReturnStateVault(key: testKey, now: { 1_700_000_000 })
  let accepted = bankVault.intercept(url: returnURL(knownToken), expectedSession: "meridian-rehearsal", expectedPaymentKey: "pay-key-1")
  let ready = bank.applying(accepted)
  var used = ""
  let submitted = ready.submitIfReady { used = $0 }
  check(
    "bank submit uses the original key only after acceptance",
    !bank.submitIfReady { _ in } && submitted && used == "pay-key-1" && ready.idempotencyKey == "pay-key-1"
  )
}

private static func returnURL(_ token: String) -> String {
  "https://app.meridian-rehearsal.test/bank/return?state=\(token)"
}

private static func refused(_ check: UrlCheck) -> Bool {
  if case .refused = check { return true }
  return false
}

private static func safeFailure(_ decision: ReturnDecision, key: String, outcome: ReturnOutcome) -> Bool {
  let attempt = PaymentAttempt(idempotencyKey: key, method: .bank).applying(decision)
  return decision.outcome == outcome
    && decision.idempotencyKey == key
    && !decision.allowsPaymentSubmit
    && !decision.createsPayment
    && !attempt.readyToSubmit
    && !attempt.submitIfReady { _ in }
}
}
