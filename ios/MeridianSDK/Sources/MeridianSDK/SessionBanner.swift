import Foundation

/// How the auth screen presents the rehearsal session the customer already selected.
/// This is not a new authentication factor: the session id is still `X-Rehearsal-Session`.
public enum SessionPhase: String, Equatable, Sendable {
  case loading
  case healthy
  case expiring
  case activeElsewhere
  case signedOut
  case unresolved
}

public enum SessionTiming {
  /// Client-side lifetime of the same rehearsal session, measured from sign-in.
  public static let lifetime: TimeInterval = 30 * 60
  /// Window before expiry in which the banner warns without blocking.
  public static let warningWindow: TimeInterval = 5 * 60
  /// How long a session probe may run before the banner stops asserting a state.
  public static let probeTimeout: TimeInterval = 8
}

public enum SessionProbeError: Error, Equatable {
  case timedOut
}

public struct BannerColor: Equatable, Sendable {
  public let red: Int
  public let green: Int
  public let blue: Int

  public init(red: Int, green: Int, blue: Int) {
    self.red = red
    self.green = green
    self.blue = blue
  }
}

public enum SessionBannerPalette {
  public static let expiringForeground = BannerColor(red: 63, green: 42, blue: 8)
  public static let expiringBackground = BannerColor(red: 251, green: 243, blue: 217)
  public static let expiringActionForeground = BannerColor(red: 255, green: 248, blue: 232)
  public static let expiringActionBackground = BannerColor(red: 63, green: 42, blue: 8)

  public static let signedOutForeground = BannerColor(red: 74, green: 18, blue: 16)
  public static let signedOutBackground = BannerColor(red: 248, green: 230, blue: 227)
  public static let signedOutActionForeground = BannerColor(red: 255, green: 255, blue: 255)
  public static let signedOutActionBackground = BannerColor(red: 74, green: 18, blue: 16)

  public static let elsewhereForeground = BannerColor(red: 14, green: 42, blue: 51)
  public static let elsewhereBackground = BannerColor(red: 232, green: 241, blue: 244)

  public static let neutralForeground = BannerColor(red: 28, green: 43, blue: 36)
  public static let neutralBackground = BannerColor(red: 231, green: 235, blue: 228)
  public static let neutralActionForeground = BannerColor(red: 255, green: 255, blue: 255)
  public static let neutralActionBackground = BannerColor(red: 28, green: 43, blue: 36)

  public static let quietForeground = BannerColor(red: 45, green: 68, blue: 58)
  public static let quietBackground = BannerColor(red: 248, green: 249, blue: 246)
  public static let skeleton = BannerColor(red: 213, green: 221, blue: 212)
}

public let sessionBannerMinimumContrast = 4.5
public let sessionBannerNameLimit = 32

public enum SessionProbe: Equatable, Sendable {
  case pending
  case absent
  case succeeded(SessionFacts)
  case failed
  case timedOut
}

public struct SessionFacts: Equatable, Sendable {
  public var sessionId: String
  public var accountName: String
  public var establishedOnDevice: String
  public var currentDevice: String
  public var authenticatedAt: Date
  public var expiresAt: Date
  public var now: Date

  public init(
    sessionId: String,
    accountName: String,
    establishedOnDevice: String,
    currentDevice: String,
    authenticatedAt: Date,
    expiresAt: Date,
    now: Date
  ) {
    self.sessionId = sessionId
    self.accountName = accountName
    self.establishedOnDevice = establishedOnDevice
    self.currentDevice = currentDevice
    self.authenticatedAt = authenticatedAt
    self.expiresAt = expiresAt
    self.now = now
  }

  public init(stored: StoredSession, currentDevice: String, now: Date) {
    self.init(
      sessionId: stored.sessionId,
      accountName: stored.accountName,
      establishedOnDevice: stored.deviceName,
      currentDevice: currentDevice,
      authenticatedAt: stored.authenticatedAt,
      expiresAt: stored.expiresAt,
      now: now
    )
  }

  public var establishedOnAnotherDevice: Bool {
    let established = establishedOnDevice.trimmingCharacters(in: .whitespacesAndNewlines)
    let current = currentDevice.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !established.isEmpty, !current.isEmpty else { return false }
    return established.caseInsensitiveCompare(current) != .orderedSame
  }
}

