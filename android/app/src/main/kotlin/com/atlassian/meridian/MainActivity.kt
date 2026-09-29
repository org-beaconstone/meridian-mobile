package com.atlassian.meridian

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.appcompat.app.AppCompatActivity
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

class MainActivity : AppCompatActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent { MaterialTheme(colors=lightColors(primary=Color(0xFF142C35),secondary=Color(0xFFD5B77A))) { MeridianScreen() } }
  }
}
@Composable fun MeridianScreen() {
  val scope=rememberCoroutineScope()
  val activity=LocalContext.current as AppCompatActivity
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
  var scaNotice by remember { mutableStateOf<String?>(null) }
  var sca by remember { mutableStateOf<ScaSession?>(null) }
  var passcode by remember { mutableStateOf("") }
  var revision by remember { mutableStateOf(0) }
  LaunchedEffect(client) {
    val current=client
    while(current!=null) {
      val started=revision
      if(!busy) try {
        val fresh=current.getState(); val definitions=current.getCatalog()
        if(current===client && started==revision && !busy) {
          state=fresh
          catalog=definitions
          if (sca == null && scaNotice == null) message="Connected to shared Java API"
        }
      } catch(e:Exception) {if(current===client)message="API unavailable: ${e.message}"}
      delay(2000)
    }
  }
  fun clearChallenge() {
    sca=null
    scaNotice=null
    passcode=""
  }
  fun applyOutcome(result: PaymentCall) {
    if(result.ok){
      state=result.state
      review=false
      clearChallenge()
      amount=""
      note=""
      paymentKey=UUID.randomUUID().toString()
      message="Demo payment complete"
    } else {
      scaNotice=null
      message=result.error?:"Awaiting confirmation. Retry the same payment."
    }
  }
  suspend fun settle(active: MeridianClient, session: ScaSession) {
    val retry=session.resubmit()
    if(retry==null){
      sca=session
      scaNotice=session.message
      return
    }
    sca=session
    val result=active.submitPayment(
      recipientId=retry.recipientId,
      amountMinor=retry.amountMinor,
      method=retry.method,
      note=retry.note,
      scenario=retry.scenario,
      idempotencyKey=retry.idempotencyKey,
      scaChallengeToken=retry.scaChallengeToken,
    )
    val again=ScaInterpreter.interpret(result.statusCode, result.body)
    if(again is ScaIntercept.NotStepUp){
      sca=null
      passcode=""
      applyOutcome(result)
    } else {
      clearChallenge()
      scaNotice=ScaCopy.FAILURE_MESSAGE
    }
  }
  Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
    Text("meridian",style=MaterialTheme.typography.h4)
    Text("Native Android · simulated GBP payments",style=MaterialTheme.typography.caption)
    OutlinedTextField(base,{base=it},label={Text("API base URL")},enabled=!busy)
    OutlinedTextField(room,{room=it},label={Text("Shared rehearsal room")},enabled=!busy)
    Button(onClick={
      if(!Regex("[A-Za-z0-9_-]{3,64}").matches(room)){message="Invalid room"}
      else try {
        client=MeridianClient(base,room)
        state=null
        catalog=null
        review=false
        clearChallenge()
        revision++
        paymentKey=UUID.randomUUID().toString()
      }catch(e:Exception){message=e.message?:"Invalid configuration"}
    },enabled=!busy){Text("Connect")}
    scaNotice?.let { Text(it, color=Color(0xFF8D2517)) }
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
      if(!review) Button(onClick={val parsed=parseAmount(amount);if(parsed.first==null)message=parsed.second?:"Invalid amount" else {review=true;clearChallenge();paymentKey=UUID.randomUUID().toString()}},enabled=!busy){Text("Review payment")}
      else {
        Text("Confirm £$amount to $recipient")
        val challenge=sca
        if(challenge!=null){
          Text(ScaCopy.BIOMETRIC_PROMPT, style=MaterialTheme.typography.subtitle1)
          Text("Fingerprint or face runs on this device. The rehearsal passcode stays on device.", style=MaterialTheme.typography.caption)
        }
        if(challenge!=null && challenge.showsPasscode){
          OutlinedTextField(
            passcode,
            {passcode=it.filter { ch -> ch.isDigit() }.take(6)},
            label={Text("Security passcode")},
            visualTransformation=PasswordVisualTransformation(),
            enabled=!busy,
          )
          Text("Rehearsal passcode ${ScaCopy.REHEARSAL_PASSCODE}. Checked on this device and not sent to the API.")
          Button(onClick={
            val active=client
            val current=sca
            if(active!=null && current!=null && !busy){
              busy=true
              revision++
              scope.launch {
                try { settle(active, current.afterPasscode(passcode)); passcode="" }
                catch(e:Exception){message="Outcome may be unknown: ${e.message}. Retry keeps the same key."}
                finally{revision++;busy=false}
              }
            }
          },enabled=!busy){Text("Verify passcode")}
        } else if(challenge!=null && challenge.phase==ScaPhase.READY) {
          val ready=challenge
          Button(onClick={
            val active=client
            if(active!=null && !busy){
              busy=true
              revision++
              scope.launch {
                try { settle(active, ready) }
                catch(e:Exception){message="Outcome may be unknown: ${e.message}. Retry keeps the same key."}
                finally{revision++;busy=false}
              }
            }
          },enabled=!busy){Text("Retry settlement")}
        } else if(challenge==null) {
          Button(onClick={
            val active=client
            val minor=parseAmount(amount).first
            if(active!=null&&minor!=null&&!busy&&sca==null){
              busy=true
              revision++
              val draft=PaymentDraft(recipient,minor,method,note,Scenario.success,paymentKey)
              scope.launch{
                try {
                  val result=active.submitPayment(recipientId=draft.recipientId,amountMinor=draft.amountMinor,method=draft.method,note=draft.note,scenario=draft.scenario,idempotencyKey=draft.idempotencyKey)
                  when(val intercept=ScaInterpreter.interpret(result.statusCode, result.body)){
                    is ScaIntercept.NotStepUp -> applyOutcome(result)
                    is ScaIntercept.Required -> {
                      val started=ScaSession.start(draft, intercept.challenge)
                      sca=started
                      val session=started.afterBiometric(
                        ScaBiometricPrompt(activity).authenticate(ScaCopy.BIOMETRIC_PROMPT)
                      )
                      settle(active, session)
                    }
                    is ScaIntercept.Expired, is ScaIntercept.Invalid -> {
                      clearChallenge()
                      scaNotice=ScaCopy.FAILURE_MESSAGE
                    }
                  }
                }catch(e:Exception){message="Outcome may be unknown: ${e.message}. Retry keeps the same key."}
                finally{revision++;busy=false}
              }
            }
          },enabled=!busy){Text(if(busy)"Confirming…" else "Confirm payment")}
        } else {
          Text("Waiting for fingerprint or face…")
        }
        TextButton(onClick={review=false;clearChallenge();paymentKey=UUID.randomUUID().toString()},enabled=!busy){Text("Edit details")}
      }
      Text("Recent activity",style=MaterialTheme.typography.h6)
      current.transactions.reversed().take(8).forEach {transaction->Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")}
      Text("Budgets",style=MaterialTheme.typography.h6)
      current.budgets.forEach {budget->Text("${budget.category} · ${money(budget.limit)}")}
    }
  }
}
