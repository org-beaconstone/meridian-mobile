import SwiftUI
import MeridianSDK

struct PaymentMethodSelector: View {
  let loading: Bool
  let rails: [PaymentRail]
  let selected: PaymentMethod
  let enabled: Bool
  let onOpen: () -> Void

  private var selectedRail: PaymentRail? {
    rails.first { $0.method == selected }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Payment method")
        .font(.subheadline.weight(.semibold))
      if loading {
        MethodSkeletonGroup()
      } else if rails.isEmpty {
        Text("No payment methods are available.")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        Button(action: onOpen) {
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(selectedRail?.title ?? "Choose payment method")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(red: 0.078, green: 0.173, blue: 0.208))
              Spacer()
              Image(systemName: "chevron.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            if let badge = selectedRail?.badge {
              Text(badge)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let warning = selectedRail?.warning {
              Text(warning)
                .font(.caption)
                .foregroundStyle(Color(red: 0.553, green: 0.145, blue: 0.090))
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(16)
          .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(Color(red: 0.863, green: 0.890, blue: 0.839), lineWidth: 1)
          )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("payment-method-open")
        .accessibilityLabel(selectedRail.map { "Payment method, \($0.title)" } ?? "Choose payment method")
      }
    }
  }
}

struct PaymentMethodBottomSheet: View {
  let loading: Bool
  let rails: [PaymentRail]
  let selected: PaymentMethod
  let onSelect: (PaymentRail) -> Void
  let onClose: () -> Void

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.black.opacity(0.45)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 14) {
        Capsule()
          .fill(Color.secondary.opacity(0.35))
          .frame(width: 36, height: 4)
          .frame(maxWidth: .infinity)
          .accessibilityHidden(true)
        Text("Payment method")
          .font(.title3.weight(.semibold))
          .accessibilityAddTraits(.isHeader)
        Text("Simulated GBP rehearsal. No real payment is sent.")
          .font(.caption)
          .foregroundStyle(.secondary)
        if loading {
          MethodSkeletonGroup()
        } else if rails.isEmpty {
          Text("No payment methods are available.")
            .font(.callout)
        } else {
          VStack(spacing: 10) {
            ForEach(rails) { rail in
              PaymentRailRow(rail: rail, selected: rail.method == selected) {
                onSelect(rail)
              }
            }
          }
        }
        Button("Done", action: onClose)
          .buttonStyle(.bordered)
          .frame(maxWidth: .infinity, alignment: .center)
          .accessibilityLabel("Close payment methods")
      }
      .padding(20)
      .frame(maxWidth: 550)
      .background(Color(red: 0.973, green: 0.976, blue: 0.965))
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      .padding(.horizontal, 8)
      .padding(.bottom, 8)
      .accessibilityIdentifier("payment-method-sheet")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct PaymentRailRow: View {
  let rail: PaymentRail
  let selected: Bool
  let onSelect: () -> Void

  var body: some View {
    Button(action: {
      guard rail.selectable else { return }
      onSelect()
    }) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
          .foregroundStyle(selected ? Color(red: 0.094, green: 0.408, blue: 0.859) : Color.secondary)
          .accessibilityHidden(true)
          .padding(.top, 2)
        VStack(alignment: .leading, spacing: 4) {
          Text(rail.title)
            .font(.body.weight(.semibold))
            .foregroundStyle(Color(red: 0.078, green: 0.173, blue: 0.208))
          Text(rail.badge)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          if let warning = rail.warning {
            Text(warning)
              .font(.caption)
              .foregroundStyle(Color(red: 0.553, green: 0.145, blue: 0.090))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(selected ? Color(red: 0.929, green: 0.957, blue: 1) : Color.white)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(
            selected ? Color(red: 0.094, green: 0.408, blue: 0.859) : Color(red: 0.863, green: 0.890, blue: 0.839),
            lineWidth: 1
          )
      )
      .opacity(rail.selectable ? 1 : 0.85)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(rail.announcement)
    .accessibilityHint(rail.warning ?? rail.badge)
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }
}

private struct MethodSkeletonGroup: View {
  var body: some View {
    VStack(spacing: 10) {
      MethodSkeletonCard()
      MethodSkeletonCard()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading payment methods")
  }
}

private struct MethodSkeletonCard: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var bright = false

  var body: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .fill(Color(red: 0.835, green: 0.867, blue: 0.816).opacity(bright || reduceMotion ? 0.95 : 0.45))
      .frame(height: 72)
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
          bright = true
        }
      }
  }
}