public struct StoredSession: Codable, Equatable, Sendable {
  public var endpoint: String
  public var sessionId: String
  public var accountName: String
  public var deviceName: String
  public var authenticatedAt: Date
  public var expiresAt: Date

  public init(
    endpoint: String,
    sessionId: String,
    accountName: String,
    deviceName: String,
    authenticatedAt: Date,
    expiresAt: Date
  ) {
    self.endpoint = endpoint
    self.sessionId = sessionId
    self.accountName = accountName
    self.deviceName = deviceName
    self.authenticatedAt = authenticatedAt
    self.expiresAt = expiresAt
  }
}

public struct SessionFieldMemory: Codable, Equatable, Sendable {
  public var endpoint: String
  public var sessionId: String

  public init(endpoint: String, sessionId: String) {
    self.endpoint = endpoint
    self.sessionId = sessionId
  }
}

public protocol SessionStore: AnyObject {
  func load() -> StoredSession?
  func save(_ session: StoredSession)
  func clear()
  func loadFields() -> SessionFieldMemory?
  func saveFields(_ fields: SessionFieldMemory)
}

public final class MemorySessionStore: SessionStore, @unchecked Sendable {
  private var session: StoredSession?
  private var fields: SessionFieldMemory?

  public init() {}

  public func load() -> StoredSession? { session }

  public func save(_ session: StoredSession) {
    self.session = session
    saveFields(SessionFieldMemory(endpoint: session.endpoint, sessionId: session.sessionId))
  }

  public func clear() { session = nil }

  public func loadFields() -> SessionFieldMemory? { fields }

  public func saveFields(_ fields: SessionFieldMemory) { self.fields = fields }
}

public final class UserDefaultsSessionStore: SessionStore, @unchecked Sendable {
  private let defaults: UserDefaults
  private let sessionKey: String
  private let fieldsKey: String

  public init(
    defaults: UserDefaults = .standard,
    sessionKey: String = "meridian.authSession",
    fieldsKey: String = "meridian.authFields"
  ) {
    self.defaults = defaults
    self.sessionKey = sessionKey
    self.fieldsKey = fieldsKey
  }

  public func load() -> StoredSession? {
    guard let data = defaults.data(forKey: sessionKey) else { return nil }
    return try? JSONDecoder().decode(StoredSession.self, from: data)
  }

  public func save(_ session: StoredSession) {
    if let data = try? JSONEncoder().encode(session) {
      defaults.set(data, forKey: sessionKey)
    }
    saveFields(SessionFieldMemory(endpoint: session.endpoint, sessionId: session.sessionId))
  }

  public func clear() {
    defaults.removeObject(forKey: sessionKey)
  }

  public func loadFields() -> SessionFieldMemory? {
    guard let data = defaults.data(forKey: fieldsKey) else { return nil }
    return try? JSONDecoder().decode(SessionFieldMemory.self, from: data)
  }

  public func saveFields(_ fields: SessionFieldMemory) {
    if let data = try? JSONEncoder().encode(fields) {
      defaults.set(data, forKey: fieldsKey)
    }
  }
}

public enum AuthAccessibility {
  public static let banner = "auth.sessionBanner"
  public static let bannerAction = "auth.sessionBanner.action"
  public static let skeleton = "auth.sessionBanner.skeleton"
  public static let endpoint = "auth.endpoint"
  public static let room = "auth.room"
  public static let connect = "auth.connect"
  public static let payment = "auth.payment"

  public static let bannerPriority = 100.0
  public static let actionPriority = 90.0
  public static let endpointPriority = 30.0
  public static let roomPriority = 20.0
  public static let connectPriority = 10.0
  public static let paymentPriority = 0.0

  /// Keyboard and screen-reader order. The banner and its action come first.
  public static func focusOrder(showsSkeleton: Bool, showsAction: Bool, allowsPayment: Bool) -> [String] {
    var order: [String] = [showsSkeleton ? skeleton : banner]
    if showsAction && !showsSkeleton {
      order.append(bannerAction)
    }
    order.append(contentsOf: [endpoint, room, connect])
    if allowsPayment {
      order.append(payment)
    }
    return order
  }
}

