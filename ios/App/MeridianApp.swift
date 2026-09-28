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
  @State private var sca: ScaChallengeHandler?
  @State private var passcodeEntry = ""
  @State private var enrolledPasscode = ""
  private let biometrics = DeviceBiometricAuthenticator()
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("meridian").font(.largeTitle).fontWeight(.semibold)
        Text("Native SwiftUI · Fictional payment rehearsal").font(.caption)
        Group {
          TextField("API base URL", text: $endpoint)
          TextField("Shared rehearsal room", text: $room)
          SecureField("Rehearsal passcode (stays on device)", text: $enrolledPasscode)
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
            Picker("Recipient", selection: $recipient) { ForEach(catalog.recipients, id: \.id) { Text($0.name).tag($0.id) } }.disabled(review || busy || sca != nil)
          }
          TextField("Amount (GBP)", text: $amount).textFieldStyle(.roundedBorder).disabled(review || busy || sca != nil)
          TextField("Reference", text: $reference).textFieldStyle(.roundedBorder).disabled(review || busy || sca != nil)
          // Intentionally hardcoded baseline: new providers still require a native release.
          Picker("Method", selection: $method) { Text("Debit card · Adyen").tag(PaymentMethod.card); Text("Bank payment · Worldpay").tag(PaymentMethod.bank) }.disabled(review || busy || sca != nil)
          if let handler = sca {
            scaCard(handler)
          } else if review {
            Text("Confirm \(amount) GBP to \(recipient)").font(.headline)
            Button("Confirm payment") { Task { await pay() } }.buttonStyle(.borderedProminent).disabled(busy)
            Button("Edit details") { review=false; key=UUID().uuidString; passcodeEntry="" }.disabled(busy)
          } else {
            Button("Review payment") { let (value,error)=parseAmount(amount); guard value != nil else {message=error ?? "Invalid amount";return}; guard reference.count<=200 else {message="Reference is too long"; return}; key=UUID().uuidString; review=true; message="Review before confirming. No real money moves." }.disabled(busy)
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

  private func scaCard(_ handler: ScaChallengeHandler) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(ScaStepUp.biometricPrompt).font(.headline)
      Text("Confirm \(amount) GBP to \(recipient)").font(.subheadline)
      switch handler.phase {
      case .biometric:
        ProgressView("Waiting for Face ID or Touch ID")
      case .passcode:
        Group {
          SecureField("Security passcode", text: $passcodeEntry).textFieldStyle(.roundedBorder)
          Button("Verify passcode") { Task { await submitPasscode() } }.buttonStyle(.borderedProminent).disabled(busy)
        }
      case .ready:
        Button("Retry settlement") { Task { await resubmit(handler) } }.buttonStyle(.borderedProminent).disabled(busy)
      case .failed(let text):
        Text(text)
      }
    }
  }

  private func connect() async {
    guard room.range(of:"^[A-Za-z0-9_-]{3,64}$",options:.regularExpression) != nil else { message="Invalid room"; return }
    generation += 1; state=nil; catalog=nil; review=false; sca=nil; passcodeEntry=""; key=UUID().uuidString
    do { client=try MeridianClient(baseURL:endpoint,sessionId:room); await refresh() } catch { message=String(describing:error) }
  }
  private func refresh() async {
    guard let client else {return}; let started=generation
    do {
      let next=try await client.getState(); let definitions=try await client.getCatalog()
      if started==generation && !busy {
        state=next; catalog=definitions
        if sca == nil && !review { message="Connected to shared Java API" }
      }
    } catch { if started==generation && sca == nil && !review {message="API unavailable: \(error)"} }
  }
  private func pay() async {
    guard let client, !busy, sca == nil else {return}
    let (minor,error)=parseAmount(amount)
    guard let minor else {message=error ?? "Invalid amount";return}
    let inflight=InFlightPayment(recipientId:recipient,amountMinor:minor,method:method,note:reference,scenario:.success,idempotencyKey:key)
    busy=true; generation += 1
    do {
      let submission=try await client.submitPayment(recipientId:inflight.recipientId,amountMinor:inflight.amountMinor,method:inflight.method,note:inflight.note,scenario:inflight.scenario,idempotencyKey:inflight.idempotencyKey)
      await apply(submission, inflight:inflight, steppedUp:false)
    } catch {
      message="Outcome may be unknown: \(error). Retry preserves the payment key."
      busy=false
    }
  }

  private func apply(_ submission: PaymentSubmission, inflight: InFlightPayment, steppedUp: Bool) async {
    if !steppedUp, let handler=ScaChallengeHandler.begin(statusCode:submission.statusCode, body:submission.body, payment:inflight) {
      switch handler.phase {
      case .failed(let text):
        // Recipient, amount, and the original idempotency key stay on the review screen.
        message=text
        sca=nil
        busy=false
      case .biometric:
        sca=handler
        busy=false
        await beginBiometric(handler)
      default:
        sca=handler
        busy=false
      }
      return
    }
    if steppedUp && submission.statusCode==202 && submission.body.code==ScaStepUp.code {
      message=ScaStepUp.failureMessage
      sca=nil
      busy=false
      return
    }
    if submission.body.ok {
      state=submission.body.state
      review=false
      amount=""
      reference=""
      key=UUID().uuidString
      sca=nil
      passcodeEntry=""
      message="Demo payment completed. Other clients will refresh."
    } else {
      message=submission.body.error ?? "Payment pending. Retry the same payment, not a new one."
    }
    busy=false
  }

  private func beginBiometric(_ handler: ScaChallengeHandler) async {
    let ok=await biometrics.authenticate(reason:ScaStepUp.biometricPrompt)
    let next=ok ? handler.biometricSucceeded() : handler.biometricUnavailableOrFailed()
    sca=next
    switch next.phase {
    case .ready:
      await resubmit(next)
    case .failed(let text):
      message=text
      sca=nil
    case .passcode:
      message="Use your in-app security passcode to continue this payment."
    default:
      break
    }
  }

  private func submitPasscode() async {
    guard let handler=sca else {return}
    let next=RehearsalPasscode.matches(entered:passcodeEntry, enrolled:enrolledPasscode)
      ? handler.passcodeVerified()
      : handler.passcodeRejected()
    passcodeEntry=""
    switch next.phase {
    case .ready:
      sca=next
      await resubmit(next)
    case .failed(let text):
      message=text
      sca=nil
    case .passcode(_, let text):
      sca=next
      message=text ?? ScaStepUp.failureMessage
    default:
      sca=next
    }
  }

  private func resubmit(_ handler: ScaChallengeHandler) async {
    guard let client, let retry=handler.resubmission(), !busy else {return}
    busy=true
    generation += 1
    do {
      let submission=try await client.submitPayment(
        recipientId:retry.recipientId,
        amountMinor:retry.amountMinor,
        method:retry.method,
        note:retry.note,
        scenario:retry.scenario,
        idempotencyKey:retry.idempotencyKey,
        scaChallengeToken:retry.scaChallengeToken
      )
      await apply(submission, inflight:handler.payment, steppedUp:true)
    } catch {
      message="Outcome may be unknown: \(error). Retry preserves the payment key."
      busy=false
    }
  }
}
