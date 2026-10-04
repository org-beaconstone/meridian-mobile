import SwiftUI
import MeridianSDK

@main struct MeridianApp: App {
  var body: some Scene { WindowGroup { MeridianView().frame(minWidth: 350, minHeight: 650) } }
}

@MainActor struct MeridianView: View {
  @SceneStorage("meridian.endpoint") private var endpoint = "http://127.0.0.1:8080/api/v1"
  @SceneStorage("meridian.room") private var room = "meridian-rehearsal"
  @SceneStorage("meridian.connectedRoom") private var connectedRoom = ""
  @SceneStorage("meridian.amount") private var amount = ""
  @SceneStorage("meridian.iban") private var iban = ""
  @SceneStorage("meridian.reference") private var reference = ""
  @SceneStorage("meridian.recipient") private var recipient = "northline-studio"
  @SceneStorage("meridian.method") private var methodRaw = PaymentMethod.card.rawValue
  @SceneStorage("meridian.review") private var review = false
  @SceneStorage("meridian.paymentKey") private var key = ""
  @State private var client: MeridianClient?
  @State private var state: BankState?
  @State private var catalog: CatalogResponse?
  @State private var busy = false
  @State private var message = "Connect to the Spring Boot API to start."
  @State private var generation = 0

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("meridian").font(.largeTitle).fontWeight(.semibold).fixedSize(horizontal: false, vertical: true)
        Text("Native SwiftUI · Fictional payment rehearsal").font(.caption).fixedSize(horizontal: false, vertical: true)
        Group {
          TextField("API base URL", text: $endpoint)
          TextField("Shared rehearsal room", text: $room)
          GrowingButton(title: "Connect", prominent: true, enabled: !busy) { Task { await connect() } }
        }.textFieldStyle(.roundedBorder)
        Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if let state {
          VStack(alignment: .leading, spacing: 8) {
            Text("Everyday account · GBP").font(.caption)
            ViewThatFits(in: .horizontal) {
              Text(money(state.balance)).font(.largeTitle)
              Text(money(state.balance)).font(.title)
              Text(money(state.balance)).font(.title2)
            }
            Text("Shared room: \(room)").font(.caption).fixedSize(horizontal: false, vertical: true)
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.078, green: 0.173, blue: 0.208)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
          Text("Make a payment").font(.title2).fixedSize(horizontal: false, vertical: true)
          if let catalog {
            VStack(alignment: .leading, spacing: 8) {
              Text("Recipient").font(.subheadline).fixedSize(horizontal: false, vertical: true)
              ForEach(catalog.recipients, id: \.id) { person in
                ChoiceRow(title: person.name, selected: recipient == person.id, enabled: !review && !busy) {
                  recipient = person.id
                }
              }
            }
          }
          AmountInputField(text: $amount, enabled: !review && !busy)
          TextField("Reference", text: $reference, axis: .vertical)
            .lineLimit(1...4)
            .textFieldStyle(.roundedBorder)
            .disabled(review || busy)
          VStack(alignment: .leading, spacing: 8) {
            Text("Method").font(.subheadline).fixedSize(horizontal: false, vertical: true)
            ChoiceRow(title: "Debit card · Adyen", selected: methodRaw == PaymentMethod.card.rawValue, enabled: !review && !busy) {
              methodRaw = PaymentMethod.card.rawValue
            }
            ChoiceRow(title: "Bank payment · Worldpay", selected: methodRaw == PaymentMethod.bank.rawValue, enabled: !review && !busy) {
              methodRaw = PaymentMethod.bank.rawValue
            }
          }
          if methodRaw == PaymentMethod.bank.rawValue {
            IbanInputField(text: $iban, enabled: !review && !busy)
          }
          if review {
            Text(confirmationLine)
              .font(.headline)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
            GrowingButton(title: busy ? "Confirming…" : "Confirm payment", prominent: true, enabled: !busy) {
              Task { await pay() }
            }
            GrowingButton(title: "Edit details", prominent: false, enabled: !busy) { editDetails() }
          } else {
            GrowingButton(title: "Review payment", prominent: true, enabled: !busy) { beginReview() }
          }
          Text("Recent activity").font(.title2)
          ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in
            HStack(alignment: .top, spacing: 12) {
              VStack(alignment: .leading, spacing: 2) {
                Text(transaction.name).fixedSize(horizontal: false, vertical: true)
                Text(transaction.provider.rawValue).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              Text(money(transaction.amount)).fixedSize(horizontal: true, vertical: true)
            }
          }
          Text("September budgets").font(.title2)
          ForEach(state.budgets, id: \.category) { budget in
            HStack(alignment: .top) {
              Text(budget.category.rawValue).fixedSize(horizontal: false, vertical: true)
              Spacer(minLength: 8)
              Text(money(budget.limit))
            }
          }
        }
      }
      .padding(24)
      .frame(maxWidth: 550)
    }
    .onAppear {
      if key.isEmpty { key = UUID().uuidString }
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        if !busy { await refresh() }
      }
    }
  }

  private var confirmationLine: String {
    let spoken = evaluateAmount(amount).spoken
    if methodRaw == PaymentMethod.bank.rawValue {
      let normalized = formatIbanGroups(validateIban(iban).normalized)
      return "Confirm \(spoken) to \(recipient) using IBAN \(normalized)"
    }
    return "Confirm \(spoken) to \(recipient)"
  }

  private func currentEntry() -> PaymentEntry {
    PaymentEntry(
      amount: amount,
      iban: iban,
      reference: reference,
      recipientId: recipient,
      method: methodRaw,
      idempotencyKey: key,
      reviewing: review
    )
  }

  private func apply(_ entry: PaymentEntry) {
    amount = entry.amount
    iban = entry.iban
    reference = entry.reference
    recipient = entry.recipientId
    methodRaw = entry.method
    key = entry.idempotencyKey
    review = entry.reviewing
  }

  private func beginReview() {
    let entry = currentEntry()
    if let error = paymentReviewError(entry) {
      message = error
      return
    }
    apply(reducePaymentEntry(entry, .review(newKey: UUID().uuidString)))
    message = "Review before confirming. No real money moves."
  }

  private func editDetails() {
    apply(reducePaymentEntry(currentEntry(), .edit(newKey: UUID().uuidString)))
  }

  private func connect() async {
    guard room.range(of: "^[A-Za-z0-9_-]{3,64}$", options: .regularExpression) != nil else {
      message = "Invalid room"
      return
    }
    generation += 1
    state = nil
    catalog = nil
    if connectedRoom != room {
      apply(reducePaymentEntry(currentEntry(), .sessionChanged(newKey: UUID().uuidString)))
      connectedRoom = room
    }
    do {
      client = try MeridianClient(baseURL: endpoint, sessionId: room)
      await refresh()
    } catch {
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
        message = "Connected to shared Java API"
      }
    } catch {
      if started == generation { message = "API unavailable: \(error)" }
    }
  }

  private func pay() async {
    guard let client, !busy else { return }
    busy = true
    generation += 1
    defer { busy = false }
    let entry = currentEntry()
    do {
      guard let minor = evaluateAmount(entry.amount).minorUnits else {
        message = evaluateAmount(entry.amount).helper
        return
      }
      let method = PaymentMethod(rawValue: entry.method) ?? .card
      let result = try await client.submitPayment(
        recipientId: entry.recipientId,
        amountMinor: minor,
        method: method,
        note: entry.reference,
        scenario: .success,
        idempotencyKey: entry.idempotencyKey
      )
      if result.ok {
        state = result.state
        apply(reducePaymentEntry(entry, .completed(newKey: UUID().uuidString)))
        message = "Demo payment completed. Other clients will refresh."
      } else {
        apply(reducePaymentEntry(entry, .pending))
        message = result.error ?? "Payment pending. Retry the same payment, not a new one."
      }
    } catch {
      apply(reducePaymentEntry(entry, .networkFailure))
      message = "Outcome may be unknown: \(error). Retry preserves the payment key."
    }
  }
}
