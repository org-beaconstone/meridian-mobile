import SwiftUI
import MeridianSDK

@main struct MeridianApp: App {
  var body: some Scene { WindowGroup { MeridianView().frame(minWidth: 350, minHeight: 650) } }
}

@MainActor struct MeridianView: View {
  @State private var endpoint = "http://127.0.0.1:8080/api/v1"
  @State private var room = "meridian-rehearsal"
  @State private var customerAccount = "everyday-gbp"
  @State private var intentAccount = "everyday-gbp"
  @State private var client: MeridianClient?
  @State private var state: BankState?
  @State private var catalog: CatalogResponse?
  @State private var recipient = "northline-studio"
  @State private var amount = ""
  @State private var reference = ""
  @State private var method: PaymentMethod = .card
  @State private var key = UUID().uuidString
  @State private var paymentIntentId = UUID().uuidString
  @State private var review = false
  @State private var busy = false
  @State private var resumed = false
  @State private var message = "Connect to the Spring Boot API to start."
  @State private var generation = 0
  @State private var intents = MeridianView.makeIntents()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("meridian").font(.largeTitle).fontWeight(.semibold)
        Text("Native SwiftUI · Fictional payment rehearsal").font(.caption)
        Group {
          TextField("API base URL", text: $endpoint)
          TextField("Shared rehearsal room", text: $room)
          TextField("Customer account", text: $customerAccount).disabled(busy)
          Button("Connect") { Task { await connect() } }.disabled(busy)
        }.textFieldStyle(.roundedBorder)
        Text(message).font(.callout).foregroundStyle(.secondary)
        if let state {
          VStack(alignment: .leading, spacing: 8) {
            Text("Everyday account · GBP").font(.caption)
            Text(money(state.balance)).font(.system(size: 38, weight: .medium))
            Text("Shared room: \(room)").font(.caption)
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.078, green: 0.173, blue: 0.208)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
          Text("Make a payment").font(.title2)
          if let catalog {
            Picker("Recipient", selection: $recipient) { ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) } }.disabled(review || busy)
          }
          TextField("Amount (GBP)", text: $amount).textFieldStyle(.roundedBorder).disabled(review || busy)
          TextField("Reference", text: $reference).textFieldStyle(.roundedBorder).disabled(review || busy)
          // Intentionally hardcoded baseline: new providers still require a native release.
          Picker("Method", selection: $method) { Text("Debit card · Adyen").tag(PaymentMethod.card); Text("Bank payment · Worldpay").tag(PaymentMethod.bank) }.disabled(review || busy)
          if review {
            Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
            Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy)
            Button("Edit details") { editDetails() }.disabled(busy)
            if resumed {
              Button("Abandon in-progress payment") { abandonIntent() }.disabled(busy)
            }
          } else {
            Button("Review payment") { reviewPayment() }.disabled(busy)
          }
          Text("Recent activity").font(.title2)
          ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in
            HStack { VStack(alignment: .leading) { Text(transaction.name); Text(transaction.provider.rawValue).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(money(transaction.amount)) }
          }
          Text("September budgets").font(.title2)
          ForEach(state.budgets, id: \.category) { budget in HStack { Text(budget.category.rawValue); Spacer(); Text(money(budget.limit)) } }
        }
      }.padding(24).frame(maxWidth: 550)
    }
    .onChange(of: customerAccount) { newValue in
      guard newValue != intentAccount else { return }
      resumed = false
      review = false
      key = UUID().uuidString
      paymentIntentId = UUID().uuidString
      intentAccount = newValue
      message = "Customer account changed. In-progress payments stay with the previous account."
    }
    .task {
      restoreActiveIntent()
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        if !busy { await refresh() }
      }
    }
  }

  private static func makeIntents() -> PaymentIntentSnapshotRepository {
    #if canImport(Security)
    PaymentIntentSnapshotRepository(store: KeychainPaymentIntentSnapshotStore())
    #else
    PaymentIntentSnapshotRepository(store: InMemoryPaymentIntentSnapshotStore())
    #endif
  }

  private func nowMs() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
  }

  private func activeIntent() -> PaymentIntentSnapshot? {
    guard PaymentIntentAccounts.isValidAccount(customerAccount) else { return nil }
    return try? intents.resumeActive(customerAccountId: customerAccount, nowEpochMs: nowMs()).first
  }

  private func apply(_ intent: PaymentIntentSnapshot) {
    intentAccount = intent.customerAccountId
    customerAccount = intent.customerAccountId
    recipient = intent.recipientId
    amount = String(format: "%d.%02d", intent.amountMinor / 100, intent.amountMinor % 100)
    reference = intent.note
    method = intent.method
    key = intent.idempotencyKey
    paymentIntentId = intent.paymentIntentId
    resumed = true
    review = true
  }

  private func rotateKeys() {
    key = UUID().uuidString
    paymentIntentId = UUID().uuidString
    intentAccount = customerAccount
    resumed = false
  }

  private func restoreActiveIntent() {
    guard let intent = activeIntent() else { return }
    apply(intent)
    message = "In-progress payment intent restored. Retry uses the same payment key."
  }

  private func reviewPayment() {
    if let intent = activeIntent() {
      apply(intent)
      message = "In-progress payment restored. Confirm retries the same payment key."
      return
    }
    let (value, error) = parseAmount(amount)
    guard value != nil else { message = error ?? "Invalid amount"; return }
    guard reference.count <= 200 else { message = "Reference is too long"; return }
    guard PaymentIntentAccounts.isValidAccount(customerAccount) else { message = "Customer account id is required"; return }
    rotateKeys()
    review = true
    message = "Review before confirming. No real money moves."
  }

  private func editDetails() {
    if resumed {
      message = "This payment is still in progress. Abandon it before changing details."
      return
    }
    review = false
    rotateKeys()
  }

  private func abandonIntent() {
    guard PaymentIntentAccounts.isValidAccount(customerAccount) else { return }
    do {
      _ = try intents.cancel(customerAccountId: customerAccount, paymentIntentId: paymentIntentId, nowEpochMs: nowMs())
      review = false
      rotateKeys()
      message = "In-progress payment abandoned. A new payment key will be used."
    } catch {
      message = "Could not abandon the payment intent."
    }
  }

  private func connect() async {
    guard room.range(of: "^[A-Za-z0-9_-]{3,64}$", options: .regularExpression) != nil else { message = "Invalid room"; return }
    guard PaymentIntentAccounts.isValidAccount(customerAccount) else { message = "Customer account id is required"; return }
    generation += 1
    state = nil
    catalog = nil
    review = false
    do {
      client = try MeridianClient(baseURL: endpoint, sessionId: room)
      if let intent = activeIntent() {
        apply(intent)
        message = "In-progress payment intent restored. Retry uses the same payment key."
      } else {
        rotateKeys()
      }
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
        if !resumed { message = "Connected to shared Java API" }
      }
    } catch {
      if started == generation { message = "API unavailable: \(error)" }
    }
  }

  private func pay() async {
    guard let client, !busy else { return }
    guard PaymentIntentAccounts.isValidAccount(customerAccount) else { message = "Customer account id is required"; return }
    busy = true
    generation += 1
    defer { busy = false }
    let (minor, error) = parseAmount(amount)
    guard let minor else { message = error ?? "Invalid amount"; return }
    let began: BeginPaymentIntent
    do {
      began = try intents.begin(
        PaymentIntentDraft(
          customerAccountId: customerAccount,
          paymentIntentId: paymentIntentId,
          idempotencyKey: key,
          recipientId: recipient,
          amountMinor: minor,
          method: method,
          note: reference
        ),
        nowEpochMs: nowMs()
      )
    } catch {
      message = error.localizedDescription
      return
    }
    if !began.payloadMatches {
      apply(began.snapshot)
      message = "An in-progress payment must be retried with its original details."
      return
    }
    key = began.snapshot.idempotencyKey
    paymentIntentId = began.snapshot.paymentIntentId
    intentAccount = began.snapshot.customerAccountId
    resumed = true
    do {
      let result = try await client.submitPayment(
        recipientId: began.snapshot.recipientId,
        amountMinor: began.snapshot.amountMinor,
        method: began.snapshot.method,
        note: began.snapshot.note,
        scenario: .success,
        idempotencyKey: began.snapshot.idempotencyKey
      )
      let updated = try intents.recordOutcome(
        customerAccountId: began.snapshot.customerAccountId,
        paymentIntentId: began.snapshot.paymentIntentId,
        response: result,
        nowEpochMs: nowMs()
      )
      if updated.status == .succeeded {
        state = result.state
        review = false
        amount = ""
        reference = ""
        rotateKeys()
        message = "Demo payment completed. Other clients will refresh."
      } else if updated.status.isTerminal {
        review = false
        rotateKeys()
        message = result.error ?? "Payment was not completed."
      } else {
        if let next = result.state { state = next }
        resumed = true
        review = true
        message = result.error ?? "Payment pending. Retry the same payment, not a new one."
      }
    } catch {
      _ = try? intents.markUncertain(
        customerAccountId: began.snapshot.customerAccountId,
        paymentIntentId: began.snapshot.paymentIntentId,
        nowEpochMs: nowMs()
      )
      resumed = true
      message = "Outcome may be unknown: \(error). Retry preserves the payment key."
    }
  }
}
