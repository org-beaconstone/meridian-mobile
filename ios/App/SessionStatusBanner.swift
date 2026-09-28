import SwiftUI
import MeridianSDK

extension SessionColor {
  var color: Color {
    Color(red: Double(red) / 255.0, green: Double(green) / 255.0, blue: Double(blue) / 255.0)
  }
}

/// Persistent session health for the payment and authentication screen.
/// The warning stays non-blocking. Only an expired session locks the transfer form.
struct SessionStatusBanner: View {
  let presentation: SessionBannerPresentation
  var actionEnabled: Bool = true
  var onExtend: () -> Void
  var onReauthenticate: () -> Void

  var body: some View {
    Group {
      if presentation.extendActionLabel != nil {
        Button(action: onExtend) {
          messageRow
        }
        .buttonStyle(.plain)
        .disabled(!actionEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityHint(presentation.accessibilityHint)
        .accessibilityAddTraits(.isButton)
      } else if let reauthenticate = presentation.reauthenticateActionLabel {
        VStack(alignment: .leading, spacing: 8) {
          messageRow
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilityLabel)
          Button(action: onReauthenticate) {
            Text(reauthenticate)
              .font(.body.weight(.semibold))
              .frame(maxWidth: .infinity, minHeight: CGFloat(presentation.minimumTapTargetPoints), alignment: .leading)
              .padding(.horizontal, 16)
              .background(Color.white)
              .foregroundStyle(presentation.foreground.color)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          .buttonStyle(.plain)
          .disabled(!actionEnabled)
          .accessibilityHint(presentation.accessibilityHint)
        }
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
      } else {
        messageRow
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(presentation.accessibilityLabel)
          .accessibilityHint(presentation.accessibilityHint)
          .accessibilityAddTraits(.isStaticText)
      }
    }
    .background(presentation.background.color)
    .foregroundStyle(presentation.foreground.color)
    .accessibilityIdentifier("session-status-banner")
  }

  private var messageRow: some View {
    HStack(alignment: .center, spacing: 12) {
      RoundedRectangle(cornerRadius: 2)
        .fill(presentation.foreground.color)
        .frame(width: 4, height: 24)
        .accessibilityHidden(true)
      Text(presentation.message)
        .font(.body)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, minHeight: CGFloat(presentation.minimumTapTargetPoints), alignment: .leading)
    .contentShape(Rectangle())
  }
}
