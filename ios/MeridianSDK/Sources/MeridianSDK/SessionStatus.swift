import Foundation

/// Local payment-session clock for the rehearsal. This is not production authentication.
/// Warning window matches the payment screen spec: under five minutes, and not a full expiry.
public let sessionWarningWindow: TimeInterval = 5 * 60
public let paymentSessionTtl: TimeInterval = 15 * 60
public let sessionExpiringMessage = "Session expiring soon. Tap to extend."

public enum SessionPresence: String, Equatable, Hashable, CaseIterable {
  case here
  case elsewhere
  case signedOut
}

public enum SessionBannerState: String, Equatable, Hashable, CaseIterable {
  case active
  case expiringSoon
  case activeElsewhere
  case signedOut
}

public enum SessionPhase: Equatable {
  case banner(SessionBannerState)
  case reauthenticate
}

public struct PaymentSessionClock: Equatable {
  public var presence: SessionPresence
  public var expiresAt: Date

  public init(presence: SessionPresence, expiresAt: Date) {
    self.presence = presence
    self.expiresAt = expiresAt
  }
}

public struct PaymentFormDraft: Equatable {
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

public struct SessionRefreshResult: Equatable {
  public var draft: PaymentFormDraft
  public var session: PaymentSessionClock

  public init(draft: PaymentFormDraft, session: PaymentSessionClock) {
    self.draft = draft
    self.session = session
  }
}

public struct SessionBannerCopy: Equatable {
  public let message: String
  public let accessibilityLabel: String
  public let accessibilityHint: String
  public let indicator: String

  public init(message: String, accessibilityLabel: String, accessibilityHint: String, indicator: String) {
    self.message = message
    self.accessibilityLabel = accessibilityLabel
    self.accessibilityHint = accessibilityHint
    self.indicator = indicator
  }
}

/// Atlassian light-theme tokens, the same values Meridian uses for semantic banners.
public struct SessionBannerPalette: Equatable {
  public let backgroundHex: String
  public let foregroundHex: String
  public let backgroundToken: String
  public let foregroundToken: String

  public init(backgroundHex: String, foregroundHex: String, backgroundToken: String, foregroundToken: String) {
    self.backgroundHex = backgroundHex
    self.foregroundHex = foregroundHex
    self.backgroundToken = backgroundToken
    self.foregroundToken = foregroundToken
  }
}

public func sessionPhase(presence: SessionPresence, expiresAt: Date, now: Date) -> SessionPhase {
  if presence == .signedOut { return .banner(.signedOut) }
  if now >= expiresAt { return .reauthenticate }
  let remaining = expiresAt.timeIntervalSince(now)
  if remaining < sessionWarningWindow { return .banner(.expiringSoon) }
  if presence == .elsewhere { return .banner(.activeElsewhere) }
  return .banner(.active)
}

public func sessionRequiresReauthentication(presence: SessionPresence, expiresAt: Date, now: Date) -> Bool {
  if case .reauthenticate = sessionPhase(presence: presence, expiresAt: expiresAt, now: now) {
    return true
  }
  return false
}

public func sessionRemainingDescription(_ remaining: TimeInterval) -> String {
  let seconds = max(0, Int(remaining))
  let minutes = seconds / 60
  let rest = seconds % 60
  if minutes > 0 && rest == 0 {
    return minutes == 1 ? "1 minute" : "\(minutes) minutes"
  }
  if minutes > 0 {
    return "\(minutes) minutes \(rest) seconds"
  }
  return "\(seconds) seconds"
}

public func sessionBannerCopy(_ state: SessionBannerState, remaining: TimeInterval? = nil) -> SessionBannerCopy {
  let hint = "Refreshes the session in place and keeps the payment details you entered."
  switch state {
  case .active:
    return SessionBannerCopy(
      message: "Session active.",
      accessibilityLabel: "Session active.",
      accessibilityHint: hint,
      indicator: "check"
    )
  case .expiringSoon:
    let suffix = remaining.map { " \(sessionRemainingDescription($0)) remaining." } ?? ""
    return SessionBannerCopy(
      message: sessionExpiringMessage,
      accessibilityLabel: sessionExpiringMessage + suffix,
      accessibilityHint: hint,
      indicator: "warning"
    )
  case .activeElsewhere:
    return SessionBannerCopy(
      message: "Session active on another device.",
      accessibilityLabel: "Session active on another device.",
      accessibilityHint: hint,
      indicator: "devices"
    )
  case .signedOut:
    return SessionBannerCopy(
      message: "Signed out.",
      accessibilityLabel: "Signed out.",
      accessibilityHint: hint,
      indicator: "signed-out"
    )
  }
}

public func sessionBannerPalette(_ state: SessionBannerState) -> SessionBannerPalette {
  switch state {
  case .active:
    return SessionBannerPalette(
      backgroundHex: "#EFFFD6",
      foregroundHex: "#4C6B1F",
      backgroundToken: "color.background.success",
      foregroundToken: "color.text.success"
    )
  case .expiringSoon:
    return SessionBannerPalette(
      backgroundHex: "#FFF5DB",
      foregroundHex: "#9E4C00",
      backgroundToken: "color.background.warning",
      foregroundToken: "color.text.warning"
    )
  case .activeElsewhere:
    return SessionBannerPalette(
      backgroundHex: "#E9F2FE",
      foregroundHex: "#1558BC",
      backgroundToken: "color.background.information",
      foregroundToken: "color.text.information"
    )
  case .signedOut:
    return SessionBannerPalette(
      backgroundHex: "#FFECEB",
      foregroundHex: "#AE2E24",
      backgroundToken: "color.background.danger",
      foregroundToken: "color.text.danger"
    )
  }
}

public func contrastRatio(foregroundHex: String, backgroundHex: String) -> Double {
  func luminance(_ hex: String) -> Double {
    let channels = hexChannels(hex)
    func linear(_ channel: Double) -> Double {
      channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(channels.0) + 0.7152 * linear(channels.1) + 0.0722 * linear(channels.2)
  }
  let lighter = max(luminance(foregroundHex), luminance(backgroundHex))
  let darker = min(luminance(foregroundHex), luminance(backgroundHex))
  return (lighter + 0.05) / (darker + 0.05)
}

public func refreshSessionInPlace(
  draft: PaymentFormDraft,
  session: PaymentSessionClock,
  now: Date,
  ttl: TimeInterval = paymentSessionTtl
) -> SessionRefreshResult {
  SessionRefreshResult(
    draft: draft,
    session: PaymentSessionClock(presence: .here, expiresAt: now.addingTimeInterval(ttl))
  )
}

private func hexChannels(_ hex: String) -> (Double, Double, Double) {
  let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
  let value = UInt64(cleaned, radix: 16) ?? 0
  let red = Double((value >> 16) & 0xFF) / 255
  let green = Double((value >> 8) & 0xFF) / 255
  let blue = Double(value & 0xFF) / 255
  return (red, green, blue)
}
