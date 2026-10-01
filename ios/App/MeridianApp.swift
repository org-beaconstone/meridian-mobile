import SwiftUI
import MeridianSDK

@main struct MeridianApp: App {
  var body: some Scene {
    WindowGroup {
      MeridianView().frame(minWidth: 350, minHeight: 650)
    }
  }
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
  @State private var enrolledPin = ""
  @State private var challengePin = ""
  @State private var signer = ReturnStateSigner(secret: ReturnStateSigner.randomSecret())
  @State private var attempt: PaymentAttempt?
  @State private var allowRetry = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("meridian").font(.largeTitle).fontWeight(.semibold)
        Text("Native SwiftUI · Fictional payment rehearsal").font(.caption)
        Group {
          TextField("API base URL", text: $endpoint)
          TextField("Shared rehearsal room", text: $room)
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
          SecureField("Rehearsal PIN (4–8 digits)", text: $enrolledPin).textFieldStyle(.roundedBorder).disabled(review || busy)
          // Intentionally hardcoded baseline: new providers still require a native release.
          Picker("Method", selection: $method) { Text("Debit card · Adyen").tag(PaymentMethod.card); Text("Bank payment · Worldpay").tag(PaymentMethod.bank) }.disabled(review || busy)
          if review {
            Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
            if method == .card {
              Text("Strong customer authentication").font(.headline)
              Button("Confirm with biometrics") { Task { await confirmBiometric() } }.disabled(busy)
              SecureField("Enter rehearsal PIN", text: $challengePin).textFieldStyle(.roundedBorder).disabled(busy)
              Button("Confirm with PIN") { confirmPin() }.disabled(busy)
            } else {
              Text("Worldpay bank handoff uses the allowlisted rehearsal host.").font(.callout)
              Button("Continue at your bank") { continueAtBank() }.buttonStyle(.borderedProminent).disabled(busy)
              Button("Deliver signed bank return") { deliverRehearsalReturn() }.disabled(busy)
            }
            if allowRetry {
              Button("Retry same payment") { retrySamePayment() }.disabled(busy)
            }
            Button("Edit details") {
              review = false
              key = UUID().uuidString
              attempt = nil
              allowRetry = false
              challengePin = ""
            }.disabled(busy)
          } else {
            Button("Review payment") {
              let (value, error) = parseAmount(amount)
              guard value != nil else { message = error ?? "Invalid amount"; return }
              guard reference.count <= 200 else { message = "Reference is too long"; return }
              key = UUID().uuidString
              attempt = nil
              allowRetry = false
              challengePin = ""
              review = true
              message = "Review before confirming. No real money moves."
            }.disabled(busy)
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
    .onOpenURL { url in Task { await completeReturn(url) } }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        if !busy { await refresh() }
      }
    }
  }

  private func prepareAttempt() -> PaymentAttempt {
    if let attempt, attempt.idempotencyKey == key, attempt.method == method { return attempt }
    let created = PaymentAttempt(idempotencyKey: key, method: method, signer: signer, enrolledPin: enrolledPin)
    attempt = created
    return created
  }

  private func connect() async {
    guard room.range(of: "^[A-Za-z0-9_-]{3,64}$", options: .regularExpression) != nil else { message = "Invalid room"; return }
    generation += 1
    state = nil
    catalog = nil
    review = false
    key = UUID().uuidString
    attempt = nil
    allowRetry = false
    challengePin = ""
    signer = ReturnStateSigner(secret: ReturnStateSigner.randomSecret())
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
        if !review { message = "Connected to shared Java API" }
      }
    } catch {
      if started == generation { message = "API unavailable: \(error)" }
    }
  }

  private func confirmBiometric() async {
    let current = prepareAttempt()
    let ok = await DeviceOwnerConfirmation().confirmBiometric()
    var started = false
    let decision = current.resumeAfterSca(biometricAccepted: ok, enteredPin: "") { paymentKey in
      started = true
      Task { await pay(idempotencyKey: paymentKey) }
    }
    if case .confirmed = decision, started {
      message = "Biometric confirmation accepted. Sending the same payment."
    } else if case .confirmed = decision {
      message = "This payment is already in progress."
    } else {
      message = "Biometric confirmation was not completed. The payment was not sent."
    }
    allowRetry = current.canRetry
  }

  private func confirmPin() {
    let current = prepareAttempt()
    var started = false
    let decision = current.resumeAfterSca(biometricAccepted: false, enteredPin: challengePin) { paymentKey in
      started = true
      Task { await pay(idempotencyKey: paymentKey) }
    }
    if case .confirmed = decision, started {
      message = "PIN confirmation accepted. Sending the same payment."
    } else if case .confirmed = decision {
      message = "This payment is already in progress."
    } else {
      message = "PIN confirmation did not match. The payment was not sent."
    }
    allowRetry = current.canRetry
  }

  private func continueAtBank() {
    let current = prepareAttempt()
    let url = current.startHandoff { BankLinkOpener.open($0) }
    allowRetry = current.canRetry
    if url != nil {
      message = "Continue at your bank. This payment is sent only after the signed return is valid."
    } else if current.isSubmitting {
      message = "This payment is already in progress."
    } else {
      message = "The bank page was not opened. The payment was not sent."
    }
  }

  private func deliverRehearsalReturn() {
    guard let url = attempt?.rehearsalReturnURL() else {
      message = "Open the bank handoff before delivering a return."
      return
    }
    Task { await completeReturn(url) }
  }

  private func completeReturn(_ url: URL) async {
    guard let current = attempt else {
      message = "No bank payment is waiting for this return. Nothing was sent."
      return
    }
    var started = false
    let outcome = current.resumeAfterReturn(url) { paymentKey in
      started = true
      Task { await pay(idempotencyKey: paymentKey) }
    }
    switch outcome {
    case .cleared:
      if !started { message = "This payment is already in progress." }
    case let .safeFailure(reason, _):
      allowRetry = current.canRetry
      message = returnFailureMessage(reason)
    case .ignored:
      break
    }
  }

  private func retrySamePayment() {
    guard let current = attempt else { message = "The payment was not sent again."; return }
    var started = false
    let accepted = current.submitIfCleared { paymentKey in
      started = true
      Task { await pay(idempotencyKey: paymentKey) }
    }
    if accepted && started {
      allowRetry = false
      message = "Retrying the same payment."
    } else {
      message = "The payment was not sent again."
    }
  }

  private func pay(idempotencyKey: String) async {
    guard let client, let current = attempt, !busy else { return }
    guard idempotencyKey == key, idempotencyKey == current.idempotencyKey else {
      current.releaseForRetry()
      allowRetry = current.canRetry
      message = "The payment was not sent again."
      return
    }
    busy = true
    generation += 1
    defer { busy = false }
    do {
      let (minor, error) = parseAmount(amount)
      guard let minor else {
        message = error ?? "Invalid amount"
        current.releaseForRetry()
        allowRetry = current.canRetry
        return
      }
      let result = try await client.submitPayment(
        recipientId: recipient,
        amountMinor: minor,
        method: method,
        note: reference,
        scenario: .success,
        idempotencyKey: idempotencyKey
      )
      if result.ok {
        current.markCompleted()
        state = result.state
        review = false
        amount = ""
        reference = ""
        challengePin = ""
        key = UUID().uuidString
        attempt = nil
        allowRetry = false
        message = "Demo payment completed. Other clients will refresh."
      } else {
        current.releaseForRetry()
        allowRetry = current.canRetry
        message = result.error ?? "Payment pending. Retry the same payment, not a new one."
      }
    } catch {
      current.releaseForRetry()
      allowRetry = current.canRetry
      message = "Outcome may be unknown: \(error). Retry preserves the payment key."
    }
  }
}
