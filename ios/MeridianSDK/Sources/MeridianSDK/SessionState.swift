import Foundation

// MARK: - SessionState

/// Authentication session state communicated via the session banner on the sign-in screen.
///
/// The banner is a **presentation-layer only** concept; it does not drive any network
/// calls and does not block the primary sign-in action. State transitions are determined
/// by the host app and injected as a value into `AuthSessionBanner`.
public enum SessionState: Equatable, Sendable, CaseIterable {
  /// Session is valid and fully active.
  case active
  /// Session will expire soon; the user should re-authenticate shortly.
  case expiring
  /// No active session — the user is signed out.
  case signedOut
  /// Re-authentication is currently in progress.
  case reAuthenticating

  // MARK: UI Copy

  /// Short banner copy shown to the user per state.
  public var bannerCopy: String {
    switch self {
    case .active:           return "You're signed in"
    case .expiring:         return "Your session is expiring soon"
    case .signedOut:        return "You're signed out"
    case .reAuthenticating: return "Re-authenticating\u{2026}"  // ellipsis
    }
  }

  // MARK: Accessibility

  /// Label announced through VoiceOver live regions on state change.
  public var accessibilityLabel: String {
    switch self {
    case .active:           return "Session active"
    case .expiring:         return "Session expiring soon"
    case .signedOut:        return "Signed out"
    case .reAuthenticating: return "Re-authenticating"
    }
  }

  /// SF Symbol name representing the current state.
  public var symbolName: String {
    switch self {
    case .active:           return "checkmark.shield.fill"
    case .expiring:         return "exclamationmark.triangle.fill"
    case .signedOut:        return "person.slash.fill"
    case .reAuthenticating: return "arrow.clockwise.circle.fill"
    }
  }
}
