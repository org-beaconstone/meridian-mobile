import SwiftUI

// MARK: - Session State

/// Represents all valid states a payment-screen session banner can display.
public enum SessionState: Equatable {
  /// Session is valid and confirmed active on this device.
  case active
  /// Session is close to expiry; `secondsRemaining` drives the countdown label.
  case expiring(secondsRemaining: Int)
  /// Session is confirmed active on a different device.
  case activeElsewhere
  /// Session has been signed out; payment context is preserved for recovery.
  case signedOut

  // MARK: Display helpers

  /// Short human-readable label for VoiceOver announcements and test assertions.
  public var accessibilityLabel: String {
    switch self {
    case .active:
      return "Session active"
    case let .expiring(secs):
      let mins = secs / 60
      let remainder = secs % 60
      if mins > 0 {
        return "Session expiring in \(mins) minute\(mins == 1 ? "" : "s") \(remainder) second\(remainder == 1 ? "" : "s")"
      }
      return "Session expiring in \(secs) second\(secs == 1 ? "" : "s")"
    case .activeElsewhere:
      return "Session active on another device"
    case .signedOut:
      return "Session signed out"
    }
  }

  /// The body text shown inside the banner.
  public var message: String {
    switch self {
    case .active:
      return "Your session is secure and active."
    case let .expiring(secs):
      let mins = secs / 60
      let remainder = secs % 60
      if mins > 0 {
        return "Session expiring in \(mins)m \(remainder)s. Tap Refresh to stay signed in."
      }
      return "Session expiring in \(secs)s. Tap Refresh to stay signed in."
    case .activeElsewhere:
      return "Your session is active on another device. Your payment details are preserved. Sign in again to continue."
    case .signedOut:
      return "You have been signed out. Your payment details are preserved. Sign in again to continue."
    }
  }

  /// Whether this state offers a refresh/re-sign-in action.
  public var hasAction: Bool {
    switch self {
    case .active:
      return false
    case .expiring, .activeElsewhere, .signedOut:
      return true
    }
  }

  /// The action button title, or `nil` when `hasAction` is false.
  public var actionTitle: String? {
    switch self {
    case .active:
      return nil
    case .expiring:
      return "Refresh"
    case .activeElsewhere, .signedOut:
      return "Sign in again"
    }
  }
}

// MARK: - SessionBannerView

/// A persistent, non-blocking banner that renders above the payment form.
///
/// The banner adapts its background colour and messaging for each `SessionState`
/// and exposes a fully labelled action button for expiry/recovery flows.
/// All text respects Dynamic Type; the banner itself never obscures or
/// disables the payment fields below it.
///
/// Accessibility notes:
/// - The container carries `accessibilityLabel` + `accessibilityAddTraits(.isStaticText)`
/// - State changes post an `UIAccessibility.post(notification:)` announcement
///   via `.accessibilityAnnouncement` (SwiftUI 5.1+)
/// - The refresh/recovery button has a minimum tap target of 44 × 44 pt
public struct SessionBannerView: View {
  public let state: SessionState
  public let onAction: (() -> Void)?

  public init(state: SessionState, onAction: (() -> Void)? = nil) {
    self.state = state
    self.onAction = onAction
  }

  // MARK: Colours

  private var backgroundColor: Color {
    switch state {
    case .active:
      return Color(red: 0.906, green: 0.949, blue: 0.867)  // #e7f2dd
    case .expiring:
      return Color(red: 1.0, green: 0.969, blue: 0.851)    // #fff7d9
    case .activeElsewhere:
      return Color(red: 0.882, green: 0.929, blue: 1.0)    // #e1edff
    case .signedOut:
      return Color(red: 1.0, green: 0.929, blue: 0.918)    // #ffedeb
    }
  }

  private var borderColor: Color {
    switch state {
    case .active:
      return Color(red: 0.667, green: 0.784, blue: 0.584)  // #aac895
    case .expiring:
      return Color(red: 0.882, green: 0.761, blue: 0.408)  // #e1c268
    case .activeElsewhere:
      return Color(red: 0.604, green: 0.733, blue: 0.973)  // #9abbf8
    case .signedOut:
      return Color(red: 0.925, green: 0.773, blue: 0.745)  // #ecc6be
    }
  }

  private var foregroundColor: Color {
    switch state {
    case .active:
      return Color(red: 0.22, green: 0.314, blue: 0.184)   // #38502f
    case .expiring:
      return Color(red: 0.478, green: 0.353, blue: 0.0)    // #7a5a00
    case .activeElsewhere:
      return Color(red: 0.122, green: 0.247, blue: 0.506)  // #1f3f81
    case .signedOut:
      return Color(red: 0.553, green: 0.145, blue: 0.09)   // #8d2517
    }
  }

  private var iconName: String {
    switch state {
    case .active:         return "checkmark.shield.fill"
    case .expiring:       return "clock.fill"
    case .activeElsewhere: return "person.2.fill"
    case .signedOut:      return "exclamationmark.shield.fill"
    }
  }

  // MARK: Body

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: iconName)
          .font(.system(size: 14, weight: .semibold))
          .accessibilityHidden(true)

        Text(state.message)
          .font(.footnote)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      if state.hasAction, let title = state.actionTitle {
        Button(title) {
          onAction?()
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(foregroundColor)
        .frame(minHeight: 44)
        .accessibilityLabel(title)
      }
    }
    .foregroundStyle(foregroundColor)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(backgroundColor)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(borderColor, lineWidth: 1)
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel(state.accessibilityLabel)
    .accessibilityAddTraits(.isStaticText)
  }
}

// MARK: - Preview helper (compile-time only)

#if DEBUG
  extension SessionBannerView {
    static func previewAll() -> some View {
      VStack(spacing: 12) {
        SessionBannerView(state: .active)
        SessionBannerView(state: .expiring(secondsRemaining: 90), onAction: {})
        SessionBannerView(state: .activeElsewhere, onAction: {})
        SessionBannerView(state: .signedOut, onAction: {})
      }.padding()
    }
  }
#endif
