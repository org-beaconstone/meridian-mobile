import Foundation

/// Rehearsal sign-in timing. This is not a production authenticator.
public enum SessionTiming {
  public static let lengthSeconds = 600
  public static let expiringThresholdSeconds = 120
  public static let previewExpiringSeconds = 90
}

public enum SessionPhase: String, CaseIterable, Identifiable {
  case active
  case expiring
  case activeElsewhere
  case signedOut
  case expired
  case unknown

  public var id: String { rawValue }

  public var pickerLabel: String {
    switch self {
    case .active: return "Active"
    case .expiring: return "Expiring"
    case .activeElsewhere: return "Active elsewhere"
    case .signedOut: return "Signed out"
    case .expired: return "Expired"
    case .unknown: return "Unknown"
    }
  }
}

public enum SessionBannerTone: String, Equatable {
  case success
  case warning
  case information
  case neutral
  case danger
  case attention
}

public enum SessionBannerAction: String, Equatable {
  case refresh
  case signIn
  case continueHere
  case tryAgain

  public var label: String {
    switch self {
    case .refresh: return "Refresh session"
    case .signIn: return "Sign in"
    case .continueHere: return "Continue here"
    case .tryAgain: return "Try again"
    }
  }
}

/// Customer rehearsal session. Distinct from the `X-Rehearsal-Session` room id.
public enum CustomerSession: Equatable {
  case active(expiresAt: Date)
  case activeElsewhere(deviceName: String)
  case signedOut
  case expired
  case unknown
}

/// Payment fields the banner must leave untouched.
public struct PaymentDraft: Equatable {
  public var recipientId: String
  public var amountText: String
  public var reference: String
  public var method: PaymentMethod
  public var reviewing: Bool
  public var idempotencyKey: String

  public init(
    recipientId: String,
    amountText: String,
    reference: String,
    method: PaymentMethod,
    reviewing: Bool,
    idempotencyKey: String
  ) {
    self.recipientId = recipientId
    self.amountText = amountText
    self.reference = reference
    self.method = method
    self.reviewing = reviewing
    self.idempotencyKey = idempotencyKey
  }
}

public struct SessionBannerModel: Equatable {
  public let phase: SessionPhase
  public let tone: SessionBannerTone
  public let title: String
  public let message: String
  public let clockLabel: String?
  public let remainingSeconds: Int?
  public let action: SessionBannerAction?
  public let actionLabel: String?
  public let accessibilityLabel: String
}

public struct SessionUpdate: Equatable {
  public let session: CustomerSession
  public let announcement: String
  public let payment: PaymentDraft
}

public func formatRemaining(_ totalSeconds: Int) -> String {
  let seconds = max(0, totalSeconds)
  let minutes = seconds / 60
  let rest = seconds % 60
  var parts: [String] = []
  if minutes > 0 {
    parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
  }
  if rest > 0 || minutes == 0 {
    parts.append("\(rest) \(rest == 1 ? "second" : "seconds")")
  }
  return parts.joined(separator: " ")
}

public func formatClock(_ totalSeconds: Int) -> String {
  let seconds = max(0, totalSeconds)
  let minutes = seconds / 60
  let rest = seconds % 60
  return String(format: "%d:%02d", minutes, rest)
}

public func sessionForPhase(
  _ phase: SessionPhase,
  now: Date,
  deviceName: String = "Meridian web"
) -> CustomerSession {
  switch phase {
  case .active:
    return .active(expiresAt: now.addingTimeInterval(TimeInterval(SessionTiming.lengthSeconds)))
  case .expiring:
    return .active(expiresAt: now.addingTimeInterval(TimeInterval(SessionTiming.previewExpiringSeconds)))
  case .activeElsewhere:
    return .activeElsewhere(deviceName: deviceName)
  case .signedOut:
    return .signedOut
  case .expired:
    return .expired
  case .unknown:
    return .unknown
  }
}

public func presentSession(_ session: CustomerSession, now: Date) -> SessionBannerModel {
  switch session {
  case let .active(expiresAt):
    let remaining = Int(floor(expiresAt.timeIntervalSince(now)))
    if remaining <= 0 { return expiredBanner() }
    if remaining <= SessionTiming.expiringThresholdSeconds { return expiringBanner(remaining) }
    return activeBanner()
  case let .activeElsewhere(deviceName):
    return elsewhereBanner(deviceName)
  case .signedOut:
    return signedOutBanner()
  case .expired:
    return expiredBanner()
  case .unknown:
    return unknownBanner()
  }
}