public struct SessionBannerModel: Equatable, Sendable {
  public var phase: SessionPhase
  public var title: String
  public var message: String
  public var actionTitle: String?
  public var blocking: Bool
  public var allowsPayment: Bool
  public var showsSkeleton: Bool
  public var foreground: BannerColor
  public var background: BannerColor
  public var actionForeground: BannerColor
  public var actionBackground: BannerColor
  public var liveAnnouncement: String
  public var accountName: String?
  public var deviceName: String?

  public init(
    phase: SessionPhase,
    title: String,
    message: String,
    actionTitle: String?,
    blocking: Bool,
    allowsPayment: Bool,
    showsSkeleton: Bool,
    foreground: BannerColor,
    background: BannerColor,
    actionForeground: BannerColor,
    actionBackground: BannerColor,
    liveAnnouncement: String,
    accountName: String?,
    deviceName: String?
  ) {
    self.phase = phase
    self.title = title
    self.message = message
    self.actionTitle = actionTitle
    self.blocking = blocking
    self.allowsPayment = allowsPayment
    self.showsSkeleton = showsSkeleton
    self.foreground = foreground
    self.background = background
    self.actionForeground = actionForeground
    self.actionBackground = actionBackground
    self.liveAnnouncement = liveAnnouncement
    self.accountName = accountName
    self.deviceName = deviceName
  }

  public static var loading: SessionBannerModel { resolve(.pending) }

  public var focusOrder: [String] {
    AuthAccessibility.focusOrder(
      showsSkeleton: showsSkeleton,
      showsAction: actionTitle != nil,
      allowsPayment: allowsPayment
    )
  }

  public static func resolve(
    _ probe: SessionProbe,
    warningWindow: TimeInterval = SessionTiming.warningWindow
  ) -> SessionBannerModel {
    switch probe {
    case .pending:
      return make(
        phase: .loading,
        title: "",
        message: "",
        actionTitle: nil,
        blocking: false,
        allowsPayment: false,
        showsSkeleton: true,
        foreground: SessionBannerPalette.quietForeground,
        background: SessionBannerPalette.quietBackground,
        actionForeground: SessionBannerPalette.quietForeground,
        actionBackground: SessionBannerPalette.quietBackground,
        liveAnnouncement: "Checking your session"
      )
    case .absent:
      return signedOut()
    case .failed, .timedOut:
      return unresolved()
    case let .succeeded(facts):
      let remaining = facts.expiresAt.timeIntervalSince(facts.now)
      if remaining <= 0 { return signedOut() }
      if remaining <= warningWindow { return expiring() }
      if facts.establishedOnAnotherDevice { return elsewhere(facts) }
      return healthy()
    }
  }

  private static func healthy() -> SessionBannerModel {
    make(
      phase: .healthy,
      title: "Session active",
      message: "Session active",
      actionTitle: nil,
      blocking: false,
      allowsPayment: true,
      showsSkeleton: false,
      foreground: SessionBannerPalette.quietForeground,
      background: SessionBannerPalette.quietBackground,
      actionForeground: SessionBannerPalette.quietForeground,
      actionBackground: SessionBannerPalette.quietBackground,
      liveAnnouncement: "Session active"
    )
  }

  private static func expiring() -> SessionBannerModel {
    let message = "Your session is about to expire. Sign in again to continue."
    return make(
      phase: .expiring,
      title: "Session expiring",
      message: message,
      actionTitle: "Sign in again",
      blocking: false,
      allowsPayment: true,
      showsSkeleton: false,
      foreground: SessionBannerPalette.expiringForeground,
      background: SessionBannerPalette.expiringBackground,
      actionForeground: SessionBannerPalette.expiringActionForeground,
      actionBackground: SessionBannerPalette.expiringActionBackground,
      liveAnnouncement: message
    )
  }

  private static func signedOut() -> SessionBannerModel {
    let message = "You've been signed out. Sign in to continue."
    return make(
      phase: .signedOut,
      title: "Signed out",
      message: message,
      actionTitle: "Sign in",
      blocking: true,
      allowsPayment: false,
      showsSkeleton: false,
      foreground: SessionBannerPalette.signedOutForeground,
      background: SessionBannerPalette.signedOutBackground,
      actionForeground: SessionBannerPalette.signedOutActionForeground,
      actionBackground: SessionBannerPalette.signedOutActionBackground,
      liveAnnouncement: message
    )
  }

