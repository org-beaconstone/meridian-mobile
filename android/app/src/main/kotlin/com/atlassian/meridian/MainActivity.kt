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
import com.atlassian.meridian.ui.ExpiryCvvRow
import com.atlassian.meridian.ui.FeatureFlags
import com.atlassian.meridian.ui.OnboardingCarousel
import com.atlassian.meridian.ui.OnboardingPage
import com.atlassian.meridian.ui.ProviderEmptyState
import com.atlassian.meridian.ui.ProviderErrorRetry
import com.atlassian.meridian.ui.ProviderRow
import com.atlassian.meridian.ui.ProviderSkeleton
import com.atlassian.meridian.ui.SessionBanner
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
  // New auth UI presentation state (gated behind FeatureFlags.revampedAuthUiEnabled).
  var catalogLoading by remember { mutableStateOf(false) }
  var catalogError by remember { mutableStateOf<String?>(null) }
  var expiry by remember { mutableStateOf("") }
  var cvv by remember { mutableStateOf("") }
  // Presentation-layer session state, derived purely from local state. It is
  // independent of the catalog fetch and never blocks the sign-in (Connect) action.
  val sessionState = when {
    client == null -> SessionState.signedOut
    state == null && busy -> SessionState.reauthenticating
    state == null -> SessionState.checking
    else -> SessionState.active
  }
  LaunchedEffect(client) {
    val current=client
    // The banner reflects signed-out immediately; the catalog fetch is separate.
    if(current!=null) catalogLoading = (catalog==null)
    while(current!=null) {
      val started=revision
      if(!busy) try {
        val fresh=current.getState(); val definitions=current.getCatalog()
        if(current===client && started==revision && !busy) {state=fresh;catalog=definitions;catalogError=null;catalogLoading=false;message="Connected to shared Java API"}
      } catch(e:Exception) {if(current===client){catalogLoading=false;catalogError="We couldn't load payment methods.";message="API unavailable: ${e.message}"}}
      delay(2000)
    }
  }
  Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
    Text("meridian",style=MaterialTheme.typography.h4)
    Text("Native Android · simulated GBP payments",style=MaterialTheme.typography.caption)
    if(FeatureFlags.revampedAuthUiEnabled) {
      // Session banner renders first and announces state changes via TalkBack.
      // It sits above the Connect button but never disables or delays it.
      SessionBanner(state=sessionState)
      if(sessionState==SessionState.signedOut || sessionState==SessionState.checking) {
        OnboardingCarousel(pages=meridianOnboardingPages)
      }
    }
    OutlinedTextField(base,{base=it},label={Text("API base URL")},enabled=!busy)
    OutlinedTextField(room,{room=it},label={Text("Shared rehearsal room")},enabled=!busy)
    Button(onClick={
      if(!Regex("[A-Za-z0-9_-]{3,64}").matches(room)){message="Invalid room"}
      else try {client=MeridianClient(base,room);state=null;catalog=null;review=false;revision++;paymentKey=UUID.randomUUID().toString()}catch(e:Exception){message=e.message?:"Invalid configuration"}
    },enabled=!busy){Text("Connect")}
    Text(message)
    state?.let { current ->
      Card(backgroundColor=Color(0xFF142C35),contentColor=Color.White,modifier=Modifier.fillMaxWidth()) {
        Column(Modifier.padding(22.dp)){Text("Everyday account");Text(money(current.balance),style=MaterialTheme.typography.h3);Text("Room: $room")}
      }
      if(FeatureFlags.revampedAuthUiEnabled) {
        Text("Payment methods",style=MaterialTheme.typography.h6)
        val providers=catalog?.providers
        when {
          // Skeleton while the catalog fetches — never a spinner over stale data.
          providers==null && catalogLoading -> ProviderSkeleton()
          // Zero providers should never happen in production: show it explicitly.
          providers!=null && providers.isEmpty() -> ProviderEmptyState()
          providers!=null -> providers.forEach { ProviderRow(it) }
        }
        // Non-blocking inline error keeps the last known list visible and offers retry.
        catalogError?.let { error ->
          ProviderErrorRetry(message="$error Retry",onRetry={revision++;catalogError=null;catalogLoading=(catalog==null)},enabled=!busy)
        }
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
      if(FeatureFlags.revampedAuthUiEnabled && method==PaymentMethod.card) {
        // Net-new grouped fields: expiry date and CVV as a two-up row.
        ExpiryCvvRow(expiry=expiry,onExpiryChange={expiry=it},cvv=cvv,onCvvChange={cvv=it},enabled=!review&&!busy)
      }
      if(!review) Button(onClick={val parsed=parseAmount(amount);if(parsed.first==null)message=parsed.second?:"Invalid amount" else {review=true;paymentKey=UUID.randomUUID().toString()}},enabled=!busy){Text("Review payment")}
      else {
        Text("Confirm £$amount to $recipient")
        Button(onClick={val active=client;val minor=parseAmount(amount).first;if(active!=null&&minor!=null&&!busy){busy=true;revision++;scope.launch{
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

/** Copy for the net-new onboarding carousel shown on the authentication screen. */
private val meridianOnboardingPages = listOf(
  OnboardingPage(
    title = "Welcome to Meridian",
    body = "A safe rehearsal space for GBP payments. No real money ever moves.",
  ),
  OnboardingPage(
    title = "Know your session at a glance",
    body = "The banner tells you when you're signed in, expiring, or signed out.",
  ),
  OnboardingPage(
    title = "Pay by card or bank",
    body = "Choose Adyen card or Worldpay bank and review before you confirm.",
  ),
  OnboardingPage(
    title = "Share a rehearsal room",
    body = "Everyone in the same room sees the same simulated account update live.",
  ),
)
