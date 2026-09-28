import Foundation

/// Payment-session health shown on the payment and authentication screen.
public enum SessionBannerState: String, Equatable {
  case active
  case expiringSoon
  case activeElsewhere
  case expired
}

/// sRGB design token. Contrast is computed against WCAG 2.1 relative luminance.
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

/// In-flight transfer details that session refresh must carry through unchanged.
public struct InFlightPaymentDraft: Equatable {
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

public struct SessionBannerPresentation: Equatable {
  public let state: SessionBannerState
  public let message: String
  public let accessibilityLabel: String
  public let accessibilityHint: String
  public let extendActionLabel: String?
  public let reauthenticateActionLabel: String?
  public let blocksInteraction: Bool
  public let background: SessionColor
  public let foreground: SessionColor
  public let minimumTapTargetPoints: Int

  public init(
    state: SessionBannerState,
    message: String,
    accessibilityLabel: String,
    accessibilityHint: String,
    extendActionLabel: String?,
    reauthenticateActionLabel: String?,
    blocksInteraction: Bool,
    background: SessionColor,
    foreground: SessionColor,
    minimumTapTargetPoints: Int
  ) {
    self.state = state
    self.message = message
    self.accessibilityLabel = accessibilityLabel
    self.accessibilityHint = accessibilityHint
    self.extendActionLabel = extendActionLabel
    self.reauthenticateActionLabel = reauthenticateActionLabel
    self.blocksInteraction = blocksInteraction
    self.background = background
    self.foreground = foreground
    self.minimumTapTargetPoints = minimumTapTargetPoints
  }

  public func contrastRatio() -> Double {
    foreground.contrastRatio(against: background)
  }

  /// Normal text needs 4.5:1. Tap targets are at least 48 points.
  public func meetsWcagAa() -> Bool {
    contrastRatio() >= 4.5
      && minimumTapTargetPoints >= SessionBanner.minimumTapTargetPoints
      && !message.isEmpty
      && accessibilityLabel == message
  }
}

public struct SessionRefreshResult: Equatable {
  public let presentation: SessionBannerPresentation
  public let draft: InFlightPaymentDraft
  public let expiresAtMs: Int64
  public let activeElsewhere: Bool

  public init(
    presentation: SessionBannerPresentation,
    draft: InFlightPaymentDraft,
    expiresAtMs: Int64,
    activeElsewhere: Bool
  ) {
    self.presentation = presentation
    self.draft = draft
    self.expiresAtMs = expiresAtMs
    self.activeElsewhere = activeElsewhere
  }
}

/// Meridian session-banner tokens shared with the native payment screens.
public enum SessionBanner {
  public static let expiringWindowMs: Int64 = 5 * 60 * 1000
  public static let defaultDurationMs: Int64 = 15 * 60 * 1000
  public static let minimumTapTargetPoints = 48

  public static let connectedMessage = "Connected to secure payments platform"
  public static let expiringMessage = "Session expiring soon. Tap to extend."
  public static let activeElsewhereMessage = "Session active on another device."
  public static let expiredMessage = "Session expired. Please re-authenticate to confirm this transfer."
  public static let extendAction = "Tap to extend"
  public static let reauthenticateAction = "Re-authenticate"

  public static let extendHint = "Refreshes this payment session and keeps the details and payment key already entered."
  public static let reauthenticateHint = "Authenticates this session again and keeps the transfer details already entered."
  public static let statusHint = "Payment session status."

  /// Brand ink #142C35 on sage #EAF0E5.
  public static let activeBackground = SessionColor(token: "color.background.subtle", red: 234, green: 240, blue: 229)
  public static let textBrand = SessionColor(token: "color.text.brand", red: 20, green: 44, blue: 53)
  /// Amber warning surface #F6D98A.
  public static let warningBackground = SessionColor(token: "color.background.warning", red: 246, green: 217, blue: 138)
  /// Info surface #EDF4FF for a session held on another device.
  public static let infoBackground = SessionColor(token: "color.background.info", red: 237, green: 244, blue: 255)
  /// Danger surface #FFEDEB and danger text #8D2517.
  public static let dangerBackground = SessionColor(token: "color.background.danger", red: 255, green: 237, blue: 235)
  public static let dangerText = SessionColor(token: "color.text.danger", red: 141, green: 37, blue: 23)

