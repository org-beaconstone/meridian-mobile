import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MeridianSDK

func runSessionBannerChecks() -> (passed: Int, failed: Int) {
  var passed = 0
  var failed = 0

  func check(_ name: String, _ ok: Bool) {
    if ok {
      print("  ✓ \(name)")
      passed += 1
    } else {
      print("  ✗ \(name)")
      failed += 1
    }
  }

  let now: Int64 = 1_000_000
  let window = SessionBanner.expiringWindowMs
  let draft = PaymentContext(
    recipientId: "northline-studio",
    amount: "12.50",
    reference: "Studio books",
    method: .bank,
    reviewing: true,
    idempotencyKey: "pay-key-136"
  )
  let cardDraft = PaymentContext(
    recipientId: "birch-bloom",
    amount: "4.00",
    reference: "Coffee",
    method: .card,
    reviewing: false,
    idempotencyKey: "card-key"
  )

  print("21. Active session banner...")
  let activeClock = SessionClock(sessionId: "room-a", expiresAtMs: now + window + 1, probe: .confirmed)
  let active = SessionBanner.present(nowMs: now, clock: activeClock)
  check("active state", active.state == .active)
  check("active copy", active.title == "Session active" && active.message == "You're securely signed in.")
  check("active has no action and does not block", active.actionLabel == nil && !active.blocksPaymentEntry)
  check("active contrast", active.meetsWcagAa())

  print("22. Expiring session shows remaining time and a non-blocking refresh...")
  let expiringClock = SessionClock(sessionId: "room-a", expiresAtMs: now + (4 * 60 + 12) * 1000, probe: .confirmed)
  let expiring = SessionBanner.present(nowMs: now, clock: expiringClock)
  check("expiring state", expiring.state == .expiring)
  check("remaining time", expiring.message == "Your session expires in 4 min 12 sec.")
  check("refresh action", expiring.actionLabel == "Refresh" && expiring.actionAccessibilityLabel == "Refresh session")
  check("expiring does not block payment entry", !expiring.blocksPaymentEntry)
  check("expiring label includes the time", expiring.accessibilityLabel.contains("4 min 12 sec"))
  check("expiring contrast", expiring.meetsWcagAa())
  let boundary = SessionBanner.present(
    nowMs: now,
    clock: SessionClock(sessionId: "room-a", expiresAtMs: now + window, probe: .confirmed)
  )
  let outside = SessionBanner.present(
    nowMs: now,
    clock: SessionClock(sessionId: "room-a", expiresAtMs: now + window + 1, probe: .confirmed)
  )
  check("five minute boundary is expiring", boundary.state == .expiring && boundary.message.contains("5 min"))
  check("just outside the window stays active", outside.state == .active)

  print("23. Active elsewhere is its own visual state...")
  let elsewhere = SessionBanner.present(
    nowMs: now,
    clock: SessionClock(sessionId: "room-a", expiresAtMs: now + window + 5_000, activeElsewhere: true, probe: .confirmed)
  )
  let elsewhereSoon = SessionBanner.present(
    nowMs: now,
    clock: SessionClock(sessionId: "room-a", expiresAtMs: now + 60_000, activeElsewhere: true, probe: .confirmed)
  )
  check("elsewhere state", elsewhere.state == .activeElsewhere)
  check("elsewhere copy", elsewhere.message == "This session is active on another device.")
  check("elsewhere inside the window still shows time", elsewhereSoon.message.contains("another device") && elsewhereSoon.message.contains("1 min"))
  check("elsewhere stays distinct from expiring", elsewhereSoon.state == .activeElsewhere)
  check("elsewhere contrast", elsewhere.meetsWcagAa() && elsewhereSoon.meetsWcagAa())

  print("24. Signed out is distinct and keeps the payment draft on sign-in...")
  let signedOut = SessionBanner.present(nowMs: now, clock: SessionClock())
  let rejected = SessionBanner.present(
    nowMs: now,
    clock: SessionClock(sessionId: "room-a", expiresAtMs: now + window + 1, probe: .rejected)
  )
  check("signed out before connect", signedOut.state == .signedOut)
  check("rejected probe is signed out", rejected.state == .signedOut && rejected.actionLabel == "Sign in")
  check("signed out copy", signedOut.message == "You've been signed out. Sign in to continue.")
  check("signed out does not block", !signedOut.blocksPaymentEntry && !rejected.blocksPaymentEntry)
  let signedIn = SessionActions.signIn(nowMs: now, sessionId: "room-a", context: draft)
  check("sign-in keeps the draft and key", signedIn.context == draft && signedIn.idempotencyKey == draft.idempotencyKey)
  check("sign-in keeps the bank provider", signedIn.provider == .worldpay && signedIn.method == .bank)
  check("sign-in opens an active window", SessionBanner.resolve(nowMs: now, clock: signedIn.clock) == .active)

  print("25. Unknown and expired recovery is non-blocking and keeps payment context...")
  let expired = SessionBanner.present(
    nowMs: now,
    clock: SessionClock(sessionId: "room-a", expiresAtMs: now, probe: .confirmed)
  )
  let past = SessionBanner.present(
    nowMs: now,
    clock: SessionClock(sessionId: "room-a", expiresAtMs: now - 1, probe: .confirmed)
  )
  let unknown = SessionBanner.present(
    nowMs: now,
    clock: SessionClock(sessionId: "room-a", expiresAtMs: now - 1, probe: .unreachable)
  )
  check("zero remaining is expired", expired.state == .expired && past.state == .expired)
  check("expired recovery copy", expired.message.contains("still here") && expired.actionLabel == "Refresh")
  check("unreachable stays unknown after the deadline", unknown.state == .unknown)
  check("unknown recovery copy", unknown.message.contains("still here") && unknown.actionLabel == "Try again")
  check("unknown and expired do not block", !expired.blocksPaymentEntry && !unknown.blocksPaymentEntry)
  check("expired and unknown contrast", expired.meetsWcagAa() && unknown.meetsWcagAa())

  let clock = SessionClock(sessionId: "room-a", expiresAtMs: 500, activeElsewhere: false, probe: .confirmed)
  let timedOut = SessionActions.noteFailure(clock: clock, context: draft, failure: .timeout)
  check("timeout keeps the draft", timedOut.context == draft)
  check("timeout keeps the session id and deadline", timedOut.clock.sessionId == "room-a" && timedOut.clock.expiresAtMs == 500)
  check("timeout does not switch the bank provider", timedOut.provider == .worldpay)
  check("timeout is unknown rather than expired", SessionBanner.resolve(nowMs: 10_000, clock: timedOut.clock) == .unknown)
  let cardTimeout = SessionActions.noteFailure(
    clock: clock,
    context: cardDraft,
    failure: SessionActions.classify(statusCode: nil, timedOut: true)
  )
  check("timeout does not switch the card provider", cardTimeout.provider == .adyen && cardTimeout.method == .card)
  let unauthorized = SessionActions.noteFailure(clock: clock, context: draft, failure: .unauthorized)
  check("401 is signed out and keeps the key", unauthorized.clock.probe == .rejected && unauthorized.idempotencyKey == draft.idempotencyKey)
  check("http 403 is signed out", SessionActions.noteFailure(clock: clock, context: draft, failure: .http(403)).clock.probe == .rejected)
  check("other http stays unknown", SessionActions.noteFailure(clock: clock, context: draft, failure: .http(503)).clock.probe == .unreachable)

  let extended = SessionActions.refresh(nowMs: now, clock: clock, context: draft, activeElsewhere: true)
  check("refresh returns the same draft", extended.context == draft)
  check("refresh keeps the session and moves the deadline", extended.clock.sessionId == "room-a" && extended.clock.expiresAtMs == now + SessionBanner.defaultDurationMs)
  check("refresh can record active elsewhere", extended.clock.activeElsewhere && extended.clock.probe == .confirmed)
  check("refresh keeps the Worldpay baseline", extended.provider == .worldpay)

  print("26. States are visually distinct and scale with text size...")
  let presentations = [
    active, expiring, elsewhere, signedOut, expired, unknown
  ]
  let tokens = Set(presentations.map { $0.background.token })
  let colors = Set(presentations.map { "\($0.background.red),\($0.background.green),\($0.background.blue)" })
  check("six background tokens", tokens.count == 6 && colors.count == 6)
  let large = SessionTextScale(fontScale: 2)
  let base = SessionTextScale(fontScale: 1)
  let compact = SessionTextScale(fontScale: 0.8)
  check("body text grows", large.bodyPoints > base.bodyPoints && large.titlePoints > base.titlePoints)
  check("tap targets stay at least 48", base.tapTargetPoints >= 48 && large.tapTargetPoints >= 48 && compact.tapTargetPoints >= 48)
  check("scaled copy wraps", large.wraps && presentations.allSatisfy { $0.meetsWcagAa(scale: large) })
  let order = SessionAccessibility.focusOrder(showsAction: true)
  check(
    "banner is announced before the payment form",
    order.first == SessionAccessibility.banner
      && order.dropFirst().first == SessionAccessibility.action
      && order.last == SessionAccessibility.paymentForm
      && (order.firstIndex(of: SessionAccessibility.banner) ?? 9) < (order.firstIndex(of: SessionAccessibility.paymentForm) ?? 0)
  )
  let quietOrder = SessionAccessibility.focusOrder(showsAction: false)
  check("active banner still precedes the form", quietOrder.first == SessionAccessibility.banner && !quietOrder.contains(SessionAccessibility.action))

  print("27. Remaining time formatting...")
  check("minutes and seconds", SessionBanner.formatRemaining(ms: 252_000) == "4 min 12 sec")
  check("exact minutes", SessionBanner.formatRemaining(ms: 300_000) == "5 min")
  check("seconds only", SessionBanner.formatRemaining(ms: 45_000) == "45 sec")
  check("partial second still reads as one second", SessionBanner.formatRemaining(ms: 1) == "1 sec")

  print("28. Session refresh calls health on the selected session...")
  let transport = runSessionRefreshTransportCheck()
  check("refresh uses the selected session and health", transport.ok)
  if !transport.ok {
    print("    \(transport.detail)")
  }

  return (passed, failed)
}

