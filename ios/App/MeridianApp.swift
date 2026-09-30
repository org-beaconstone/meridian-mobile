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
  @State private var methodId = "adyen-card-gb"
  @State private var key = UUID().uuidString
  @State private var review = false
  @State private var busy = false
  @State private var message = "Connect to the Spring Boot API to start."
  @State private var generation = 0
  @State private var controls = CorridorControls()
  @State private var gateRevision = 0
  var body: some View {
    let _ = gateRevision
    let methods = controls.visibleMethods(accountId: room)
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
          if controls.flags.killSwitch {
            Text(paymentsPausedMessage).font(.callout)
          }
          if let catalog {
            Picker("Recipient", selection: $recipient) { ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) } }.disabled(review || busy || controls.flags.killSwitch)
          }
          TextField("Amount (GBP)", text: $amount).textFieldStyle(.roundedBorder).disabled(review || busy || controls.flags.killSwitch)
          TextField("Reference", text: $reference).textFieldStyle(.roundedBorder).disabled(review || busy || controls.flags.killSwitch)
          // Adyen card and Worldpay bank stay hardcoded. Flags only show or hide those rails.
          if methods.isEmpty {
            Text("No payment methods are available for this account.").font(.callout)
          } else {
            Picker("Method", selection: $methodId) {
              ForEach(methods) { method in Text(method.label).tag(method.id) }
            }.disabled(review || busy || controls.flags.killSwitch)
          }
          if !controls.flags.killSwitch && review {
            Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
            Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy)
            Button("Edit details") { review=false; key=UUID().uuidString }.disabled(busy)
          } else if !controls.flags.killSwitch {
            Button("Review payment") { let (value,error)=parseAmount(amount); guard value != nil else {message=error ?? "Invalid amount";return}; guard reference.count<=200 else {message="Reference is too long"; return}; key=UUID().uuidString; review=true; message="Review before confirming. No real money moves." }.disabled(busy || methods.isEmpty)
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
    generation += 1
    state=nil
    catalog=nil
    review=false
    key=UUID().uuidString
    controls.reset()
    methodId = "adyen-card-gb"
    gateRevision += 1
    do { client=try MeridianClient(baseURL:endpoint,sessionId:room); await refresh() } catch { message=String(describing:error) }
  }
  private func refresh() async {
    guard let client else {return}; let started=generation
    do {
      let next=try await client.getState()
      let definitions=try await client.getCatalog()
      if started==generation && !busy {
        state=next
        catalog=definitions
        await applyConfig(client)
        message = controls.flags.killSwitch ? paymentsPausedMessage : "Connected to shared Java API"
      }
    } catch { if started==generation {message="API unavailable: \(error)"} }
  }
  private func applyConfig(_ client: MeridianClient) async {
    do {
      let data = try await client.fetchConfig()
      guard controls.applyServerPayload(data) else { return }
      _ = controls.resolve(accountId: room)
      let visible = controls.visibleMethods(accountId: room)
      if !visible.contains(where: { $0.id == methodId }) {
        methodId = visible.first?.id ?? "adyen-card-gb"
      }
      gateRevision += 1
    } catch {
      // Keep the last applied flags. A missing /config leaves rehearsal defaults.
    }
  }
  private func pay() async {
    guard let client, !busy else {return}
    busy=true
    generation += 1
    defer {busy=false}
    await applyConfig(client)
    if controls.blocksNewIntent(idempotencyKey: key) {
      message = paymentsPausedMessage
      return
    }
    do {
      let (minor,error)=parseAmount(amount)
      guard let minor else {message=error ?? "Invalid amount";return}
      switch controls.createIntent(idempotencyKey: key, accountId: room, recipientId: recipient, amountMinor: minor, note: reference, methodId: methodId) {
      case .failure(let reason):
        message = reason.message
      case .success(let intent):
        let result=try await client.submitPayment(recipientId: intent.recipientId, amountMinor: intent.amountMinor, method: intent.method, note: intent.note, scenario:.success, idempotencyKey: intent.idempotencyKey)
        if result.ok {
          _ = controls.complete(intentId: intent.id, reference: result.transaction?.reference ?? intent.id)
          state=result.state
          review=false
          amount=""
          reference=""
          key=UUID().uuidString
          message="Demo payment completed. Other clients will refresh."
        } else if result.code == "PAYMENT_PENDING" {
          message=result.error ?? "Payment pending. Retry the same payment, not a new one."
        } else {
          controls.markDeclined(intentId: intent.id)
          message=result.error ?? "Payment pending. Retry the same payment, not a new one."
        }
      }
    } catch {message="Outcome may be unknown: \(error). Retry preserves the payment key."}
  }
}
