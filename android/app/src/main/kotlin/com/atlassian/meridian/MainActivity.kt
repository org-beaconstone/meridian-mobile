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
  var currency by remember { mutableStateOf(CurrencyCode.GBP) }
  var railId by remember { mutableStateOf(gbpBaseline.first().id) }
  var cachedGbp by remember { mutableStateOf(gbpBaseline) }
  var surface by remember { mutableStateOf(resolvePaymentSurface(false, null, gbpBaseline).surface) }
  var review by remember { mutableStateOf(false) }
  var busy by remember { mutableStateOf(false) }
  var paymentKey by remember { mutableStateOf(UUID.randomUUID().toString()) }
  var message by remember { mutableStateOf("Fictional payment rehearsal. Connect to the Java API.") }
  var revision by remember { mutableStateOf(0) }

  fun applySurface(flagEnabled: Boolean, providers: List<Provider>?): Boolean {
    val previous = surface.flagEnabled
    val resolved = resolvePaymentSurface(flagEnabled, providers, cachedGbp)
    cachedGbp = resolved.cachedGbp
    surface = resolved.surface
    val next = reconcileSelection(resolved.surface, currency, railId, review)
    val paused = review && !next.reviewing && previous && !flagEnabled
    if (review && !next.reviewing) paymentKey = UUID.randomUUID().toString()
    currency = next.currency
    railId = next.railId
    review = next.reviewing
    if (paused) message = "European payments are paused. GBP card and bank payments are still available."
    return paused
  }

  LaunchedEffect(client) {
    val current=client
    while(current!=null) {
      val started=revision
      if(!busy) {
        val enabled = current.mobileEuPaymentsEnabled()
        try {
          val fresh=current.getState(); val definitions=current.getCatalog()
          if(current===client && started==revision && !busy) {
            state=fresh
            catalog=definitions
            val paused = applySurface(enabled, definitions.providers)
            if (!paused) message = if (enabled) "Connected to shared Java API · EU payments on" else "Connected to shared Java API"
          }
        } catch(e:Exception) {
          if(current===client && !busy) {
            applySurface(enabled, catalog?.providers)
            message="API unavailable: ${e.message}"
          }
        }
      }
      delay(2000)
    }
  }
  val selectedCurrency = if (surface.currencies.contains(currency)) currency else CurrencyCode.GBP
  val visibleRails = surface.rails.filter { it.currency == selectedCurrency }.ifEmpty { surface.rails }
  val activeRailId = if (visibleRails.any { it.id == railId }) railId else visibleRails.first().id
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
        currency = CurrencyCode.GBP
        railId = gbpBaseline.first().id
        cachedGbp = gbpBaseline
        surface = resolvePaymentSurface(false, null, gbpBaseline).surface
      }catch(e:Exception){message=e.message?:"Invalid configuration"}
    },enabled=!busy){Text("Connect")}
    Text(message)
    state?.let { current ->
      Card(backgroundColor=Color(0xFF142C35),contentColor=Color.White,modifier=Modifier.fillMaxWidth()) {
        Column(Modifier.padding(22.dp)){
          Text("Everyday account")
          Text(money(current.balance),style=MaterialTheme.typography.h3)
          Text("Room: $room")
          Text(if (surface.flagEnabled) "EU payments on for this cohort" else "GBP · Adyen card and Worldpay bank")
        }
      }
      Text("Make a payment",style=MaterialTheme.typography.h6)
      catalog?.recipients?.forEach { person ->
        Row {RadioButton(selected=recipient==person.id,onClick={recipient=person.id},enabled=!review&&!busy);Text(person.name,Modifier.padding(top=12.dp))}
      }
      if (surface.currencies.contains(CurrencyCode.EUR)) {
        Text("Currency")
        Row {RadioButton(selectedCurrency==CurrencyCode.GBP,{
          val next = reconcileSelection(surface, CurrencyCode.GBP, railId, review)
          if (review && !next.reviewing) paymentKey = UUID.randomUUID().toString()
          currency = next.currency; railId = next.railId; review = next.reviewing
        },enabled=!review&&!busy);Text("GBP",Modifier.padding(top=12.dp))}
        Row {RadioButton(selectedCurrency==CurrencyCode.EUR,{
          val next = reconcileSelection(surface, CurrencyCode.EUR, railId, review)
          if (review && !next.reviewing) paymentKey = UUID.randomUUID().toString()
          currency = next.currency; railId = next.railId; review = next.reviewing
        },enabled=!review&&!busy);Text("EUR",Modifier.padding(top=12.dp))}
      }
      OutlinedTextField(amount,{amount=it},label={Text("Amount (${selectedCurrency.name})")},enabled=!review&&!busy)
      OutlinedTextField(note,{note=it.take(200)},label={Text("Reference")},enabled=!review&&!busy)
      visibleRails.forEach { rail ->
        Row {RadioButton(activeRailId==rail.id,{railId=rail.id},enabled=!review&&!busy);Text(rail.label,Modifier.padding(top=12.dp))}
      }
      if(!review) Button(onClick={val parsed=parseAmount(amount, selectedCurrency);if(parsed.first==null)message=parsed.second?:"Invalid amount" else {review=true;paymentKey=UUID.randomUUID().toString()}},enabled=!busy){Text("Review payment")}
      else {
        Text("Confirm ${money(parseAmount(amount, selectedCurrency).first ?: 0, selectedCurrency)} to $recipient")
        Button(onClick={
          val active=client
          val rail = surface.rails.firstOrNull { it.id == activeRailId }
          val minor=parseAmount(amount, CurrencyCode.GBP).first
          if (rail == null) {
            message = "Payment method unavailable. GBP card and bank payments are still available."
            review = false
          } else if (rail.currency != CurrencyCode.GBP) {
            message = "EUR stays on this device. The shared ledger settles in GBP pence, so no payment was sent."
          } else if(active!=null&&minor!=null&&!busy){
            val methodForPayment = rail.method
            val keyForPayment = paymentKey
            busy=true
            revision++
            scope.launch{
              try {val result=active.submitPayment(recipientId=recipient,amountMinor=minor,method=methodForPayment,note=note,idempotencyKey=keyForPayment)
                if(result.ok){state=result.state;review=false;amount="";note="";paymentKey=UUID.randomUUID().toString();message="Demo payment complete"}
                else message=result.error?:"Awaiting confirmation. Retry the same payment."
              }catch(e:Exception){message="Outcome may be unknown: ${e.message}. Retry keeps the same key."}finally{revision++;busy=false}
            }
          }
        },enabled=!busy){Text(if(busy)"Confirming…" else "Confirm payment")}
        TextButton(onClick={review=false;paymentKey=UUID.randomUUID().toString()},enabled=!busy){Text("Edit details")}
      }
      Text("Recent activity",style=MaterialTheme.typography.h6)
      current.transactions.reversed().take(8).forEach {transaction->Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")}
      Text("Budgets",style=MaterialTheme.typography.h6)
      current.budgets.forEach {budget->Text("${budget.category} · ${money(budget.limit)}")}
    }
  }
}