public func applySessionAction(
  session: CustomerSession,
  action: SessionBannerAction,
  now: Date,
  apiReachable: Bool,
  payment: PaymentDraft
) -> SessionUpdate {
  switch action {
  case .refresh:
    if apiReachable {
      return SessionUpdate(
        session: .active(expiresAt: now.addingTimeInterval(TimeInterval(SessionTiming.lengthSeconds))),
        announcement: "Session refreshed. Payment details are unchanged.",
        payment: payment
      )
    }
    return SessionUpdate(
      session: session,
      announcement: "Couldn't refresh the session. Your payment details are still here.",
      payment: payment
    )
  case .signIn:
    return SessionUpdate(
      session: .active(expiresAt: now.addingTimeInterval(TimeInterval(SessionTiming.lengthSeconds))),
      announcement: "Signed in on this device. Payment details are unchanged.",
      payment: payment
    )
  case .continueHere:
    return SessionUpdate(
      session: .active(expiresAt: now.addingTimeInterval(TimeInterval(SessionTiming.lengthSeconds))),
      announcement: "Continuing on this device. Payment details are unchanged.",
      payment: payment
    )
  case .tryAgain:
    if apiReachable {
      return SessionUpdate(
        session: .active(expiresAt: now.addingTimeInterval(TimeInterval(SessionTiming.lengthSeconds))),
        announcement: "Session confirmed. Payment details are unchanged.",
        payment: payment
      )
    }
    return SessionUpdate(
      session: .unknown,
      announcement: "We still couldn't confirm this session. Your payment details are still here.",
      payment: payment
    )
  }
}

private func model(
  phase: SessionPhase,
  tone: SessionBannerTone,
  title: String,
  message: String,
  clockLabel: String? = nil,
  remainingSeconds: Int? = nil,
  action: SessionBannerAction? = nil
) -> SessionBannerModel {
  SessionBannerModel(
    phase: phase,
    tone: tone,
    title: title,
    message: message,
    clockLabel: clockLabel,
    remainingSeconds: remainingSeconds,
    action: action,
    actionLabel: action?.label,
    accessibilityLabel: "\(title). \(message)"
  )
}

private func activeBanner() -> SessionBannerModel {
  model(
    phase: .active,
    tone: .success,
    title: "Session active",
    message: "Signed in on this device. You can keep entering this payment."
  )
}

private func expiringBanner(_ remaining: Int) -> SessionBannerModel {
  let spoken = formatRemaining(remaining)
  return model(
    phase: .expiring,
    tone: .warning,
    title: "Session expiring",
    message: "\(spoken) remaining. Refresh to stay signed in. This payment stays on screen.",
    clockLabel: formatClock(remaining),
    remainingSeconds: remaining,
    action: .refresh
  )
}

private func elsewhereBanner(_ deviceName: String) -> SessionBannerModel {
  model(
    phase: .activeElsewhere,
    tone: .information,
    title: "Active on another device",
    message: "Signed in on \(displayDevice(deviceName)). Continue here when you are ready. Entered payment details stay on this screen.",
    action: .continueHere
  )
}

private func signedOutBanner() -> SessionBannerModel {
  model(
    phase: .signedOut,
    tone: .neutral,
    title: "Signed out",
    message: "Sign in again to send this payment. The amount, recipient and reference you entered are kept.",
    action: .signIn
  )
}

private func expiredBanner() -> SessionBannerModel {
  model(
    phase: .expired,
    tone: .danger,
    title: "Session expired",
    message: "Your sign-in has expired. Sign in again to continue. Entered payment details are still here.",
    action: .signIn
  )
}

private func unknownBanner() -> SessionBannerModel {
  model(
    phase: .unknown,
    tone: .attention,
    title: "Session unknown",
    message: "We couldn't confirm this session. Try again when you are ready. Your payment details stay on this screen.",
    action: .tryAgain
  )
}

private func displayDevice(_ name: String) -> String {
  let trimmed = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  if trimmed.isEmpty { return "another device" }
  if trimmed.count <= 40 { return trimmed }
  return String(trimmed.prefix(40))
}