  public static func nowMs() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
  }

  /// Expired wins over every other signal. Elsewhere is shown while time remains.
  /// Expiring soon is the closed window of five minutes before timeout.
  public static func present(nowMs: Int64, expiresAtMs: Int64, activeElsewhere: Bool) -> SessionBannerPresentation {
    let remaining = expiresAtMs - nowMs
    let state: SessionBannerState
    if remaining <= 0 {
      state = .expired
    } else if activeElsewhere {
      state = .activeElsewhere
    } else if remaining <= expiringWindowMs {
      state = .expiringSoon
    } else {
      state = .active
    }

    let message: String
    let hint: String
    let background: SessionColor
    let foreground: SessionColor
    switch state {
    case .active:
      message = connectedMessage
      hint = statusHint
      background = activeBackground
      foreground = textBrand
    case .expiringSoon:
      message = expiringMessage
      hint = extendHint
      background = warningBackground
      foreground = textBrand
    case .activeElsewhere:
      message = activeElsewhereMessage
      hint = statusHint
      background = infoBackground
      foreground = textBrand
    case .expired:
      message = expiredMessage
      hint = reauthenticateHint
      background = dangerBackground
      foreground = dangerText
    }

    return SessionBannerPresentation(
      state: state,
      message: message,
      accessibilityLabel: message,
      accessibilityHint: hint,
      extendActionLabel: state == .expiringSoon ? extendAction : nil,
      reauthenticateActionLabel: state == .expired ? reauthenticateAction : nil,
      blocksInteraction: state == .expired,
      background: background,
      foreground: foreground,
      minimumTapTargetPoints: minimumTapTargetPoints
    )
  }
}

public enum SessionRefresh {
  /// Moves expiry forward and returns the same payment draft.
  public static func extend(
    nowMs: Int64,
    durationMs: Int64 = SessionBanner.defaultDurationMs,
    draft: InFlightPaymentDraft,
    activeElsewhere: Bool
  ) -> SessionRefreshResult {
    let expiresAtMs = nowMs + durationMs
    return SessionRefreshResult(
      presentation: SessionBanner.present(nowMs: nowMs, expiresAtMs: expiresAtMs, activeElsewhere: activeElsewhere),
      draft: draft,
      expiresAtMs: expiresAtMs,
      activeElsewhere: activeElsewhere
    )
  }

  /// Opens a new authentication window on this device without replacing the draft.
  public static func reauthenticate(
    nowMs: Int64,
    durationMs: Int64 = SessionBanner.defaultDurationMs,
    draft: InFlightPaymentDraft
  ) -> SessionRefreshResult {
    let expiresAtMs = nowMs + durationMs
    return SessionRefreshResult(
      presentation: SessionBanner.present(nowMs: nowMs, expiresAtMs: expiresAtMs, activeElsewhere: false),
      draft: draft,
      expiresAtMs: expiresAtMs,
      activeElsewhere: false
    )
  }

  /// Keeps the previous expiry and draft when refresh does not succeed.
  public static func retain(
    nowMs: Int64,
    expiresAtMs: Int64,
    activeElsewhere: Bool,
    draft: InFlightPaymentDraft
  ) -> SessionRefreshResult {
    SessionRefreshResult(
      presentation: SessionBanner.present(nowMs: nowMs, expiresAtMs: expiresAtMs, activeElsewhere: activeElsewhere),
      draft: draft,
      expiresAtMs: expiresAtMs,
      activeElsewhere: activeElsewhere
    )
  }
}
