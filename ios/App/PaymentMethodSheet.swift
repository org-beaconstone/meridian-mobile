import SwiftUI
import MeridianSDK

struct PaymentMethodSheet: View {
  @Binding var method: PaymentMethod
  let rails: [PaymentMethodOption]?
  let onClose: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pulse = false

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.black.opacity(0.45)
        .ignoresSafeArea()
        .onTapGesture(perform: onClose)
        .accessibilityLabel("Dismiss payment methods")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(perform: onClose)
      VStack(alignment: .leading, spacing: 14) {
        Capsule()
          .fill(Color.secondary.opacity(0.35))
          .frame(width: 36, height: 4)
          .frame(maxWidth: .infinity)
          .accessibilityHidden(true)
        HStack {
          Text("Payment method")
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
          Spacer()
          Button("Close", action: onClose)
        }
        if let rails {
          VStack(spacing: 10) {
            ForEach(Array(rails.enumerated()), id: \.element.id) { offset, rail in
              railButton(rail, position: offset + 1, total: rails.count)
            }
          }
        } else {
          VStack(spacing: 10) {
            skeleton
            skeleton
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Loading payment methods")
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(red: 0.973, green: 0.976, blue: 0.965))
      .clipShape(SheetTopShape())
      .accessibilityElement(children: .contain)
      .accessibilityAddTraits(.isModal)
    }
  }

  private var skeleton: some View {
    RoundedRectangle(cornerRadius: 12)
      .fill(Color(red: 0.89, green: 0.92, blue: 0.89))
      .frame(height: 72)
      .opacity(reduceMotion ? 0.7 : (pulse ? 0.4 : 0.95))
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
          pulse = true
        }
      }
      .accessibilityHidden(true)
  }

  private func railButton(_ rail: PaymentMethodOption, position: Int, total: Int) -> some View {
    let chosen = method == rail.method
    let border = rail.available
      ? (chosen ? Color(red: 0.094, green: 0.408, blue: 0.859) : Color(red: 0.863, green: 0.890, blue: 0.839))
      : Color(red: 0.925, green: 0.776, blue: 0.745)
    let fill = rail.available
      ? (chosen ? Color(red: 0.929, green: 0.957, blue: 1) : Color.white)
      : Color(red: 1, green: 0.965, blue: 0.957)
    return Button {
      guard rail.available else { return }
      method = rail.method
      onClose()
    } label: {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
          .foregroundStyle(rail.available ? Color(red: 0.094, green: 0.408, blue: 0.859) : Color.secondary)
          .padding(.top, 2)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(rail.badge)
            .foregroundStyle(rail.available ? Color.primary : Color.secondary)
            .multilineTextAlignment(.leading)
          if let warning = rail.warning {
            Text(warning)
              .font(.caption)
              .foregroundStyle(Color(red: 0.553, green: 0.145, blue: 0.090))
              .multilineTextAlignment(.leading)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(fill)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .disabled(!rail.available)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(rail.accessibilityAnnouncement(position: position, total: total))
    .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
  }
}

private struct SheetTopShape: Shape {
  func path(in rect: CGRect) -> Path {
    let radius: CGFloat = 20
    var path = Path()
    path.move(to: CGPoint(x: 0, y: rect.maxY))
    path.addLine(to: CGPoint(x: 0, y: radius))
    path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
    path.addLine(to: CGPoint(x: rect.maxX - radius, y: 0))
    path.addQuadCurve(to: CGPoint(x: rect.maxX, y: radius), control: CGPoint(x: rect.maxX, y: 0))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}
