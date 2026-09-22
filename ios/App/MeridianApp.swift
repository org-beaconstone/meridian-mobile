import SwiftUI
import MeridianSDK

@main struct MeridianApp: App {
  var body: some Scene { WindowGroup { MeridianView().frame(minWidth: 350, minHeight: 650) } }
}

@MainActor struct MeridianView: View {
  @State private var endpoint = "http://127.0.0.1:8080/api/v1"
  @State private var room = "meridian-rehearsal"
  @State private var client: MeridianClient?
  @State private var state: BankState?
  @State private var catalog: CatalogResponse?
  @State private var recipient = "northline-studio"
  @State private var amount = ""
  @State private var reference = ""
  @State private var method: PaymentMethod = .card
  @State private var key = UUID().uuidString
  @State private var review = false
  @State private var busy = false
  @State private var message = "Connect to the Spring Boot API to start."
  @State private var generation = 0

  // PAY-16: session banner and dynamic provider list state
  @State private var sessionState: SessionState = .signedOut
  @State private var catalogState: CatalogState = .idle

  // PAY-16: add-card carousel fields (grouped expiry/CVV two-up row)
  @State private var cardExpiryMonth = ""
  @State private var cardExpiryYear = ""
  @State private var cardCVV = ""

  // Onboarding pages shown in the card payment carousel
  private let cardOnboardingPages: [OnboardingPage] = [
    OnboardingPage(
      systemImageName: "creditcard.fill",
      title: "Add your credit card",
      subtitle: "Pay quickly and securely using Adyen card processing."
    ),
    OnboardingPage(
      systemImageName: "building.columns.fill",
      title: "Bank payment",
      subtitle: "Transfer directly from your account via Worldpay."
    ),
    OnboardingPage(
      systemImageName: "checkmark.shield.fill",
      title: "Safe & rehearsed",
      subtitle: "No real money moves in this demo environment."
    ),
    OnboardingPage(
      systemImageName: "arrow.clockwise.circle.fill",
      title: "Always up to date",
      subtitle: "Payment providers refresh automatically from the catalog."
    ),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("meridian").font(.largeTitle).fontWeight(.semibold)
        Text("Native SwiftUI · Fictional payment rehearsal").font(.caption)

        // PAY-16 – Session banner (gated by feature flag; no effect on sign-in flow)
        AuthSessionBanner(sessionState: sessionState)

        Group {
          TextField("API base URL", text: $endpoint)
          TextField("Shared rehearsal room", text: $room)
          Button("Connect") { Task { await connect() } }.disabled(busy)
        }.textFieldStyle(.roundedBorder)

        Text(message).font(.callout).foregroundStyle(.secondary)

        if let state {
          accountCard(state)
          Text("Make a payment").font(.title2)

          // PAY-16 – Onboarding carousel visible in card payment mode when flag is on
          if FeatureFlags.authSessionBannerEnabled && method == .card && !review {
            OnboardingCarousel(pages: cardOnboardingPages)
          }

          // Recipient picker – shown once catalog is available (always)
          if let catalog {
            Picker("Recipient", selection: $recipient) {
              ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) }
            }.disabled(review || busy)
          }

          // PAY-16 – Provider list with skeleton / retry (flag-gated)
          if FeatureFlags.authSessionBannerEnabled {
            providerSection
          }

          TextField("Amount (GBP)", text: $amount).textFieldStyle(.roundedBorder).disabled(review || busy)
          TextField("Reference", text: $reference).textFieldStyle(.roundedBorder).disabled(review || busy)

          // Intentionally hardcoded baseline: new providers still require a native release.
          Picker("Method", selection: $method) {
            Text("Debit card · Adyen").tag(PaymentMethod.card)
            Text("Bank payment · Worldpay").tag(PaymentMethod.bank)
          }.disabled(review || busy)

          // PAY-16 – Grouped expiry/CVV two-up row shown during card review when flag is on
          if FeatureFlags.authSessionBannerEnabled && method == .card {
            Text("Add your credit card").font(.headline)
            GroupedCardFields(
              expiryMonth: $cardExpiryMonth,
              expiryYear: $cardExpiryYear,
              cvv: $cardCVV
            )
          }

