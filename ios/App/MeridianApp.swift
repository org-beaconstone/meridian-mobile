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
  @State private var targetCurrency = accountCurrency
  @State private var key = UUID().uuidString
  @State private var review = false
  @State private var busy = false
  @State private var quoteBusy = false
  @State private var quote: FxQuoteLock?
  @State private var quoteSeconds = 0
  @State private var quoteError: String?
  @State private var message = "Connect to the Spring Boot API to start."
  @State private var generation = 0

  private var crossCurrency: Bool {
    isCrossCurrency(source: accountCurrency, target: targetCurrency)
  }

  private var confirmBlocked: Bool {
    if busy || quoteBusy { return true }
    guard crossCurrency else { return false }
    let (minor, _) = parseAmount(amount)
    return rateLockBlockReason(
      sourceCurrency: accountCurrency,
      targetCurrency: targetCurrency,
      amountMinor: minor ?? 0,
      quote: quote,
      now: Date()
    ) != nil
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("meridian").font(.largeTitle).fontWeight(.semibold)
        Text("Native SwiftUI · Fictional payment rehearsal").font(.caption)
        Group {
          TextField("API base URL", text: $endpoint)
          TextField("Shared rehearsal room", text: $room)
          Button("Connect") { Task { await connect() } }.disabled(busy || quoteBusy)
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
            Picker("Recipient", selection: $recipient) { ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) } }.disabled(review || busy || quoteBusy)
          }
          TextField("Amount (GBP)", text: $amount).textFieldStyle(.roundedBorder).disabled(review || busy || quoteBusy)
          TextField("Reference", text: $reference).textFieldStyle(.roundedBorder).disabled(review || busy || quoteBusy)
          Picker("Recipient currency", selection: $targetCurrency) {
            Text("GBP · no conversion").tag(accountCurrency)
            Text("EUR · convert from GBP").tag("EUR")
          }.disabled(review || busy || quoteBusy)
          // Intentionally hardcoded baseline: new providers still require a native release.
          Picker("Method", selection: $method) { Text("Debit card · Adyen").tag(PaymentMethod.card); Text("Bank payment · Worldpay").tag(PaymentMethod.bank) }.disabled(review || busy || quoteBusy)
          if review {
            reviewSheet
          } else {
            Button("Review payment") { Task { await beginReview() } }.disabled(busy || quoteBusy)
          }
          Text("Recent activity").font(.title2)
          ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in HStack { VStack(alignment:.leading){Text(transaction.name);Text(transaction.provider.rawValue).font(.caption).foregroundStyle(.secondary)};Spacer();Text(money(transaction.amount)) } }
          Text("September budgets").font(.title2)
          ForEach(state.budgets, id: \.category) { budget in HStack {Text(budget.category.rawValue);Spacer();Text(money(budget.limit))} }
        }
      }.padding(24).frame(maxWidth: 550)
    }.task {
      while !Task.isCancelled { try? await Task.sleep(for: .seconds(2)); if !busy && !quoteBusy { await refresh() } }
    }
    .task(id: quote.map { "\($0.quoteId)|\($0.expiresAt.timeIntervalSince1970)" } ?? "") {
      await trackQuote()
    }
  }

  @ViewBuilder private var reviewSheet: some View {
    Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
    if crossCurrency {
      VStack(alignment: .leading, spacing: 8) {
        if quoteBusy && quote == nil {
          Text("Locking the exchange rate…").font(.callout)
        }
        if let quote {
          Text("Locked rate \(quote.rate) · \(quote.sourceCurrency) to \(quote.targetCurrency)")
            .font(.headline)
          if let target = quote.targetAmountMinor {
            Text("Recipient gets \(formatMinor(target, currency: quote.targetCurrency))")
          }
          Text(quoteSeconds == 0 ? FxCopy.expired : "\(FxCopy.locked) · \(quoteSeconds)s")
            .font(.callout)
            .foregroundStyle(quoteSeconds == 0 ? .red : .secondary)
            .accessibilityIdentifier("rate-lock-seconds")
          GeometryReader { geo in
            ZStack(alignment: .leading) {
              Capsule().fill(Color.gray.opacity(0.25))
              Capsule()
                .fill(quoteSeconds == 0 ? Color.red : Color.accentColor)
                .frame(width: geo.size.width * CGFloat(quoteSeconds) / CGFloat(quoteLockSeconds))
            }
          }
          .frame(height: 8)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Rate lock countdown")
          .accessibilityValue("\(quoteSeconds) seconds remaining")
        }
        if let quoteError {
          Text(quoteError).foregroundStyle(.red).font(.callout)
        }
        if !quoteBusy && (quoteError != nil || (quote != nil && quoteSeconds == 0)) {
          Button(quote == nil ? FxCopy.retry : FxCopy.refresh) { Task { await refreshQuote() } }
            .disabled(busy || quoteBusy)
        }
      }
      .padding(12)
      .background(Color.gray.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(confirmBlocked)
    Button("Edit details") { leaveReview(rotateKey: true) }.disabled(busy || quoteBusy)
  }

  private func trackQuote() async {
    guard let active = quote else { return }
    while !Task.isCancelled {
      let left = active.remainingSeconds(at: Date())
      quoteSeconds = left
      if left == 0 { break }
      try? await Task.sleep(for: .seconds(1))
    }
  }

  private func leaveReview(rotateKey: Bool) {
    review = false
    quote = nil
    quoteError = nil
    quoteSeconds = 0
    if rotateKey { key = UUID().uuidString }
  }

  private func connect() async {
    guard room.range(of:"^[A-Za-z0-9_-]{3,64}$",options:.regularExpression) != nil else { message="Invalid room"; return }
    generation += 1
    state = nil
    catalog = nil
    leaveReview(rotateKey: true)
    do { client = try MeridianClient(baseURL: endpoint, sessionId: room); await refresh() } catch { message = String(describing: error) }
  }

  private func refresh() async {
    guard let client else { return }
    let started = generation
    do {
      let next = try await client.getState()
      let definitions = try await client.getCatalog()
      if started == generation && !busy && !quoteBusy {
        state = next
        catalog = definitions
        if !review { message = "Connected to shared Java API" }
      }
    } catch {
      if started == generation { message = "API unavailable: \(error)" }
    }
  }

  private func beginReview() async {
    let (value, error) = parseAmount(amount)
    guard let value else { message = error ?? "Invalid amount"; return }
    guard reference.count <= 200 else { message = "Reference is too long"; return }
    key = UUID().uuidString
    quote = nil
    quoteError = nil
    quoteSeconds = 0
    review = true
    if crossCurrency {
      await fetchQuote(amountMinor: value, replacing: true)
    } else {
      message = "Review before confirming. No real money moves."
    }
  }

  /// Re-fetches the rate in place. Amount, recipient, reference, method, currency and payment key stay.
  private func refreshQuote() async {
    let (value, error) = parseAmount(amount)
    guard let value else { message = error ?? "Invalid amount"; return }
    await fetchQuote(amountMinor: value, replacing: false)
  }

  private func fetchQuote(amountMinor: Int, replacing: Bool) async {
    guard let client else { return }
    quoteBusy = true
    defer { quoteBusy = false }
    do {
      let fetched = try await client.requestFxQuote(
        sourceCurrency: accountCurrency,
        targetCurrency: targetCurrency,
        amountMinor: amountMinor
      )
      let locked = lockQuote(
        fetched,
        sourceCurrency: accountCurrency,
        targetCurrency: targetCurrency,
        amountMinor: amountMinor,
        lockedAt: Date()
      )
      quote = locked
      quoteSeconds = locked.remainingSeconds(at: Date())
      quoteError = nil
      message = "Rate locked for \(quoteSeconds) seconds. No real money moves."
    } catch {
      if replacing { quote = nil }
      quoteError = FxCopy.unavailable
      message = FxCopy.unavailable
    }
  }

  private func pay() async {
    guard let client, !busy, !quoteBusy else { return }
    let (minor, error) = parseAmount(amount)
    guard let minor else { message = error ?? "Invalid amount"; return }
    if let blocked = rateLockBlockReason(
      sourceCurrency: accountCurrency,
      targetCurrency: targetCurrency,
      amountMinor: minor,
      quote: quote,
      now: Date()
    ) {
      message = blocked
      return
    }
    busy = true
    generation += 1
    defer { busy = false }
    let attachedQuoteId = crossCurrency ? quote?.quoteId : nil
    do {
      let result = try await client.submitPayment(
        recipientId: recipient,
        amountMinor: minor,
        method: method,
        note: reference,
        scenario: .success,
        idempotencyKey: key,
        quoteId: attachedQuoteId
      )
      if result.ok {
        state = result.state
        leaveReview(rotateKey: true)
        amount = ""
        reference = ""
        targetCurrency = accountCurrency
        message = "Demo payment completed. Other clients will refresh."
      } else {
        message = result.error ?? "Payment pending. Retry the same payment, not a new one."
      }
    } catch {
      message = "Outcome may be unknown: \(error). Retry preserves the payment key."
    }
  }
}
