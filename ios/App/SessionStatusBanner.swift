import SwiftUI
#if os(iOS)
import UIKit
#endif
import MeridianSDK

extension SessionColor {
  var swiftUIColor: Color {
    Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
  }
}

/// Persistent session banner for the payment and authentication screen.
/// Text uses Dynamic Type. The refresh and recovery actions do not cover the payment form.
struct SessionStatusBanner: View {
  let presentation: SessionBannerPresentation
  let refreshing: Bool
  let onAction: () -> Void

  @ScaledMetric(relativeTo: .body) private var scaledTap: CGFloat = 48

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 12) {
        RoundedRectangle(cornerRadius: 2)
          .fill(presentation.foreground.swiftUIColor)
          .frame(width: 4)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(presentation.title)
            .font(.headline)
            .foregroundStyle(presentation.foreground.swiftUIColor)
            .fixedSize(horizontal: false, vertical: true)
          Text(presentation.message)
            .font(.body)
            .foregroundStyle(presentation.foreground.swiftUIColor)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(presentation.accessibilityLabel)
      .accessibilityHint(presentation.accessibilityHint)
      .accessibilityIdentifier(SessionAccessibility.banner)

      if let action = presentation.actionLabel,
         let actionBackground = presentation.actionBackground,
         let actionForeground = presentation.actionForeground {
        Button(action: onAction) {
          Text(refreshing ? "Refreshing…" : action)
            .font(.body)
            .foregroundStyle(actionForeground.swiftUIColor)
            .frame(maxWidth: .infinity, minHeight: max(48, scaledTap))
        }
        .buttonStyle(.plain)
        .background(actionBackground.swiftUIColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .disabled(refreshing)
        .accessibilityLabel(refreshing ? "Refreshing session" : (presentation.actionAccessibilityLabel ?? action))
        .accessibilityHint(presentation.accessibilityHint)
        .accessibilityIdentifier(SessionAccessibility.action)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(presentation.background.swiftUIColor)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .onChange(of: presentation.state) { _ in
      announce(presentation.accessibilityLabel)
    }
  }

  private func announce(_ message: String) {
    #if os(iOS)
    UIAccessibility.post(notification: .announcement, argument: message)
    #endif
  }
}