private final class SessionHeaderCapture: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var lastRequest: URLRequest?
  nonisolated(unsafe) static var hits = 0

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    SessionHeaderCapture.lastRequest = request
    SessionHeaderCapture.hits += 1
    let url = request.url ?? URL(string: "http://127.0.0.1/")!
    let response = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: [
        "Content-Type": "application/json",
        "X-Meridian-Session-Elsewhere": "true"
      ]
    )!
    let body = Data("{\"status\":\"ok\",\"service\":\"meridian\",\"simulation\":true}".utf8)
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private func runSessionRefreshTransportCheck() -> (ok: Bool, detail: String) {
  SessionHeaderCapture.lastRequest = nil
  SessionHeaderCapture.hits = 0
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [SessionHeaderCapture.self]
  let urlSession = URLSession(configuration: configuration)
  let semaphore = DispatchSemaphore(value: 0)
  let box = TransportBox()
  Task {
    do {
      let client = try MeridianClient(
        baseURL: "http://127.0.0.1:9/api/v1",
        sessionId: "room-136",
        urlSession: urlSession
      )
      let payload = try await client.refreshSession()
      let request = SessionHeaderCapture.lastRequest
      let path = request?.url?.path ?? ""
      let session = request?.value(forHTTPHeaderField: "X-Rehearsal-Session")
      let method = request?.httpMethod
      let idempotency = request?.value(forHTTPHeaderField: "Idempotency-Key")
      box.ok = payload.healthy
        && payload.activeElsewhere
        && method == "GET"
        && path.hasSuffix("/health")
        && session == "room-136"
        && idempotency == nil
        && !path.contains("payments")
        && SessionHeaderCapture.hits == 1
      if !box.ok {
        box.detail = "method=\(method ?? "nil") path=\(path) session=\(session ?? "nil") hits=\(SessionHeaderCapture.hits) elsewhere=\(payload.activeElsewhere)"
      }
    } catch {
      box.ok = false
      box.detail = String(describing: error)
    }
    semaphore.signal()
  }
  let wait = semaphore.wait(timeout: .now() + 10)
  if wait == .timedOut {
    return (false, "refreshSession timed out")
  }
  return (box.ok, box.detail)
}

private final class TransportBox: @unchecked Sendable {
  var ok = false
  var detail = ""
}
