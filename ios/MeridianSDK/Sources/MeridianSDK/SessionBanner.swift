import Foundation
#if os(iOS) || os(macOS)
import os
#endif

// MARK: - Copy

/// Approved payment-screen session banner copy.
public enum SessionBannerCopy {
  public static let active = "You're securely signed in"
  public static let expiring = "Your session ends soon"
  public static let signedOutElsewhere = "We signed you out on another device"
  public static let lookupFailed = "We couldn't confirm your session. Try again"
  /// Corridor-only lines keep this prefix intact and truncate the suffix first.
  public static let europeanLaunchCore = "New: payments now supported"
  public static let europeanLaunchDetail = "in your European corridor"
  public static let europeanLaunch = europeanLaunchCore + " " + europeanLaunchDetail
  public static let europeanLaunchNotice = "european_launch"
  public static let dismissedAnnouncement = "Session banner dismissed"
}

public enum SessionBannerKind: String, Equatable, Hashable, CaseIterable {
  case active
  case expiring
  case signedOutElsewhere = "signed_out_elsewhere"
  case lookupFailed = "lookup_failed"
  case corridorNotice = "corridor_notice"
}

// MARK: - Presentation

public struct SessionBannerIdentity: Equatable, Hashable {
  public var kind: SessionBannerKind
  public var corridorID: String?
  public var notice: String?
  public var deviceDetail: String?

  public init(
    kind: SessionBannerKind,
    corridorID: String? = nil,
    notice: String? = nil,
    deviceDetail: String? = nil
  ) {
    self.kind = kind
    self.corridorID = corridorID
    self.notice = notice
    self.deviceDetail = deviceDetail
  }
}

public struct SessionBannerContent: Equatable {
  public var kind: SessionBannerKind
  public var coreMessage: String
  public var detail: String?
  public var dismissible: Bool
  public var identity: SessionBannerIdentity
  /// Observability bucket. Corridor notices are part of the state key.
  public var metricsState: String
  /// Full copy for VoiceOver. Visual truncation does not remove this.
  public var accessibilityLabel: String

  public init(
    kind: SessionBannerKind,
    coreMessage: String,
    detail: String?,
    dismissible: Bool,
    identity: SessionBannerIdentity,
    metricsState: String,
    accessibilityLabel: String
  ) {
    self.kind = kind
    self.coreMessage = coreMessage
    self.detail = detail
    self.dismissible = dismissible
    self.identity = identity
    self.metricsState = metricsState
    self.accessibilityLabel = accessibilityLabel
  }
}

public enum SessionBannerPresentation: Equatable {
  case hidden
  case skeleton
  case banner(SessionBannerContent)
}

public struct SessionBannerQuery: Equatable {
  public var isResolving: Bool
  public var session: RehearsalSessionInfo?
  public var corridor: CorridorInfo?
  public var lookupFailed: Bool

  public init(
    isResolving: Bool = false,
    session: RehearsalSessionInfo? = nil,
    corridor: CorridorInfo? = nil,
    lookupFailed: Bool = false
  ) {
    self.isResolving = isResolving
    self.session = session
    self.corridor = corridor
    self.lookupFailed = lookupFailed
  }
}

public struct SessionBannerAnnouncement: Equatable {
  public var id: Int
  public var message: String

  public init(id: Int, message: String) {
    self.id = id
    self.message = message
  }
}

public struct SessionBannerStep: Equatable {
  public var presentation: SessionBannerPresentation
  public var announcement: SessionBannerAnnouncement?

  public init(presentation: SessionBannerPresentation, announcement: SessionBannerAnnouncement?) {
    self.presentation = presentation
    self.announcement = announcement
  }
}

/// Successful GET /state confirms the current X-Rehearsal-Session.
/// A missing session object is active; it does not call a separate auth API.
public func confirmedSession(from state: BankState) -> RehearsalSessionInfo {
  state.session ?? RehearsalSessionInfo(status: .active)
}

