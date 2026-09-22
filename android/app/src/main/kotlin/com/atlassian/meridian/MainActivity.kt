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
import com.atlassian.meridian.ui.MeridianAppTheme
import com.atlassian.meridian.ui.MeridianTheme
import com.atlassian.meridian.ui.OnboardingCarousel
import com.atlassian.meridian.ui.OnboardingPage
import com.atlassian.meridian.ui.ProviderListSection
import com.atlassian.meridian.ui.SessionBanner
import com.atlassian.meridian.ui.SessionState
import com.atlassian.meridian.ui.TokenIllustration
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    // MeridianAppTheme publishes the semantic design tokens and selects light/dark automatically.
    setContent { MeridianAppTheme { MeridianScreen() } }
  }
}

/**
 * Onboarding pages shown by the new carousel. Illustrations use token-colored blocks (no bundled
 * image assets) so the component stays self-contained for the internal dogfood build.
 */
private val onboardingPages: List<OnboardingPage>
  @Composable get() {
    val tokens = MeridianTheme.colors
    return listOf(
      OnboardingPage(
        title = "Rehearse payments safely",
        body = "A fictional GBP sandbox. No real money ever moves.",
        illustration = { m -> TokenIllustration(tokens.accent, m) },
      ),
      OnboardingPage(
        title = "Know your session at a glance",
        body = "The banner shows whether you're signed in before you pay.",
        illustration = { m -> TokenIllustration(tokens.bannerReauthBackground, m) },
      ),
      OnboardingPage(
        title = "Live provider catalog",
        body = "Available payment methods stay current without a reload.",
        illustration = { m -> TokenIllustration(tokens.bannerActiveBackground, m) },
      ),
      OnboardingPage(
        title = "Add your credit card",
        body = "Card number, expiry and CVV, grouped for quick entry.",
        illustration = { m -> TokenIllustration(tokens.bannerExpiringBackground, m) },
      ),
    )
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
  // New authentication-experience state (gated behind FeatureFlags.dynamicAuthExperience).
  val flagOn = FeatureFlags.dynamicAuthExperience
  var expiry by remember { mutableStateOf("") }
  var cvv by remember { mutableStateOf("") }
  // Catalog fetch outcome, tracked separately so the last-known provider list stays visible on error.
  var catalogError by remember { mutableStateOf<String?>(null) }
  var catalogLoading by remember { mutableStateOf(false) }
  var catalogRetryTick by remember { mutableStateOf(0) }
  // Presentation-layer session state derived from connection/refresh outcomes. This is independent
  // of the catalog fetch: a catalog error never changes the session banner state.
  val sessionState = remember(client, state, catalogRetryTick) {
    when {
      client == null -> SessionState.SignedOut
      state == null -> SessionState.Checking
      else -> SessionState.Active
    }
  }
  LaunchedEffect(client) {
    val current=client
    while(current!=null) {
      val started=revision
      if(!busy) {
        try {
          val fresh=current.getState()
          if(current===client && started==revision && !busy) {state=fresh;message="Connected to shared Java API"}
        } catch(e:Exception) {if(current===client)message="API unavailable: ${e.message}"}
        // Catalog fetch is independent of session/state: failures keep the last-known catalog and
        // surface a non-blocking inline error with retry, they do not block the banner or sign-in.
        if(catalog==null) catalogLoading=true
        try {
          val definitions=current.getCatalog()
          if(current===client && started==revision) {catalog=definitions;catalogError=null}
        } catch(e:Exception) {if(current===client) catalogError="We couldn't load payment methods."}
        finally { catalogLoading=false }
      }
      delay(2000)
    }
  }
  Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
    Text("meridian",style=MaterialTheme.typography.h4)
    Text("Native Android · simulated GBP payments",style=MaterialTheme.typography.caption)
    // New: session banner announces state via a TalkBack live region. It sits above the primary
    // sign-in action so it never wraps or blocks it, and it does not wait on the catalog fetch.
    if(flagOn) SessionBanner(state=sessionState)
    // New: onboarding carousel with page-indicator dots, shown before sign-in.
    if(flagOn && client==null) OnboardingCarousel(pages=onboardingPages)
    OutlinedTextField(base,{base=it},label={Text("API base URL")},enabled=!busy)
    OutlinedTextField(room,{room=it},label={Text("Shared rehearsal room")},enabled=!busy)
    Button(onClick={
      if(!Regex("[A-Za-z0-9_-]{3,64}").matches(room)){message="Invalid room"}
      else try {client=MeridianClient(base,room);state=null;catalog=null;catalogError=null;review=false;revision++;paymentKey=UUID.randomUUID().toString()}catch(e:Exception){message=e.message?:"Invalid configuration"}
    },enabled=!busy){Text(if(flagOn) "Sign in" else "Connect")}
    Text(message)
    // New: provider list with skeleton loader + non-blocking inline error/retry, gated behind flag.
    if(flagOn && client!=null) ProviderListSection(
      providers=catalog?.providers ?: emptyList(),
      isInitialLoading=catalogLoading,
      errorMessage=catalogError,
      onRetry={ catalogError=null; catalogLoading=true; catalogRetryTick++; val active=client
        if(active!=null) scope.launch {
          try { val definitions=active.getCatalog(); if(active===client){catalog=definitions;catalogError=null} }
          catch(e:Exception){ if(active===client) catalogError="We couldn't load payment methods." }
          finally { catalogLoading=false }
        } else catalogLoading=false
      },
    )
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
      // New: grouped expiry/CVV two-up field row, shown for card entry. Presentation-only — these
      // values are not stored or submitted (no real card credentials handled).
      if(flagOn && method==PaymentMethod.card) ExpiryCvvRow(expiry=expiry,onExpiryChange={expiry=it},cvv=cvv,onCvvChange={cvv=it},enabled=!review&&!busy)
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
