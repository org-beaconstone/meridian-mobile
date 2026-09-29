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
  @State private var scaNotice: String?
  @State private var sca: ScaSession?
  @State private var passcode = ""
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
        if let scaNotice {
          Text(scaNotice).font(.callout).foregroundStyle(Color(red: 0.55, green: 0.15, blue: 0.09))
        }
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
            if sca != nil {
              Text(ScaCopy.biometricPrompt).font(.headline)
              Text("Face ID or Touch ID runs on this device. The rehearsal passcode stays on device.").font(.caption).foregroundStyle(.secondary)
            }
            if sca?.showsPasscode == true {
              SecureField("Security passcode", text: $passcode)
                .textFieldStyle(.roundedBorder)
              Text("Rehearsal passcode \(ScaCopy.rehearsalPasscode). Checked on this device and not sent to the API.").font(.caption)
              Button("Verify passcode") { Task { await verifyPasscode() } }.buttonStyle(.borderedProminent).disabled(busy)
            } else if sca?.phase == .ready {
              Button("Retry settlement") { Task { await retrySettlement() } }.buttonStyle(.borderedProminent).disabled(busy)
            } else if sca == nil {
              Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy)
            } else {
              Text("Waiting for Face ID or Touch ID…").font(.caption)
            }
            Button("Edit details") { review=false; sca=nil; scaNotice=nil; passcode=""; key=UUID().uuidString }.disabled(busy)
          } else {
            Button("Review payment") { let (value,error)=parseAmount(amount); guard value != nil else {message=error ?? "Invalid amount";return}; guard reference.count<=200 else {message="Reference is too long"; return}; key=UUID().uuidString; sca=nil; scaNotice=nil; review=true; message="Review before confirming. No real money moves." }.disabled(busy)
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
    generation += 1; state=nil; catalog=nil; review=false; sca=nil; scaNotice=nil; passcode=""; key=UUID().uuidString
    do { client=try MeridianClient(baseURL:endpoint,sessionId:room); await refresh() } catch { message=String(describing:error) }
  }
  private func refresh() async {
    guard let client else {return}; let started=generation
    do {
      let next=try await client.getState(); let definitions=try await client.getCatalog()
      if started==generation && !busy {
        state=next; catalog=definitions
        if sca == nil && scaNotice == nil { message="Connected to shared Java API" }
      }
    } catch { if started==generation {message="API unavailable: \(error)"} }
  }
  private func pay() async {
    guard let client, !busy, sca == nil else {return}
    let (minor,error)=parseAmount(amount)
    guard let minor else {message=error ?? "Invalid amount";return}
    let draft=PaymentDraft(recipientId:recipient,amountMinor:minor,method:method,note:reference,scenario:.success,idempotencyKey:key)
    busy=true; generation += 1
    defer { busy=false }
    do {
      let result=try await client.submitPayment(recipientId:draft.recipientId,amountMinor:draft.amountMinor,method:draft.method,note:draft.note,scenario:draft.scenario,idempotencyKey:draft.idempotencyKey)
      switch ScaInterpreter.intercept(statusCode: result.statusCode, body: result.body) {
      case .notStepUp:
        applyOutcome(result, draft: draft)
      case .required(let challenge):
        var session=ScaSession(draft:draft,challenge:challenge)
        sca=session
        let status=await DeviceBiometric().authenticate(reason:ScaCopy.biometricPrompt)
        session.completeBiometric(status)
        await continueChallenge(session, client: client)
      case .expired, .invalid:
        sca=nil
        passcode=""
        scaNotice=ScaCopy.failureMessage
      }
    } catch {
      scaNotice=nil
      message="Outcome may be unknown: \(error). Retry preserves the payment key."
    }
  }
  private func verifyPasscode() async {
    guard let client, var session=sca, !busy else {return}
    busy=true; generation += 1
    defer { busy=false }
    session.submitPasscode(passcode)
    passcode=""
    await continueChallenge(session, client: client)
  }
  private func retrySettlement() async {
    guard let client, let session=sca, session.phase == .ready, !busy else {return}
    busy=true; generation += 1
    defer { busy=false }
    await continueChallenge(session, client: client)
  }
  private func continueChallenge(_ session: ScaSession, client: MeridianClient) async {
    guard let retry = session.resubmit() else {
      sca=session
      scaNotice=session.message
      return
    }
    sca=session
    do {
      let result=try await client.submitPayment(recipientId:retry.recipientId,amountMinor:retry.amountMinor,method:retry.method,note:retry.note,scenario:retry.scenario,idempotencyKey:retry.idempotencyKey,scaChallengeToken:retry.scaChallengeToken)
      if case .notStepUp = ScaInterpreter.intercept(statusCode: result.statusCode, body: result.body) {
        sca=nil
        passcode=""
        applyOutcome(result, draft: session.draft)
      } else {
        sca=nil
        passcode=""
        scaNotice=ScaCopy.failureMessage
      }
    } catch {
      sca=session
      scaNotice=nil
      message="Outcome may be unknown: \(error). Retry preserves the payment key."
    }
  }
  private func applyOutcome(_ result: PaymentCall, draft: PaymentDraft) {
    if result.ok {
      state=result.state
      review=false
      sca=nil
      scaNotice=nil
      passcode=""
      amount=""
      reference=""
      key=UUID().uuidString
      message="Demo payment completed. Other clients will refresh."
    } else {
      scaNotice=nil
      message=result.error ?? "Payment pending. Retry the same payment, not a new one."
      _=draft
    }
  }
}
