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
import java.util.Date

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
  var consent by remember { mutableStateOf(false) }
  var intentLocked by remember { mutableStateOf(false) }
  var attempt by remember { mutableStateOf<PaymentIntentAttempt?>(null) }
  var outcome by remember { mutableStateOf<PaymentIntentSubmission?>(null) }
  var tick by remember { mutableStateOf(System.currentTimeMillis()) }
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
  LaunchedEffect(review, attempt) {
    while(review && attempt!=null) {
      delay(1000)
      tick=System.currentTimeMillis()
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
        state=null;catalog=null;review=false;revision++
        attempt=null;outcome=null;consent=false;intentLocked=false
      }catch(e:Exception){message=e.message?:"Invalid configuration"}
    },enabled=!busy){Text("Connect")}
    Text(message)
    state?.let { current ->
      val currentAttempt=attempt
      val expired=currentAttempt?.let { isQuoteExpired(it.quoteExpiresAt, Date(tick)) } ?: false
      Card(backgroundColor=Color(0xFF142C35),contentColor=Color.White,modifier=Modifier.fillMaxWidth()) {
        Column(Modifier.padding(22.dp)){Text("Everyday account");Text(money(current.balance),style=MaterialTheme.typography.h3);Text("Room: $room")}
      }
      Text("Make a payment",style=MaterialTheme.typography.h6)
      catalog?.recipients?.forEach { person ->
        Row {RadioButton(selected=recipient==person.id,onClick={recipient=person.id},enabled=!review&&!busy);Text(person.name,Modifier.padding(top=12.dp))}
      }
      OutlinedTextField(amount,{amount=it},label={Text("Amount (GBP)")},enabled=!review&&!busy)
      OutlinedTextField(note,{note=it.take(200)},label={Text("Local reference")},enabled=!review&&!busy)
      // Intentional two-provider native baseline; changing it requires an app release.
      Row {RadioButton(method==PaymentMethod.card,{method=PaymentMethod.card},enabled=!review&&!busy);Text("Debit card · Adyen",Modifier.padding(top=12.dp))}
      Row {RadioButton(method==PaymentMethod.bank,{method=PaymentMethod.bank},enabled=!review&&!busy);Text("Bank payment · Worldpay",Modifier.padding(top=12.dp))}
      if(!review) Button(onClick={
        val parsed=parseAmount(amount)
        if(parsed.first==null) message=parsed.second?:"Invalid amount"
        else if(parsed.first!! > current.balance) message="Insufficient balance"
        else {
          val person=catalog?.recipients?.firstOrNull { it.id==recipient }
          try {
            attempt=preparePaymentIntent(recipient, person?.name ?: "", person?.detail ?: "", amount, note, method)
            consent=false;outcome=null;intentLocked=false;review=true;tick=System.currentTimeMillis()
            message="Review before confirming. No real money moves."
          } catch(e:MeridianError){message=e.message?:"Invalid payment"}
        }
      },enabled=!busy){Text("Review payment")}
      else if(currentAttempt!=null) {
        ReviewRow("Recipient", currentAttempt.review.recipientName)
        if(currentAttempt.review.recipientDetail.isNotEmpty()) Text(currentAttempt.review.recipientDetail,style=MaterialTheme.typography.caption)
        ReviewRow("Amount", currentAttempt.review.amountLabel)
        ReviewRow("Fees", currentAttempt.review.feeLabel)
        ReviewRow("Method", currentAttempt.review.methodLabel)
        ReviewRow("Bank", currentAttempt.review.bank)
        ReviewRow("Quote expiry", currentAttempt.review.expiryLabel)
        Text(currentAttempt.review.consentSummary,style=MaterialTheme.typography.body2)
        Row {
          Checkbox(checked=consent,onCheckedChange={consent=it},enabled=!busy&&!intentLocked)
          Text("I agree to this payment",Modifier.padding(top=12.dp))
        }
        Text("Idempotency ${currentAttempt.idempotencyKey}",style=MaterialTheme.typography.caption)
        Text("Payload hash ${currentAttempt.payloadHash}",style=MaterialTheme.typography.caption)
        val terminal=outcome?.terminal==true
        if(terminal) {
          Text(outcome?.message ?: "")
          outcome?.intentId?.let { Text(it,style=MaterialTheme.typography.caption) }
          Button(onClick={
            review=false;attempt=null;outcome=null;consent=false;intentLocked=false;amount="";note=""
            message="Enter a new payment. The previous intent was not reused."
          },enabled=!busy){Text("New payment")}
        } else if(expired && !intentLocked) {
          Text("This quote has expired.")
          Button(onClick={
            if(!busy&&!intentLocked) {
              val person=catalog?.recipients?.firstOrNull { it.id==recipient }
              try {
                attempt=preparePaymentIntent(recipient, person?.name ?: "", person?.detail ?: "", amount, note, method)
                consent=false;outcome=null;tick=System.currentTimeMillis()
                message="Quote refreshed. Review the new expiry before confirming."
              } catch(e:MeridianError){message=e.message?:"Could not refresh quote"}
            }
          },enabled=!busy&&!intentLocked){Text("Refresh quote")}
        } else {
          Button(onClick={
            val active=client
            if(active==null||busy) return@Button
            if(!intentLocked && !consent) { message="Consent is required"; return@Button }
            if(!intentLocked && expired) { message="Quote expired. Refresh the quote before confirming."; return@Button }
            busy=true;intentLocked=true;revision++
            scope.launch {
              try {
                val submission=currentAttempt.submit(Date(tick), true) { body, key, hash ->
                  active.submitPaymentIntent(body, key, hash)
                }
                outcome=submission
                message=submission.message
                if(submission.disposition==IntentDisposition.succeeded) submission.state?.let { state=it }
              } catch(e:MeridianError.DuplicateSubmission) {
                message=e.message?:"Payment is already being submitted."
              } catch(e:MeridianError.QuoteExpired) {
                message=e.message
              } catch(e:MeridianError.ValidationError) {
                message=e.message
              } catch(e:Exception) {
                message="Outcome may be unknown: ${e.message}. Retry keeps the same idempotency key and payload hash."
              } finally { revision++;busy=false }
            }
          },enabled=!busy&&consent){Text(if(busy)"Confirming…" else if(intentLocked)"Retry payment" else "Confirm payment")}
        }
        if(!intentLocked && !terminal) TextButton(onClick={review=false;attempt=null;outcome=null;consent=false},enabled=!busy){Text("Edit details")}
      }
      Text("Recent activity",style=MaterialTheme.typography.h6)
      current.transactions.reversed().take(8).forEach {transaction->Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")}
      Text("Budgets",style=MaterialTheme.typography.h6)
      current.budgets.forEach {budget->Text("${budget.category} · ${money(budget.limit)}")}
    }
  }
}

@Composable private fun ReviewRow(label: String, value: String) {
  Row(Modifier.fillMaxWidth(), horizontalArrangement=Arrangement.SpaceBetween) {
    Text(label, color=Color(0xFF57675E))
    Text(value)
  }
}
