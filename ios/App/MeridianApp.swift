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
  @State private var journal = IdempotencyJournal.restore(UserDefaults.standard.string(forKey: IdempotencyJournal.snapshotDefaultsKey) ?? IdempotencyJournal.emptySnapshot)
  @State private var returns = ReturnStateGuard()
  @State private var catalogCache = CatalogCache()
  @ScaledMetric(relativeTo: .largeTitle) private var balanceSize: CGFloat = 38
  private var balanceNode: A11yNode { AccessibilityCatalog.node("balance")! }
  private var amountNode: A11yNode { AccessibilityCatalog.node("amount-input")! }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("meridian").font(.largeTitle).fontWeight(.semibold)
        Text("Native SwiftUI · Fictional payment rehearsal").font(.caption)
        Group {
          TextField("API base URL", text: $endpoint)
          TextField("Shared rehearsal room", text: $room)
          Button(AccessibilityCatalog.node("connect")!.voiceOverLabel) { Task { await connect() } }
            .disabled(busy)
            .frame(minHeight: 44)
            .accessibilityLabel(AccessibilityCatalog.node("connect")!.voiceOverLabel)
        }.textFieldStyle(.roundedBorder)
        Text(message).font(.callout).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently)
        if let state {
          VStack(alignment: .leading, spacing: 8) {
            Text("Everyday account · GBP").font(.caption)
            Text(money(state.balance))
              .font(.system(size: balanceSize, weight: .medium))
              .minimumScaleFactor(0.6)
              .lineLimit(1)
              .environment(\.layoutDirection, .leftToRight)
              .accessibilityLabel(balanceNode.voiceOverLabel)
              .accessibilityValue(money(state.balance))
            Text("Shared room: \(room)").font(.caption)
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color(red:0.078,green:0.173,blue:0.208)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
          Text("Make a payment").font(.title2)
          if let catalog {
            Picker("Recipient", selection: $recipient) { ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) } }.disabled(review || busy)
          }
          TextField("Amount (GBP)", text: $amount)
            .textFieldStyle(.roundedBorder)
            .disabled(review || busy)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel(amountNode.voiceOverLabel)
          TextField("Reference", text: $reference).textFieldStyle(.roundedBorder).disabled(review || busy)
          // Intentionally hardcoded baseline: new providers still require a native release.
          Picker("Method", selection: $method) {
            Text(AccessibilityCatalog.node("method-card")!.voiceOverLabel).tag(PaymentMethod.card).accessibilityLabel(AccessibilityCatalog.node("method-card")!.voiceOverLabel)
            Text(AccessibilityCatalog.node("method-bank")!.voiceOverLabel).tag(PaymentMethod.bank).accessibilityLabel(AccessibilityCatalog.node("method-bank")!.voiceOverLabel)
          }.disabled(review || busy)
          if review {
            Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
            Button(AccessibilityCatalog.node("confirm-payment")!.voiceOverLabel) { Task { await pay() } }
              .buttonStyle(.borderedProminent)
              .disabled(busy)
              .frame(minHeight: 44)
              .accessibilityLabel(AccessibilityCatalog.node("confirm-payment")!.voiceOverLabel)
            Button("Edit details") { editDetails() }
              .disabled(busy)
              .frame(minHeight: 44)
              .accessibilityIdentifier(AccessibilityCatalog.node("back-navigation")!.id)
              .accessibilityLabel("Edit details")
          } else {
            Button(AccessibilityCatalog.node("review-payment")!.voiceOverLabel) { reviewPayment() }
              .disabled(busy)
              .frame(minHeight: 44)
              .accessibilityLabel(AccessibilityCatalog.node("review-payment")!.voiceOverLabel)
          }
          Text("Recent activity").font(.title2)
          ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in HStack { VStack(alignment:.leading){Text(transaction.name);Text(transaction.provider.rawValue).font(.caption).foregroundStyle(.secondary)};Spacer();Text(money(transaction.amount)).environment(\.layoutDirection, .leftToRight) } }
          Text("September budgets").font(.title2)
          ForEach(state.budgets, id: \.category) { budget in HStack {Text(budget.category.rawValue);Spacer();Text(money(budget.limit)).environment(\.layoutDirection, .leftToRight)} }
        }
      }.padding(24).frame(maxWidth: 550, alignment: .leading)
    }
    .onOpenURL { url in
      returns.select(room)
      let now = Int64(Date().timeIntervalSince1970 * 1000)
      message = returns.userMessage(returns.openUrl(url.absoluteString, now: now))
    }
    .task {
      returns.select(room)
      while !Task.isCancelled { try? await Task.sleep(for: .seconds(2)); if !busy { await refresh() } }
    }
  }
  private func persist() {
    UserDefaults.standard.set(journal.snapshot(), forKey: IdempotencyJournal.snapshotDefaultsKey)
  }
  private func unfinishedElsewhere() -> Bool {
    journal.status == "uncertain" && journal.sessionId != room
  }
  private func reviewPayment() {
    let (value, error) = parseAmount(amount)
    guard let value else { message = error ?? "Invalid amount"; return }
    guard reference.count <= 200 else { message = "Reference is too long"; return }
    if unfinishedElsewhere() {
      message = "Finish the unfinished payment in \(journal.sessionId ?? "the previous room") before starting another."
      return
    }
    if journal.status == "uncertain" {
      key = journal.key ?? key
      review = true
      message = "Retry uses the original payment key."
      return
    }
    if journal.status == "draft" { _ = journal.discardDraft() }
    let next = UUID().uuidString
    if let failure = journal.begin(sessionId: room, key: next, recipientId: recipient, currency: "GBP", minor: value, exponent: 2, method: method.rawValue, note: reference) {
      message = failure.message
      return
    }
    persist()
    key = next
    review = true
    message = "Review before confirming. No real money moves."
  }
  private func editDetails() {
    if journal.status == "uncertain" {
      message = "Retry the same payment. The payment key is unchanged."
      return
    }
    _ = journal.discardDraft()
    persist()
    review = false
    key = UUID().uuidString
  }
  private func connect() async {
    guard room.range(of:"^[A-Za-z0-9_-]{3,64}$",options:.regularExpression) != nil else { message="Invalid room"; return }
    generation += 1
    state = nil
    catalog = nil
    review = false
    returns.select(room)
    if unfinishedElsewhere() {
      message = "An unfinished payment is still open in \(journal.sessionId ?? room). Reconnect to that room to retry it."
    }
    do { client = try MeridianClient(baseURL: endpoint, sessionId: room); await refresh() } catch { message = String(describing: error) }
  }
  private func refresh() async {
    guard let client else { return }
    let started = generation
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    do {
      let next = try await client.getState()
      let definitions = try await client.getCatalog()
      guard started == generation && !busy else { return }
      switch decodeLiveCatalog(definitions) {
      case let .failure(error):
        message = "Catalog rejected: \(error.code)"
      case let .success(document):
        catalogCache.store(session: room, document: document, at: now, ttlMillis: CatalogCache.defaultTtlMillis)
        state = next
        catalog = definitions
        message = unfinishedElsewhere() ? "An unfinished payment is still open in \(journal.sessionId ?? room). Reconnect to that room to retry it." : "Connected to shared Java API"
      }
    } catch {
      guard started == generation else { return }
      switch catalogCache.read(session: room, at: now) {
      case "expired":
        catalog = nil
        message = "Catalog cache expired. Reconnect before paying."
      case "hit":
        message = "API unavailable. Cached catalog is still inside its lifetime."
      default:
        message = "API unavailable: \(error)"
      }
    }
  }
  private func pay() async {
    guard let client, !busy else { return }
    if unfinishedElsewhere() {
      message = "Finish the unfinished payment in \(journal.sessionId ?? "the previous room") before paying here."
      return
    }
    busy = true
    generation += 1
    defer { busy = false }
    do {
      let (minor, error) = parseAmount(amount)
      guard let minor else { message = error ?? "Invalid amount"; return }
      if journal.status != "draft" && journal.status != "uncertain" {
        message = "Review the payment before confirming."
        return
      }
      switch journal.retry(note: reference, recipientId: recipient, minor: minor, method: method.rawValue, currency: "GBP") {
      case .failure:
        message = "Retry the same payment. The payment key is unchanged."
        return
      case let .success(retained):
        key = retained
      }
      _ = journal.markUncertain()
      persist()
      let result = try await client.submitPayment(recipientId: recipient, amountMinor: minor, method: method, note: reference, scenario: .success, idempotencyKey: key)
      if result.ok {
        state = result.state
        _ = journal.markCompleted()
        persist()
        review = false
        amount = ""
        reference = ""
        key = UUID().uuidString
        message = "Demo payment completed. Other clients will refresh."
      } else {
        if let paymentId = result.paymentId {
          returns.select(room)
          _ = returns.arm(sessionId: room, paymentId: paymentId, nonce: key, exp: Int64(Date().timeIntervalSince1970 * 1000) + 300_000, key: key)
        }
        message = result.error ?? "Payment pending. Retry the same payment, not a new one."
      }
    } catch { message = "Outcome may be unknown: \(error). Retry preserves the payment key." }
  }
}
