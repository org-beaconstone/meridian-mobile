import SwiftUI
import MeridianSDK
#if canImport(UIKit)
import UIKit
#endif

extension Color {
  init(banner color: BannerColor) {
    self.init(
      .sRGB,
      red: Double(color.red) / 255,
      green: Double(color.green) / 255,
      blue: Double(color.blue) / 255,
      opacity: 1
    )
  }
}

public enum SessionAnnouncer {
  public static func announce(_ message: String) {
    guard !message.isEmpty else { return }
    if #available(iOS 17.0, macOS 14.0, *) {
      AccessibilityNotification.Announcement(message).post()
    } else {
      #if canImport(UIKit)
      UIAccessibility.post(notification: .announcement, argument: message)
      #endif
    }
  }
}

/// Auth-screen session banner. Sits in normal layout flow so it cannot cover the fields below.
public struct SessionBannerView: View {
  public let model: SessionBannerModel
  public var actionEnabled: Bool
  public var onAction: () -> Void

  public init(
    model: SessionBannerModel,
    actionEnabled: Bool = true,
    onAction: @escaping () -> Void = {}
  ) {
    self.model = model
    self.actionEnabled = actionEnabled
    self.onAction = onAction
  }

  public var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .contain)
      .onChange(of: model.liveAnnouncement) { announcement in
        SessionAnnouncer.announce(announcement)
      }
  }

  @ViewBuilder private var content: some View {
    if model.showsSkeleton {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(banner: SessionBannerPalette.skeleton))
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .accessibilityElement()
        .accessibilityLabel(model.liveAnnouncement)
        .accessibilityIdentifier(AuthAccessibility.skeleton)
        .accessibilitySortPriority(AuthAccessibility.bannerPriority)
        .accessibilityAddTraits(.updatesFrequently)
    } else if model.phase == .healthy {
      Text(model.message)
        .font(.caption)
        .foregroundStyle(Color(banner: model.foreground))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(banner: model.background), in: Capsule())
        .accessibilityLabel(model.liveAnnouncement)
        .accessibilityIdentifier(AuthAccessibility.banner)
        .accessibilitySortPriority(AuthAccessibility.bannerPriority)
        .accessibilityAddTraits(.updatesFrequently)
    } else {
      VStack(alignment: .leading, spacing: 8) {
        Text(model.title)
          .font(.headline)
          .foregroundStyle(Color(banner: model.foreground))
          .accessibilityHidden(true)
        Text(model.message)
          .font(.body)
          .foregroundStyle(Color(banner: model.foreground))
          .lineLimit(6)
          .truncationMode(.tail)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityLabel(model.liveAnnouncement)
          .accessibilityIdentifier(AuthAccessibility.banner)
          .accessibilitySortPriority(AuthAccessibility.bannerPriority)
          .accessibilityAddTraits(.updatesFrequently)
        if let actionTitle = model.actionTitle {
          Button(action: onAction) {
            Text(actionTitle)
              .fontWeight(.semibold)
              .lineLimit(1)
              .truncationMode(.tail)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .foregroundStyle(Color(banner: model.actionForeground))
              .background(
                Color(banner: model.actionBackground),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
              )
          }
          .buttonStyle(.plain)
          .disabled(!actionEnabled)
          .accessibilityIdentifier(AuthAccessibility.bannerAction)
          .accessibilitySortPriority(AuthAccessibility.actionPriority)
          .accessibilityHint("Signs in with the rehearsal session already on this screen")
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color(banner: model.background),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
    }
  }
}
