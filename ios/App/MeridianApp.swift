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
  @State private var transactionId: String?
  @State private var review = false
  @State private var busy = false
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
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color(red:0.078,green:0.173,blue:0.208)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
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
            Button("Submit challenge retry") { Task { await challenge() } }.disabled(busy)
            Button("Edit details") { Task { await editPayment() } }.disabled(busy)
          } else {
            Button("Review payment") { Task { await reviewPayment() } }.disabled(busy)
          }
          Text("Recent activity").font(.title2)
          ForEach(Array(state.transactions.reversed().prefix(8)), id: \.id) { transaction in HStack { VStack(alignment:.leading){Text(transaction.name);Text(transaction.provider.rawValue).font(.caption).foregroundStyle(.secondary)};Spacer();Text(money(transaction.amount)) } }
          Text("September budgets").font(.title2)
          ForEach(state.budgets, id: \.category) { budget in HStack {Text(budget.category.rawValue);Spacer();Text(money(budget.limit))} }
        }
      }.padding(24).frame(maxWidth: 550)
    }.task {
      while !Task.isCancelled { try? await Task.sleep(for: .seconds(2)); if !busy { await refresh() } }
    }
  }
  private func connect() async {
    guard room.range(of:"^[A-Za-z0-9_-]{3,64}$",options:.regularExpression) != nil else { message="Invalid room"; return }
    generation += 1; state=nil; catalog=nil
    do {
      let directory = try idempotencyDirectory()
      let store = FileIdempotencyStore(fileURL: FileIdempotencyStore.fileURL(directory: directory, sessionId: room))
      let keys = try IdempotencyKeyManager(store: store)
      client = try MeridianClient(baseURL: endpoint, sessionId: room, idempotency: keys)
      let inflight = keys.activeRecords()
      if inflight.count == 1, let record = inflight.first, let fingerprint = record.fingerprint, let attempt = PaymentAttempt.fromFingerprint(fingerprint) {
        transactionId = record.transactionId
        recipient = attempt.recipientId
        amount = amountField(attempt.amountMinor)
        reference = attempt.note
        method = PaymentMethod(rawValue: attempt.method) ?? .card
        review = true
        message = "A payment is still in progress. Confirm retries the same idempotency key."
      } else {
        transactionId = nil
        review = false
      }
      await refresh()
    } catch { message=String(describing:error) }
  }
  private func reviewPayment() async {
    let (value, error) = parseAmount(amount)
    guard let value else { message = error ?? "Invalid amount"; return }
    guard reference.count <= 200 else { message = "Reference is too long"; return }
    guard let client else { message = "Connect before reviewing"; return }
    let id = UUID().uuidString
    do {
      try await client.preparePayment(transactionId: id, recipientId: recipient, amountMinor: value, method: method, note: reference)
      transactionId = id
      review = true
      message = "Review before confirming. No real money moves."
    } catch { message = String(describing: error) }
  }
  private func editPayment() async {
    if let client, let transactionId { try? await client.cancelTransaction(transactionId: transactionId) }
    transactionId = nil
    review = false
  }
  private func refresh() async {
    guard let client else {return}; let started=generation
    do { let next=try await client.getState(); let definitions=try await client.getCatalog(); if started==generation && !busy {state=next;catalog=definitions; if !review {message="Connected to shared Java API"}} } catch { if started==generation {message="API unavailable: \(error)"} }
  }
  private func pay() async {
    await send(challenge: false)
  }
  private func challenge() async {
    await send(challenge: true)
  }
  private func send(challenge: Bool) async {
    guard let client, let transactionId, !busy else {return}; busy=true; generation += 1
    defer {busy=false}
    do {
      let (minor,error)=parseAmount(amount)
      guard let minor else {message=error ?? "Invalid amount";return}
      let result: PaymentResponse
      if challenge {
        result = try await client.submitChallenge(transactionId: transactionId, recipientId: recipient, amountMinor: minor, method: method, note: reference)
      } else {
        result = try await client.submitPayment(recipientId: recipient, amountMinor: minor, method: method, note: reference, transactionId: transactionId)
      }
      if result.ok {state=result.state;review=false;amount="";reference="";self.transactionId=nil;message="Demo payment completed. Other clients will refresh."}
      else {message=result.error ?? "Payment pending. Retry the same payment, not a new one."}
    } catch MeridianError.idempotencyKeyExpired(let id) {
      try? await client.cancelTransaction(transactionId: id)
      self.transactionId = nil
      review = false
      message = "This payment key expired after 24 hours. Review the payment again before retrying."
    } catch {message="Outcome may be unknown: \(error). Retry preserves the payment key."}
  }
  private func idempotencyDirectory() throws -> URL {
    let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let directory = base.appendingPathComponent("Meridian", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
  private func amountField(_ pence: Int) -> String {
    let remainder = abs(pence % 100)
    return "\(pence / 100).\(String(format: "%02d", remainder))"
  }
}
