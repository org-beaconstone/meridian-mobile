import SwiftUI
import MeridianSDK

@main struct MeridianApp: App {
  var body: some Scene {
    WindowGroup { MeridianView().frame(minWidth: 350, minHeight: 650) }
  }
}

@MainActor struct MeridianView: View {
  @State private var endpoint = "http://127.0.0.1:8080/api/v1"
  @State private var room = "meridian-rehearsal"
  @State private var client: MeridianClient?
  @State private var state: BankState?
  @State private var catalog: CatalogResponse?
  @State private var catalogLoading = false
  @State private var catalogFailed = false
  @State private var recipient = "northline-studio"
  @State private var amount = ""
  @State private var reference = ""
  @State private var corridor: PaymentCorridor = .eurozone
  @State private var method: PaymentMethod? = .card
  @State private var key = UUID().uuidString
  @State private var review = false
  @State private var busy = false
  @State private var message = "Connect to the Spring Boot API to start."
  @State private var generation = 0
  @ScaledMetric(relativeTo: .largeTitle) private var balanceSize: CGFloat = 38

  private var phase: PaymentMethodPhase {
    paymentMethodPhase(
      catalog: catalog,
      retrieving: catalogLoading,
      failed: catalogFailed,
      corridor: corridor
    )
  }

  var body: some View {
    GeometryReader { proxy in
      let contentWidth = max(min(proxy.size.width, 720) - 48, 0)
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("meridian")
            .font(.largeTitle)
            .fontWeight(.semibold)
            .foregroundStyle(Color(PaymentTextColors.ink))
          Text("Native SwiftUI · Fictional payment rehearsal")
            .font(.caption)
            .foregroundStyle(Color(PaymentTextColors.secondary))
          Group {
            TextField("API base URL", text: $endpoint)
              .accessibilityLabel("API base URL")
            TextField("Shared rehearsal room", text: $room)
              .accessibilityLabel("Shared rehearsal room")
            Button("Connect") { Task { await connect() } }
              .disabled(busy)
          }
          .textFieldStyle(.roundedBorder)
          Text(message)
            .font(.callout)
            .foregroundStyle(Color(PaymentTextColors.secondary))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.updatesFrequently)
          if client != nil {
            if let state { balanceCard(state) }
            paymentForm(width: contentWidth)
            if let state { activity(state) }
          }
        }
        .padding(24)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .background(Color(PaymentTextColors.canvas))
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        if !busy { await refresh() }
      }
    }
  }

  private func balanceCard(_ state: BankState) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Everyday account · GBP")
        .font(.caption)
        .foregroundStyle(Color(PaymentTextColors.onInkMuted))
      Text(money(state.balance))
        .font(.system(size: balanceSize, weight: .medium))
        .foregroundStyle(Color(PaymentTextColors.onInk))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text("Shared room: \(room)")
        .font(.caption)
        .foregroundStyle(Color(PaymentTextColors.onInkMuted))
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(PaymentTextColors.ink))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Everyday account. Balance \(money(state.balance)). Currency British pounds, GBP. Shared room \(room)"
    )
  }

  private func paymentForm(width: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Make a payment")
        .font(.title2)
        .foregroundStyle(Color(PaymentTextColors.ink))
        .accessibilityAddTraits(.isHeader)
      if let catalog {
        Picker("Recipient", selection: $recipient) {
          ForEach(catalog.recipients, id: \.id) { person in
            Text(person.name).tag(person.id)
          }
        }
        .disabled(review || busy)
        .accessibilityLabel("Recipient")
      }
      TextField("Amount (GBP)", text: $amount)
        .textFieldStyle(.roundedBorder)
        .disabled(review || busy)
        .accessibilityLabel("Amount in British pounds, GBP")
      TextField("Reference", text: $reference)
        .textFieldStyle(.roundedBorder)
        .disabled(review || busy)
        .accessibilityLabel("Payment reference")
      PaymentCorridorSelection(selected: corridor, enabled: !review && !busy) { next in
        corridor = next
        reconcileSelection()
      }
      PaymentMethodSelection(
        phase: phase,
        selected: method,
        enabled: !review && !busy,
        width: width,
        onSelect: { method = $0 }
      )
      if review {
        reviewActions
      } else {
        Button("Review payment") { beginReview() }
          .buttonStyle(.borderedProminent)
          .disabled(busy || method == nil || !isReady)
      }
    }
  }

  private var isReady: Bool {
    if case .ready = phase { return true }
    return false
  }

  private var reviewActions: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(reviewSummary)
        .font(.headline)
        .foregroundStyle(Color(PaymentTextColors.ink))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(reviewAccessibility)
      Button("Confirm payment") { Task { await pay() } }
        .buttonStyle(.borderedProminent)
        .disabled(busy || method == nil)
      Button("Edit details") {
        review = false
        key = UUID().uuidString
      }
      .disabled(busy)
    }
  }

  private var reviewSummary: String {
    let rail = method.map { railLabel(for: $0) } ?? "No rail"
    return "Confirm \(amount) GBP to \(recipient) via \(rail)"
  }

  private var reviewAccessibility: String {
    let rail = method.map { railAccessibilityLabel(for: $0) } ?? "No payment rail selected."
    return "Confirm \(amount) British pounds, GBP, to \(recipient). \(rail)"
  }

  private func activity(_ state: BankState) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Recent activity")
        .font(.title2)
        .foregroundStyle(Color(PaymentTextColors.ink))
        .accessibilityAddTraits(.isHeader)
      ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text(transaction.name)
              .foregroundStyle(Color(PaymentTextColors.ink))
              .fixedSize(horizontal: false, vertical: true)
            Text(railLabel(for: transaction.method))
              .font(.caption)
              .foregroundStyle(Color(PaymentTextColors.secondary))
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 8)
          Text(money(transaction.amount))
            .foregroundStyle(Color(PaymentTextColors.ink))
            .accessibilityLabel("\(money(transaction.amount)), British pounds, GBP")
        }
      }
      Text("September budgets")
        .font(.title2)
        .foregroundStyle(Color(PaymentTextColors.ink))
        .accessibilityAddTraits(.isHeader)
      ForEach(state.budgets, id: \.category) { budget in
        HStack {
          Text(budget.category.rawValue)
            .foregroundStyle(Color(PaymentTextColors.ink))
          Spacer()
          Text(money(budget.limit))
            .foregroundStyle(Color(PaymentTextColors.ink))
            .accessibilityLabel("\(money(budget.limit)), British pounds, GBP")
        }
      }
    }
  }

  private func reconcileSelection() {
    // A payment already under review keeps its rail and idempotency key.
    if review || busy { return }
    switch phase {
    case let .ready(options):
      if let method, options.contains(where: { $0.method == method }) { return }
      method = options.first?.method
    case .empty:
      method = nil
    case .loading, .unavailable:
      break
    }
  }

  private func beginReview() {
    let (value, error) = parseAmount(amount)
    guard value != nil else {
      message = error ?? "Invalid amount"
      return
    }
    guard reference.count <= 200 else {
      message = "Reference is too long"
      return
    }
    guard method != nil else {
      message = "Choose a payment method"
      return
    }
    key = UUID().uuidString
    review = true
    message = "Review before confirming. No real money moves."
  }

  private func connect() async {
    guard room.range(of: "^[A-Za-z0-9_-]{3,64}$", options: .regularExpression) != nil else {
      message = "Invalid room"
      return
    }
    generation += 1
    state = nil
    catalog = nil
    catalogLoading = true
    catalogFailed = false
    review = false
    key = UUID().uuidString
    do {
      client = try MeridianClient(baseURL: endpoint, sessionId: room)
      await refresh()
    } catch {
      catalogLoading = false
      catalogFailed = true
      message = String(describing: error)
    }
  }

  private func refresh() async {
    guard let client else { return }
    let started = generation
    do {
      let next = try await client.getState()
      let definitions = try await client.getCatalog()
      if started == generation && !busy {
        state = next
        catalog = definitions
        catalogLoading = false
        catalogFailed = false
        message = "Connected to shared Java API"
        reconcileSelection()
      }
    } catch {
      if started == generation {
        catalogLoading = false
        if catalog == nil { catalogFailed = true }
        message = "API unavailable: \(error)"
      }
    }
  }

  private func pay() async {
    guard let client, let method, !busy else { return }
    busy = true
    generation += 1
    defer { busy = false }
    do {
      let (minor, error) = parseAmount(amount)
      guard let minor else {
        message = error ?? "Invalid amount"
        return
      }
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
