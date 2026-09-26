import Foundation
import SwiftUI
@testable import MeridianSDK
import MeridianUI
#if os(macOS)
import AppKit
#endif

private let anchor = Date(timeIntervalSince1970: 1_700_000_000)

private func facts(
  account: String = "everyday-account",
  established: String = "iPhone",
  current: String = "iPhone",
  remaining: TimeInterval = SessionTiming.lifetime
) -> SessionFacts {
  SessionFacts(
    sessionId: "meridian-rehearsal",
    accountName: account,
    establishedOnDevice: established,
    currentDevice: current,
    authenticatedAt: anchor.addingTimeInterval(-60),
    expiresAt: anchor.addingTimeInterval(remaining),
    now: anchor
  )
}

private final class BannerLog {
  var passed = 0
  var failed = 0

  func check(_ title: String, _ ok: Bool, detail: String = "") {
    if ok {
      print("  ✓ \(title)")
      passed += 1
    } else {
      let extra = detail.isEmpty ? "" : " — \(detail)"
      print("  ✗ \(title)\(extra)")
      failed += 1
    }
  }
}

@MainActor
func runSessionBannerChecks() async -> (passed: Int, failed: Int) {
  print("\n=== Auth screen session banner ===\n")
  let log = BannerLog()

  let loading = SessionBannerModel.loading
  log.check(
    "Loading skeleton does not assert a session state",
    loading.phase == .loading
      && loading.showsSkeleton
      && !loading.blocking
      && !loading.allowsPayment
      && loading.actionTitle == nil
      && loading.message.isEmpty
      && loading.liveAnnouncement == "Checking your session"
      && !loading.liveAnnouncement.localizedCaseInsensitiveContains("signed out")
      && !loading.liveAnnouncement.localizedCaseInsensitiveContains("expire")
  )

  let healthy = SessionBannerModel.resolve(.succeeded(facts()))
  log.check(
    "Healthy session stays a minimal non-blocking indicator",
    healthy.phase == .healthy
      && healthy.message == "Session active"
      && healthy.liveAnnouncement == "Session active"
      && !healthy.blocking
      && healthy.allowsPayment
      && !healthy.showsSkeleton
      && healthy.actionTitle == nil
  )

  let expiring = SessionBannerModel.resolve(
    .succeeded(facts(remaining: SessionTiming.warningWindow))
  )
  log.check(
    "Expiring soon uses the approved copy and does not block",
    expiring.phase == .expiring
      && expiring.title == "Session expiring"
      && expiring.message == "Your session is about to expire. Sign in again to continue."
      && expiring.liveAnnouncement == expiring.message
      && expiring.actionTitle == "Sign in again"
      && !expiring.blocking
      && expiring.allowsPayment
      && !expiring.showsSkeleton
  )

  let signedOut = SessionBannerModel.resolve(.absent)
  log.check(
    "Signed out blocks and asks for the existing sign-in",
    signedOut.phase == .signedOut
      && signedOut.message == "You've been signed out. Sign in to continue."
      && signedOut.liveAnnouncement == signedOut.message
      && signedOut.actionTitle == "Sign in"
      && signedOut.blocking
      && !signedOut.allowsPayment
      && !signedOut.showsSkeleton
  )

  let elsewhere = SessionBannerModel.resolve(
    .succeeded(facts(account: "Ada", established: "iPad", current: "iPhone"))
  )
  log.check(
    "Active elsewhere is informational",
    elsewhere.phase == .activeElsewhere
      && elsewhere.title == "Signed in elsewhere"
      && elsewhere.message == "Signed in elsewhere on iPad for Ada."
      && elsewhere.actionTitle == nil
      && !elsewhere.blocking
      && elsewhere.allowsPayment
      && elsewhere.accountName == "Ada"
      && elsewhere.deviceName == "iPad"
  )

  let rawAccount = String(repeating: "A", count: 80)
  let rawDevice = String(repeating: "D", count: 70)
  let truncated = SessionBannerModel.resolve(
    .succeeded(facts(account: rawAccount, established: rawDevice, current: "iPhone"))
  )
  let emoji = truncateForBanner(String(repeating: "😀", count: 40))
  log.check(
    "Long account and device names truncate",
    truncated.phase == .activeElsewhere
      && truncated.accountName?.count == sessionBannerNameLimit
      && truncated.deviceName?.count == sessionBannerNameLimit
      && truncated.accountName?.hasSuffix("…") == true
      && truncated.deviceName?.hasSuffix("…") == true
      && !truncated.message.contains(rawAccount)
      && !truncated.message.contains(rawDevice)
      && truncated.message.contains("Signed in elsewhere")
      && truncateForBanner("  hello  ") == "hello"
      && truncateForBanner(String(repeating: "b", count: 32)).count == 32
      && !truncateForBanner(String(repeating: "b", count: 32)).contains("…")
      && emoji.count == sessionBannerNameLimit
      && emoji.hasSuffix("…")
  )

  let failed = SessionBannerModel.resolve(.failed)
  let timedOut = SessionBannerModel.resolve(.timedOut)
  log.check(
    "Failed and timed-out checks stay neutral",
    failed.phase == .unresolved
      && timedOut.phase == .unresolved
      && failed == timedOut
      && failed.message == "We couldn't confirm your session. You can continue."
      && !failed.blocking
      && failed.allowsPayment
      && failed.actionTitle == "Try again"
      && !failed.message.localizedCaseInsensitiveContains("signed out")
      && !failed.message.localizedCaseInsensitiveContains("expire")
      && !failed.message.localizedCaseInsensitiveContains("elsewhere")
  )

  let transitionProbes: [SessionProbe] = [
    .pending,
    .succeeded(facts()),
    .succeeded(facts(remaining: SessionTiming.warningWindow)),
    .succeeded(facts(account: "Ledger", established: "Kitchen iPad", current: "iPhone")),
    .failed,
    .timedOut,
    .succeeded(facts(remaining: 0)),
    .succeeded(facts()),
  ]
  let transition = transitionProbes.map { SessionBannerModel.resolve($0) }
  let phases = transition.map(\.phase)
  let announcements = Set(transition.map(\.liveAnnouncement))
  log.check(
    "State transitions announce each change and only block when expired",
    phases == [.loading, .healthy, .expiring, .activeElsewhere, .unresolved, .unresolved, .signedOut, .healthy]
      && transition.filter(\.blocking).count == 1
      && transition[6].blocking
      && announcements.count == 6
      && transition[2].liveAnnouncement != transition[6].liveAnnouncement
      && !transition[4].message.contains("Kitchen")
      && !transition[4].message.contains("Ledger")
  )

  log.check(
    "A failed recheck does not keep an active-elsewhere claim",
    elsewhere.phase == .activeElsewhere
      && SessionBannerModel.resolve(.failed).phase == .unresolved
      && !SessionBannerModel.resolve(.timedOut).message.contains("iPad")
  )

  let restored = SessionBannerModel.resolve(.succeeded(facts()))
  log.check(
    "Signing back in clears the blocking prompt",
    signedOut.blocking
      && !restored.blocking
      && restored.phase == .healthy
      && restored.allowsPayment
      && restored.liveAnnouncement != signedOut.liveAnnouncement
  )

  let atWarning = SessionBannerModel.resolve(.succeeded(facts(remaining: SessionTiming.warningWindow)))
  let justOutside = SessionBannerModel.resolve(
    .succeeded(facts(remaining: SessionTiming.warningWindow + 1))
  )
  let exactExpiry = SessionBannerModel.resolve(.succeeded(facts(remaining: 0)))
  let expiredElsewhere = SessionBannerModel.resolve(
    .succeeded(facts(established: "iPad", current: "iPhone", remaining: -1))
  )
  let expiringElsewhere = SessionBannerModel.resolve(
    .succeeded(facts(established: "iPad", current: "iPhone", remaining: 60))
  )
  log.check(
    "Expiry boundaries prefer blocking only at expiry",
    SessionTiming.lifetime == 30 * 60
      && SessionTiming.warningWindow == 5 * 60
      && SessionTiming.probeTimeout == 8
      && atWarning.phase == .expiring
      && !atWarning.blocking
      && justOutside.phase == .healthy
      && exactExpiry.phase == .signedOut
      && exactExpiry.blocking
      && expiredElsewhere.phase == .signedOut
      && expiringElsewhere.phase == .expiring
  )

  let treatments = [loading, healthy, expiring, elsewhere, signedOut, failed]
  let expiringRatio = contrastRatio(expiring.foreground, expiring.background)
  let signedOutActionRatio = contrastRatio(signedOut.actionForeground, signedOut.actionBackground)
  let quietRatio = contrastRatio(healthy.foreground, healthy.background)
  log.check(
    "Banner contrast meets WCAG AA",
    treatments.allSatisfy(meetsSessionBannerContrast)
      && expiringRatio > 11
      && expiringRatio < 14
      && signedOutActionRatio > 14
      && signedOutActionRatio < 17
      && quietRatio > 9
      && quietRatio < 11
  )

  let signedOutOrder = signedOut.focusOrder
  let expiringOrder = expiring.focusOrder
  let loadingOrder = loading.focusOrder
  let unresolvedOrder = failed.focusOrder
  let signedOutAction = index(of: AuthAccessibility.bannerAction, in: signedOutOrder)
  let signedOutFields = index(of: AuthAccessibility.endpoint, in: signedOutOrder)
  let expiringAction = index(of: AuthAccessibility.bannerAction, in: expiringOrder)
  let expiringFields = index(of: AuthAccessibility.endpoint, in: expiringOrder)
  let retryAction = index(of: AuthAccessibility.bannerAction, in: unresolvedOrder)
  let retryFields = index(of: AuthAccessibility.room, in: unresolvedOrder)
  log.check(
    "Banner action comes before the rest of the auth screen",
    AuthAccessibility.bannerPriority > AuthAccessibility.actionPriority
      && AuthAccessibility.actionPriority > AuthAccessibility.endpointPriority
      && AuthAccessibility.endpointPriority > AuthAccessibility.roomPriority
      && AuthAccessibility.roomPriority > AuthAccessibility.connectPriority
      && AuthAccessibility.connectPriority > AuthAccessibility.paymentPriority
      && signedOutOrder.first == AuthAccessibility.banner
      && signedOutAction >= 0
      && signedOutFields >= 0
      && signedOutAction < signedOutFields
      && !signedOutOrder.contains(AuthAccessibility.payment)
      && expiringAction >= 0
      && expiringFields >= 0
      && expiringAction < expiringFields
      && expiringOrder.last == AuthAccessibility.payment
      && loadingOrder.first == AuthAccessibility.skeleton
      && !loadingOrder.contains(AuthAccessibility.bannerAction)
      && !loadingOrder.contains(AuthAccessibility.payment)
      && retryAction >= 0
      && retryFields >= 0
      && retryAction < retryFields
  )

  let sameDevice = SessionBannerModel.resolve(
    .succeeded(facts(established: "iPhone", current: "iphone"))
  )
  let blankDevice = SessionBannerModel.resolve(
    .succeeded(facts(established: "   ", current: "iPhone"))
  )
  log.check(
    "Same device does not show active elsewhere",
    sameDevice.phase == .healthy
      && blankDevice.phase == .healthy
      && !facts(established: "iPhone", current: " iphone ").establishedOnAnotherDevice
      && facts(established: "iPad", current: "iPhone").establishedOnAnotherDevice
  )

  let stored = StoredSession(
    endpoint: "http://127.0.0.1:8080/api/v1",
    sessionId: "meridian-rehearsal",
    accountName: "meridian-rehearsal",
    deviceName: "iPhone",
    authenticatedAt: anchor,
    expiresAt: anchor.addingTimeInterval(SessionTiming.lifetime)
  )
  let memory = MemorySessionStore()
  memory.save(stored)
  let memoryRemembered = memory.load() == stored && memory.loadFields()?.sessionId == stored.sessionId
  memory.clear()
  let memoryKeptFields = memory.load() == nil && memory.loadFields()?.sessionId == stored.sessionId
  let suite = "meridian.banner.tests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suite)
  var diskOK = false
  if let defaults {
    let disk = UserDefaultsSessionStore(defaults: defaults, sessionKey: "session", fieldsKey: "fields")
    disk.save(stored)
    let loaded = disk.load()
    disk.clear()
    diskOK = loaded == stored
      && disk.load() == nil
      && disk.loadFields()?.sessionId == "meridian-rehearsal"
      && disk.loadFields()?.endpoint == stored.endpoint
    defaults.removePersistentDomain(forName: suite)
  }
  log.check(
    "Session store keeps the selected rehearsal session id",
    memoryRemembered
      && memoryKeptFields
      && diskOK
      && stored.sessionId == "meridian-rehearsal"
  )

  log.check(
    "Probe timeout reports timeout and a fast probe succeeds",
    await probeFinishedQuickly() && await probeTimedOut()
  )

  let forbidden = ["European", "corridor", "Stripe", "Adyen", "Worldpay", "launch"]
  let copy = treatments.flatMap { [$0.title, $0.message, $0.liveAnnouncement, $0.actionTitle ?? ""] }
  log.check(
    "Banner copy stays on session state",
    forbidden.allSatisfy { word in
      copy.allSatisfy { !$0.localizedCaseInsensitiveContains(word) }
    }
  )

  let phoneWidths: [CGFloat] = [320, 390, 428]
  let phoneModels = [loading, healthy, expiring, truncated, signedOut, failed]
  var renderDetail = ""
  var renderOK = true
  for width in phoneWidths {
    for model in phoneModels {
      let size = renderedSize(of: SessionBannerView(model: model), width: width)
      if !sizeIsBounded(size, width: width, maxHeight: 420) {
        renderOK = false
        renderDetail = "banner \(model.phase) at \(width) rendered \(describe(size))"
      }
    }
  }
  log.check("Phone-width banner render stays bounded", renderOK, detail: renderDetail)

  let shortElsewhere = renderedSize(of: SessionBannerView(model: elsewhere), width: 320)
  let longMessage = SessionBannerModel(
    phase: .activeElsewhere,
    title: "Signed in elsewhere",
    message: String(repeating: "W", count: 2000),
    actionTitle: nil,
    blocking: false,
    allowsPayment: true,
    showsSkeleton: false,
    foreground: SessionBannerPalette.elsewhereForeground,
    background: SessionBannerPalette.elsewhereBackground,
    actionForeground: SessionBannerPalette.elsewhereForeground,
    actionBackground: SessionBannerPalette.elsewhereBackground,
    liveAnnouncement: "Signed in elsewhere",
    accountName: nil,
    deviceName: nil
  )
  let longSize = renderedSize(of: SessionBannerView(model: longMessage), width: 320)
  log.check(
    "Long banner text does not stretch the layout",
    sizeIsBounded(longSize, width: 320, maxHeight: 450)
      && sizeIsBounded(shortElsewhere, width: 320, maxHeight: 450)
      && (longSize?.height ?? 9_999) < (shortElsewhere?.height ?? 0) + 280,
    detail: "long \(describe(longSize)) short \(describe(shortElsewhere))"
  )

  let openPayment = renderedSize(of: AuthHost(banner: expiring), width: 390)
  let blocked = renderedSize(of: AuthHost(banner: signedOut), width: 390)
  let paymentGap = (openPayment?.height ?? 0) - (blocked?.height ?? 0)
  log.check(
    "Blocking auth screen omits payment content",
    sizeIsBounded(openPayment, width: 390, maxHeight: 900)
      && sizeIsBounded(blocked, width: 390, maxHeight: 900)
      && paymentGap > 50,
    detail: "expiring \(describe(openPayment)) signedOut \(describe(blocked)) gap \(paymentGap)"
  )

  return (log.passed, log.failed)
}

