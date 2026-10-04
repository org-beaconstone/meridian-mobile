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
  var targetCurrency by remember { mutableStateOf(ACCOUNT_CURRENCY) }
  var review by remember { mutableStateOf(false) }
  var busy by remember { mutableStateOf(false) }
  var quoteBusy by remember { mutableStateOf(false) }
  var quote by remember { mutableStateOf<FxQuoteLock?>(null) }
  var quoteSeconds by remember { mutableStateOf(0) }
  var quoteError by remember { mutableStateOf<String?>(null) }
  var paymentKey by remember { mutableStateOf(UUID.randomUUID().toString()) }
  var message by remember { mutableStateOf("Fictional payment rehearsal. Connect to the Java API.") }
  var revision by remember { mutableStateOf(0) }
  val crossCurrency = isCrossCurrency(ACCOUNT_CURRENCY, targetCurrency)
  LaunchedEffect(client) {
    val current=client
    while(current!=null) {
      val started=revision
      if(!busy && !quoteBusy) try {
        val fresh=current.getState(); val definitions=current.getCatalog()
        if(current===client && started==revision && !busy && !quoteBusy) {
          state=fresh
          catalog=definitions
          if(!review) message="Connected to shared Java API"
        }
      } catch(e:Exception) {if(current===client)message="API unavailable: ${e.message}"}
      delay(2000)
    }
  }
  LaunchedEffect(quote?.quoteId, quote?.expiresAtEpochMs) {
    val active=quote ?: return@LaunchedEffect
    while(true) {
      val left=active.remainingSeconds(System.currentTimeMillis())
      quoteSeconds=left
      if(left==0) break
      delay(1000)
    }
  }
  fun clearQuote(rotateKey: Boolean) {
    review=false
    quote=null
    quoteError=null
    quoteSeconds=0
    if(rotateKey) paymentKey=UUID.randomUUID().toString()
  }
  fun fetchQuote(active: MeridianClient, amountMinor: Int, replaceOnFailure: Boolean) {
    quoteBusy=true
    scope.launch {
      try {
        val fetched=active.requestFxQuote(ACCOUNT_CURRENCY, targetCurrency, amountMinor)
        val locked=lockQuote(fetched, ACCOUNT_CURRENCY, targetCurrency, amountMinor, System.currentTimeMillis())
        quote=locked
        quoteSeconds=locked.remainingSeconds(System.currentTimeMillis())
        quoteError=null
        message="Rate locked for $quoteSeconds seconds. No real money moves."
      } catch(e:Exception) {
        if(replaceOnFailure) quote=null
        quoteError=FxCopy.unavailable
        message=FxCopy.unavailable
      } finally { quoteBusy=false }
    }
  }
  Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
    Text("meridian",style=MaterialTheme.typography.h4)
    Text("Native Android · simulated GBP payments",style=MaterialTheme.typography.caption)
    OutlinedTextField(base,{base=it},label={Text("API base URL")},enabled=!busy&&!quoteBusy)
    OutlinedTextField(room,{room=it},label={Text("Shared rehearsal room")},enabled=!busy&&!quoteBusy)
    Button(onClick={
      if(!Regex("[A-Za-z0-9_-]{3,64}").matches(room)){message="Invalid room"}
      else try {client=MeridianClient(base,room);state=null;catalog=null;clearQuote(true);revision++}catch(e:Exception){message=e.message?:"Invalid configuration"}
    },enabled=!busy&&!quoteBusy){Text("Connect")}
    Text(message)
    state?.let { current ->
      Card(backgroundColor=Color(0xFF142C35),contentColor=Color.White,modifier=Modifier.fillMaxWidth()) {
        Column(Modifier.padding(22.dp)){Text("Everyday account");Text(money(current.balance),style=MaterialTheme.typography.h3);Text("Room: $room")}
      }
      Text("Make a payment",style=MaterialTheme.typography.h6)
      catalog?.recipients?.forEach { person ->
        Row {RadioButton(selected=recipient==person.id,onClick={recipient=person.id},enabled=!review&&!busy&&!quoteBusy);Text(person.name,Modifier.padding(top=12.dp))}
      }
      OutlinedTextField(amount,{amount=it},label={Text("Amount (GBP)")},enabled=!review&&!busy&&!quoteBusy)
      OutlinedTextField(note,{note=it.take(200)},label={Text("Reference")},enabled=!review&&!busy&&!quoteBusy)
      Text("Recipient currency")
      Row {RadioButton(targetCurrency==ACCOUNT_CURRENCY,{targetCurrency=ACCOUNT_CURRENCY},enabled=!review&&!busy&&!quoteBusy);Text("GBP · no conversion",Modifier.padding(top=12.dp))}
      Row {RadioButton(targetCurrency=="EUR",{targetCurrency="EUR"},enabled=!review&&!busy&&!quoteBusy);Text("EUR · convert from GBP",Modifier.padding(top=12.dp))}
      // Intentional two-provider native baseline; changing it requires an app release.
      Row {RadioButton(method==PaymentMethod.card,{method=PaymentMethod.card},enabled=!review&&!busy&&!quoteBusy);Text("Debit card · Adyen",Modifier.padding(top=12.dp))}
      Row {RadioButton(method==PaymentMethod.bank,{method=PaymentMethod.bank},enabled=!review&&!busy&&!quoteBusy);Text("Bank payment · Worldpay",Modifier.padding(top=12.dp))}
      if(!review) Button(onClick={
        val parsed=parseAmount(amount)
        if(parsed.first==null) message=parsed.second?:"Invalid amount"
        else {
          review=true
          paymentKey=UUID.randomUUID().toString()
          quote=null
          quoteError=null
          quoteSeconds=0
          if(crossCurrency) {
            val active=client
            if(active!=null) fetchQuote(active, parsed.first!!, true)
          } else message="Review before confirming. No real money moves."
        }
      },enabled=!busy&&!quoteBusy){Text("Review payment")}
      else {
        val minor=parseAmount(amount).first
        val blocked=crossCurrency && rateLockBlockReason(ACCOUNT_CURRENCY, targetCurrency, minor ?: 0, quote, System.currentTimeMillis()) != null
        Text("Confirm £$amount to $recipient")
        if(crossCurrency) {
          if(quoteBusy && quote==null) Text("Locking the exchange rate…")
          quote?.let { locked ->
            Text("Locked rate ${locked.rate} · ${locked.sourceCurrency} to ${locked.targetCurrency}")
            locked.targetAmountMinor?.let { target -> Text("Recipient gets ${formatMinor(target, locked.targetCurrency)}") }
            Text(if(quoteSeconds==0) FxCopy.expired else "${FxCopy.locked} · ${quoteSeconds}s")
            LinearProgressIndicator(
              progress=quoteSeconds / QUOTE_LOCK_SECONDS.toFloat(),
              modifier=Modifier.fillMaxWidth().height(8.dp),
              color=if(quoteSeconds==0) Color(0xFFAE2A19) else Color(0xFF1868DB),
              backgroundColor=Color(0xFFD7DED0),
            )
          }
          quoteError?.let { Text(it, color=Color(0xFFAE2A19)) }
          if(!quoteBusy && (quoteError!=null || (quote!=null && quoteSeconds==0))) {
            Button(onClick={
              val active=client
              val value=parseAmount(amount).first
              if(active!=null && value!=null) fetchQuote(active, value, false)
            },enabled=!busy&&!quoteBusy){Text(if(quote==null) FxCopy.retry else FxCopy.refresh)}
          }
        }
        Button(onClick={
          val active=client
          if(active!=null && minor!=null && !busy && !quoteBusy) {
            val reason=rateLockBlockReason(ACCOUNT_CURRENCY, targetCurrency, minor, quote, System.currentTimeMillis())
            if(reason!=null) message=reason
            else {
              busy=true
              revision++
              val attached=if(crossCurrency) quote?.quoteId else null
              scope.launch {
                try {
                  val result=active.submitPayment(recipientId=recipient,amountMinor=minor,method=method,note=note,idempotencyKey=paymentKey,quoteId=attached)
                  if(result.ok){
                    state=result.state
                    clearQuote(true)
                    amount=""
                    note=""
                    targetCurrency=ACCOUNT_CURRENCY
                    message="Demo payment complete"
                  } else message=result.error?:"Awaiting confirmation. Retry the same payment."
                } catch(e:Exception){message="Outcome may be unknown: ${e.message}. Retry keeps the same key."}
                finally{revision++;busy=false}
              }
            }
          }
        },enabled=!busy&&!quoteBusy&&!blocked){Text(if(busy)"Confirming…" else "Confirm payment")}
        TextButton(onClick={clearQuote(true)},enabled=!busy&&!quoteBusy){Text("Edit details")}
      }
      Text("Recent activity",style=MaterialTheme.typography.h6)
      current.transactions.reversed().take(8).forEach {transaction->Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")}
      Text("Budgets",style=MaterialTheme.typography.h6)
      current.budgets.forEach {budget->Text("${budget.category} · ${money(budget.limit)}")}
    }
  }
}
