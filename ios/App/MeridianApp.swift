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
  @State private var scaSession: ScaSession?
  @State private var passcode = ""
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
            if let scaSession, scaSession.showsPasscode {
              Text(ScaCopy.biometricPrompt).font(.callout)
              SecureField("In-app passcode", text: $passcode).textFieldStyle(.roundedBorder).disabled(busy)
              Text("Rehearsal passcode \(ScaCopy.rehearsalPasscode). It stays on this device and is not sent to the API.").font(.caption)
              Button("Verify passcode") { Task { await verifyPasscode() } }.buttonStyle(.borderedProminent).disabled(busy)
            } else if let token = scaSession?.resubmitToken {
              Button("Confirm payment") { Task { await retryVerified(token) } }.buttonStyle(.borderedProminent).disabled(busy)
            } else {
              Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy)
            }
            Button("Edit details") { review=false; key=UUID().uuidString; scaSession=nil; passcode="" }.disabled(busy)
          } else {
            Button("Review payment") { let (value,error)=parseAmount(amount); guard value != nil else {message=error ?? "Invalid amount";return}; guard reference.count<=200 else {message="Reference is too long"; return}; key=UUID().uuidString; scaSession=nil; passcode=""; review=true; message="Review before confirming. No real money moves." }.disabled(busy)
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
    generation += 1; state=nil; catalog=nil; review=false; key=UUID().uuidString; scaSession=nil; passcode=""
    do { client=try MeridianClient(baseURL:endpoint,sessionId:room); await refresh() } catch { message=String(describing:error) }
  }
  private func refresh() async {
    guard let client else {return}; let started=generation
    do { let next=try await client.getState(); let definitions=try await client.getCatalog(); if started==generation && !busy {state=next;catalog=definitions;message="Connected to shared Java API"} } catch { if started==generation {message="API unavailable: \(error)"} }
  }
  private func pay() async {
    guard let client, !busy else {return}; busy=true; generation += 1
    defer {busy=false}
    do {
      let (minor,error)=parseAmount(amount)
      guard let minor else {message=error ?? "Invalid amount";return}
      let draft=PaymentDraft(recipientId:recipient,amountMinor:minor,method:method,note:reference,scenario:.success,idempotencyKey:key)
      let call=try await client.submitPayment(recipientId:draft.recipientId,amountMinor:draft.amountMinor,method:draft.method,note:draft.note,scenario:draft.scenario,idempotencyKey:draft.idempotencyKey)
      await resolve(call, draft:draft, client:client, allowStepUp:true)
    } catch {message="Outcome may be unknown: \(error). Retry preserves the payment key."}
  }
  private func retryVerified(_ token: String) async {
    guard let client, let session=scaSession, !busy else {return}
    busy=true; generation += 1
    defer {busy=false}
    await resubmit(token:token, draft:session.draft, client:client)
  }
  private func verifyPasscode() async {
    guard let client, var session=scaSession, !busy else {return}
    session.submitPasscode(passcode)
    passcode=""
    scaSession=session
    guard case .readyToResubmit(let token)=session.phase else {message=ScaCopy.failureMessage; return}
    busy=true; generation += 1
    defer {busy=false}
    await resubmit(token:token, draft:session.draft, client:client)
  }
  private func resolve(_ call: PaymentCall, draft: PaymentDraft, client: MeridianClient, allowStepUp: Bool) async {
    switch ScaInterpreter.intercept(statusCode:call.statusCode, body:call.body) {
    case .notStepUp:
      if call.response.ok {
        state=call.response.state; review=false; amount=""; reference=""; key=UUID().uuidString; scaSession=nil; passcode=""
        message="Demo payment completed. Other clients will refresh."
      } else {
        message=call.response.error ?? "Payment pending. Retry the same payment, not a new one."
      }
    case .invalid, .expired:
      message=ScaCopy.failureMessage
    case .required(let challenge):
      guard allowStepUp else {message=ScaCopy.failureMessage; return}
      var session=ScaSession(draft:draft, challenge:challenge)
      let biometric=await LocalAuthenticationBiometric().authenticate(reason:ScaCopy.biometricPrompt)
      session.completeBiometric(biometric)
      scaSession=session
      if case .readyToResubmit(let token)=session.phase {
        await resubmit(token:token, draft:draft, client:client)
      } else {
        message=ScaCopy.biometricPrompt
      }
    }
  }
  private func resubmit(token: String, draft: PaymentDraft, client: MeridianClient) async {
    if scaSession?.challenge.isExpired() == true {message=ScaCopy.failureMessage; return}
    do {
      let call=try await client.submitPayment(recipientId:draft.recipientId,amountMinor:draft.amountMinor,method:draft.method,note:draft.note,scenario:draft.scenario,idempotencyKey:draft.idempotencyKey,scaChallengeToken:token)
      await resolve(call, draft:draft, client:client, allowStepUp:false)
    } catch {message="Outcome may be unknown: \(error). Retry preserves the payment key."}
  }
}