public func sessionBannerQuery(
  isResolving: Bool = false,
  state: BankState?,
  lookupFailed: Bool = false
) -> SessionBannerQuery {
  if lookupFailed {
    return SessionBannerQuery(isResolving: false, session: nil, corridor: nil, lookupFailed: true)
  }
  guard let state else {
    return SessionBannerQuery(isResolving: isResolving, session: nil, corridor: nil, lookupFailed: false)
  }
  return SessionBannerQuery(
    isResolving: isResolving,
    session: confirmedSession(from: state),
    corridor: state.corridor,
    lookupFailed: false
  )
}

public func resolveSessionBanner(
  _ query: SessionBannerQuery,
  dismissed: Set<SessionBannerIdentity> = []
) -> SessionBannerPresentation {
  if query.lookupFailed {
    return .banner(lookupFailedBanner())
  }
  // Skeleton only while the first snapshot is still unknown, so a refresh
  // does not replace a confirmed banner with a flash of the wrong state.
  if query.isResolving && query.session == nil {
    return .skeleton
  }
  let corridor = recognizedCorridor(query.corridor)
  if query.session == nil && corridor == nil {
    return .hidden
  }
  let content = makeBanner(session: query.session, corridor: corridor)
  if content.dismissible && dismissed.contains(content.identity) {
    return .hidden
  }
  return .banner(content)
}

private struct RecognizedCorridor: Equatable {
  var id: String
  var notice: String
  var message: String
}

private func recognizedCorridor(_ info: CorridorInfo?) -> RecognizedCorridor? {
  guard
    let info,
    let notice = info.notice?.trimmingCharacters(in: .whitespacesAndNewlines),
    notice == SessionBannerCopy.europeanLaunchNotice
  else {
    return nil
  }
  let id = info.id.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !id.isEmpty else { return nil }
  return RecognizedCorridor(id: id, notice: notice, message: SessionBannerCopy.europeanLaunch)
}

private func lookupFailedBanner() -> SessionBannerContent {
  SessionBannerContent(
    kind: .lookupFailed,
    coreMessage: SessionBannerCopy.lookupFailed,
    detail: nil,
    dismissible: false,
    identity: SessionBannerIdentity(kind: .lookupFailed),
    metricsState: SessionBannerKind.lookupFailed.rawValue,
    accessibilityLabel: SessionBannerCopy.lookupFailed
  )
}

private func makeBanner(session: RehearsalSessionInfo?, corridor: RecognizedCorridor?) -> SessionBannerContent {
  if let session {
    let kind: SessionBannerKind
    let core: String
    switch session.status {
    case .active:
      kind = .active
      core = SessionBannerCopy.active
    case .expiring:
      kind = .expiring
      core = SessionBannerCopy.expiring
    case .signedOutElsewhere:
      kind = .signedOutElsewhere
      core = SessionBannerCopy.signedOutElsewhere
    }
    var details: [String] = []
    let device = session.deviceDetail?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let device, !device.isEmpty {
      details.append(device)
    }
    if let corridor {
      details.append(corridor.message)
    }
    let detail = details.isEmpty ? nil : details.joined(separator: " · ")
    let label = detail.map { "\(core). \($0)" } ?? core
    let metrics = corridor.map { "\(kind.rawValue)+\($0.notice)" } ?? kind.rawValue
    return SessionBannerContent(
      kind: kind,
      coreMessage: core,
      detail: detail,
      dismissible: true,
      identity: SessionBannerIdentity(
        kind: kind,
        corridorID: corridor?.id,
        notice: corridor?.notice,
        deviceDetail: device
      ),
      metricsState: metrics,
      accessibilityLabel: label
    )
  }

  return SessionBannerContent(
    kind: .corridorNotice,
    coreMessage: SessionBannerCopy.europeanLaunchCore,
    detail: SessionBannerCopy.europeanLaunchDetail,
    dismissible: true,
    identity: SessionBannerIdentity(
      kind: .corridorNotice,
      corridorID: corridor?.id,
      notice: corridor?.notice
    ),
    metricsState: SessionBannerKind.corridorNotice.rawValue,
    accessibilityLabel: SessionBannerCopy.europeanLaunch
  )
}

