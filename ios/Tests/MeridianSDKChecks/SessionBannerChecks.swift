import Foundation
@testable import MeridianSDK

final class CollectingBannerLog: SessionBannerLogSink {
  var lines: [String] = []
  func log(_ line: String) { lines.append(line) }
}

func runSessionBannerChecks(passed: inout Int, failed: inout Int) {
  var n = 21
  func expect(_ title: String, _ ok: Bool) {
    if ok {
      print("\(n). \(title)...\n  ✓")
      passed += 1
    } else {
      print("\(n). \(title)...\n  ✗ \(title)")
      failed += 1
    }
    n += 1
  }

  expect(
    "European launch copy matches the spec",
    SessionBannerCopy.europeanLaunch == "New: payments now supported in your European corridor"
      && SessionBannerCopy.europeanLaunch == SessionBannerCopy.europeanLaunchCore + " " + SessionBannerCopy.europeanLaunchDetail
  )

  let active = resolveSessionBanner(SessionBannerQuery(session: RehearsalSessionInfo(status: .active)))
  expect(
    "Active banner copy",
    bannerMessage(active) == SessionBannerCopy.active && bannerKind(active) == .active && bannerDismissible(active)
  )

  let expiring = resolveSessionBanner(SessionBannerQuery(session: RehearsalSessionInfo(status: .expiring)))
  expect("Expiring banner copy", bannerMessage(expiring) == SessionBannerCopy.expiring && bannerKind(expiring) == .expiring)

  let signedOut = resolveSessionBanner(
    SessionBannerQuery(session: RehearsalSessionInfo(status: .signedOutElsewhere, deviceDetail: "iPhone 15"))
  )
  expect(
    "Signed-out-elsewhere copy keeps the core and puts the device in the detail",
    bannerCore(signedOut) == SessionBannerCopy.signedOutElsewhere
      && bannerDetail(signedOut) == "iPhone 15"
      && bannerLabel(signedOut) == "\(SessionBannerCopy.signedOutElsewhere). iPhone 15"
  )

  let failedLookup = resolveSessionBanner(
    SessionBannerQuery(session: RehearsalSessionInfo(status: .active), lookupFailed: true)
  )
  expect(
    "Lookup-failed copy replaces a stale signed-in state and is not dismissible",
    bannerMessage(failedLookup) == SessionBannerCopy.lookupFailed
      && bannerKind(failedLookup) == .lookupFailed
      && !bannerDismissible(failedLookup)
  )

  let corridorOnly = resolveSessionBanner(
    SessionBannerQuery(corridor: CorridorInfo(id: "eu", notice: "european_launch"))
  )
  expect(
    "Corridor-notice state uses the European launch copy",
    bannerKind(corridorOnly) == .corridorNotice
      && bannerDismissible(corridorOnly)
      && bannerLabel(corridorOnly) == SessionBannerCopy.europeanLaunch
      && bannerCore(corridorOnly) == SessionBannerCopy.europeanLaunchCore
      && bannerDetail(corridorOnly) == SessionBannerCopy.europeanLaunchDetail
  )

  let combined = resolveSessionBanner(
    SessionBannerQuery(
      session: RehearsalSessionInfo(status: .active),
      corridor: CorridorInfo(id: "eu", notice: "european_launch")
    )
  )
  expect(
    "Active session keeps its core and adds the corridor notice as detail",
    bannerCore(combined) == SessionBannerCopy.active
      && bannerDetail(combined) == SessionBannerCopy.europeanLaunch
      && bannerLabel(combined) == "\(SessionBannerCopy.active). \(SessionBannerCopy.europeanLaunch)"
      && bannerMetrics(combined) == "active+european_launch"
  )

  let unknownCorridor = resolveSessionBanner(
    SessionBannerQuery(
      session: RehearsalSessionInfo(status: .active),
      corridor: CorridorInfo(id: "us", notice: "other_launch")
    )
  )
  expect(
    "Unknown corridor notices are not shown",
    bannerKind(unknownCorridor) == .active && bannerDetail(unknownCorridor) == nil
  )

  let firstInstall = resolveSessionBanner(SessionBannerQuery())
  expect("First-time install with no session and no corridor shows no banner", firstInstall == .hidden)

  let resolving = resolveSessionBanner(SessionBannerQuery(isResolving: true))
  expect("Skeleton while session status is resolving", resolving == .skeleton)

  let refreshing = resolveSessionBanner(
    SessionBannerQuery(isResolving: true, session: RehearsalSessionInfo(status: .expiring))
  )
  expect(
    "A refresh keeps the confirmed banner instead of flashing the skeleton",
    bannerKind(refreshing) == .expiring
  )

  let blankDevice = resolveSessionBanner(
    SessionBannerQuery(session: RehearsalSessionInfo(status: .active, deviceDetail: "   "))
  )
  expect("Blank device detail is omitted", bannerDetail(blankDevice) == nil)

  var blocked = SessionBannerEngine(logSink: CollectingBannerLog())
  let failedStep = blocked.update(SessionBannerQuery(lookupFailed: true))
  let failedDismiss = blocked.dismiss()
  expect(
    "Lookup-failed dismissal is ignored and not logged",
    failedStep.presentation == failedLookup
      && failedDismiss.presentation == failedLookup
      && failedDismiss.announcement == nil
      && blocked.metrics.dismissals[SessionBannerKind.lookupFailed.rawValue] == nil
      && blocked.metrics.log.isEmpty
  )

  let sink = CollectingBannerLog()
  var rates = SessionBannerEngine(logSink: sink)
  let firstActive = rates.update(SessionBannerQuery(session: RehearsalSessionInfo(status: .active)))
  _ = rates.update(SessionBannerQuery(session: RehearsalSessionInfo(status: .expiring)))
  let secondActive = rates.update(SessionBannerQuery(session: RehearsalSessionInfo(status: .active)))
  let dismissedActive = rates.dismiss()
  expect(
    "Dismissal rate is logged by state",
    firstActive.announcement?.message == SessionBannerCopy.active
      && secondActive.announcement?.message == SessionBannerCopy.active
      && dismissedActive.announcement?.message == SessionBannerCopy.dismissedAnnouncement
      && rates.metrics.dismissalRate(state: "active") == 0.5
      && sink.lines == ["session_banner_dismissal state=active dismissals=1 impressions=2 rate=0.5000"]
  )

  var memory = SessionBannerEngine(logSink: CollectingBannerLog())
  _ = memory.update(SessionBannerQuery(session: RehearsalSessionInfo(status: .active)))
  _ = memory.dismiss()
  let stillActive = memory.update(SessionBannerQuery(session: RehearsalSessionInfo(status: .active)))
  let nowExpiring = memory.update(SessionBannerQuery(session: RehearsalSessionInfo(status: .expiring)))
  expect(
    "Dismissing active hides only that state and expiring shows again",
    stillActive.presentation == .hidden
      && stillActive.announcement == nil
      && bannerKind(nowExpiring.presentation) == .expiring
      && nowExpiring.announcement?.message == SessionBannerCopy.expiring
  )

  var corridorMemory = SessionBannerEngine(logSink: CollectingBannerLog())
  _ = corridorMemory.update(SessionBannerQuery(session: RehearsalSessionInfo(status: .active)))
  _ = corridorMemory.dismiss()
  let withCorridor = corridorMemory.update(
    SessionBannerQuery(
      session: RehearsalSessionInfo(status: .active),
      corridor: CorridorInfo(id: "eu", notice: "european_launch")
    )
  )
  expect(
    "A new corridor notice brings the banner back",
    bannerKind(withCorridor.presentation) == .active
      && bannerDetail(withCorridor.presentation) == SessionBannerCopy.europeanLaunch
  )

  var deviceMemory = SessionBannerEngine(logSink: CollectingBannerLog())
  _ = deviceMemory.update(SessionBannerQuery(session: RehearsalSessionInfo(status: .signedOutElsewhere)))
  _ = deviceMemory.dismiss()
  let otherDevice = deviceMemory.update(
    SessionBannerQuery(session: RehearsalSessionInfo(status: .signedOutElsewhere, deviceDetail: "Kitchen iPad"))
  )
  expect(
    "A changed device brings a signed-out banner back",
    bannerDetail(otherDevice.presentation) == "Kitchen iPad"
  )

  memory.resetSession()
  let afterReset = memory.update(SessionBannerQuery(session: RehearsalSessionInfo(status: .active)))
  expect(
    "A new rehearsal session shows a previously dismissed banner",
    bannerKind(afterReset.presentation) == .active
  )

  var quiet = SessionBannerEngine(logSink: CollectingBannerLog())
  _ = quiet.update(SessionBannerQuery(session: RehearsalSessionInfo(status: .active)))
  let repeatActive = quiet.update(SessionBannerQuery(session: RehearsalSessionInfo(status: .active)))
  expect(
    "Repeating the same confirmed state does not announce again",
    repeatActive.announcement == nil && quiet.metrics.impressions["active"] == 1
  )

  let confirmed = confirmedSession(from: BankState(version: 1, balance: 100, transactions: [], budgets: []))
  expect(
    "GET /state without a session object confirms the rehearsal session as active",
    confirmed.status == .active && confirmed.deviceDetail == nil
  )

  let loaded = sessionBannerQuery(
    state: BankState(
      version: 1,
      balance: 100,
      transactions: [],
      budgets: [],
      session: RehearsalSessionInfo(status: .expiring),
      corridor: CorridorInfo(id: "eu", notice: "european_launch")
    )
  )
  expect(
    "State query reads session and corridor from GET /state",
    loaded.session?.status == .expiring && loaded.corridor?.notice == "european_launch" && !loaded.lookupFailed
  )

  let dropped = sessionBannerQuery(
    state: BankState(version: 1, balance: 100, transactions: [], budgets: [], session: RehearsalSessionInfo(status: .active)),
    lookupFailed: true
  )
  expect("A failed lookup does not keep the previous signed-in snapshot", dropped.lookupFailed && dropped.session == nil)

  let narrow = fitSessionBannerLine(
    core: SessionBannerCopy.active,
    detail: "Pixel · \(SessionBannerCopy.europeanLaunch)",
    dismissible: true,
    contentWidth: SessionBannerLayout.smallestDeviceWidth
  )
  expect(
    "Corridor detail truncates before the core session message",
    narrow.core == SessionBannerCopy.active
      && narrow.corePreserved
      && narrow.detailTruncated
      && narrow.detail?.hasPrefix("Pixel") == true
      && narrow.detail?.contains("corridor") == false
  )

  let signedOutFit = fitSessionBannerLine(
    core: SessionBannerCopy.signedOutElsewhere,
    detail: String(repeating: "iPad ", count: 12),
    dismissible: true,
    contentWidth: SessionBannerLayout.smallestDeviceWidth
  )
  let signedOutWithRoom = fitSessionBannerLine(
    core: SessionBannerCopy.signedOutElsewhere,
    detail: String(repeating: "iPad ", count: 12),
    dismissible: true,
    contentWidth: 420
  )
  expect(
    "Device detail truncates before the signed-out message",
    signedOutFit.core == SessionBannerCopy.signedOutElsewhere
      && signedOutFit.corePreserved
      && signedOutFit.detailTruncated
      && signedOutWithRoom.core == SessionBannerCopy.signedOutElsewhere
      && signedOutWithRoom.detailTruncated
      && signedOutWithRoom.detail?.hasPrefix("iPad") == true
  )

  let cores = [
    SessionBannerCopy.active,
    SessionBannerCopy.expiring,
    SessionBannerCopy.signedOutElsewhere,
  ]
  let coresFit = cores.allSatisfy { core in
    let fit = fitSessionBannerLine(core: core, detail: nil, dismissible: true, contentWidth: SessionBannerLayout.smallestDeviceWidth)
    return fit.core == core && fit.corePreserved && !fit.detailTruncated
  }
  let lookupFit = fitSessionBannerLine(
    core: SessionBannerCopy.lookupFailed,
    detail: nil,
    dismissible: false,
    contentWidth: SessionBannerLayout.smallestDeviceWidth
  )
  expect(
    "Session messages fit on one line at the smallest supported width",
    coresFit && lookupFit.core == SessionBannerCopy.lookupFailed && lookupFit.corePreserved
  )

  let wide = fitSessionBannerLine(
    core: SessionBannerCopy.active,
    detail: SessionBannerCopy.europeanLaunch,
    dismissible: true,
    contentWidth: 800
  )
  expect(
    "A wide layout keeps the full corridor notice",
    wide.detail == SessionBannerCopy.europeanLaunch && !wide.detailTruncated && wide.corePreserved
  )

  let kinds = SessionBannerKind.allCases
  let contrastOK = kinds.allSatisfy { kind in
    [SessionBannerColorScheme.light, .dark].allSatisfy { scheme in
      let palette = sessionBannerPalette(kind: kind, colorScheme: scheme)
      let measured = sessionBannerContrastRatio(palette.foreground, palette.background)
      return palette.contrastRatio >= 4.5 && abs(palette.contrastRatio - measured) < 0.001
    }
  }
  let activeLight = sessionBannerPalette(kind: .active, colorScheme: .light)
  let activeDark = sessionBannerPalette(kind: .active, colorScheme: .dark)
  let corridorLight = sessionBannerPalette(kind: .corridorNotice, colorScheme: .light)
  expect(
    "Banner contrast meets WCAG 2.1 AA and uses the balance-card tokens",
    contrastOK
      && activeLight.foregroundHex == MeridianBannerTokens.balanceCardBackground
      && activeDark.backgroundHex == MeridianBannerTokens.balanceCardBackground
      && activeDark.foregroundHex == MeridianBannerTokens.balanceCardForeground
      && corridorLight == activeLight
  )

  let plainState = decodeState("""
  {"version":1,"balance":10,"transactions":[],"budgets":[]}
  """)
  expect(
    "BankState decodes when session and corridor are absent",
    plainState != nil && plainState?.session == nil && plainState?.corridor == nil && plainState?.balance == 10
  )

  let decoded = decodeState("""
  {"version":1,"balance":10,"transactions":[],"budgets":[],"session":{"status":"signed_out_elsewhere","deviceDetail":"iPhone 15"},"corridor":{"id":"eu","notice":"european_launch"}}
  """)
  expect(
    "BankState decodes session status and corridor notice from GET /state",
    decoded?.session?.status == .signedOutElsewhere
      && decoded?.session?.deviceDetail == "iPhone 15"
      && decoded?.corridor?.id == "eu"
      && decoded?.corridor?.notice == "european_launch"
  )
}

private func decodeState(_ json: String) -> BankState? {
  try? JSONDecoder().decode(BankState.self, from: Data(json.utf8))
}

private func bannerContent(_ presentation: SessionBannerPresentation) -> SessionBannerContent? {
  if case .banner(let content) = presentation { return content }
  return nil
}

private func bannerMessage(_ presentation: SessionBannerPresentation) -> String? {
  bannerContent(presentation)?.coreMessage
}

private func bannerCore(_ presentation: SessionBannerPresentation) -> String? {
  bannerContent(presentation)?.coreMessage
}

private func bannerDetail(_ presentation: SessionBannerPresentation) -> String? {
  bannerContent(presentation)?.detail
}

private func bannerLabel(_ presentation: SessionBannerPresentation) -> String? {
  bannerContent(presentation)?.accessibilityLabel
}

private func bannerKind(_ presentation: SessionBannerPresentation) -> SessionBannerKind? {
  bannerContent(presentation)?.kind
}

private func bannerDismissible(_ presentation: SessionBannerPresentation) -> Bool {
  bannerContent(presentation)?.dismissible ?? false
}

private func bannerMetrics(_ presentation: SessionBannerPresentation) -> String? {
  bannerContent(presentation)?.metricsState
}
