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
import androidx.compose.ui.platform.LocalConfiguration
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
  val configuration = LocalConfiguration.current
  val fullScreen = selectorUsesFullScreen(
    isRegularWidth = isRegularSelectorWidth(configuration.smallestScreenWidthDp),
    isAccessibilityText = isLargeAccessibilityText(configuration.fontScale),
  )
  var base by remember { mutableStateOf("http://10.0.2.2:8080/api/v1") }
  var room by remember { mutableStateOf("meridian-rehearsal") }
  var client by remember { mutableStateOf<MeridianClient?>(null) }
  var state by remember { mutableStateOf<BankState?>(null) }
  var catalog by remember { mutableStateOf<CatalogResponse?>(null) }
  var recipient by remember { mutableStateOf("northline-studio") }
  var amount by remember { mutableStateOf("") }
  var note by remember { mutableStateOf("") }
  var methodKey by remember { mutableStateOf<String?>(null) }
  var bankKey by remember { mutableStateOf<String?>(null) }
  var showMethods by remember { mutableStateOf(false) }
  var showBanks by remember { mutableStateOf(false) }
  var catalogLoading by remember { mutableStateOf(false) }
  var review by remember { mutableStateOf(false) }
  var busy by remember { mutableStateOf(false) }
  var paymentKey by remember { mutableStateOf(UUID.randomUUID().toString()) }
  var message by remember { mutableStateOf("Fictional payment rehearsal. Connect to the Java API.") }
  var revision by remember { mutableStateOf(0) }
  val selected = methodChoice(methodKey, catalog?.providers.orEmpty())
  LaunchedEffect(client) {
    val current=client
    while(current!=null) {
      val started=revision
      if(!busy) try {
        val fresh=current.getState(); val definitions=current.getCatalog()
        if(current===client && started==revision && !busy) {
          state=fresh
          catalog=definitions
          if(!review) {
            val next=reconciledSelection(SelectionState(methodKey, bankKey), definitions.providers)
            methodKey=next.methodId
            bankKey=next.bankId
          }
          catalogLoading=false
          message="Connected to shared Java API"
        }
      } catch(e:Exception) {if(current===client){catalogLoading=false;message="API unavailable: ${e.message}"}}
      delay(2000)
    }
  }
  Box(Modifier.fillMaxSize()) {
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
          methodKey=null
          bankKey=null
          showMethods=false
          showBanks=false
          catalogLoading=true
        }catch(e:Exception){catalogLoading=false;message=e.message?:"Invalid configuration"}
      },enabled=!busy){Text("Connect")}
      Text(message)
      if(catalogLoading && state==null) SelectorSkeleton()
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
        if(catalogLoading && catalog==null) {
          SelectorSkeleton()
        } else if(selected!=null) {
          CatalogChoiceButton(
            title = selected.providerName,
            subtitle = "${selected.methodLabel} · ${eligibilityLabel(selected.eligible)}",
            logo = selected.logoLabel,
            enabled = !review && !busy,
          ) { showMethods = true }
        } else if(catalog!=null) {
          val groups = methodGroups(catalog?.providers.orEmpty())
          if(groups.isEmpty()) Text(methodSelectorEmptyMessage)
          else Button(onClick={showMethods=true},enabled=!review&&!busy){Text("Choose payment method")}
        }
        if(selected != null && selected.requiresBank) {
          val banks = selected.banks
          val chosen = banks.firstOrNull { it.id==bankKey }
          when {
            banks.isEmpty() -> TextButton(onClick={showBanks=true},enabled=!review&&!busy){Text(bankSelectorEmptyMessage)}
            chosen!=null -> CatalogChoiceButton(chosen.name, "Bank", logoLabel(chosen.name), !review&&!busy) { showBanks=true }
            else -> Button(onClick={showBanks=true},enabled=!review&&!busy){Text("Choose a bank")}
          }
        }
        if(!review) Button(onClick={
          val failure=selectionError(amount, selected, bankKey)
          if(failure!=null) message=failure
          else {review=true;paymentKey=UUID.randomUUID().toString();message="Review before confirming. No real money moves."}
        },enabled=!busy){Text("Review payment")}
        else {
          Text(confirmTitle(amount, recipient, selected, bankKey))
          Button(onClick={
            val active=client
            val failure=selectionError(amount, selected, bankKey)
            val method=selected?.let { payableMethod(it.method) }
            if(failure!=null){message=failure}
            else if(active!=null&&method!=null&&!busy){busy=true;revision++;scope.launch{
              try {
                val minor=parseAmount(amount).first ?: return@launch
                val result=active.submitPayment(recipientId=recipient,amountMinor=minor,method=method,note=note,idempotencyKey=paymentKey)
                if(result.ok){state=result.state;review=false;amount="";note="";paymentKey=UUID.randomUUID().toString();message="Demo payment complete"}
                else message=result.error?:"Awaiting confirmation. Retry the same payment."
              }catch(e:Exception){message="Outcome may be unknown: ${e.message}. Retry keeps the same key."}finally{revision++;busy=false}
            }}
          },enabled=!busy){Text(if(busy)"Confirming…" else "Confirm payment")}
          TextButton(onClick={review=false;paymentKey=UUID.randomUUID().toString()},enabled=!busy){Text("Edit details")}
        }
        Text("Recent activity",style=MaterialTheme.typography.h6)
        current.transactions.reversed().take(8).forEach {transaction->Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")}
        Text("Budgets",style=MaterialTheme.typography.h6)
        current.budgets.forEach {budget->Text("${budget.category} · ${money(budget.limit)}")}
      }
    }
    if(showMethods) {
      SelectorOverlay("Payment method", fullScreen, { showMethods=false }) {
        MethodSelectorContent(catalogLoading && catalog==null, methodGroups(catalog?.providers.orEmpty()), methodKey) { choice ->
          if(choice.eligible) {
            val next=reconciledSelection(SelectionState(choice.id, null), catalog?.providers.orEmpty())
            methodKey=next.methodId
            bankKey=next.bankId
            showMethods=false
          }
        }
      }
    } else if(showBanks && selected!=null) {
      SelectorOverlay("Choose a bank", fullScreen, { showBanks=false }) {
        BankSelectorContent(catalogLoading && catalog==null, selected.banks, bankKey) { bank ->
          bankKey=bank.id
          showBanks=false
        }
      }
    }
  }
}

private fun selectionError(amount: String, choice: MethodChoice?, bankKey: String?): String? {
  val parsed=parseAmount(amount)
  if(parsed.first==null) return parsed.second ?: "Invalid amount"
  if(choice==null || !choice.eligible) return "Select an available payment method"
  if(payableMethod(choice.method)==null) return "This payment method cannot be submitted"
  if(choice.requiresBank && choice.banks.isNotEmpty() && bankKey==null) return "Choose a bank to continue"
  return null
}

private fun confirmTitle(amount: String, recipient: String, choice: MethodChoice?, bankKey: String?): String {
  val bank = choice?.banks?.firstOrNull { it.id == bankKey }?.name
  val via = choice?.let { " via ${it.providerName}" }.orEmpty()
  val withBank = bank?.let { ", $it" }.orEmpty()
  return "Confirm £$amount to $recipient$via$withBank"
}