// MARK: - Engine

public protocol SessionBannerLogSink: AnyObject {
  func log(_ line: String)
}

public final class DefaultSessionBannerLogSink: SessionBannerLogSink {
  public init() {}

  public func log(_ line: String) {
    #if os(iOS) || os(macOS)
    Logger(subsystem: "com.beaconstone.meridian", category: "session-banner")
      .info("\(line, privacy: .public)")
    #else
    print(line)
    #endif
  }
}

public final class SessionBannerMetrics {
  public private(set) var impressions: [String: Int] = [:]
  public private(set) var dismissals: [String: Int] = [:]
  public private(set) var log: [String] = []
  private let logSink: any SessionBannerLogSink

  public init(logSink: any SessionBannerLogSink = DefaultSessionBannerLogSink()) {
    self.logSink = logSink
  }

  public func recordImpression(state: String) {
    impressions[state, default: 0] += 1
  }

  public func recordDismissal(state: String) {
    dismissals[state, default: 0] += 1
    let shown = impressions[state] ?? 0
    let dismissed = dismissals[state] ?? 0
    let rate = shown > 0 ? Double(dismissed) / Double(shown) : 0
    let rateText = String(format: "%.4f", rate)
    let line = "session_banner_dismissal state=\(state) dismissals=\(dismissed) impressions=\(shown) rate=\(rateText)"
    log.append(line)
    logSink.log(line)
  }

  public func dismissalRate(state: String) -> Double? {
    let shown = impressions[state] ?? 0
    guard shown > 0 else { return nil }
    return Double(dismissals[state] ?? 0) / Double(shown)
  }
}

public struct SessionBannerEngine {
  private var dismissed: Set<SessionBannerIdentity> = []
  private var current: SessionBannerPresentation = .hidden
  private var visibleIdentity: SessionBannerIdentity?
  private var announcedIdentity: SessionBannerIdentity?
  private var announcementID = 0
  public let metrics: SessionBannerMetrics

  public init(logSink: any SessionBannerLogSink = DefaultSessionBannerLogSink()) {
    self.metrics = SessionBannerMetrics(logSink: logSink)
  }

  public mutating func update(_ query: SessionBannerQuery) -> SessionBannerStep {
    let presentation = resolveSessionBanner(query, dismissed: dismissed)
    current = presentation
    guard case .banner(let content) = presentation else {
      visibleIdentity = nil
      announcedIdentity = nil
      return SessionBannerStep(presentation: presentation, announcement: nil)
    }
    if visibleIdentity != content.identity {
      metrics.recordImpression(state: content.metricsState)
      visibleIdentity = content.identity
    }
    guard announcedIdentity != content.identity else {
      return SessionBannerStep(presentation: presentation, announcement: nil)
    }
    announcedIdentity = content.identity
    return SessionBannerStep(
      presentation: presentation,
      announcement: nextAnnouncement(content.accessibilityLabel)
    )
  }

  public mutating func dismiss() -> SessionBannerStep {
    guard case .banner(let content) = current, content.dismissible else {
      return SessionBannerStep(presentation: current, announcement: nil)
    }
    dismissed.insert(content.identity)
    metrics.recordDismissal(state: content.metricsState)
    current = .hidden
    visibleIdentity = nil
    announcedIdentity = nil
    return SessionBannerStep(
      presentation: .hidden,
      announcement: nextAnnouncement(SessionBannerCopy.dismissedAnnouncement)
    )
  }

