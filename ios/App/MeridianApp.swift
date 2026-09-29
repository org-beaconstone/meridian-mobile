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
  @State private var sca: ScaSession?
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
            if let session = sca, session.showsPasscode {
              Text(ScaCopy.biometricPrompt).font(.callout)
              Text("In-app passcode. It stays on this device and is not sent to the API.").font(.caption)
              SecureField("Security passcode", text: $passcode).textFieldStyle(.roundedBorder).disabled(busy)
              Button("Verify passcode") { Task { await verifyPasscode() } }.buttonStyle(.borderedProminent).disabled(busy)
            } else {
              Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy)
            }
            Button("Edit details") { review = false; sca = nil; passcode = ""; key = UUID().uuidString }.disabled(busy)
          } else {
            Button("Review payment") { let (value,error)=parseAmount(amount); guard value != nil else {message=error ?? "Invalid amount";return}; guard reference.count<=200 else {message="Reference is too long"; return}; key=UUID().uuidString; sca=nil; passcode=""; review=true; message="Review before confirming. No real money moves." }.disabled(busy)
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
    generation += 1; state=nil; catalog=nil; review=false; sca=nil; passcode=""; key=UUID().uuidString
    do { client=try MeridianClient(baseURL:endpoint,sessionId:room); await refresh() } catch { message=String(describing:error) }
  }
  private func refresh() async {
    guard let client else {return}; let started=generation
    do {
      let next=try await client.getState(); let definitions=try await client.getCatalog()
      if started==generation && !busy {
        state=next; catalog=definitions
        if sca == nil && message != ScaCopy.failureMessage { message="Connected to shared Java API" }
      }
    } catch { if started==generation {message="API unavailable: \(error)"} }
  }
  private func pay() async {
    guard let client, !busy else {return}
    busy=true
    generation += 1
    defer { busy=false }
    do {
      let (minor,error)=parseAmount(amount)
      guard let minor else { message=error ?? "Invalid amount"; return }
      let draft=sca?.draft ?? PaymentDraft(recipientId:recipient,amountMinor:minor,method:method,note:reference,scenario:.success,idempotencyKey:key)
      let token=sca?.resubmitToken
      let call=try await client.submitPayment(recipientId:draft.recipientId,amountMinor:draft.amountMinor,method:draft.method,note:draft.note,scenario:draft.scenario,idempotencyKey:draft.idempotencyKey,scaChallengeToken:token)
      await apply(call, draft:draft, client:client, allowStepUp:token == nil)
    } catch {
      message="Outcome may be unknown: \(error). Retry preserves the payment key."
    }
  }
  private func verifyPasscode() async {
    guard let client, var session=sca, !busy else {return}
    busy=true
    generation += 1
    defer { busy=false }
    session=session.afterPasscode(passcode)
    passcode=""
    sca=session
    guard let token=session.resubmitToken else {
      message=session.message ?? ScaCopy.failureMessage
      return
    }
    do {
      let call=try await client.submitPayment(recipientId:session.draft.recipientId,amountMinor:session.draft.amountMinor,method:session.draft.method,note:session.draft.note,scenario:session.draft.scenario,idempotencyKey:session.draft.idempotencyKey,scaChallengeToken:token)
      await apply(call, draft:session.draft, client:client, allowStepUp:false)
    } catch {
      message="Outcome may be unknown: \(error). Retry preserves the payment key."
    }
  }
  private func apply(_ call: PaymentCall, draft: PaymentDraft, client: MeridianClient, allowStepUp: Bool) async {
    switch ScaInterpreter.intercept(statusCode: call.statusCode, body: call.body) {
    case .notStepUp:
      if call.ok {
        state=call.state
        review=false
        amount=""
        reference=""
        key=UUID().uuidString
        sca=nil
        passcode=""
        message="Demo payment completed. Other clients will refresh."
      } else {
        message=call.error ?? "Payment pending. Retry the same payment, not a new one."
      }
    case .invalid, .expired:
      message=ScaCopy.failureMessage
    case let .required(challenge):
      if !allowStepUp {
        message=ScaCopy.failureMessage
        return
      }
      var session=ScaSession(draft:draft, challenge:challenge)
      sca=session
      message=ScaCopy.biometricPrompt
      let status=await LocalAuthenticationBiometric().authenticate(reason: ScaCopy.biometricPrompt)
      session=session.afterBiometric(status)
      sca=session
      guard let token=session.resubmitToken else {
        if let notice=session.message { message=notice }
        return
      }
      do {
        let again=try await client.submitPayment(recipientId:draft.recipientId,amountMinor:draft.amountMinor,method:draft.method,note:draft.note,scenario:draft.scenario,idempotencyKey:draft.idempotencyKey,scaChallengeToken:token)
        sca=nil
        await apply(again, draft:draft, client:client, allowStepUp:false)
      } catch {
        message="Outcome may be unknown: \(error). Retry preserves the payment key."
      }
    }
  }
}
