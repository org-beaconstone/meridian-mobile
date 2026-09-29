import Foundation

/// Visual session states for the payment and authentication screen.
/// Unknown and expired are recovery states. They never block the payment form.
public enum SessionVisualState: String, Equatable, CaseIterable {
  case active
  case expiring
  case activeElsewhere
  case signedOut
  case expired
  case unknown
}

public enum SessionProbeResult: Equatable {
  /// No rehearsal session has been selected yet.
  case notSignedIn
  /// The selected session answered a health or state read.
  case confirmed
  /// The selected session could not be confirmed. This is not an expiry.
  case unreachable
  /// The selected session was rejected (HTTP 401 or 403).
  case rejected
}

public enum SessionFailure: Equatable {
  case timeout
  case unauthorized
  case http(Int)
  case other
}

/// sRGB token. Contrast uses the WCAG 2.1 relative luminance formula.
public struct SessionColor: Equatable {
  public let token: String
  public let red: Int
  public let green: Int
  public let blue: Int

  public init(token: String, red: Int, green: Int, blue: Int) {
    self.token = token
    self.red = red
    self.green = green
    self.blue = blue
  }

  public func relativeLuminance() -> Double {
    func channel(_ value: Int) -> Double {
      let c = Double(value) / 255.0
      if c <= 0.04045 { return c / 12.92 }
      return pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
  }

  public func contrastRatio(against other: SessionColor) -> Double {
    let lighter = max(relativeLuminance(), other.relativeLuminance())
    let darker = min(relativeLuminance(), other.relativeLuminance())
    return (lighter + 0.05) / (darker + 0.05)
  }
}

/// Payment fields a session refresh must leave untouched.
public struct PaymentContext: Equatable {
  public var recipientId: String
  public var amount: String
  public var reference: String
  public var method: PaymentMethod
  public var reviewing: Bool
  public var idempotencyKey: String

  public init(
    recipientId: String,
    amount: String,
    reference: String,
    method: PaymentMethod,
    reviewing: Bool,
    idempotencyKey: String
  ) {
    self.recipientId = recipientId
    self.amount = amount
    self.reference = reference
    self.method = method
    self.reviewing = reviewing
    self.idempotencyKey = idempotencyKey
  }
}

public struct SessionClock: Equatable {
  public var sessionId: String?
  public var expiresAtMs: Int64?
  public var activeElsewhere: Bool
  public var probe: SessionProbeResult

  public init(
    sessionId: String? = nil,
    expiresAtMs: Int64? = nil,
    activeElsewhere: Bool = false,
    probe: SessionProbeResult = .notSignedIn
  ) {
    self.sessionId = sessionId
    self.expiresAtMs = expiresAtMs
    self.activeElsewhere = activeElsewhere
    self.probe = probe
  }
}

public struct SessionTransition: Equatable {
  public var clock: SessionClock
  public var context: PaymentContext

  public init(clock: SessionClock, context: PaymentContext) {
    self.clock = clock
    self.context = context
  }

  public var method: PaymentMethod { context.method }
  public var idempotencyKey: String { context.idempotencyKey }

  /// Card stays Adyen and bank stays Worldpay. Recovery never names another provider.
  public var provider: ProviderId { SessionBanner.providerBaseline(for: context.method) }
}

public struct SessionBannerPresentation: Equatable {
  public let state: SessionVisualState
  public let title: String
  public let message: String
  public let accessibilityLabel: String
  public let accessibilityHint: String
  public let actionLabel: String?
  public let actionAccessibilityLabel: String?
  public let blocksPaymentEntry: Bool
  public let background: SessionColor
  public let foreground: SessionColor
  public let actionBackground: SessionColor?
  public let actionForeground: SessionColor?

  public init(
    state: SessionVisualState,
    title: String,
    message: String,
    accessibilityLabel: String,
    accessibilityHint: String,
    actionLabel: String?,
    actionAccessibilityLabel: String?,
    blocksPaymentEntry: Bool,
    background: SessionColor,
    foreground: SessionColor,
    actionBackground: SessionColor?,
    actionForeground: SessionColor?
  ) {
    self.state = state
    self.title = title
    self.message = message
    self.accessibilityLabel = accessibilityLabel
    self.accessibilityHint = accessibilityHint
    self.actionLabel = actionLabel
    self.actionAccessibilityLabel = actionAccessibilityLabel
    self.blocksPaymentEntry = blocksPaymentEntry
    self.background = background
    self.foreground = foreground
    self.actionBackground = actionBackground
    self.actionForeground = actionForeground
  }

  public func meetsWcagAa(scale: SessionTextScale = SessionTextScale(fontScale: 1)) -> Bool {
    let text = foreground.contrastRatio(against: background) >= SessionBanner.minimumContrast
    let action: Bool
    if let actionBackground, let actionForeground, actionLabel != nil {
      action = actionForeground.contrastRatio(against: actionBackground) >= SessionBanner.minimumContrast
    } else {
      action = actionLabel == nil
    }
    return text
      && action
      && scale.tapTargetPoints >= SessionBanner.minimumTapTargetPoints
      && scale.wraps
      && !title.isEmpty
      && !message.isEmpty
      && accessibilityLabel.contains(message)
  }
}

/// Dynamic text scale. Tap targets stay at least 48 points while body text grows.
public struct SessionTextScale: Equatable {
  public var fontScale: Double

