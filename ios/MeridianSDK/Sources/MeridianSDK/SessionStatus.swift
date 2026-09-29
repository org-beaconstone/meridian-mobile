import Foundation

/// Payment-session health shown on the authentication screen.
/// Expired wins over every other signal. Active on another device wins over the
/// local expiry warning, because extending here would not move that other device.
public enum SessionPhase: String, Hashable, CaseIterable {
  case active
  case expiringSoon
  case activeElsewhere
  case expired
}

public enum SessionTiming {
  /// Amber warning begins when this much time, or less, remains.
  public static let warningWindow: TimeInterval = 5 * 60
  /// Rehearsal payment session length after connect, extend, or re-authentication.
  public static let lifetime: TimeInterval = 15 * 60
  /// WCAG target size requested for the extend and re-authenticate controls.
  public static let minimumTapTarget: Double = 48
}

public enum SessionBannerCopy {
  public static let active = "Connected to secure payments platform"
  public static let expiringSoon = "Session expiring soon. Tap to extend."
  public static let activeElsewhere = "Session active on another device."
  public static let expired = "Session expired. Please re-authenticate to confirm this transfer."

  public static func text(for phase: SessionPhase) -> String {
    switch phase {
    case .active:
      return active
    case .expiringSoon:
      return expiringSoon
    case .activeElsewhere:
      return activeElsewhere
    case .expired:
      return expired
    }
  }
}

public struct SessionColor: Equatable, Hashable {
  public let red: Int
  public let green: Int
  public let blue: Int

  public init(red: Int, green: Int, blue: Int) {
    self.red = red
    self.green = green
    self.blue = blue
  }
}

public struct SessionBannerTokens: Equatable {
  public let background: SessionColor
  public let foreground: SessionColor
  public let indicator: SessionColor

  public init(background: SessionColor, foreground: SessionColor, indicator: SessionColor) {
    self.background = background
    self.foreground = foreground
    self.indicator = indicator
  }
}

/// Palette taken from the Meridian mobile tokens: ink #142C35, sage #EAF0E5,
/// positive #387744, info #EDF4FF, focus #1868DB, danger #AE2A19, amber #F5C451.
public func sessionBannerTokens(_ phase: SessionPhase) -> SessionBannerTokens {
  switch phase {
  case .active:
    return SessionBannerTokens(
      background: SessionColor(red: 0xEA, green: 0xF0, blue: 0xE5),
      foreground: SessionColor(red: 0x14, green: 0x2C, blue: 0x35),
      indicator: SessionColor(red: 0x38, green: 0x77, blue: 0x44)
    )
  case .expiringSoon:
    return SessionBannerTokens(
      background: SessionColor(red: 0xF5, green: 0xC4, blue: 0x51),
      foreground: SessionColor(red: 0x14, green: 0x2C, blue: 0x35),
      indicator: SessionColor(red: 0x14, green: 0x2C, blue: 0x35)
    )
  case .activeElsewhere:
    return SessionBannerTokens(
      background: SessionColor(red: 0xED, green: 0xF4, blue: 0xFF),
      foreground: SessionColor(red: 0x14, green: 0x2C, blue: 0x35),
      indicator: SessionColor(red: 0x18, green: 0x68, blue: 0xDB)
    )
  case .expired:
    return SessionBannerTokens(
      background: SessionColor(red: 0xAE, green: 0x2A, blue: 0x19),
      foreground: SessionColor(red: 0xFF, green: 0xFF, blue: 0xFF),
      indicator: SessionColor(red: 0xFF, green: 0xFF, blue: 0xFF)
    )
  }
}

public func resolveSessionPhase(now: Date, expiresAt: Date, activeElsewhere: Bool) -> SessionPhase {
  let remaining = expiresAt.timeIntervalSince(now)
  if remaining <= 0 { return .expired }
  if activeElsewhere { return .activeElsewhere }
  if remaining <= SessionTiming.warningWindow { return .expiringSoon }
  return .active
}

public func sessionBlocksInteraction(_ phase: SessionPhase) -> Bool {
  phase == .expired
}

public func sessionOffersExtend(_ phase: SessionPhase) -> Bool {
  phase == .expiringSoon
}

public struct InFlightPaymentDraft: Equatable {
  public let recipientId: String
  public let amount: String
  public let reference: String
  public let method: PaymentMethod
  public let reviewing: Bool
  public let idempotencyKey: String

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

public struct SessionRefresh: Equatable {
  public let draft: InFlightPaymentDraft
  public let expiresAt: Date

  public init(draft: InFlightPaymentDraft, expiresAt: Date) {
    self.draft = draft
    self.expiresAt = expiresAt
  }
}

/// Moves the session deadline forward and returns the same payment draft.
public func refreshSessionInPlace(
  draft: InFlightPaymentDraft,
  now: Date,
  lifetime: TimeInterval = SessionTiming.lifetime
) -> SessionRefresh {
  SessionRefresh(draft: draft, expiresAt: now.addingTimeInterval(lifetime))
}

private func srgbChannel(_ value: Int) -> Double {
  let channel = Double(value) / 255.0
  if channel <= 0.04045 {
    return channel / 12.92
  }
  return pow((channel + 0.055) / 1.055, 2.4)
}

public func relativeLuminance(_ color: SessionColor) -> Double {
  (0.2126 * srgbChannel(color.red)) + (0.7152 * srgbChannel(color.green)) + (0.0722 * srgbChannel(color.blue))
}

public func contrastRatio(_ first: SessionColor, _ second: SessionColor) -> Double {
  let lighter = max(relativeLuminance(first), relativeLuminance(second))
  let darker = min(relativeLuminance(first), relativeLuminance(second))
  return (lighter + 0.05) / (darker + 0.05)
}