  /// Clears dismissal memory for a new rehearsal session. Metrics stay cumulative.
  public mutating func resetSession() {
    dismissed.removeAll()
    current = .hidden
    visibleIdentity = nil
    announcedIdentity = nil
  }

  private mutating func nextAnnouncement(_ message: String) -> SessionBannerAnnouncement {
    announcementID += 1
    return SessionBannerAnnouncement(id: announcementID, message: message)
  }
}

// MARK: - One-line layout

public enum SessionBannerLayout {
  /// Smallest iOS 16 phone width (iPhone SE 2nd generation / iPhone 13 mini).
  public static let smallestDeviceWidth: Double = 375
  public static let bannerHorizontalPadding: Double = 16
  public static let dismissControlWidth: Double = 44
  public static let itemSpacing: Double = 8
  public static let fontSize: Double = 13
  /// Conservative average advance for 13pt SF text, so detail yields before the core.
  public static let characterAdvance: Double = 7.8

  public static func textWidth(_ text: String) -> Double {
    Double(text.count) * characterAdvance
  }

  public static func textBudget(contentWidth: Double, dismissible: Bool) -> Double {
    let padding = bannerHorizontalPadding * 2
    let dismiss = dismissible ? dismissControlWidth + itemSpacing : 0
    return max(0, contentWidth - padding - dismiss)
  }
}

public struct SessionBannerLineFit: Equatable {
  public var core: String
  public var detail: String?
  public var corePreserved: Bool
  public var detailTruncated: Bool

  public init(core: String, detail: String?, corePreserved: Bool, detailTruncated: Bool) {
    self.core = core
    self.detail = detail
    self.corePreserved = corePreserved
    self.detailTruncated = detailTruncated
  }
}

public func fitSessionBannerLine(
  core: String,
  detail: String?,
  dismissible: Bool,
  contentWidth: Double
) -> SessionBannerLineFit {
  let budget = SessionBannerLayout.textBudget(contentWidth: contentWidth, dismissible: dismissible)
  if let detail, !detail.isEmpty {
    let remaining = budget - SessionBannerLayout.textWidth(core) - SessionBannerLayout.itemSpacing
    if SessionBannerLayout.textWidth(detail) <= remaining {
      return SessionBannerLineFit(core: core, detail: detail, corePreserved: true, detailTruncated: false)
    }
    let truncated = remaining > 0 ? truncateBannerDetail(detail, to: remaining) : nil
    return SessionBannerLineFit(core: core, detail: truncated, corePreserved: true, detailTruncated: true)
  }
  if SessionBannerLayout.textWidth(core) <= budget {
    return SessionBannerLineFit(core: core, detail: nil, corePreserved: true, detailTruncated: false)
  }
  return SessionBannerLineFit(
    core: truncateBannerDetail(core, to: budget) ?? core,
    detail: nil,
    corePreserved: false,
    detailTruncated: false
  )
}

private func truncateBannerDetail(_ text: String, to width: Double) -> String? {
  let ellipsis = "…"
  let ellipsisWidth = SessionBannerLayout.textWidth(ellipsis)
  if width < ellipsisWidth {
    return nil
  }
  if SessionBannerLayout.textWidth(text) <= width {
    return text
  }
  var end = text.count
  while end > 0 {
    let prefix = String(text.prefix(end)).trimmingCharacters(in: .whitespacesAndNewlines)
    if prefix.isEmpty {
      end -= 1
      continue
    }
    let candidate = prefix + ellipsis
    if SessionBannerLayout.textWidth(candidate) <= width {
      return candidate
    }
    end -= 1
  }
  return ellipsis
}

// MARK: - Color tokens

public enum SessionBannerColorScheme: Equatable {
  case light
  case dark
}

