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
  @State private var attempt: PaymentIntentAttempt?
  @State private var outcome: PaymentIntentSubmission?
  @State private var consent = false
  @State private var review = false
  @State private var busy = false
  @State private var intentLocked = false
  @State private var now = Date()
  @State private var message = "Connect to the Spring Boot API to start."
  @State private var generation = 0

  private var quoteExpired: Bool {
    guard let attempt else { return false }
    return isQuoteExpired(quoteExpiresAt: attempt.quoteExpiresAt, now: now)
  }

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
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color(red:0.078,green:0.173,blue:0.208)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
          Text("Make a payment").font(.title2)
          if let catalog {
            Picker("Recipient", selection: $recipient) { ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) } }.disabled(review || busy)
          }
          TextField("Amount (GBP)", text: $amount).textFieldStyle(.roundedBorder).disabled(review || busy)
          TextField("Local reference", text: $reference).textFieldStyle(.roundedBorder).disabled(review || busy)
          // Intentionally hardcoded baseline: new providers still require a native release.
          Picker("Method", selection: $method) { Text("Debit card · Adyen").tag(PaymentMethod.card); Text("Bank payment · Worldpay").tag(PaymentMethod.bank) }.disabled(review || busy)
          if review, let attempt {
            VStack(alignment: .leading, spacing: 8) {
              reviewRow("Recipient", attempt.review.recipientName)
              if !attempt.review.recipientDetail.isEmpty {
                Text(attempt.review.recipientDetail).font(.caption).foregroundStyle(.secondary)
              }
              reviewRow("Amount", attempt.review.amountLabel)
              reviewRow("Fees", attempt.review.feeLabel)
              reviewRow("Method", attempt.review.methodLabel)
              reviewRow("Bank", attempt.review.bank)
              reviewRow("Quote expiry", attempt.review.expiryLabel)
              Text(attempt.review.consentSummary).font(.footnote)
              Toggle("I agree to this payment", isOn: $consent).disabled(busy || intentLocked)
              Text("Idempotency \(attempt.idempotencyKey)").font(.caption2).foregroundStyle(.secondary)
              Text("Payload hash \(attempt.payloadHash)").font(.caption2).foregroundStyle(.secondary)
            }
            if let outcome, outcome.terminal {
              Text(outcome.message).font(.headline)
              if let intentId = outcome.intentId { Text(intentId).font(.caption) }
              Button("New payment") { newPayment() }.disabled(busy)
            } else if quoteExpired && !intentLocked {
              Text("This quote has expired.").font(.callout)
              Button("Refresh quote") { refreshQuote() }.disabled(busy || intentLocked)
            } else {
              Button(intentLocked ? "Retry payment" : "Confirm payment") { Task { await pay() } }
                .buttonStyle(.borderedProminent)
                .disabled(busy || !consent)
            }
            if !intentLocked && outcome?.terminal != true {
              Button("Edit details") { editDetails() }.disabled(busy)
            }
          } else {
            Button("Review payment") { openReview(balance: state.balance) }.disabled(busy)
          }
          Text("Recent activity").font(.title2)
          ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in HStack { VStack(alignment:.leading){Text(transaction.name);Text(transaction.provider.rawValue).font(.caption).foregroundStyle(.secondary)};Spacer();Text(money(transaction.amount)) } }
          Text("September budgets").font(.title2)
          ForEach(state.budgets, id: \.category) { budget in HStack {Text(budget.category.rawValue);Spacer();Text(money(budget.limit))} }
        }
      }.padding(24).frame(maxWidth: 550)
    }.task {
      while !Task.isCancelled { try? await Task.sleep(for: .seconds(2)); if !busy { await refresh() } }
    }.task(id: review) {
      while review && !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        now = Date()
      }
    }
  }

  private func reviewRow(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title).foregroundStyle(.secondary)
      Spacer()
      Text(value).multilineTextAlignment(.trailing)
    }.font(.callout)
  }

  private func connect() async {
    guard room.range(of:"^[A-Za-z0-9_-]{3,64}$",options:.regularExpression) != nil else { message="Invalid room"; return }
    generation += 1
    state=nil
    catalog=nil
    review=false
    attempt=nil
    outcome=nil
    consent=false
    intentLocked=false
    do { client=try MeridianClient(baseURL:endpoint,sessionId:room); await refresh() } catch { message=String(describing:error) }
  }

  private func refresh() async {
    guard let client else {return}; let started=generation
    do { let next=try await client.getState(); let definitions=try await client.getCatalog(); if started==generation && !busy {state=next;catalog=definitions;message="Connected to shared Java API"} } catch { if started==generation {message="API unavailable: \(error)"} }
  }

  private func openReview(balance: Int) {
    let (minor, error) = parseAmount(amount)
    guard let minor else { message = error ?? "Invalid amount"; return }
    guard minor <= balance else { message = "Insufficient balance"; return }
    let person = catalog?.recipients.first { $0.id == recipient }
    do {
      attempt = try preparePaymentIntent(
        recipientId: recipient,
        recipientName: person?.name ?? "",
        recipientDetail: person?.detail ?? "",
        amountInput: amount,
        localReference: reference,
        method: method,
        now: Date()
      )
      consent = false
      outcome = nil
      intentLocked = false
      review = true
      now = Date()
      message = "Review before confirming. No real money moves."
    } catch {
      message = (error as? MeridianError)?.errorDescription ?? String(describing: error)
    }
  }

  private func editDetails() {
    guard !busy, !intentLocked else { return }
    review = false
    attempt = nil
    outcome = nil
    consent = false
  }

  private func refreshQuote() {
    guard !busy, !intentLocked, let person = catalog?.recipients.first(where: { $0.id == recipient }) else { return }
    do {
      attempt = try preparePaymentIntent(
        recipientId: recipient,
        recipientName: person.name,
        recipientDetail: person.detail,
        amountInput: amount,
        localReference: reference,
        method: method,
        now: Date()
      )
      consent = false
      outcome = nil
      now = Date()
      message = "Quote refreshed. Review the new expiry before confirming."
    } catch {
      message = (error as? MeridianError)?.errorDescription ?? String(describing: error)
    }
  }

  private func newPayment() {
    review = false
    attempt = nil
    outcome = nil
    consent = false
    intentLocked = false
    amount = ""
    reference = ""
    message = "Enter a new payment. The previous intent was not reused."
  }

  private func pay() async {
    guard let client, let attempt, !busy else { return }
    if outcome?.terminal == true { return }
    let alreadySent = await attempt.hasSubmitted()
    if !alreadySent {
      if !consent { message = "Consent is required"; return }
      if isQuoteExpired(quoteExpiresAt: attempt.quoteExpiresAt, now: now) {
        message = "Quote expired. Refresh the quote before confirming."
        return
      }
    }
    busy = true
    generation += 1
    defer { busy = false }
    do {
      let submission = try await attempt.submit(now: now, consentAccepted: true) { body, key, hash in
        try await client.submitPaymentIntent(canonicalBody: body, idempotencyKey: key, payloadHash: hash)
      }
      intentLocked = true
      outcome = submission
      message = submission.message
      if submission.disposition == .succeeded, let next = submission.state { state = next }
    } catch let error as MeridianError {
      intentLocked = await attempt.hasSubmitted()
      switch error {
      case .duplicateSubmission, .quoteExpired, .validationError:
        message = error.errorDescription ?? "Payment was not submitted."
      default:
        message = "Outcome may be unknown: \(error.localizedDescription). Retry keeps the same idempotency key and payload hash."
      }
    } catch {
      intentLocked = await attempt.hasSubmitted()
      message = "Outcome may be unknown: \(error). Retry keeps the same idempotency key and payload hash."
    }
  }
}
