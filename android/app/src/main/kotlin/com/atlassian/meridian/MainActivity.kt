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
  var paymentKey by remember { mutableStateOf(newPaymentIdempotencyKey()) }
  var message by remember { mutableStateOf("Fictional payment rehearsal. Connect to the Java API.") }
  var revision by remember { mutableStateOf(0) }
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
      else try {client=MeridianClient(base,room);state=null;catalog=null;review=false;revision++;paymentKey=newPaymentIdempotencyKey()}catch(e:Exception){message=e.message?:"Invalid configuration"}
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
      if(!review) Button(onClick={val parsed=parseAmount(amount);if(parsed.first==null)message=parsed.second?:"Invalid amount" else {review=true;paymentKey=newPaymentIdempotencyKey()}},enabled=!busy){Text("Review payment")}
      else {
        Text("Confirm £$amount to $recipient")
        Text("A gateway timeout retries this payment with the same key and method.",style=MaterialTheme.typography.caption)
        Button(onClick={
          val active=client
          val minor=parseAmount(amount).first
          val paymentMethod=method
          val attemptKey=paymentKey
          if(active!=null && minor!=null && !busy){
            busy=true
            revision++
            val startedRevision=revision
            scope.launch {
              try {
                val result=PaymentOrchestrator(active).submit(
                  recipientId=recipient,
                  amountMinor=minor,
                  method=paymentMethod,
                  note=note,
                  idempotencyKey=attemptKey,
                ) { _, _ ->
                  message="Gateway timed out. Retrying this payment with the same key and method."
                }
                if(startedRevision!=revision) return@launch
                if(result.ok){
                  state=result.state
                  review=false
                  amount=""
                  note=""
                  paymentKey=newPaymentIdempotencyKey()
                  message="Demo payment complete"
                } else message=result.error?:"Awaiting confirmation. Retry the same payment with the same key."
              } catch(e:MeridianError.HttpError) {
                if(startedRevision==revision) {
                  message=if(GatewayRetry.isTimeout(e.statusCode)) e.message?:"" else "Outcome may be unknown: ${e.message}. Retry keeps the same key and method."
                }
              } catch(e:Exception) {
                if(startedRevision==revision) message="Outcome may be unknown: ${e.message}. Retry keeps the same key and method."
              } finally {
                revision++
                busy=false
              }
            }
          }
        },enabled=!busy){Text(if(busy)"Confirming…" else "Confirm payment")}
        TextButton(onClick={review=false;paymentKey=newPaymentIdempotencyKey()},enabled=!busy){Text("Edit details")}
      }
      Text("Recent activity",style=MaterialTheme.typography.h6)
      current.transactions.reversed().take(8).forEach {transaction->Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")}
      Text("Budgets",style=MaterialTheme.typography.h6)
      current.budgets.forEach {budget->Text("${budget.category} · ${money(budget.limit)}")}
    }
  }
}
