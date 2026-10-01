import SwiftUI
import MeridianSDK

extension SessionBannerTone {
  var background: Color {
    switch self {
    case .success: return Color(red: 0.906, green: 0.949, blue: 0.867)
    case .warning: return Color(red: 1.0, green: 0.969, blue: 0.839)
    case .information: return Color(red: 0.914, green: 0.949, blue: 1.0)
    case .neutral: return Color(red: 0.957, green: 0.961, blue: 0.969)
    case .danger: return Color(red: 1.0, green: 0.929, blue: 0.922)
    case .attention: return Color(red: 0.953, green: 0.929, blue: 0.890)
    }
  }

  var border: Color {
    switch self {
    case .success: return Color(red: 0.478, green: 0.686, blue: 0.471)
    case .warning: return Color(red: 0.886, green: 0.698, blue: 0.012)
    case .information: return Color(red: 0.094, green: 0.408, blue: 0.859)
    case .neutral: return Color(red: 0.545, green: 0.584, blue: 0.533)
    case .danger: return Color(red: 0.682, green: 0.165, blue: 0.098)
    case .attention: return Color(red: 0.835, green: 0.718, blue: 0.478)
    }
  }

  var foreground: Color {
    switch self {
    case .success: return Color(red: 0.122, green: 0.302, blue: 0.196)
    case .warning: return Color(red: 0.325, green: 0.247, blue: 0.016)
    case .information: return Color(red: 0.047, green: 0.227, blue: 0.478)
    case .neutral: return Color(red: 0.078, green: 0.173, blue: 0.208)
    case .danger: return Color(red: 0.553, green: 0.145, blue: 0.090)
    case .attention: return Color(red: 0.239, green: 0.180, blue: 0.086)
    }
  }
}

/// Persistent session banner for the payment and authentication screens.
struct SessionBannerView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let model: SessionBannerModel
  let onAction: (SessionBannerAction) -> Void

  var body: some View {
    let stacked = dynamicTypeSize.isAccessibilitySize
    VStack(alignment: .leading, spacing: 8) {
      if stacked {
        title
        clock
      } else {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          title
          Spacer(minLength: 8)
          clock
        }
      }
      Text(model.message)
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
      if let action = model.action, let label = model.actionLabel {
        Button(label) { onAction(action) }
          .buttonStyle(.bordered)
          .controlSize(.large)
          .accessibilityHint("Keeps the amount, recipient and reference already entered")
      }
    }
    .foregroundStyle(model.tone.foreground)
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(model.tone.background)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(model.tone.border, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("session-banner")
  }

  private var title: some View {
    Text(model.title)
      .font(.headline)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityAddTraits(.isHeader)
  }

  @ViewBuilder private var clock: some View {
    if let clockLabel = model.clockLabel {
      Text(clockLabel)
        .font(.title3.monospacedDigit())
        .accessibilityHidden(true)
    }
  }
}
