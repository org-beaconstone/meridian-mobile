import SwiftUI
import MeridianSDK

extension Color {
  init(_ color: ContrastColor) {
    self.init(red: color.red, green: color.green, blue: color.blue)
  }
}

struct PaymentCorridorSelection: View {
  let selected: PaymentCorridor
  let enabled: Bool
  let onSelect: (PaymentCorridor) -> Void
  @FocusState private var focused: PaymentCorridor?
  @ScaledMetric(relativeTo: .body) private var indicator: CGFloat = 22

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Payment corridor")
        .font(.headline)
        .foregroundStyle(Color(PaymentTextColors.ink))
        .accessibilityAddTraits(.isHeader)
      VStack(alignment: .leading, spacing: 12) {
        ForEach(PaymentCorridor.allCases) { corridor in
          corridorButton(corridor)
        }
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func corridorButton(_ corridor: PaymentCorridor) -> some View {
    let isSelected = selected == corridor
    return Button {
      onSelect(corridor)
    } label: {
      HStack(alignment: .top, spacing: 12) {
        radio(isSelected)
        VStack(alignment: .leading, spacing: 4) {
          Text(corridor.title)
            .font(.body)
            .foregroundStyle(Color(PaymentTextColors.ink))
            .fixedSize(horizontal: false, vertical: true)
          Text(corridor.summary)
            .font(.subheadline)
            .foregroundStyle(Color(PaymentTextColors.secondary))
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(cardBackground(isSelected))
      .overlay(cardBorder(isSelected, focused: focused == corridor))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .focused($focused, equals: corridor)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(corridorAccessibilityLabel(corridor))
    .accessibilityValue(isSelected ? "Selected" : "Not selected")
    .accessibilityHint("Selects this payment corridor")
    .accessibilityAddTraits(.isButton)
  }

  private func radio(_ selected: Bool) -> some View {
    RadioMark(selected: selected, diameter: indicator)
  }
}

struct PaymentMethodSelection: View {
  let phase: PaymentMethodPhase
  let selected: PaymentMethod?
  let enabled: Bool
  let width: CGFloat
  let onSelect: (PaymentMethod) -> Void
  @ScaledMetric(relativeTo: .body) private var bodyPoint: CGFloat = 17

  private var fontScale: Double { Double(bodyPoint / 17) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Payment method")
        .font(.headline)
        .foregroundStyle(Color(PaymentTextColors.ink))
        .accessibilityAddTraits(.isHeader)
      switch phase {
      case .loading:
        shimmer
      case let .unavailable(message):
        notice(title: "Payment methods unavailable", message: message)
      case let .empty(corridor):
        notice(title: "No payment methods", message: emptyPaymentMethodsMessage(corridor: corridor))
      case let .ready(options):
        optionsList(options)
      }
    }
    .accessibilityElement(children: .contain)
  }

  private var shimmer: some View {
    VStack(alignment: .leading, spacing: 12) {
      ShimmerCard()
      ShimmerCard()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(paymentMethodsLoadingLabel)
    .accessibilityAddTraits(.updatesFrequently)
  }

  private func notice(title: String, message: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.body.weight(.semibold))
        .foregroundStyle(Color(PaymentTextColors.ink))
        .fixedSize(horizontal: false, vertical: true)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(Color(PaymentTextColors.secondary))
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(cardBackground(false))
    .overlay(cardBorder(false, focused: false))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title). \(message)")
  }

  private func optionsList(_ options: [PaymentOption]) -> some View {
    let sideBySide = options.count > 1 && usesSideBySideRails(widthPoints: Double(width), fontScale: fontScale)
    return Group {
      if sideBySide {
        HStack(alignment: .top, spacing: 12) {
          ForEach(options) { option in
            optionButton(option).frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(options) { option in
            optionButton(option)
          }
        }
      }
    }
  }

  private func optionButton(_ option: PaymentOption) -> some View {
    OptionCard(option: option, selected: selected == option.method, enabled: enabled, onSelect: onSelect)
  }
}

private struct OptionCard: View {
  let option: PaymentOption
  let selected: Bool
  let enabled: Bool
  let onSelect: (PaymentMethod) -> Void
  @FocusState private var focused: Bool
  @ScaledMetric(relativeTo: .body) private var indicator: CGFloat = 22

  var body: some View {
    Button {
      onSelect(option.method)
    } label: {
      HStack(alignment: .top, spacing: 12) {
        RadioMark(selected: selected, diameter: indicator)
        VStack(alignment: .leading, spacing: 4) {
          Text(option.railLabel)
            .font(.body)
            .foregroundStyle(Color(PaymentTextColors.ink))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
          Text("British pounds · GBP")
            .font(.subheadline)
            .foregroundStyle(Color(PaymentTextColors.secondary))
            .fixedSize(horizontal: false, vertical: true)
          if selected {
            Text("Selected")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Color(PaymentTextColors.ink))
          }
        }
        Spacer(minLength: 0)
      }
      .padding(16)
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .background(cardBackground(selected))
      .overlay(cardBorder(selected, focused: focused))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .focused($focused)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(option.accessibilityLabel)
    .accessibilityValue(selected ? "Selected" : "Not selected")
    .accessibilityHint("Selects this payment rail")
    .accessibilityAddTraits(.isButton)
  }
}

private struct RadioMark: View {
  let selected: Bool
  let diameter: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .stroke(Color(PaymentTextColors.ink), lineWidth: 2)
      if selected {
        Circle()
          .fill(Color(PaymentTextColors.ink))
          .padding(diameter * 0.25)
      }
    }
    .frame(width: diameter, height: diameter)
    .accessibilityHidden(true)
    .padding(.top, 2)
  }
}

private struct ShimmerCard: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var move = false
  @ScaledMetric(relativeTo: .body) private var line: CGFloat = 14

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Circle()
        .fill(Color(PaymentTextColors.shimmer))
        .frame(width: line * 1.7, height: line * 1.7)
      VStack(alignment: .leading, spacing: 8) {
        shimmerBar
          .frame(height: line)
          .padding(.trailing, line * 3)
        shimmerBar
          .frame(maxWidth: line * 8, alignment: .leading)
          .frame(height: line * 0.85)
      }
      Spacer(minLength: 0)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(PaymentTextColors.surface))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color(PaymentTextColors.border).opacity(0.45), lineWidth: 1)
    )
    .accessibilityHidden(true)
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
        move = true
      }
    }
  }

  private var shimmerBar: some View {
    RoundedRectangle(cornerRadius: 6, style: .continuous)
      .fill(Color(PaymentTextColors.shimmer))
      .overlay {
        if !reduceMotion {
          GeometryReader { geo in
            LinearGradient(
              colors: [.clear, Color.white.opacity(0.7), .clear],
              startPoint: .leading,
              endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.45)
            .offset(x: move ? geo.size.width : -geo.size.width)
          }
          .clipped()
        }
      }
      .clipped()
  }
}

private func cardBackground(_ selected: Bool) -> some View {
  RoundedRectangle(cornerRadius: 12, style: .continuous)
    .fill(Color(selected ? PaymentTextColors.selectedFill : PaymentTextColors.surface))
}

private func cardBorder(_ selected: Bool, focused: Bool) -> some View {
  RoundedRectangle(cornerRadius: 12, style: .continuous)
    .strokeBorder(
      Color(focused ? PaymentTextColors.action : (selected ? PaymentTextColors.ink : PaymentTextColors.border)),
      lineWidth: focused ? 3 : 1
    )
}
