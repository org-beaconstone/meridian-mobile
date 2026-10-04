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
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import java.util.UUID

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent { MaterialTheme(colors=lightColors(primary=Color(0xFF142C35),secondary=Color(0xFFD5B77A))) { MeridianScreen() } }
  }
}

private data class HeldPayment(
  val key: String,
  val recipientId: String,
  val amountMinor: Int,
  val method: PaymentMethod,
  val note: String,
)

@Composable fun MeridianScreen() {
  val scope=rememberCoroutineScope()
  var base by remember { mutableStateOf("http://10.0.2.2:8080/api/v1") }
  var room by remember { mutableStateOf("meridian-rehearsal") }
  var connectedRoom by remember { mutableStateOf("") }
  var client by remember { mutableStateOf<MeridianClient?>(null) }
  var state by remember { mutableStateOf<BankState?>(null) }
  var catalog by remember { mutableStateOf<CatalogResponse?>(null) }
  var health by remember { mutableStateOf<SessionHealth?>(null) }
  var recipient by remember { mutableStateOf("northline-studio") }
  var amount by remember { mutableStateOf("") }
  var note by remember { mutableStateOf("") }
  var method by remember { mutableStateOf(PaymentMethod.card) }
  var review by remember { mutableStateOf(false) }
  var busy by remember { mutableStateOf(false) }
  var paymentKey by remember { mutableStateOf(UUID.randomUUID().toString()) }
  var held by remember { mutableStateOf<HeldPayment?>(null) }
  var retryBanner by remember { mutableStateOf<String?>(null) }
  var message by remember { mutableStateOf("Fictional payment rehearsal. Connect to the Java API.") }
  var revision by remember { mutableStateOf(0) }
  val stateNow = rememberUpdatedState(state)
  LaunchedEffect(client) {
    val current=client ?: return@LaunchedEffect
    current.startSessionHealthPolling(this, 5_000)
    current.sessionHealth().collect { snapshot ->
      if (current === client) health = snapshot.health
    }
  }
  LaunchedEffect(client) {
    val current=client
    while(current!=null) {
      val started=revision
      if(!busy) try {
        val fresh=current.getState(); val definitions=current.getCatalog()
        if(current===client && started==revision && !busy) {state=fresh;catalog=definitions;message="Connected to shared Java API"}
      } catch(e:Exception) {
        if(current===client) message = if (stateNow.value == null) "API unavailable: ${e.message}" else "Connection interrupted. Payment details are still here."
      }
      delay(2000)
    }
  }
  fun matchesHeld(minor: Int): Boolean {
    val attempt=held ?: return false
    return attempt.method==method && attempt.recipientId==recipient && attempt.note==note && attempt.amountMinor==minor
  }
  fun keyForSubmit(minor: Int): String {
    if (matchesHeld(minor)) return held!!.key
    if (held?.key == paymentKey) paymentKey = UUID.randomUUID().toString()
    return paymentKey
  }
  fun applySuccess(activeKey: String, activeRecipient: String, minor: Int, activeMethod: PaymentMethod, activeNote: String, next: BankState?) {
    state=next
    val stillSame=method==activeMethod && recipient==activeRecipient && note==activeNote && parseAmount(amount).first==minor && paymentKey==activeKey
    if(stillSame){
      review=false
      amount=""
      note=""
      paymentKey=UUID.randomUUID().toString()
    }
    held=null
    retryBanner=null
    message="Demo payment complete"
  }
  fun retryHeld() {
    val active=client
    val attempt=held
    if(active==null || attempt==null || busy) return
    busy=true
    revision++
    scope.launch {
      try {
        val result=active.submitPayment(recipientId=attempt.recipientId,amountMinor=attempt.amountMinor,method=attempt.method,note=attempt.note,idempotencyKey=attempt.key)
        if(result.ok) applySuccess(attempt.key, attempt.recipientId, attempt.amountMinor, attempt.method, attempt.note, result.state)
        else {
          retryBanner=result.error ?: "Payment is unresolved. Retry uses the same payment key."
          message="Payment details are unchanged."
        }
      } catch(e:Exception) {
        retryBanner=if (e is MeridianError.RetriesExhausted) {
          "Gateway HTTP ${e.statusCode} after ${e.attempts} attempts. Your amount, recipient and reference are unchanged. Retry uses the same payment key."
        } else {
          "Outcome may be unknown. Your payment details are unchanged. Retry uses the same payment key."
        }
        message="Payment details are unchanged."
      } finally { revision++; busy=false }
    }
  }
  fun submit() {
    val active=client
    val minor=parseAmount(amount).first
    if(active==null || minor==null || busy) return
    val activeKey=keyForSubmit(minor)
    val activeMethod=method
    val activeRecipient=recipient
    val activeNote=note
    busy=true
    revision++
    scope.launch {
      try {
        val result=active.submitPayment(recipientId=activeRecipient,amountMinor=minor,method=activeMethod,note=activeNote,idempotencyKey=activeKey)
        if(result.ok) applySuccess(activeKey, activeRecipient, minor, activeMethod, activeNote, result.state)
        else {
          held=HeldPayment(activeKey, activeRecipient, minor, activeMethod, activeNote)
          retryBanner=result.error ?: "Payment is unresolved. Retry uses the same payment key."
          message="Payment details are unchanged."
        }
      } catch(e:Exception) {
        held=HeldPayment(activeKey, activeRecipient, minor, activeMethod, activeNote)
        retryBanner=if (e is MeridianError.RetriesExhausted) {
          "Gateway HTTP ${e.statusCode} after ${e.attempts} attempts. Your amount, recipient and reference are unchanged. Retry uses the same payment key."
        } else {
          "Outcome may be unknown. Your payment details are unchanged. Retry uses the same payment key."
        }
        message="Payment details are unchanged."
      } finally { revision++; busy=false }
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
        val switching=connectedRoom.isNotEmpty() && connectedRoom!=room
        client?.stopSessionHealthPolling()
        client=MeridianClient(base,room)
        connectedRoom=room
        if(switching){
          state=null
          catalog=null
          review=false
          held=null
          retryBanner=null
          health=null
          paymentKey=UUID.randomUUID().toString()
        }
        revision++
      } catch(e:Exception){message=e.message?:"Invalid configuration"}
    },enabled=!busy){Text("Connect")}
    Text(message)
    retryBanner?.let { banner ->
      Card(backgroundColor=Color(0xFFFFEDEB),modifier=Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp)) {
          Text(banner)
          Button(onClick={ retryHeld() },enabled=!busy){ Text(if(busy) "Retrying…" else "Retry payment") }
        }
      }
    }
    health?.let { snapshot ->
      when (val notice=corridorNotice(snapshot, method)) {
        is CorridorNotice.SwitchRail -> Card(backgroundColor=Color(0xFFFFF7E6),modifier=Modifier.fillMaxWidth()) {
          Column(Modifier.padding(14.dp)) {
            Text("${railLabel(notice.prompt.selectedMethod)} is ${notice.prompt.reason} in corridor ${notice.prompt.corridorId}. ${railLabel(notice.prompt.alternateMethod)} is eligible. Choosing it does not send the payment.")
            Button(onClick={
              if (held?.key == paymentKey) paymentKey = UUID.randomUUID().toString()
              method = notice.prompt.alternateMethod
            },enabled=!busy){
              Text(if (notice.prompt.alternateMethod==PaymentMethod.card) "Use debit card" else "Use bank payment")
            }
          }
        }
        is CorridorNotice.Unavailable -> Card(backgroundColor=Color(0xFFFFF7E6),modifier=Modifier.fillMaxWidth()) {
          Text(notice.message, Modifier.padding(14.dp))
        }
        null -> Unit
      }
    }
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
      if(!review) Button(onClick={val parsed=parseAmount(amount);if(parsed.first==null)message=parsed.second?:"Invalid amount" else { if(held==null) paymentKey=UUID.randomUUID().toString(); review=true }},enabled=!busy){Text("Review payment")}
      else {
        Text("Confirm £$amount to $recipient")
        Button(onClick={ submit() },enabled=!busy){Text(if(busy)"Confirming…" else "Confirm payment")}
        TextButton(onClick={review=false; if(held==null) paymentKey=UUID.randomUUID().toString()},enabled=!busy){Text("Edit details")}
      }
      Text("Recent activity",style=MaterialTheme.typography.h6)
      current.transactions.reversed().take(8).forEach {transaction->Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")}
      Text("Budgets",style=MaterialTheme.typography.h6)
      current.budgets.forEach {budget->Text("${budget.category} · ${money(budget.limit)}")}
    }
  }
}
