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
    setContent { MaterialTheme(colors=lightColors(primary=Color(0xFF142C35),secondary=Color(0xFFD5B77A))) { MeridianScreen() } }
  }
}
@Composable fun MeridianScreen() {
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
  var sessionExpiresAt by remember { mutableStateOf<Long?>(null) }
  var sessionActiveElsewhere by remember { mutableStateOf(false) }
  var sessionActionBusy by remember { mutableStateOf(false) }
  var nowMs by remember { mutableStateOf(System.currentTimeMillis()) }
  val phase = sessionExpiresAt?.let { resolveSessionPhase(nowMs, it, sessionActiveElsewhere) }
  val sessionBlocked = phase?.let { sessionBlocksInteraction(it) } == true
  fun renewSession() {
    val activeClient = client
    if (activeClient == null || sessionActionBusy) return
    sessionActionBusy = true
    scope.launch {
      try {
        activeClient.getHealth()
        val draft = InFlightPaymentDraft(recipient, amount, note, method, review, paymentKey)
        sessionExpiresAt = refreshSessionInPlace(draft, System.currentTimeMillis()).expiresAtMillis
        nowMs = System.currentTimeMillis()
      } catch (e: Exception) {
        message = "Could not refresh the session: ${e.message}. Payment details are unchanged."
      } finally {
        sessionActionBusy = false
      }
    }
  }
  LaunchedEffect(Unit) {
    while (true) {
      nowMs = System.currentTimeMillis()
      delay(1000)
    }
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
      else try {
        client=MeridianClient(base,room)
        state=null
        catalog=null
        review=false
        revision++
        paymentKey=UUID.randomUUID().toString()
        sessionActiveElsewhere=false
        nowMs=System.currentTimeMillis()
        sessionExpiresAt=nowMs+SessionTiming.lifetimeMillis
      }catch(e:Exception){message=e.message?:"Invalid configuration"}
    },enabled=!busy){Text("Connect")}
    Text(message)
    phase?.let { currentPhase ->
      SessionStatusBanner(
        phase = currentPhase,
        actionEnabled = !sessionActionBusy,
        onExtend = { if (phase?.let { sessionOffersExtend(it) } == true) renewSession() },
        onReauthenticate = { if (phase?.let { sessionBlocksInteraction(it) } == true) renewSession() },
      )
    }
    state?.let { current ->
      Card(backgroundColor=Color(0xFF142C35),contentColor=Color.White,modifier=Modifier.fillMaxWidth()) {
        Column(Modifier.padding(22.dp)){Text("Everyday account");Text(money(current.balance),style=MaterialTheme.typography.h3);Text("Room: $room")}
      }
      Text("Make a payment",style=MaterialTheme.typography.h6)
      catalog?.recipients?.forEach { person ->
        Row {RadioButton(selected=recipient==person.id,onClick={recipient=person.id},enabled=!review&&!busy&&!sessionBlocked);Text(person.name,Modifier.padding(top=12.dp))}
      }
      OutlinedTextField(amount,{amount=it},label={Text("Amount (GBP)")},enabled=!review&&!busy&&!sessionBlocked)
      OutlinedTextField(note,{note=it.take(200)},label={Text("Reference")},enabled=!review&&!busy&&!sessionBlocked)
      // Intentional two-provider native baseline; changing it requires an app release.
      Row {RadioButton(method==PaymentMethod.card,{method=PaymentMethod.card},enabled=!review&&!busy&&!sessionBlocked);Text("Debit card · Adyen",Modifier.padding(top=12.dp))}
      Row {RadioButton(method==PaymentMethod.bank,{method=PaymentMethod.bank},enabled=!review&&!busy&&!sessionBlocked);Text("Bank payment · Worldpay",Modifier.padding(top=12.dp))}
      if(!review) Button(onClick={if(sessionBlocked){message=SessionBannerCopy.expired} else {val parsed=parseAmount(amount);if(parsed.first==null)message=parsed.second?:"Invalid amount" else {review=true;paymentKey=UUID.randomUUID().toString()}}},enabled=!busy&&!sessionBlocked){Text("Review payment")}
      else {
        Text("Confirm £$amount to $recipient")
        Button(onClick={if(sessionBlocked){message=SessionBannerCopy.expired;return@Button};val active=client;val minor=parseAmount(amount).first;if(active!=null&&minor!=null&&!busy){busy=true;revision++;scope.launch{
          try {val result=active.submitPayment(recipientId=recipient,amountMinor=minor,method=method,note=note,idempotencyKey=paymentKey)
            if(result.ok){state=result.state;review=false;amount="";note="";paymentKey=UUID.randomUUID().toString();message="Demo payment complete"}
            else message=result.error?:"Awaiting confirmation. Retry the same payment."
          }catch(e:Exception){message="Outcome may be unknown: ${e.message}. Retry keeps the same key."}finally{revision++;busy=false}
        }}},enabled=!busy&&!sessionBlocked){Text(if(busy)"Confirming…" else "Confirm payment")}
        TextButton(onClick={review=false;paymentKey=UUID.randomUUID().toString()},enabled=!busy&&!sessionBlocked){Text("Edit details")}
      }
      Text("Recent activity",style=MaterialTheme.typography.h6)
      current.transactions.reversed().take(8).forEach {transaction->Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")}
      Text("Budgets",style=MaterialTheme.typography.h6)
      current.budgets.forEach {budget->Text("${budget.category} · ${money(budget.limit)}")}
    }
  }
}
