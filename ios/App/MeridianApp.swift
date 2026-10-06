import SwiftUI
import MeridianSDK

@main struct MeridianApp: App {
  var body: some Scene { WindowGroup { MeridianView().frame(minWidth: 350, minHeight: 650) } }
}

@MainActor struct MeridianView: View {
  @State private var endpoint = "http://127.0.0.1:8080/api/v1"
  @State private var room = "meridian-rehearsal"
  @State private var customerAccount = "demo-customer"
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
  @State private var resumedIntentId: String?
  @State private var restoredStorage = false
  @State private var ledger = PaymentIntentLedger(store: KeychainPaymentIntentStore())

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("meridian").font(.largeTitle).fontWeight(.semibold)
        Text("Native SwiftUI · Fictional payment rehearsal").font(.caption)
        Text("Payment intents are stored in the iOS Keychain for this customer account.").font(.caption).foregroundStyle(.secondary)
        Group {
          TextField("API base URL", text: $endpoint).disabled(busy)
          TextField("Shared rehearsal room", text: $room).disabled(busy)
          TextField("Customer account", text: $customerAccount).disabled(busy)
          Button("Connect") { Task { await connect() } }.disabled(busy)
        }.textFieldStyle(.roundedBorder)
        Text(message).font(.callout).foregroundStyle(.secondary)
        if let state {
          VStack(alignment: .leading, spacing: 8) {
            Text("Everyday account · GBP").font(.caption)
            Text(money(state.balance)).font(.system(size: 38, weight: .medium))
            Text("Shared room: \(room)").font(.caption)
            Text("Customer account: \(customerAccount)").font(.caption)
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.078, green: 0.173, blue: 0.208)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
          Text("Make a payment").font(.title2)
          if let resumedIntentId {
            Text("Resuming \(resumedIntentId). The idempotency key stays in protected storage.").font(.caption)
          }
          if let catalog {
            Picker("Recipient", selection: $recipient) { ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) } }.disabled(review || busy)
          }
          TextField("Amount (GBP)", text: $amount).textFieldStyle(.roundedBorder).disabled(review || busy)
          TextField("Reference", text: $reference).textFieldStyle(.roundedBorder).disabled(review || busy)
          Picker("Method", selection: $method) {
            Text("Debit card · Adyen").tag(PaymentMethod.card)
            Text("Bank payment · Worldpay").tag(PaymentMethod.bank)
          }.disabled(review || busy)
          if review {
            Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
            Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy)
            Button("Edit details") { editDetails() }.disabled(busy)
          } else {
            Button("Review payment") { reviewPayment() }.disabled(busy)
          }
          Text("Recent activity").font(.title2)
          ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in
            HStack {
              VStack(alignment: .leading) {
                Text(transaction.name)
                Text(transaction.provider.rawValue).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Text(money(transaction.amount))
            }
          }
          Text("September budgets").font(.title2)
          ForEach(state.budgets, id: \.category) { budget in
            HStack { Text(budget.category.rawValue); Spacer(); Text(money(budget.limit)) }
          }
        }
      }.padding(24).frame(maxWidth: 550)
    }.task {
      if !restoredStorage {
        restoredStorage = true
        restoreStoredAccount()
      }
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        if !busy { await refresh() }
      }
    }
  }

  private func amountField(_ pence: Int) -> String {
    String(format: "%d.%02d", pence / 100, pence % 100)
  }

  private func apply(_ intent: PaymentIntentSnapshot) {
    recipient = intent.recipientId
    amount = amountField(intent.amountMinor)
    reference = intent.note
    method = intent.method
    key = intent.idempotencyKey
    review = true
    resumedIntentId = intent.paymentIntentId
  }

  private func restoreStoredAccount() {
    do {
      guard let saved = try ledger.lastCustomerAccountId(), customerAccount == "demo-customer" else { return }
      customerAccount = saved
      if let intent = try ledger.activeIntents(customerAccountId: saved).first {
        apply(intent)
        message = "Active payment intent \(intent.paymentIntentId) is stored for \(saved). Connect to resume it."
      }
    } catch {
      message = "Protected storage is unavailable: \(error.localizedDescription)"
    }
  }

  private func connect() async {
    guard room.range(of: "^[A-Za-z0-9_-]{3,64}$", options: .regularExpression) != nil else {
      message = "Invalid room"
      return
    }
    guard PaymentIntentIds.isValidCustomerAccountId(customerAccount) else {
      message = "Invalid customer account"
      return
    }
    generation += 1
    state = nil
    catalog = nil
    resumedIntentId = nil
    do {
      client = try MeridianClient(baseURL: endpoint, sessionId: room)
    } catch {
      message = String(describing: error)
      return
    }
    do {
      try ledger.rememberCustomerAccount(customerAccount)
    } catch {
      message = "Could not store the customer account: \(error.localizedDescription)"
    }
    await refresh()
    let refreshMessage = message
    do {
      if let intent = try ledger.activeIntents(customerAccountId: customerAccount).first {
        apply(intent)
        let resume = "Resumed active payment intent \(intent.paymentIntentId) (\(intent.status.rawValue)). Retry uses the same idempotency key."
        message = refreshMessage.hasPrefix("API unavailable") ? "\(refreshMessage) \(resume)" : resume
      } else {
        review = false
        resumedIntentId = nil
        key = UUID().uuidString
      }
    } catch {
      message = "Could not read protected payment intent storage: \(error.localizedDescription)"
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
        if resumedIntentId == nil { message = "Connected to shared Java API" }
      }
    } catch {
      if started == generation { message = "API unavailable: \(error)" }
    }
  }

  private func reviewPayment() {
    let (value, error) = parseAmount(amount)
    guard let value else {
      message = error ?? "Invalid amount"
      return
    }
    guard reference.count <= 200 else {
      message = "Reference is too long"
      return
    }
    do {
      let prepared = try ledger.begin(
        customerAccountId: customerAccount,
        recipientId: recipient,
        amountMinor: value,
        method: method,
        note: reference,
        scenario: .success
      )
      if let token = prepared.returnState, !ledger.verifyReturnState(prepared.snapshot, returnState: token) {
        message = "Return state could not be verified."
        return
      }
      key = prepared.snapshot.idempotencyKey
      resumedIntentId = prepared.snapshot.paymentIntentId
      review = true
      message = prepared.returnState == nil
        ? "Review before confirming. The existing idempotency key will be reused."
        : "Review before confirming. No real money moves."
    } catch PaymentIntentError.activeIntentInProgress(let id) {
      if let existing = try? ledger.snapshot(customerAccountId: customerAccount, paymentIntentId: id) {
        apply(existing)
        message = "Finish payment intent \(id) before starting a different one. The same idempotency key will be reused."
      } else {
        message = "Another payment intent is still active."
      }
    } catch {
      message = "Could not store the payment intent: \(error.localizedDescription)"
    }
  }

  private func editDetails() {
    guard let id = resumedIntentId else {
      review = false
      key = UUID().uuidString
      return
    }
    do {
      let current = try ledger.snapshot(customerAccountId: customerAccount, paymentIntentId: id)
      if current.status != .created {
        message = "This payment was already submitted. Retry uses the same idempotency key."
        return
      }
      _ = try ledger.cancel(customerAccountId: customerAccount, paymentIntentId: id)
      review = false
      resumedIntentId = nil
      key = UUID().uuidString
    } catch {
      message = "Could not update the payment intent: \(error.localizedDescription)"
    }
  }

  private func pay() async {
    guard let client, !busy else { return }
    guard let intentId = resumedIntentId else {
      message = "Review the payment before confirming."
      return
    }
    let account = customerAccount
    busy = true
    generation += 1
    defer { busy = false }
    var submitted = false
    do {
      let snapshot = try ledger.markSubmitted(customerAccountId: account, paymentIntentId: intentId)
      submitted = true
      key = snapshot.idempotencyKey
      let result = try await client.submitPayment(
        recipientId: snapshot.recipientId,
        amountMinor: snapshot.amountMinor,
        method: snapshot.method,
        note: snapshot.note,
        scenario: snapshot.scenario,
        idempotencyKey: snapshot.idempotencyKey
      )
      let updated = try ledger.record(response: result, customerAccountId: account, paymentIntentId: intentId)
      if updated.status == .completed {
        state = result.state ?? state
        review = false
        amount = ""
        reference = ""
        resumedIntentId = nil
        key = UUID().uuidString
        message = "Demo payment completed. Other clients will refresh."
      } else if updated.status.isTerminal {
        review = false
        resumedIntentId = nil
        key = UUID().uuidString
        message = result.error ?? "Payment was declined."
      } else {
        review = true
        resumedIntentId = updated.paymentIntentId
        key = updated.idempotencyKey
        message = result.error ?? "Payment pending. Retry the same payment, not a new one."
      }
    } catch {
      if submitted {
        if let uncertain = try? ledger.markUncertain(customerAccountId: account, paymentIntentId: intentId) {
          key = uncertain.idempotencyKey
          resumedIntentId = uncertain.paymentIntentId
          review = true
        }
        message = "Outcome may be unknown: \(error). Retry preserves the payment key."
      } else {
        message = "Could not store the payment intent: \(error.localizedDescription)"
      }
    }
  }
}