  public init(fontScale: Double) {
    self.fontScale = max(0.5, fontScale)
  }

  public var titlePoints: Double { 15 * fontScale }
  public var bodyPoints: Double { 13 * fontScale }
  public var tapTargetPoints: Double { max(SessionBanner.minimumTapTargetPoints, 48 * fontScale) }
  /// Banner copy wraps instead of clipping when the system text size increases.
  public var wraps: Bool { true }
}

public struct SessionProbePayload: Equatable {
  public var healthy: Bool
  public var activeElsewhere: Bool

  public init(healthy: Bool, activeElsewhere: Bool) {
    self.healthy = healthy
    self.activeElsewhere = activeElsewhere
  }
}

public enum SessionAccessibility {
  public static let banner = "payment.sessionBanner"
  public static let action = "payment.sessionBanner.action"
  public static let endpoint = "auth.endpoint"
  public static let room = "auth.room"
  public static let connect = "auth.connect"
  public static let paymentForm = "payment.form"

  /// VoiceOver and TalkBack meet the banner, then its action, then the rest of the screen.
  public static func focusOrder(showsAction: Bool) -> [String] {
    var order = [banner]
    if showsAction { order.append(action) }
    order.append(contentsOf: [endpoint, room, connect, paymentForm])
    return order
  }
}

public enum SessionBanner {
  public static let expiringWindowMs: Int64 = 5 * 60 * 1000
  public static let defaultDurationMs: Int64 = 15 * 60 * 1000
  public static let minimumTapTargetPoints: Double = 48
  public static let minimumContrast: Double = 4.5

  public static let textBrand = SessionColor(token: "color.text.brand", red: 20, green: 44, blue: 53)
  public static let surfaceSubtle = SessionColor(token: "color.background.subtle", red: 234, green: 240, blue: 229)
  public static let surfaceWarning = SessionColor(token: "color.background.warning", red: 246, green: 217, blue: 138)
  public static let surfaceInfo = SessionColor(token: "color.background.info", red: 237, green: 244, blue: 255)
  public static let surfaceSignedOut = SessionColor(token: "color.background.signedOut", red: 248, green: 230, blue: 227)
  public static let textSignedOut = SessionColor(token: "color.text.signedOut", red: 111, green: 29, blue: 22)
  public static let surfaceExpired = SessionColor(token: "color.background.expired", red: 243, green: 208, blue: 203)
  public static let textExpired = SessionColor(token: "color.text.expired", red: 92, green: 17, blue: 12)
  public static let surfaceUnknown = SessionColor(token: "color.background.neutral", red: 231, green: 235, blue: 228)
  public static let textUnknown = SessionColor(token: "color.text.neutral", red: 28, green: 43, blue: 36)
  public static let actionInk = SessionColor(token: "color.action.inverse", red: 248, green: 249, blue: 246)

  public static func nowMs() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
  }

  public static func providerBaseline(for method: PaymentMethod) -> ProviderId {
    switch method {
    case .card: return .adyen
    case .bank: return .worldpay
    }
  }

