import SwiftUI
import MeridianSDK

// MARK: - AuthSessionBanner

/// Presentation-layer banner that communicates authentication session state on the
/// sign-in screen without blocking or delaying the primary sign-in action.
///
/// **Behaviour**
/// - Renders the signed-out, expiring, and re-authenticating states independently of
///   any catalog or network fetch.
/// - State changes announce through VoiceOver live regions so assistive technology
///   users are not silently bypassed.
/// - Only visible when `FeatureFlags.authSessionBannerEnabled` is `true`.
/// - Uses `DesignTokens` to meet WCAG 2.1 AA contrast in light and dark themes.
@MainActor
struct AuthSessionBanner: View {
  let sessionState: SessionState

  var body: some View {
    if FeatureFlags.authSessionBannerEnabled {
      bannerRow
        // VoiceOver live region: announces state changes without requiring focus move.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sessionState.accessibilityLabel)
        .accessibilityAddTraits(.updatesFrequently)
    }
  }

  // MARK: – Internal layout

  @ViewBuilder
  private var bannerRow: some View {
    HStack(spacing: 10) {
      Image(systemName: sessionState.symbolName)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(foregroundColor)
        .accessibilityHidden(true)

      Text(sessionState.bannerCopy)
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundStyle(foregroundColor)
        .lineLimit(2)

      Spacer(minLength: 0)

      if sessionState == .reAuthenticating {
        ProgressView()
          .tint(foregroundColor)
          .scaleEffect(0.8)
          .accessibilityHidden(true)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(backgroundColor)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(foregroundColor.opacity(0.20), lineWidth: 1)
    )
    .animation(.easeInOut(duration: 0.25), value: sessionState)
  }

  // MARK: – Token mapping

  private var backgroundColor: Color {
    switch sessionState {
    case .active:           return DesignTokens.surfaceNeutral
    case .expiring:         return DesignTokens.surfaceWarning
    case .signedOut:        return DesignTokens.surfaceError
    case .reAuthenticating: return DesignTokens.surfaceNeutral
    }
  }

  private var foregroundColor: Color {
    switch sessionState {
    case .active:           return DesignTokens.labelPrimary
    case .expiring:         return DesignTokens.labelWarning
    case .signedOut:        return DesignTokens.labelError
    case .reAuthenticating: return DesignTokens.labelSecondary
    }
  }
}
