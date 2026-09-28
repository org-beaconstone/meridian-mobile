package com.atlassian.meridian

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

class MainActivity : AppCompatActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent { MaterialTheme(colors=lightColors(primary=Color(0xFF142C35),secondary=Color(0xFFD5B77A))) { MeridianScreen(this) } }
  }
}
@Composable fun MeridianScreen(activity: AppCompatActivity) {
  val scope=rememberCoroutineScope()
  var base by remember { mutableStateOf("http://10.0.2.2:8080/api/v1") }
  var room by remember { mutableStateOf("meridian-rehearsal") }
  var client by remember { mutableStateOf<MeridianClient?>(null) }
  var state by remember { mutableStateOf<BankState?>(null) }
  var catalog by remember { mutableStateOf<CatalogResponse?>(null) }
  var recipient by remember { mutableStateOf("northline-studio") }
  var amount by remember { mutableStateOf("") }
  var note by remember { mutableStateOf("") }
  var method by remember { mutableStateOf(PaymentMethod.card) }
  var review by remember { mutableStateOf(false) }
  var busy by remember { mutableStateOf(false) }
  var paymentKey by remember { mutableStateOf(UUID.randomUUID().toString()) }
  var message by remember { mutableStateOf("Fictional payment rehearsal. Connect to the Java API.") }
  var revision by remember { mutableStateOf(0) }
  var sca by remember { mutableStateOf<ScaChallengeHandler?>(null) }
  var passcodeEntry by remember { mutableStateOf("") }
  var enrolledPasscode by remember { mutableStateOf("") }
  LaunchedEffect(client) {
    val current=client
    while(current!=null) {
      val started=revision
      if(!busy) try {
        val fresh=current.getState(); val definitions=current.getCatalog()
        if(current===client && started==revision && !busy) {
          state=fresh; catalog=definitions
          if(sca==null && !review) message="Connected to shared Java API"
        }
      } catch(e:Exception) {if(current===client && sca==null && !review) message="API unavailable: ${e.message}"}
      delay(2000)
    }
  }
  fun inflight(minor: Int)=InFlightPayment(recipient, minor, method, note, Scenario.success, paymentKey)
  fun clearSuccess(next: BankState?) {
    state=next; review=false; amount=""; note=""; paymentKey=UUID.randomUUID().toString()
    sca=null; passcodeEntry=""; message="Demo payment complete"
  }
  fun finishOrdinary(submission: PaymentSubmission) {
    if(submission.body.ok) clearSuccess(submission.body.state)
    else message=submission.body.error?:"Awaiting confirmation. Retry the same payment."
  }
  fun applyResubmit(submission: PaymentSubmission) {
    if(submission.statusCode==202 && submission.body.code==ScaStepUp.CODE) {
      message=ScaStepUp.FAILURE_MESSAGE
      sca=null
    } else finishOrdinary(submission)
  }
  fun launchResubmit(handler: ScaChallengeHandler) {
    val active=client ?: return
    busy=true
    revision++
    scope.launch {
      try { resubmit(active, handler) { applyResubmit(it) } }
      catch(e:Exception) { message="Outcome may be unknown: ${e.message}. Retry keeps the same key." }
      finally { revision++; busy=false }
    }
  }
  Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
    Text("meridian",style=MaterialTheme.typography.h4)
    Text("Native Android · simulated GBP payments",style=MaterialTheme.typography.caption)
    OutlinedTextField(base,{base=it},label={Text("API base URL")},enabled=!busy)
    OutlinedTextField(room,{room=it},label={Text("Shared rehearsal room")},enabled=!busy)
    OutlinedTextField(
      enrolledPasscode,
      {enrolledPasscode=it.filter { ch -> ch.isDigit() }.take(6)},
      label={Text("Rehearsal passcode (stays on device)")},
      visualTransformation=PasswordVisualTransformation(),
      keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.NumberPassword),
      enabled=!busy,
    )
    Button(onClick={
      if(!Regex("[A-Za-z0-9_-]{3,64}").matches(room)){message="Invalid room"}
      else try {client=MeridianClient(base,room);state=null;catalog=null;review=false;sca=null;passcodeEntry="";revision++;paymentKey=UUID.randomUUID().toString()}catch(e:Exception){message=e.message?:"Invalid configuration"}
    },enabled=!busy && sca==null){Text("Connect")}
    Text(message)
    state?.let { current ->
      Card(backgroundColor=Color(0xFF142C35),contentColor=Color.White,modifier=Modifier.fillMaxWidth()) {
        Column(Modifier.padding(22.dp)){Text("Everyday account");Text(money(current.balance),style=MaterialTheme.typography.h3);Text("Room: $room")}
      }
      Text("Make a payment",style=MaterialTheme.typography.h6)
      catalog?.recipients?.forEach { person ->
        Row {RadioButton(selected=recipient==person.id,onClick={recipient=person.id},enabled=!review&&!busy&&sca==null);Text(person.name,Modifier.padding(top=12.dp))}
      }
      OutlinedTextField(amount,{amount=it},label={Text("Amount (GBP)")},enabled=!review&&!busy&&sca==null)
      OutlinedTextField(note,{note=it.take(200)},label={Text("Reference")},enabled=!review&&!busy&&sca==null)
      // Intentional two-provider native baseline; changing it requires an app release.
      Row {RadioButton(method==PaymentMethod.card,{method=PaymentMethod.card},enabled=!review&&!busy&&sca==null);Text("Debit card · Adyen",Modifier.padding(top=12.dp))}
      Row {RadioButton(method==PaymentMethod.bank,{method=PaymentMethod.bank},enabled=!review&&!busy&&sca==null);Text("Bank payment · Worldpay",Modifier.padding(top=12.dp))}
      val handler=sca
      if(handler!=null) {
        Text(ScaStepUp.BIOMETRIC_PROMPT, style=MaterialTheme.typography.subtitle1)
        Text("Confirm £$amount to $recipient")
        when(val phase=handler.phase) {
          is ScaPhase.Biometric -> CircularProgressIndicator()
          is ScaPhase.Passcode -> {
            OutlinedTextField(
              passcodeEntry,
              {passcodeEntry=it.filter { ch -> ch.isDigit() }.take(6)},
              label={Text("Security passcode")},
              visualTransformation=PasswordVisualTransformation(),
              keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.NumberPassword),
              enabled=!busy,
            )
            Button(onClick={
              val next=if(RehearsalPasscode.matches(passcodeEntry, enrolledPasscode)) handler.passcodeVerified(System.currentTimeMillis())
                else handler.passcodeRejected(System.currentTimeMillis())
              passcodeEntry=""
              when(val nextPhase=next.phase) {
                is ScaPhase.Ready -> {sca=next; launchResubmit(next)}
                is ScaPhase.Failed -> {message=nextPhase.message; sca=null}
                is ScaPhase.Passcode -> {sca=next; message=nextPhase.message?:ScaStepUp.FAILURE_MESSAGE}
                is ScaPhase.Biometric -> sca=next
              }
            },enabled=!busy){Text("Verify passcode")}
          }
          is ScaPhase.Ready -> Button(onClick={launchResubmit(handler)},enabled=!busy){Text("Retry settlement")}
          is ScaPhase.Failed -> Text(phase.message)
        }
      } else if(!review) Button(onClick={val parsed=parseAmount(amount);if(parsed.first==null)message=parsed.second?:"Invalid amount" else {review=true;paymentKey=UUID.randomUUID().toString()}},enabled=!busy){Text("Review payment")}
      else {
        Text("Confirm £$amount to $recipient")
        Button(onClick={
          val active=client; val minor=parseAmount(amount).first
          if(active!=null&&minor!=null&&!busy&&sca==null){
            busy=true; revision++
            val payment=inflight(minor)
            scope.launch{
              try {
                val result=active.submitPayment(recipientId=payment.recipientId,amountMinor=payment.amountMinor,method=payment.method,note=payment.note,idempotencyKey=payment.idempotencyKey)
                val opened=ScaChallengeHandler.begin(result.statusCode, result.body, payment, System.currentTimeMillis())
                if(opened==null) finishOrdinary(result)
                else when(val phase=opened.phase) {
                  is ScaPhase.Failed -> {message=phase.message; sca=null}
                  is ScaPhase.Biometric -> {
                    sca=opened
                    busy=false
                    val ok=ScaBiometrics.authenticate(activity)
                    val now=System.currentTimeMillis()
                    val next=if(ok) opened.biometricSucceeded(now) else opened.biometricUnavailableOrFailed(now)
                    sca=next
                    when(val nextPhase=next.phase) {
                      is ScaPhase.Ready -> {
                        busy=true
                        resubmit(active, next) { applyResubmit(it) }
                      }
                      is ScaPhase.Failed -> {message=nextPhase.message; sca=null}
                      is ScaPhase.Passcode -> message="Use your in-app security passcode to continue this payment."
                      is ScaPhase.Biometric -> Unit
                    }
                  }
                  else -> sca=opened
                }
              }catch(e:Exception){message="Outcome may be unknown: ${e.message}. Retry keeps the same key."}
              finally{revision++; busy=false}
            }
          }
        },enabled=!busy){Text(if(busy)"Confirming…" else "Confirm payment")}
        TextButton(onClick={review=false;paymentKey=UUID.randomUUID().toString();passcodeEntry=""},enabled=!busy){Text("Edit details")}
      }
      Text("Recent activity",style=MaterialTheme.typography.h6)
      current.transactions.reversed().take(8).forEach {transaction->Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")}
      Text("Budgets",style=MaterialTheme.typography.h6)
      current.budgets.forEach {budget->Text("${budget.category} · ${money(budget.limit)}")}
    }
  }
}

private suspend fun resubmit(
  client: MeridianClient?,
  handler: ScaChallengeHandler,
  apply: (PaymentSubmission) -> Unit,
) {
  val retry=handler.resubmission() ?: return
  val active=client ?: return
  val submission=active.submitPayment(
    recipientId=retry.recipientId,
    amountMinor=retry.amountMinor,
    method=retry.method,
    note=retry.note,
    scenario=retry.scenario,
    idempotencyKey=retry.idempotencyKey,
    scaChallengeToken=retry.scaChallengeToken,
  )
  apply(submission)
}
