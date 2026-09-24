import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Posts session-banner changes to VoiceOver. UIKit is iOS-only; the desktop
/// rehearsal compiles the same SwiftUI source without a device announcement.
enum SessionBannerAccessibility {
  static func post(_ message: String) {
    #if os(iOS)
    UIAccessibility.post(notification: .announcement, argument: message)
    #endif
  }
}

/// Corridor-aware session banner shown above the payment method picker.
struct SessionBannerView: View {
  var step: SessionBannerStep
  var onDismiss: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @State private var postedAnnouncementID: Int?

  var body: some View {
    Group {
      switch step.presentation {
      case .hidden:
        EmptyView()
      case .skeleton:
        skeleton
      case .banner(let content):
        banner(content)
      }
    }
    .onAppear(perform: announce)
    .onChange(of: step.announcement?.id) { _ in
      announce()
    }
  }

  private var theme: SessionBannerColorScheme {
    colorScheme == .dark ? .dark : .light
  }

  private func announce() {
    guard let announcement = step.announcement else { return }
    guard postedAnnouncementID != announcement.id else { return }
    postedAnnouncementID = announcement.id
    SessionBannerAccessibility.post(announcement.message)
  }

  private var skeleton: some View {
    let palette = sessionBannerPalette(kind: .active, colorScheme: theme)
    return HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 4)
        .fill(Color(sessionBannerRGB: palette.foreground).opacity(0.2))
        .frame(width: 168, height: 10)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, CGFloat(SessionBannerLayout.bannerHorizontalPadding))
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background(Color(sessionBannerRGB: palette.background))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading session status")
  }

  private func banner(_ content: SessionBannerContent) -> some View {
    let palette = sessionBannerPalette(kind: content.kind, colorScheme: theme)
    let foreground = Color(sessionBannerRGB: palette.foreground)
    return Color.clear
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .overlay {
        GeometryReader { proxy in
          bannerLine(content, width: proxy.size.width, foreground: foreground)
        }
      }
      .background(Color(sessionBannerRGB: palette.background))
      .accessibilityElement(children: .contain)
  }

  private func bannerLine(
    _ content: SessionBannerContent,
    width: CGFloat,
    foreground: Color
  ) -> some View {
    let fit = fitSessionBannerLine(
      core: content.coreMessage,
      detail: content.detail,
      dismissible: content.dismissible,
      contentWidth: Double(width)
    )
    return HStack(spacing: CGFloat(SessionBannerLayout.itemSpacing)) {
      HStack(spacing: CGFloat(SessionBannerLayout.itemSpacing)) {
        Text(fit.core)
          .lineLimit(1)
          .layoutPriority(1)
        if let detail = fit.detail {
          Text(detail)
            .lineLimit(1)
            .truncationMode(.tail)
            .layoutPriority(0)
        }
      }
      .font(.system(size: CGFloat(SessionBannerLayout.fontSize), weight: .medium))
      .foregroundStyle(foreground)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(content.accessibilityLabel)

      if content.dismissible {
        Button(action: onDismiss) {
          Image(systemName: "xmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: CGFloat(SessionBannerLayout.dismissControlWidth), height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss session banner")
      }
    }
    .padding(.leading, CGFloat(SessionBannerLayout.bannerHorizontalPadding))
    .padding(.trailing, content.dismissible ? 0 : CGFloat(SessionBannerLayout.bannerHorizontalPadding))
  }
}

extension Color {
  init(sessionBannerRGB rgb: SessionBannerRGB) {
    self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
  }
}
