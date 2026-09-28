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
  @State private var iban = ""
  @State private var method: PaymentMethod = .card
  @State private var currency: PayCurrency = .gbp
  @State private var key = makeIdempotencyKey()
  @State private var quote: FxQuoteLock?
  @State private var quoteSeconds = 0
  @State private var review = false
  @State private var busy = false
  @State private var quoteBusy = false
  @State private var message = "Connect to the Spring Boot API to start."
  @State private var generation = 0

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
            Picker("Recipient", selection: $recipient) {
              ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) }
            }.disabled(review || busy)
          }
          TextField("Amount (GBP)", text: $amount).textFieldStyle(.roundedBorder).disabled(review || busy)
          if currency == .eur {
            Text("GBP amount to convert. The account is debited in pence.").font(.caption)
          }
          Picker("Currency", selection: $currency) {
            Text("GBP · no conversion").tag(PayCurrency.gbp)
            Text("EUR · convert from GBP").tag(PayCurrency.eur)
          }.disabled(review || busy)
          if ibanRequired(currency: currency, method: method) {
            TextField("Recipient IBAN", text: $iban).textFieldStyle(.roundedBorder).disabled(review || busy)
          }
          TextField("Reference", text: $reference).textFieldStyle(.roundedBorder).disabled(review || busy)
          // Intentionally hardcoded baseline: new providers still require a native release.
          Picker("Method", selection: $method) {
            Text("Debit card · Adyen").tag(PaymentMethod.card)
            Text("Bank payment · Worldpay").tag(PaymentMethod.bank)
          }.disabled(review || busy)
          if review {
            reviewCard
          } else {
            Button("Review payment") { Task { await beginReview() } }.disabled(busy || quoteBusy)
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
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        if !busy { await refresh() }
      }
    }
    .task(id: quote?.quoteId) { await trackQuote() }
  }

  @ViewBuilder private var reviewCard: some View {
    let minor = parseAmount(amount).0 ?? 0
    let blocked = submissionBlockReason(
      currency: currency,
      method: method,
      iban: iban,
      quote: quote,
      amountMinor: minor,
      now: Date()
    )
    VStack(alignment: .leading, spacing: 8) {
      Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
      if currency == .eur, let quote {
        Text("Recipient gets \(moneyEur(quote.targetAmountMinor)) at \(quote.rate)")
        Text(quoteSeconds == 0
          ? quoteExpiredMessage
          : "Rate locked for \(quoteSeconds)s")
          .font(.callout)
          .foregroundStyle(quoteSeconds == 0 ? .red : .secondary)
        Button("Refresh conversion rate") { Task { await refreshQuote() } }.disabled(busy || quoteBusy)
      }
      if let blocked, blocked != quoteExpiredMessage || quote == nil {
        Text(blocked).font(.callout).foregroundStyle(.red)
      }
      Button("Confirm payment") { Task { await pay() } }
        .buttonStyle(.borderedProminent)
        .disabled(busy || quoteBusy || blocked != nil)
      Button("Edit details") {
        review = false
        quote = nil
        key = makeIdempotencyKey()
      }.disabled(busy || quoteBusy)
    }
  }

  private func trackQuote() async {
    guard let active = quote else { return }
    while !Task.isCancelled {
      let left = active.remainingSeconds(at: Date())
      quoteSeconds = left
      if left == 0 { break }
      try? await Task.sleep(for: .milliseconds(250))
    }
  }

  private func connect() async {
    guard room.range(of: "^[A-Za-z0-9_-]{3,64}$", options: .regularExpression) != nil else {
      message = "Invalid room"
      return
    }
    generation += 1
    state = nil
    catalog = nil
    review = false
    quote = nil
    key = makeIdempotencyKey()
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

  private func beginReview() async {
    let (value, error) = parseAmount(amount)
    guard let value else {
      message = error ?? "Invalid amount"
      return
    }
    guard reference.count <= 200 else {
      message = "Reference is too long"
      return
    }
    if let blocked = ibanBlockReason(currency: currency, method: method, iban: iban) {
      message = blocked
      return
    }
    if currency == .eur {
      guard let client else { return }
      quoteBusy = true
      defer { quoteBusy = false }
      do {
        let fetched = try await client.requestFxQuote(amountMinor: value)
        let locked = lockQuote(fetched, lockedAt: Date())
        quote = locked
        quoteSeconds = locked.remainingSeconds(at: Date())
        key = makeIdempotencyKey()
        review = true
        message = "Rate locked for 60 seconds. No real money moves."
      } catch {
        message = "Could not lock a conversion rate: \(error)"
      }
      return
    }
    quote = nil
    key = makeIdempotencyKey()
    review = true
    message = "Review before confirming. No real money moves."
  }

  private func refreshQuote() async {
    guard let client, !busy else { return }
    let (value, error) = parseAmount(amount)
    guard let value else {
      message = error ?? "Invalid amount"
      return
    }
    quoteBusy = true
    defer { quoteBusy = false }
    do {
      let fetched = try await client.requestFxQuote(amountMinor: value)
      let locked = lockQuote(fetched, lockedAt: Date())
      quote = locked
      quoteSeconds = locked.remainingSeconds(at: Date())
      message = "Conversion rate refreshed. The payment key is unchanged."
    } catch {
      message = "Could not refresh the conversion rate: \(error)"
    }
  }

  private func pay() async {
    guard let client, !busy else { return }
    let (minor, error) = parseAmount(amount)
    guard let minor else {
      message = error ?? "Invalid amount"
      return
    }
    if let blocked = submissionBlockReason(
      currency: currency,
      method: method,
      iban: iban,
      quote: quote,
      amountMinor: minor,
      now: Date()
    ) {
      message = blocked
      return
    }
    busy = true
    generation += 1
    defer { busy = false }
    do {
      let result = try await submitPaymentWithRetry(idempotencyKey: key, method: method) { attemptKey, attemptMethod in
        try await client.submitPayment(
          recipientId: recipient,
          amountMinor: minor,
          method: attemptMethod,
          note: reference,
          scenario: .success,
          idempotencyKey: attemptKey
        )
      }
      if result.ok {
        state = result.state
        review = false
        amount = ""
        reference = ""
        iban = ""
        quote = nil
        key = makeIdempotencyKey()
        message = "Demo payment completed. Other clients will refresh."
      } else {
        message = result.error ?? "Payment pending. Retry the same payment, not a new one."
      }
    } catch {
      message = "Outcome may be unknown: \(error). Retry preserves the payment key."
    }
  }
}
