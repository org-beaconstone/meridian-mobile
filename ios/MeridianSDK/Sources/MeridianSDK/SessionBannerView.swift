import SwiftUI

/// A persistent banner displayed on the payment/authentication screen that communicates
/// the current session state to the user without blocking entered payment data.
///
/// The banner is invisible when the session is ``SessionState/active``.
/// All other states render a colour-coded strip with an icon, a heading, optional recovery
/// guidance, and — for the ``SessionState/expiring(_:)`` state — a non-blocking Refresh button.
///
/// Accessibility: the entire banner is exposed as a single VoiceOver element whose label
/// combines the heading, recovery guidance, and button hint. Dynamic Type is supported
/// through the use of standard SwiftUI font styles.
public struct SessionBannerView: View {
  public let sessionState: SessionState
  /// Called when the user taps Refresh on an expiring-session banner.
  /// If `nil` the Refresh button is suppressed even in the expiring state.
  public let onRefresh: (() -> Void)?

  public init(sessionState: SessionState, onRefresh: (() -> Void)? = nil) {
    self.sessionState = sessionState
    self.onRefresh = onRefresh
  }

  public var body: some View {
    // Active state is healthy – no visual affordance needed.
    if case .active = sessionState {
      EmptyView()
    } else {
      bannerStrip
    }
  }

  // MARK: - Private

  @ViewBuilder
  private var bannerStrip: some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: iconSystemName)
        .foregroundStyle(accentColor)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(sessionState.label)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(labelColor)

        if sessionState.showsRecoveryGuidance {
          Text(recoveryText)
            .font(.caption)
            .foregroundStyle(labelColor.opacity(0.85))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if sessionState.allowsRefresh, let onRefresh {
        Button(action: onRefresh) {
          Text("Refresh")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(accentColor)
        }
        // Described separately so VoiceOver reads it as an interactive element.
        .accessibilityLabel("Refresh session")
        .accessibilityHint("Extends your current session without leaving this screen")
        .accessibilityRemoveTraits(.isStaticText)
        .accessibilityAddTraits(.isButton)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(backgroundColor)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    // Merge all child elements so VoiceOver reads the banner as one item.
    .accessibilityElement(children: .combine)
    .accessibilityLabel(voiceOverLabel)
    .accessibilityAddTraits(.isStaticText)
  }

  private var backgroundColor: Color {
    switch sessionState {
    case .active:          return .clear
    case .expiring:        return Color(red: 1.00, green: 0.95, blue: 0.76)
    case .activeElsewhere: return Color(red: 1.00, green: 0.97, blue: 0.84)
    case .signedOut:       return Color(red: 1.00, green: 0.91, blue: 0.91)
    case .unknown:         return Color(red: 1.00, green: 0.91, blue: 0.91)
    }
  }

  private var accentColor: Color {
    switch sessionState {
    case .active:          return .green
    case .expiring:        return Color(red: 0.89, green: 0.47, blue: 0.00)
    case .activeElsewhere: return Color(red: 0.78, green: 0.58, blue: 0.00)
    case .signedOut:       return Color(red: 0.80, green: 0.09, blue: 0.09)
    case .unknown:         return Color(red: 0.80, green: 0.09, blue: 0.09)
    }
  }

  private var labelColor: Color {
    switch sessionState {
    case .active:          return .primary
    case .expiring,
         .activeElsewhere: return Color(red: 0.45, green: 0.28, blue: 0.00)
    case .signedOut,
         .unknown:         return Color(red: 0.50, green: 0.02, blue: 0.02)
    }
  }

  private var iconSystemName: String {
    switch sessionState {
    case .active:          return "checkmark.circle.fill"
    case .expiring:        return "clock.fill"
    case .activeElsewhere: return "person.2.fill"
    case .signedOut:       return "lock.fill"
    case .unknown:         return "exclamationmark.triangle.fill"
    }
  }

  private var recoveryText: String {
    switch sessionState {
    case .signedOut: return "Sign in again to continue. Your payment details are preserved."
    case .unknown:   return "Check your connection. Your payment details are preserved."
    default:         return ""
    }
  }

  private var voiceOverLabel: String {
    var parts = [sessionState.label]
    if sessionState.showsRecoveryGuidance { parts.append(recoveryText) }
    if sessionState.allowsRefresh { parts.append("Refresh session available") }
    return parts.joined(separator: ". ")
  }
}