/// Tokens shared with the account balance card (`#142C35` / `#F8F9F6`).
public enum MeridianBannerTokens {
  public static let balanceCardBackground = "142C35"
  public static let balanceCardForeground = "F8F9F6"
  public static let infoBackground = "EAF0E5"
  public static let expiringBackground = "F3E6C8"
  public static let signedOutBackground = "F6E4C4"
  public static let lookupFailedBackground = "F8E4E0"
  public static let expiringDarkBackground = "3A3424"
  public static let signedOutDarkBackground = "3F3328"
  public static let lookupFailedDarkBackground = "3A2220"
}

public struct SessionBannerRGB: Equatable {
  public var red: Double
  public var green: Double
  public var blue: Double

  public init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  public init(hex: String) {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") {
      value.removeFirst()
    }
    let parsed = UInt32(value, radix: 16) ?? 0
    red = Double((parsed >> 16) & 0xFF) / 255
    green = Double((parsed >> 8) & 0xFF) / 255
    blue = Double(parsed & 0xFF) / 255
  }
}

public struct SessionBannerPalette: Equatable {
  public var backgroundHex: String
  public var foregroundHex: String
  public var background: SessionBannerRGB
  public var foreground: SessionBannerRGB
  public var contrastRatio: Double

  public init(backgroundHex: String, foregroundHex: String) {
    self.backgroundHex = backgroundHex
    self.foregroundHex = foregroundHex
    self.background = SessionBannerRGB(hex: backgroundHex)
    self.foreground = SessionBannerRGB(hex: foregroundHex)
    self.contrastRatio = sessionBannerContrastRatio(foreground, background)
  }
}

public func sessionBannerContrastRatio(_ foreground: SessionBannerRGB, _ background: SessionBannerRGB) -> Double {
  func luminance(_ color: SessionBannerRGB) -> Double {
    func channel(_ value: Double) -> Double {
      if value <= 0.04045 {
        return value / 12.92
      }
      return pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
  }
  let lighter = max(luminance(foreground), luminance(background))
  let darker = min(luminance(foreground), luminance(background))
  return (lighter + 0.05) / (darker + 0.05)
}

public func sessionBannerPalette(
  kind: SessionBannerKind,
  colorScheme: SessionBannerColorScheme
) -> SessionBannerPalette {
  switch (kind, colorScheme) {
  case (.active, .light), (.corridorNotice, .light):
    return SessionBannerPalette(
      backgroundHex: MeridianBannerTokens.infoBackground,
      foregroundHex: MeridianBannerTokens.balanceCardBackground
    )
  case (.expiring, .light):
    return SessionBannerPalette(
      backgroundHex: MeridianBannerTokens.expiringBackground,
      foregroundHex: MeridianBannerTokens.balanceCardBackground
    )
  case (.signedOutElsewhere, .light):
    return SessionBannerPalette(
      backgroundHex: MeridianBannerTokens.signedOutBackground,
      foregroundHex: MeridianBannerTokens.balanceCardBackground
    )
  case (.lookupFailed, .light):
    return SessionBannerPalette(
      backgroundHex: MeridianBannerTokens.lookupFailedBackground,
      foregroundHex: MeridianBannerTokens.balanceCardBackground
    )
  case (.active, .dark), (.corridorNotice, .dark):
    return SessionBannerPalette(
      backgroundHex: MeridianBannerTokens.balanceCardBackground,
      foregroundHex: MeridianBannerTokens.balanceCardForeground
    )
  case (.expiring, .dark):
    return SessionBannerPalette(
      backgroundHex: MeridianBannerTokens.expiringDarkBackground,
      foregroundHex: MeridianBannerTokens.balanceCardForeground
    )
  case (.signedOutElsewhere, .dark):
    return SessionBannerPalette(
      backgroundHex: MeridianBannerTokens.signedOutDarkBackground,
      foregroundHex: MeridianBannerTokens.balanceCardForeground
    )
  case (.lookupFailed, .dark):
    return SessionBannerPalette(
      backgroundHex: MeridianBannerTokens.lookupFailedDarkBackground,
      foregroundHex: MeridianBannerTokens.balanceCardForeground
    )
  }
}