  public static func hasSession(_ clock: SessionClock) -> Bool {
    guard let id = clock.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
      return false
    }
    return true
  }

  /// Expired wins over an active countdown. An unreachable probe stays unknown even if the clock has passed.
  public static func resolve(nowMs: Int64, clock: SessionClock) -> SessionVisualState {
    if !hasSession(clock) || clock.probe == .notSignedIn || clock.probe == .rejected {
      return .signedOut
    }
    if clock.probe == .unreachable {
      return .unknown
    }
    guard let expiresAtMs = clock.expiresAtMs else {
      return .unknown
    }
    let remaining = expiresAtMs - nowMs
    if remaining <= 0 {
      return .expired
    }
    if clock.activeElsewhere {
      return .activeElsewhere
    }
    if remaining <= expiringWindowMs {
      return .expiring
    }
    return .active
  }

  /// Ceiling to the next second so a session that is still expiring never reads as zero.
  public static func formatRemaining(ms: Int64) -> String {
    let positive = max(ms, Int64(0))
    let totalSeconds = (positive + 999) / 1000
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    if minutes > 0 && seconds > 0 {
      return "\(minutes) min \(seconds) sec"
    }
    if minutes > 0 {
      return "\(minutes) min"
    }
    return "\(seconds) sec"
  }

  public static func present(nowMs: Int64, clock: SessionClock) -> SessionBannerPresentation {
    let state = resolve(nowMs: nowMs, clock: clock)
    let remaining = clock.expiresAtMs.map { $0 - nowMs }

    let title: String
    let message: String
    let hint: String
    let actionLabel: String?
    let actionAccessibilityLabel: String?
    let background: SessionColor
    let foreground: SessionColor
    let actionBackground: SessionColor?
    let actionForeground: SessionColor?

    switch state {
    case .active:
      title = "Session active"
      message = "You're securely signed in."
      hint = "Payment session status."
      actionLabel = nil
      actionAccessibilityLabel = nil
      background = surfaceSubtle
      foreground = textBrand
      actionBackground = nil
      actionForeground = nil
    case .expiring:
      let time = formatRemaining(ms: remaining ?? 0)
      title = "Session expiring"
      message = "Your session expires in \(time)."
      hint = "Refreshes this session and keeps the payment details and idempotency key already entered."
      actionLabel = "Refresh"
      actionAccessibilityLabel = "Refresh session"
      background = surfaceWarning
      foreground = textBrand
      actionBackground = textBrand
      actionForeground = actionInk
    case .activeElsewhere:
      title = "Active on another device"
      if let remaining, remaining > 0, remaining <= expiringWindowMs {
        message = "This session is active on another device. It expires in \(formatRemaining(ms: remaining))."
      } else {
        message = "This session is active on another device."
      }
      hint = "Payment session status. Entered payment details stay on this device."
      actionLabel = nil
      actionAccessibilityLabel = nil
      background = surfaceInfo
      foreground = textBrand
      actionBackground = nil
      actionForeground = nil
    case .signedOut:
      title = "Signed out"
      message = "You've been signed out. Sign in to continue."
      hint = "Signs in to the selected session and keeps the payment details already entered."
      actionLabel = "Sign in"
      actionAccessibilityLabel = "Sign in to this session"
      background = surfaceSignedOut
      foreground = textSignedOut
      actionBackground = textSignedOut
      actionForeground = actionInk
    case .expired:
      title = "Session expired"
      message = "This session has expired. Refresh to continue. Your payment details are still here."
      hint = "Refreshes this session and keeps the amount, recipient, reference, method, and payment key."
      actionLabel = "Refresh"
      actionAccessibilityLabel = "Refresh session"
      background = surfaceExpired
      foreground = textExpired
      actionBackground = textExpired
      actionForeground = actionInk
    case .unknown:
      title = "Session not confirmed"
      message = "We couldn't confirm this session. Your payment details are still here."
      hint = "Checks the same session again and keeps the payment details and payment key already entered."
      actionLabel = "Try again"
      actionAccessibilityLabel = "Try again to confirm this session"
      background = surfaceUnknown
      foreground = textUnknown
      actionBackground = textUnknown
      actionForeground = actionInk
    }

    return SessionBannerPresentation(
      state: state,
      title: title,
      message: message,
      accessibilityLabel: "\(title). \(message)",
      accessibilityHint: hint,
      actionLabel: actionLabel,
      actionAccessibilityLabel: actionAccessibilityLabel,
      blocksPaymentEntry: false,
      background: background,
      foreground: foreground,
      actionBackground: actionBackground,
      actionForeground: actionForeground
    )
  }
}

public enum SessionActions {
  public static func signIn(
    nowMs: Int64,
    sessionId: String,
    context: PaymentContext,
    durationMs: Int64 = SessionBanner.defaultDurationMs
  ) -> SessionTransition {
    SessionTransition(
      clock: SessionClock(
        sessionId: sessionId,
        expiresAtMs: nowMs + durationMs,
        activeElsewhere: false,
        probe: .confirmed
      ),
      context: context
    )
  }

  /// Moves the same session's deadline forward. The payment draft is returned unchanged.
  public static func refresh(
    nowMs: Int64,
    clock: SessionClock,
    context: PaymentContext,
    activeElsewhere: Bool,
    durationMs: Int64 = SessionBanner.defaultDurationMs
  ) -> SessionTransition {
    SessionTransition(
      clock: SessionClock(
        sessionId: clock.sessionId,
        expiresAtMs: nowMs + durationMs,
        activeElsewhere: activeElsewhere,
        probe: .confirmed
      ),
      context: context
    )
  }

  /// Records a failed probe without moving the deadline, the session id, or the payment draft.
  public static func noteFailure(
    clock: SessionClock,
    context: PaymentContext,
    failure: SessionFailure
  ) -> SessionTransition {
    let probe: SessionProbeResult
    if !SessionBanner.hasSession(clock) {
      probe = .notSignedIn
    } else {
      switch failure {
      case .unauthorized:
        probe = .rejected
      case .timeout, .other:
        probe = .unreachable
      case let .http(code):
        probe = (code == 401 || code == 403) ? .rejected : .unreachable
      }
    }
    return SessionTransition(
      clock: SessionClock(
        sessionId: clock.sessionId,
        expiresAtMs: clock.expiresAtMs,
        activeElsewhere: clock.activeElsewhere,
        probe: probe
      ),
      context: context
    )
  }

  public static func classify(statusCode: Int?, timedOut: Bool) -> SessionFailure {
    if timedOut { return .timeout }
    guard let statusCode else { return .other }
    if statusCode == 401 || statusCode == 403 { return .unauthorized }
    return .http(statusCode)
  }
}
