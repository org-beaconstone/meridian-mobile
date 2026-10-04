package com.atlassian.meridian

import android.content.Context
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
import java.util.UUID

/** Room-scoped flag cache. Values stay on device so a later launch can evaluate before the first paint. */
class SharedPrefsFeatureFlagCache(context: Context) : FeatureFlagCache {
  private val prefs = context.getSharedPreferences("meridian.flags", Context.MODE_PRIVATE)

  override fun read(key: String): FeatureFlagEvaluation? {
    val raw = prefs.getString(key, null) ?: return null
    val parts = raw.split("|", limit = 4)
    if (parts.size != 4) return null
    return FeatureFlagEvaluation(parts[0], parts[1] == "1", parts[2], parts[3])
  }

  override fun write(key: String, evaluation: FeatureFlagEvaluation) {
    val raw = listOf(evaluation.key, if (evaluation.enabled) "1" else "0", evaluation.variant, evaluation.source).joinToString("|")
    prefs.edit().putString(key, raw).apply()
  }
}

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
  var flag by remember { mutableStateOf<FeatureFlagEvaluation?>(null) }
  var currency by remember { mutableStateOf("GBP") }
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
      val evaluation=try { current.evaluateEuPaymentsFlag() } catch(e:Exception) { FeatureFlagEvaluation.legacy("default") }
      if(!busy) try {
        val fresh=current.getState(); val definitions=current.getCatalog()
        if(current===client && started==revision && !busy) {
          val wasEnabled=flag?.enabled==true
          flag=evaluation
          if(wasEnabled && !evaluation.enabled) { currency="GBP"; if(review) { review=false; paymentKey=UUID.randomUUID().toString() } }
          val choices=paymentMethodChoices(evaluation, definitions)
          if(choices.none { it.method==method }) method=choices.first().method
          state=fresh; catalog=definitions
          message=if(evaluation.enabled) "Connected to shared Java API · dynamic catalog" else "Connected to shared Java API"
        }
      } catch(e:Exception) {if(current===client && started==revision){flag=evaluation; message="API unavailable: ${e.message}"}}
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
      else try {client=MeridianClient(base,room,SharedPrefsFeatureFlagCache(context));state=null;catalog=null;flag=null;currency="GBP";review=false;revision++;paymentKey=UUID.randomUUID().toString()}catch(e:Exception){message=e.message?:"Invalid configuration"}
    },enabled=!busy){Text("Connect")}
    Text(message)
    state?.let { current ->
      Card(backgroundColor=Color(0xFF142C35),contentColor=Color.White,modifier=Modifier.fillMaxWidth()) {
        Column(Modifier.padding(22.dp)){Text("Everyday account");Text(money(current.balance),style=MaterialTheme.typography.h3);Text("Room: $room")}
      }
      if(flag==null) Text("Checking payment configuration…")
      else {
        val activeFlag=flag!!
        val shown=if(activeFlag.enabled) currency else "GBP"
        Text("Make a payment",style=MaterialTheme.typography.h6)
        Text("Flag ${FeatureFlags.mobileEuPayments} · ${activeFlag.variant}",style=MaterialTheme.typography.caption)
        catalog?.recipients?.forEach { person ->
          Row {RadioButton(selected=recipient==person.id,onClick={recipient=person.id},enabled=!review&&!busy);Text(person.name,Modifier.padding(top=12.dp))}
        }
        if(activeFlag.enabled) {
          Row {
            RadioButton(currency=="GBP",{currency="GBP"},enabled=!review&&!busy);Text("GBP",Modifier.padding(top=12.dp))
            RadioButton(currency=="EUR",{currency="EUR"},enabled=!review&&!busy);Text("EUR",Modifier.padding(top=12.dp))
          }
        }
        OutlinedTextField(amount,{amount=it},label={Text(if(shown=="EUR") "Amount (EUR)" else "Amount (GBP)")},enabled=!review&&!busy)
        OutlinedTextField(note,{note=it.take(200)},label={Text("Reference")},enabled=!review&&!busy)
        paymentMethodChoices(activeFlag, catalog).forEach { choice ->
          Row {RadioButton(method==choice.method,{method=choice.method},enabled=!review&&!busy);Text(choice.title,Modifier.padding(top=12.dp))}
        }
        if(!review) Button(onClick={val parsed=parseAmount(amount);if(parsed.first==null)message=parsed.second?:"Invalid amount" else {review=true;paymentKey=UUID.randomUUID().toString()}},enabled=!busy){Text("Review payment")}
        else {
          val minorPreview=parseAmount(amount).first ?: 0
          Text("Confirm ${formatMinor(minorPreview, shown)} to $recipient")
          Button(onClick={val active=client;val minor=parseAmount(amount).first;if(active!=null&&minor!=null&&!busy){busy=true;revision++;scope.launch{
            try {val result=active.submitPayment(recipientId=recipient,amountMinor=minor,method=method,note=note,idempotencyKey=paymentKey,displayCurrency=shown)
              if(result.ok){state=result.state;review=false;amount="";note="";paymentKey=UUID.randomUUID().toString();message="Demo payment complete"}
              else message=result.error?:"Awaiting confirmation. Retry the same payment."
            }catch(e:Exception){message="Outcome may be unknown: ${e.message}. Retry keeps the same key."}finally{revision++;busy=false}
          }}},enabled=!busy){Text(if(busy)"Confirming…" else "Confirm payment")}
          TextButton(onClick={review=false;paymentKey=UUID.randomUUID().toString()},enabled=!busy){Text("Edit details")}
        }
      }
      Text("Recent activity",style=MaterialTheme.typography.h6)
      current.transactions.reversed().take(8).forEach {transaction->Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")}
      Text("Budgets",style=MaterialTheme.typography.h6)
      current.budgets.forEach {budget->Text("${budget.category} · ${money(budget.limit)}")}
    }
  }
}

private data class MethodChoice(val id: String, val method: PaymentMethod, val title: String)

/** Flag off keeps the hardcoded Adyen/Worldpay baseline. Flag on hydrates those same providers from the catalog. */
private fun paymentMethodChoices(flag: FeatureFlagEvaluation?, catalog: CatalogResponse?): List<MethodChoice> {
  val legacy = listOf(
    MethodChoice("adyen", PaymentMethod.card, "Debit card · Adyen"),
    MethodChoice("worldpay", PaymentMethod.bank, "Bank payment · Worldpay"),
  )
  if (flag?.enabled != true || catalog == null) return legacy
  val hydrated = catalog.providers.mapNotNull { provider ->
    val method = when (provider.methods.firstOrNull()) {
      "card" -> PaymentMethod.card
      "bank" -> PaymentMethod.bank
      else -> null
    } ?: return@mapNotNull null
    val title = if (method == PaymentMethod.card) "Debit card · ${provider.name}" else "Bank payment · ${provider.name}"
    MethodChoice(provider.id, method, title)
  }
  return hydrated.ifEmpty { legacy }
}
