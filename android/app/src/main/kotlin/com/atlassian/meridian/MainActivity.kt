package com.atlassian.meridian

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent { MaterialTheme(colors=lightColors(primary=Color(0xFF142C35),secondary=Color(0xFFD5B77A))) { MeridianScreen(this@MainActivity) } }
  }
}
@Composable fun MeridianScreen(activity: ComponentActivity) {
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
  var scaSession by remember { mutableStateOf<ScaSession?>(null) }
  var passcode by remember { mutableStateOf("") }
  val biometric = remember(activity) { AndroidBiometricAuthenticator(activity) }
  suspend fun applyResult(active: MeridianClient, draft: PaymentDraft, call: PaymentCall, allowStepUp: Boolean) {
    when (val intercept = ScaInterpreter.intercept(call.statusCode, call.bodyText)) {
      is ScaIntercept.NotStepUp -> {
        if (call.response.ok) {
          state = call.response.state
          review = false
          amount = ""
          note = ""
          paymentKey = UUID.randomUUID().toString()
          scaSession = null
          passcode = ""
          message = "Demo payment complete"
        } else message = call.response.error ?: "Awaiting confirmation. Retry the same payment."
      }
      is ScaIntercept.Invalid, is ScaIntercept.Expired -> message = ScaCopy.FAILURE_MESSAGE
      is ScaIntercept.Required -> {
        if (!allowStepUp) {
          message = ScaCopy.FAILURE_MESSAGE
          return
        }
        var session = ScaSession.start(draft, intercept.challenge)
        scaSession = session
        message = ScaCopy.BIOMETRIC_PROMPT
        session = session.afterBiometric(biometric.authenticate(ScaCopy.BIOMETRIC_PROMPT))
        scaSession = session
        val token = session.resubmitToken ?: return
        if (session.challenge.isExpired()) {
          message = ScaCopy.FAILURE_MESSAGE
          return
        }
        val again = active.submitPayment(
          recipientId = draft.recipientId,
          amountMinor = draft.amountMinor,
          method = draft.method,
          note = draft.note,
          scenario = draft.scenario,
          idempotencyKey = draft.idempotencyKey,
          scaChallengeToken = token,
        )
        scaSession = null
        applyResult(active, draft, again, false)
      }
    }
  }
  suspend fun resubmit(active: MeridianClient, draft: PaymentDraft, token: String) {
    if (scaSession?.challenge?.isExpired() == true) {
      message = ScaCopy.FAILURE_MESSAGE
      return
    }
    val again = active.submitPayment(
      recipientId = draft.recipientId,
      amountMinor = draft.amountMinor,
      method = draft.method,
      note = draft.note,
      scenario = draft.scenario,
      idempotencyKey = draft.idempotencyKey,
      scaChallengeToken = token,
    )
    applyResult(active, draft, again, false)
  }
  LaunchedEffect(client) {
    val current=client
    while(current!=null) {
      val started=revision
      if(!busy) try {
        val fresh=current.getState(); val definitions=current.getCatalog()
        if(current===client && started==revision && !busy) {state=fresh;catalog=definitions;message="Connected to shared Java API"}
      } catch(e:Exception) {if(current===client)message="API unavailable: ${e.message}"}
      delay(2000)
    }
  }
  Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
    Text("meridian",style=MaterialTheme.typography.h4)
    Text("Native Android · simulated GBP payments",style=MaterialTheme.typography.caption)
    OutlinedTextField(base,{base=it},label={Text("API base URL")},enabled=!busy)
    OutlinedTextField(room,{room=it},label={Text("Shared rehearsal room")},enabled=!busy)
    Button(onClick={
      if(!Regex("[A-Za-z0-9_-]{3,64}").matches(room)){message="Invalid room"}
      else try {client=MeridianClient(base,room);state=null;catalog=null;review=false;scaSession=null;passcode="";revision++;paymentKey=UUID.randomUUID().toString()}catch(e:Exception){message=e.message?:"Invalid configuration"}
    },enabled=!busy){Text("Connect")}
    Text(message)
    state?.let { current ->
      Card(backgroundColor=Color(0xFF142C35),contentColor=Color.White,modifier=Modifier.fillMaxWidth()) {
        Column(Modifier.padding(22.dp)){Text("Everyday account");Text(money(current.balance),style=MaterialTheme.typography.h3);Text("Room: $room")}
      }
      Text("Make a payment",style=MaterialTheme.typography.h6)
      catalog?.recipients?.forEach { person ->
        Row {RadioButton(selected=recipient==person.id,onClick={recipient=person.id},enabled=!review&&!busy);Text(person.name,Modifier.padding(top=12.dp))}
      }
      OutlinedTextField(amount,{amount=it},label={Text("Amount (GBP)")},enabled=!review&&!busy)
      OutlinedTextField(note,{note=it.take(200)},label={Text("Reference")},enabled=!review&&!busy)
      // Intentional two-provider native baseline; changing it requires an app release.
      Row {RadioButton(method==PaymentMethod.card,{method=PaymentMethod.card},enabled=!review&&!busy);Text("Debit card · Adyen",Modifier.padding(top=12.dp))}
      Row {RadioButton(method==PaymentMethod.bank,{method=PaymentMethod.bank},enabled=!review&&!busy);Text("Bank payment · Worldpay",Modifier.padding(top=12.dp))}
      if(!review) Button(onClick={val parsed=parseAmount(amount);if(parsed.first==null)message=parsed.second?:"Invalid amount" else {review=true;scaSession=null;passcode="";paymentKey=UUID.randomUUID().toString()}},enabled=!busy){Text("Review payment")}
      else {
        Text("Confirm £$amount to $recipient")
        val session=scaSession
        if(session!=null && session.showsPasscode) {
          Text(ScaCopy.BIOMETRIC_PROMPT)
          Text("Rehearsal passcode ${ScaCopy.REHEARSAL_PASSCODE}. It stays on this device and is not sent to the API.")
          OutlinedTextField(passcode,{passcode=it},label={Text("In-app passcode")},enabled=!busy)
          Button(onClick={
            val active=client
            val current=scaSession
            if(active!=null && current!=null && !busy) {
              val next=current.afterPasscode(passcode)
              passcode=""
              scaSession=next
              val token=next.resubmitToken
              if(token==null) message=ScaCopy.FAILURE_MESSAGE
              else {busy=true;revision++;scope.launch {
                try {resubmit(active,next.draft,token)}
                catch(e:Exception){message="Outcome may be unknown: ${e.message}. Retry keeps the same key."}
                finally {revision++;busy=false}
              }}
            }
          },enabled=!busy){Text(if(busy)"Confirming…" else "Verify passcode")}
        } else Button(onClick={val active=client;val minor=parseAmount(amount).first;val ready=scaSession;val token=ready?.resubmitToken;if(active!=null&&!busy&&token!=null&&ready!=null){busy=true;revision++;scope.launch{
          try {resubmit(active,ready.draft,token)}
          catch(e:Exception){message="Outcome may be unknown: ${e.message}. Retry keeps the same key."}
          finally{revision++;busy=false}
        }} else if(active!=null&&minor!=null&&!busy){busy=true;revision++;scope.launch{
          try {
            val draft=PaymentDraft(recipient,minor,method,note,Scenario.success,paymentKey)
            val result=active.submitPayment(recipientId=draft.recipientId,amountMinor=draft.amountMinor,method=draft.method,note=draft.note,idempotencyKey=draft.idempotencyKey)
            applyResult(active,draft,result,true)
          }catch(e:Exception){message="Outcome may be unknown: ${e.message}. Retry keeps the same key."}finally{revision++;busy=false}
        }}},enabled=!busy){Text(if(busy)"Confirming…" else "Confirm payment")}
        TextButton(onClick={review=false;scaSession=null;passcode="";paymentKey=UUID.randomUUID().toString()},enabled=!busy){Text("Edit details")}
      }
      Text("Recent activity",style=MaterialTheme.typography.h6)
      current.transactions.reversed().take(8).forEach {transaction->Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")}
      Text("Budgets",style=MaterialTheme.typography.h6)
      current.budgets.forEach {budget->Text("${budget.category} · ${money(budget.limit)}")}
    }
  }
}