          if review {
            Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
            Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy)
            Button("Edit details") { review = false; key = UUID().uuidString }.disabled(busy)
          } else {
            Button("Review payment") {
              let (value, error) = parseAmount(amount)
              guard value != nil else { message = error ?? "Invalid amount"; return }
              guard reference.count <= 200 else { message = "Reference is too long"; return }
              key = UUID().uuidString; review = true
              message = "Review before confirming. No real money moves."
            }.disabled(busy)
          }

          Text("Recent activity").font(.title2)
          ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { tx in
            HStack {
              VStack(alignment: .leading) {
                Text(tx.name)
                Text(tx.provider.rawValue).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Text(money(tx.amount))
            }
          }

          Text("September budgets").font(.title2)
          ForEach(state.budgets, id: \.category) { budget in
            HStack { Text(budget.category.rawValue); Spacer(); Text(money(budget.limit)) }
          }
        }
      }.padding(24).frame(maxWidth: 550)
    }.task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        if !busy { await refresh() }
      }
    }
  }

  // MARK: – Account card

  private func accountCard(_ state: BankState) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Everyday account · GBP").font(.caption)
      Text(money(state.balance)).font(.system(size: 38, weight: .medium))
      Text("Shared room: \(room)").font(.caption)
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DesignTokens.surfaceBrand)
    .foregroundStyle(DesignTokens.labelOnBrand)
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }

  // MARK: – PAY-16 Provider section (flag-gated)

  @ViewBuilder
  private var providerSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Payment providers").font(.subheadline).foregroundStyle(.secondary)
      ProviderListView(catalogState: catalogState) {
        Task { await retryCatalog() }
      }
    }
  }

  // MARK: – Network actions

  private func connect() async {
    guard room.range(of: "^[A-Za-z0-9_-]{3,64}$", options: .regularExpression) != nil else {
      message = "Invalid room"; return
    }
    generation += 1
    state = nil
    catalog = nil
    review = false
    key = UUID().uuidString
    sessionState = .reAuthenticating
    catalogState = .loading(lastKnown: nil)

    do {
      client = try MeridianClient(baseURL: endpoint, sessionId: room)
      await refresh()
    } catch {
      message = String(describing: error)
      sessionState = .signedOut
      catalogState = .idle
    }
  }

  private func refresh() async {
    guard let client else { return }
    let started = generation
    do {
      let next = try await client.getState()
      let definitions = try await client.getCatalog()
      guard started == generation && !busy else { return }
      state = next
      catalog = definitions
      message = "Connected to shared Java API"
      sessionState = .active

      let providers = definitions.providers
      catalogState = providers.isEmpty ? .empty : .loaded(providers)
    } catch {
      guard started == generation else { return }
      message = "API unavailable: \(error)"

      // On first connect failure the session is still signed out; on subsequent
      // refresh failures the session remains active but the catalog is stale.
      if state == nil {
        sessionState = .signedOut
        catalogState = .idle
      } else {
        // Preserve last known provider list with inline error.
        let lastKnown: [Provider]? = catalog?.providers
        catalogState = .failed(
          "We couldn't load payment methods. Retry",
          lastKnown: lastKnown
        )
      }
    }
  }

  private func retryCatalog() async {
    guard let client else { return }
    let lastKnown: [Provider]? = {
      if case .failed(_, let providers) = catalogState { return providers }
      if case .loaded(let providers) = catalogState { return providers }
      return nil
    }()
    catalogState = .loading(lastKnown: lastKnown)
    do {
      let definitions = try await client.getCatalog()
      let providers = definitions.providers
      catalog = definitions
      catalogState = providers.isEmpty ? .empty : .loaded(providers)
    } catch {
      catalogState = .failed(
        "We couldn't load payment methods. Retry",
        lastKnown: lastKnown
      )
    }
  }

  private func pay() async {
    guard let client, !busy else { return }
    busy = true
    generation += 1
    defer { busy = false }
    do {
      let (minor, error) = parseAmount(amount)
      guard let minor else { message = error ?? "Invalid amount"; return }
      let result = try await client.submitPayment(
        recipientId: recipient,
        amountMinor: minor,
        method: method,
        note: reference,
        scenario: .success,
        idempotencyKey: key
      )
      if result.ok {
        state = result.state
        review = false
        amount = ""
        reference = ""
        cardExpiryMonth = ""
        cardExpiryYear = ""
        cardCVV = ""
        key = UUID().uuidString
        message = "Demo payment completed. Other clients will refresh."
      } else {
        message = result.error ?? "Payment pending. Retry the same payment, not a new one."
      }
    } catch {
      message = "Outcome may be unknown: \(error). Retry preserves the payment key."
    }
  }
}
