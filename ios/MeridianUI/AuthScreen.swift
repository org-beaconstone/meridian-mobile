import SwiftUI
import MeridianSDK

/// Sign-in screen. The session banner is the first view, so its action is ahead of the fields in tab order.
public struct AuthScreen<PaymentContent: View>: View {
  @Binding private var endpoint: String
  @Binding private var room: String
  private let banner: SessionBannerModel
  private let busy: Bool
  private let message: String
  private let onSignIn: () -> Void
  private let payment: () -> PaymentContent

  public init(
    endpoint: Binding<String>,
    room: Binding<String>,
    banner: SessionBannerModel,
    busy: Bool,
    message: String,
    onSignIn: @escaping () -> Void,
    @ViewBuilder payment: @escaping () -> PaymentContent
  ) {
    _endpoint = endpoint
    _room = room
    self.banner = banner
    self.busy = busy
    self.message = message
    self.onSignIn = onSignIn
    self.payment = payment
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SessionBannerView(model: banner, actionEnabled: !busy, onAction: onSignIn)
      Text("meridian")
        .font(.largeTitle)
        .fontWeight(.semibold)
      Text("Native SwiftUI · Fictional payment rehearsal")
        .font(.caption)
      TextField("API base URL", text: $endpoint)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier(AuthAccessibility.endpoint)
        .accessibilitySortPriority(AuthAccessibility.endpointPriority)
      TextField("Shared rehearsal room", text: $room)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier(AuthAccessibility.room)
        .accessibilitySortPriority(AuthAccessibility.roomPriority)
      Button("Sign in", action: onSignIn)
        .accessibilityIdentifier(AuthAccessibility.connect)
        .accessibilitySortPriority(AuthAccessibility.connectPriority)
        .disabled(busy)
      Text(message)
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      if banner.allowsPayment {
        payment()
          .accessibilityIdentifier(AuthAccessibility.payment)
          .accessibilitySortPriority(AuthAccessibility.paymentPriority)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
