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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent { MaterialTheme(colors=lightColors(primary=Color(0xFF142C35),secondary=Color(0xFFD5B77A))) { MeridianScreen() } }
  }
}
@Composable fun MeridianScreen() {
  val scope=rememberCoroutineScope()
  val context=LocalContext.current
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
  LaunchedEffect(client) {
    val current=client
    while(current!=null) {
      val started=revision
      if(!busy) try {
        val fresh=current.getState(); val definitions=current.loadCatalog()
        if(current===client && started==revision && !busy) {
          state=fresh
          catalog=definitions.catalog
          val active=ProviderBaseline.active(definitions.catalog)
          val offered=active.any { ProviderBaseline.methodOf(it)==method }
          val wasReview=review
          if(!offered) {
            if(review) paymentKey=UUID.randomUUID().toString()
            review=false
            active.firstOrNull()?.let { provider -> ProviderBaseline.methodOf(provider)?.let { method=it } }
          }
          message = when {
            active.isEmpty() -> "No payment method is available right now."
            !offered && wasReview -> "That payment method is unavailable. Review the payment again."
            definitions.origin==CatalogOrigin.NETWORK || definitions.origin==CatalogOrigin.CACHE -> "Connected to shared Java API"
            else -> "Connected to shared Java API. Using saved provider catalog."
          }
        }
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
      else try {client=MeridianClient(base,room,catalogStore=EncryptedFileCatalogStore(File(context.filesDir,"catalog/$room")));state=null;catalog=null;review=false;revision++;paymentKey=UUID.randomUUID().toString()}catch(e:Exception){message=e.message?:"Invalid configuration"}
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
      // Allowlist stays Adyen card and Worldpay bank. Catalog availability only hides one of those two.
      val shown=catalog
      val activeMethods=if(shown==null) emptyList() else ProviderBaseline.active(shown)
      activeMethods.forEach { provider ->
        val choice=ProviderBaseline.methodOf(provider) ?: return@forEach
        Row {RadioButton(method==choice,{method=choice},enabled=!review&&!busy);Text(ProviderBaseline.label(provider.id),Modifier.padding(top=12.dp))}
      }
      if(shown!=null && activeMethods.isEmpty()) Text("No payment method is available right now.")
      if(!review) Button(onClick={
        val parsed=parseAmount(amount)
        val stillOffered=shown?.let { current -> ProviderBaseline.active(current).any { provider -> ProviderBaseline.methodOf(provider)==method } } == true
        if(parsed.first==null)message=parsed.second?:"Invalid amount"
        else if(!stillOffered) message="That payment method is unavailable."
        else {review=true;paymentKey=UUID.randomUUID().toString()}
      },enabled=!busy && activeMethods.isNotEmpty()){Text("Review payment")}
      else {
        Text("Confirm £$amount to $recipient")
        Button(onClick={val active=client;val minor=parseAmount(amount).first;val stillOffered=catalog?.let { ProviderBaseline.active(it).any { provider -> ProviderBaseline.methodOf(provider)==method } } == true;if(!stillOffered){review=false;paymentKey=UUID.randomUUID().toString();message="That payment method is unavailable."}else if(active!=null&&minor!=null&&!busy){busy=true;revision++;scope.launch{
          try {val result=active.submitPayment(recipientId=recipient,amountMinor=minor,method=method,note=note,idempotencyKey=paymentKey)
            if(result.ok){state=result.state;review=false;amount="";note="";paymentKey=UUID.randomUUID().toString();message="Demo payment complete"}
            else message=result.error?:"Awaiting confirmation. Retry the same payment."
          }catch(e:Exception){message="Outcome may be unknown: ${e.message}. Retry keeps the same key."}finally{revision++;busy=false}
        }}},enabled=!busy){Text(if(busy)"Confirming…" else "Confirm payment")}
        TextButton(onClick={review=false;paymentKey=UUID.randomUUID().toString()},enabled=!busy){Text("Edit details")}
      }
      Text("Recent activity",style=MaterialTheme.typography.h6)
      current.transactions.reversed().take(8).forEach {transaction->Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")}
      Text("Budgets",style=MaterialTheme.typography.h6)
      current.budgets.forEach {budget->Text("${budget.category} · ${money(budget.limit)}")}
    }
  }
}