  private static func unresolved() -> SessionBannerModel {
    let message = "We couldn't confirm your session. You can continue."
    return make(
      phase: .unresolved,
      title: "Session status unavailable",
      message: message,
      actionTitle: "Try again",
      blocking: false,
      allowsPayment: true,
      showsSkeleton: false,
      foreground: SessionBannerPalette.neutralForeground,
      background: SessionBannerPalette.neutralBackground,
      actionForeground: SessionBannerPalette.neutralActionForeground,
      actionBackground: SessionBannerPalette.neutralActionBackground,
      liveAnnouncement: message
    )
  }

  private static func elsewhere(_ facts: SessionFacts) -> SessionBannerModel {
    let accountSource = facts.accountName.trimmingCharacters(in: .whitespacesAndNewlines)
    let deviceSource = facts.establishedOnDevice.trimmingCharacters(in: .whitespacesAndNewlines)
    let account = truncateForBanner(accountSource.isEmpty ? "your account" : accountSource)
    let device = truncateForBanner(deviceSource.isEmpty ? "another device" : deviceSource)
    let message = "Signed in elsewhere on \(device) for \(account)."
    return make(
      phase: .activeElsewhere,
      title: "Signed in elsewhere",
      message: message,
      actionTitle: nil,
      blocking: false,
      allowsPayment: true,
      showsSkeleton: false,
      foreground: SessionBannerPalette.elsewhereForeground,
      background: SessionBannerPalette.elsewhereBackground,
      actionForeground: SessionBannerPalette.elsewhereForeground,
      actionBackground: SessionBannerPalette.elsewhereBackground,
      liveAnnouncement: message,
      accountName: account,
      deviceName: device
    )
  }

  private static func make(
    phase: SessionPhase,
    title: String,
    message: String,
    actionTitle: String?,
    blocking: Bool,
    allowsPayment: Bool,
    showsSkeleton: Bool,
    foreground: BannerColor,
    background: BannerColor,
    actionForeground: BannerColor,
    actionBackground: BannerColor,
    liveAnnouncement: String,
    accountName: String? = nil,
    deviceName: String? = nil
  ) -> SessionBannerModel {
    SessionBannerModel(
      phase: phase,
      title: title,
      message: message,
      actionTitle: actionTitle,
      blocking: blocking,
      allowsPayment: allowsPayment,
      showsSkeleton: showsSkeleton,
      foreground: foreground,
      background: background,
      actionForeground: actionForeground,
      actionBackground: actionBackground,
      liveAnnouncement: liveAnnouncement,
      accountName: accountName,
      deviceName: deviceName
    )
  }
}

public func truncateForBanner(_ value: String, limit: Int = sessionBannerNameLimit) -> String {
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  guard limit > 0 else { return "" }
  guard trimmed.count > limit else { return trimmed }
  let keep = trimmed.index(trimmed.startIndex, offsetBy: limit - 1)
  return String(trimmed[..<keep]) + "…"
}

public func contrastRatio(_ foreground: BannerColor, _ background: BannerColor) -> Double {
  func channel(_ value: Int) -> Double {
    let unit = Double(value) / 255
    return unit <= 0.04045 ? unit / 12.92 : pow((unit + 0.055) / 1.055, 2.4)
  }
  func luminance(_ color: BannerColor) -> Double {
    (0.2126 * channel(color.red)) + (0.7152 * channel(color.green)) + (0.0722 * channel(color.blue))
  }
  let lighter = max(luminance(foreground), luminance(background))
  let darker = min(luminance(foreground), luminance(background))
  return (lighter + 0.05) / (darker + 0.05)
}

public func meetsSessionBannerContrast(_ model: SessionBannerModel) -> Bool {
  guard contrastRatio(model.foreground, model.background) >= sessionBannerMinimumContrast else {
    return false
  }
  guard model.actionTitle != nil else { return true }
  return contrastRatio(model.actionForeground, model.actionBackground) >= sessionBannerMinimumContrast
}

public func withSessionTimeout<T: Sendable>(
  _ seconds: TimeInterval,
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { try await operation() }
    group.addTask {
      try await Task.sleep(for: .seconds(seconds))
      throw SessionProbeError.timedOut
    }
    defer { group.cancelAll() }
    guard let value = try await group.next() else {
      throw SessionProbeError.timedOut
    }
    return value
  }
}
