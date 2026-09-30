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
  @State private var handoff: IntentSnapshot?
  @State private var snapshotStore = FileIntentSnapshotStore.defaultStore()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("meridian").font(.largeTitle).fontWeight(.semibold)
        Text("Native SwiftUI · Fictional payment rehearsal").font(.caption)
        Group {
          TextField("API base URL", text: $endpoint)
          TextField("Shared rehearsal room", text: $room)
          Button("Connect") { Task { await connect(resuming: false) } }.disabled(busy)
        }.textFieldStyle(.roundedBorder)
        Text(message).font(.callout).foregroundStyle(.secondary)
        if let handoff, handoff.phase == .succeeded {
          receiptCard(makeReceipt(snapshot: handoff, intent: nil))
        }
        if let handoff, handoff.phase == .declined {
          Text(recoveryFeedback(for: .declined))
            .font(.callout)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 1, green: 0.93, blue: 0.92))
            .clipShape(RoundedRectangle(cornerRadius: 8))
          Button("New payment") { startNewPayment() }.disabled(busy)
        }
        if let state {
          VStack(alignment: .leading, spacing: 8) {
            Text("Everyday account · GBP").font(.caption)
            Text(money(state.balance)).font(.system(size: 38, weight: .medium))
            Text("Shared room: \(room)").font(.caption)
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.078, green: 0.173, blue: 0.208)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
          Text("Make a payment").font(.title2)
          if handoff?.phase != .declined {
            if let catalog {
              Picker("Recipient", selection: $recipient) { ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) } }.disabled(review || busy || statusLocked)
            }
            TextField("Amount (GBP)", text: $amount).textFieldStyle(.roundedBorder).disabled(review || busy || statusLocked)
            TextField("Reference", text: $reference).textFieldStyle(.roundedBorder).disabled(review || busy || statusLocked)
            // Intentionally hardcoded baseline: new providers still require a native release.
            Picker("Method", selection: $method) { Text("Debit card · Adyen").tag(PaymentMethod.card); Text("Bank payment · Worldpay").tag(PaymentMethod.bank) }.disabled(review || busy || statusLocked)
            if statusLocked {
              Text(recoveryFeedback(for: handoff?.phase ?? .processing)).font(.callout)
              if handoff?.intentId != nil {
                Button("Check status again") { Task { await checkStatusAgain() } }.disabled(busy)
              } else {
                Button("Retry this payment") { Task { await pay() } }.disabled(busy)
              }
            } else if review {
              Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
              Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy)
              Button("Edit details") { review = false; key = UUID().uuidString }.disabled(busy)
            } else {
              Button("Review payment") { reviewPayment() }.disabled(busy)
            }
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
          ForEach(state.budgets, id: \.category) { budget in HStack { Text(budget.category.rawValue); Spacer(); Text(money(budget.limit)) } }
        }
      }.padding(24).frame(maxWidth: 550)
    }
    .task { await restoreHandoffIfNeeded() }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        if !busy { await refresh() }
      }
    }
  }

  private var statusLocked: Bool {
    guard let handoff else { return false }
    switch recoveryAction(for: handoff) {
    case .poll, .holdUnknown:
      return true
    case .showReceipt, .showDecline:
      return false
    }
  }

  @ViewBuilder private func receiptCard(_ receipt: PaymentReceipt) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Payment complete").font(.headline)
      Text("Recipient").font(.caption).foregroundStyle(.secondary)
      Text(receipt.recipientName)
      Text("Amount").font(.caption).foregroundStyle(.secondary)
      Text(money(receipt.amountMinor))
      Text("Support reference").font(.caption).foregroundStyle(.secondary)
      Text(receipt.supportReference).font(.system(.body, design: .monospaced))
      if let transactionId = receipt.transactionId {
        Text("Transaction \(transactionId)").font(.caption)
      }
      if let date = receipt.transactionDate {
        Text(date).font(.caption)
      }
      Text("\(methodLabel(receipt.method)) · \(providerLabel(receipt.provider))").font(.caption)
      if let note = receipt.note, !note.isEmpty {
        Text(note).font(.caption)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(red: 0.91, green: 0.95, blue: 0.87))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private func methodLabel(_ method: String?) -> String {
    method == "bank" ? "Bank payment" : "Debit card"
  }

  private func reviewPayment() {
    let (value, error) = parseAmount(amount)
    guard value != nil else { message = error ?? "Invalid amount"; return }
    guard reference.count <= 200 else { message = "Reference is too long"; return }
    key = UUID().uuidString
    review = true
    message = "Review before confirming. No real money moves."
  }

  private func startNewPayment() {
    snapshotStore.remove(sessionId: room)
    handoff = nil
    review = false
    amount = ""
    reference = ""
    key = UUID().uuidString
    message = "Ready for a new demo payment."
  }

  private func restoreHandoffIfNeeded() async {
    guard let saved = snapshotStore.latestRecoverable() else { return }
    endpoint = saved.baseURL
    room = saved.sessionId
    await connect(resuming: true)
  }

  private func connect(resuming: Bool) async {
    guard room.range(of: "^[A-Za-z0-9_-]{3,64}$", options: .regularExpression) != nil else {
      message = "Invalid room"
      return
    }
    generation += 1
    let saved = snapshotStore.load(sessionId: room)
    state = nil
    catalog = nil
    if let saved {
      handoff = saved
      key = saved.idempotencyKey
      recipient = saved.recipientId
      method = saved.method == "bank" ? .bank : .card
      review = false
    } else if !resuming {
      handoff = nil
      review = false
      key = UUID().uuidString
    }
    do {
      client = try MeridianClient(baseURL: endpoint, sessionId: room)
      if let saved {
        await recover(saved)
      }
      await refresh()
    } catch {
      message = String(describing: error)
    }
  }

  private func recover(_ saved: IntentSnapshot) async {
    switch recoveryAction(for: saved) {
    case .poll(let intentId):
      await pollStatus(intentId: intentId)
    case .showReceipt:
      message = recoveryFeedback(for: .succeeded)
    case .showDecline:
      message = recoveryFeedback(for: .declined)
    case .holdUnknown:
      message = recoveryFeedback(for: .unknown)
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
        if handoff == nil {
          message = "Connected to shared Java API"
        }
      }
    } catch {
      if started == generation && handoff == nil {
        message = "API unavailable: \(error)"
      }
    }
  }

  private func pay() async {
    guard let client, !busy else { return }
    if handoff?.phase == .declined { return }
    if let handoff, case .poll = recoveryAction(for: handoff) { return }
    busy = true
    generation += 1
    defer { busy = false }
    let (minor, error) = parseAmount(amount)
    guard let minor else { message = error ?? "Invalid amount"; return }
    let recipientName = catalog?.recipients.first { $0.id == recipient }?.name ?? recipient
    do {
      let result = try await client.submitPayment(
        recipientId: recipient,
        amountMinor: minor,
        method: method,
        note: reference,
        scenario: .success,
        idempotencyKey: key
      )
      let snapshot = IntentSnapshot(
        intentId: result.paymentId,
        sessionId: room,
        baseURL: endpoint,
        idempotencyKey: key,
        recipientId: recipient,
        recipientName: result.transaction?.name ?? recipientName,
        amountMinor: result.transaction?.amount ?? minor,
        method: method.rawValue,
        note: reference,
        phase: phase(for: result),
        supportReference: result.transaction?.reference,
        transaction: result.transaction,
        provider: result.transaction?.provider.rawValue ?? baselineProvider(method: method.rawValue),
        detail: result.error,
        updatedAt: isoTimestamp()
      )
      if let next = result.state { state = next }
      snapshotStore.save(snapshot)
      handoff = snapshot
      if snapshot.phase == .succeeded {
        review = false
        amount = ""
        reference = ""
        key = UUID().uuidString
        message = recoveryFeedback(for: .succeeded)
        return
      }
      if snapshot.phase == .declined {
        message = recoveryFeedback(for: .declined)
        return
      }
      if let intentId = snapshot.intentId, !intentId.isEmpty {
        await pollStatus(intentId: intentId, ownsBusy: false)
      } else {
        message = recoveryFeedback(for: .unknown)
      }
    } catch {
      let snapshot = IntentSnapshot(
        intentId: handoff?.intentId,
        sessionId: room,
        baseURL: endpoint,
        idempotencyKey: key,
        recipientId: recipient,
        recipientName: recipientName,
        amountMinor: minor,
        method: method.rawValue,
        note: reference,
        phase: .unknown,
        provider: baselineProvider(method: method.rawValue),
        detail: recoveryFeedback(for: .unknown),
        updatedAt: isoTimestamp()
      )
      snapshotStore.save(snapshot)
      handoff = snapshot
      message = recoveryFeedback(for: .unknown)
    }
  }

  private func checkStatusAgain() async {
    guard let intentId = handoff?.intentId, !intentId.isEmpty else { return }
    await pollStatus(intentId: intentId)
  }

  private func pollStatus(intentId: String, ownsBusy: Bool = true) async {
    guard let client else { return }
    if ownsBusy {
      guard !busy else { return }
      busy = true
      generation += 1
    }
    message = recoveryFeedback(for: handoff?.phase == .pending ? .pending : .processing)
    defer { if ownsBusy { busy = false } }
    let poller = PaymentStatusPoller(getIntent: { id in
      try await client.getPaymentIntent(id: id)
    })
    let result = await poller.poll(intentId: intentId)
    guard var current = handoff ?? snapshotStore.load(sessionId: room) else { return }
    current = applying(result, to: current)
    snapshotStore.save(current)
    handoff = current
    message = recoveryFeedback(for: current.phase)
    if result.phase == .succeeded {
      review = false
      amount = ""
      reference = ""
      key = UUID().uuidString
      if let next = try? await client.getState() { state = next }
    }
  }
}
