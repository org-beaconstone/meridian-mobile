import SwiftUI
import MeridianSDK

extension SessionColor {
  fileprivate var color: Color {
    Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
  }
}

/// Native session status banner for the payment and authentication screen.
struct SessionStatusBanner: View {
  let phase: SessionPhase
  var actionEnabled: Bool = true
  var onExtend: () -> Void
  var onReauthenticate: () -> Void

  var body: some View {
    let copy = SessionBannerCopy.text(for: phase)
    let label = bannerLabel(copy: copy, tokens: sessionBannerTokens(phase))
    if sessionOffersExtend(phase) {
      Button(action: { if actionEnabled { onExtend() } }) { label }
        .buttonStyle(.plain)
        .allowsHitTesting(actionEnabled)
        .accessibilityLabel("Session status. \(copy)")
        .accessibilityHint(actionEnabled
          ? "Extends the payment session and keeps the details already entered."
          : "Session refresh in progress.")
        .accessibilityIdentifier("session-status-banner")
    } else if sessionBlocksInteraction(phase) {
      Button(action: { if actionEnabled { onReauthenticate() } }) { label }
        .buttonStyle(.plain)
        .allowsHitTesting(actionEnabled)
        .accessibilityLabel("Session status. \(copy)")
        .accessibilityHint(actionEnabled
          ? "Authenticates again and keeps the transfer details already entered."
          : "Session refresh in progress.")
        .accessibilityIdentifier("session-status-banner")
    } else {
      label
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session status. \(copy)")
        .accessibilityIdentifier("session-status-banner")
    }
  }

  private func bannerLabel(copy: String, tokens: SessionBannerTokens) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Circle()
        .fill(tokens.indicator.color)
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
      Text(copy)
        .font(.system(size: 15))
        .foregroundStyle(tokens.foreground.color)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, minHeight: SessionTiming.minimumTapTarget, alignment: .leading)
    .background(tokens.background.color)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(tokens.indicator.color.opacity(0.55), lineWidth: 1)
    )
    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