private func index(of identifier: String, in order: [String]) -> Int {
  order.firstIndex(of: identifier) ?? -1
}

private func probeFinishedQuickly() async -> Bool {
  do {
    let value = try await withSessionTimeout(1) { @Sendable () async throws -> String in
      "ok"
    }
    return value == "ok"
  } catch {
    return false
  }
}

private func probeTimedOut() async -> Bool {
  do {
    _ = try await withSessionTimeout(0.15) { @Sendable () async throws -> String in
      try await Task.sleep(for: .seconds(5))
      return "late"
    }
    return false
  } catch SessionProbeError.timedOut {
    return true
  } catch {
    return false
  }
}

private struct AuthHost: View {
  @State private var endpoint = "http://127.0.0.1:8080/api/v1"
  @State private var room = "meridian-rehearsal-room-with-a-long-name"
  let banner: SessionBannerModel

  var body: some View {
    AuthScreen(
      endpoint: $endpoint,
      room: $room,
      banner: banner,
      busy: false,
      message: "Connected to shared Java API",
      onSignIn: {}
    ) {
      Text("Make a payment")
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
    }
  }
}

@MainActor
private func renderedSize<V: View>(of view: V, width: CGFloat) -> CGSize? {
  let renderer = ImageRenderer(content: view.frame(width: width, alignment: .topLeading))
  renderer.proposedSize = ProposedViewSize(width: width, height: nil)
  renderer.scale = 1
  #if os(macOS)
  return renderer.nsImage?.size
  #else
  return renderer.uiImage?.size
  #endif
}

private func sizeIsBounded(_ size: CGSize?, width: CGFloat, maxHeight: CGFloat) -> Bool {
  guard let size else { return false }
  let widthMatches = abs(size.width - width) <= 2 || abs(size.width / 2 - width) <= 2
  return widthMatches && size.height > 20 && size.height < maxHeight
}

private func describe(_ size: CGSize?) -> String {
  guard let size else { return "nil" }
  return "\(size.width)x\(size.height)"
}
