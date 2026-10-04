import SwiftUI
import MeridianSDK

#if canImport(UIKit)
import UIKit
#endif

/// Persistent payment-session banner for the native payment and authentication screen.
struct SessionStatusBanner: View {
  let state: SessionBannerState
  var remaining: TimeInterval?
  let onRefresh: () -> Void

  private var copy: SessionBannerCopy {
    sessionBannerCopy(state, remaining: state == .expiringSoon ? remaining : nil)
  }

  private var palette: SessionBannerPalette { sessionBannerPalette(state) }

  var body: some View {
    Button(action: onRefresh) {
      HStack(alignment: .center, spacing: 10) {
        RoundedRectangle(cornerRadius: 2)
          .fill(Color(sessionHex: palette.foregroundHex))
          .frame(width: 4, height: 28)
          .accessibilityHidden(true)
        SessionGlyph(kind: copy.indicator)
        Text(copy.message)
          .font(.subheadline.weight(.semibold))
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .background(Color(sessionHex: palette.backgroundHex))
      .foregroundStyle(Color(sessionHex: palette.foregroundHex))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(copy.accessibilityLabel)
    .accessibilityHint(copy.accessibilityHint)
    .accessibilityAddTraits(.isButton)
    .accessibilityAddTraits(.updatesFrequently)
    .accessibilityIdentifier("session-status-banner")
    .onChange(of: copy.accessibilityLabel) { label in
      announceSessionChange(label)
    }
  }
}

private func announceSessionChange(_ label: String) {
  #if canImport(UIKit)
  UIAccessibility.post(notification: .announcement, argument: label)
  #else
  _ = label
  #endif
}

private struct SessionGlyph: View {
  let kind: String

  var body: some View {
    Image(systemName: symbol)
      .font(.body.weight(.semibold))
      .accessibilityHidden(true)
  }

  private var symbol: String {
    switch kind {
    case "check":
      return "checkmark.circle"
    case "warning":
      return "exclamationmark.triangle"
    case "devices":
      return "rectangle.on.rectangle"
    default:
      return "person.crop.circle.badge.minus"
    }
  }
}

private extension Color {
  init(sessionHex: String) {
    let cleaned = sessionHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var value: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&value)
    let red = Double((value >> 16) & 0xFF) / 255
    let green = Double((value >> 8) & 0xFF) / 255
    let blue = Double(value & 0xFF) / 255
    self.init(red: red, green: green, blue: blue)
  }
}

struct SessionStatusBanner_Previews: PreviewProvider {
  static var previews: some View {
    VStack(spacing: 0) {
      SessionStatusBanner(state: .active, remaining: 600, onRefresh: {})
      SessionStatusBanner(state: .expiringSoon, remaining: 240, onRefresh: {})
      SessionStatusBanner(state: .activeElsewhere, remaining: 600, onRefresh: {})
      SessionStatusBanner(state: .signedOut, remaining: nil, onRefresh: {})
    }
  }
}
