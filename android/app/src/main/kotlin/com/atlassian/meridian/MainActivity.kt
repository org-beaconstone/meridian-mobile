package com.atlassian.meridian

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import android.util.Log
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.atlassian.meridian.ui.PaymentSessionBanner
import com.atlassian.meridian.ui.SessionBannerAnnouncer
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent {
      val dark = isSystemInDarkTheme()
      MaterialTheme(
        colors = if (dark) darkColors(
          primary = Color(0xFF142C35),
          secondary = Color(0xFFD5B77A),
          background = Color(0xFF0E1A1E),
          surface = Color(0xFF14282F),
          onPrimary = Color.White,
          onSecondary = Color(0xFF142C35),
          onBackground = Color.White,
          onSurface = Color.White,
        ) else lightColors(primary = Color(0xFF142C35), secondary = Color(0xFFD5B77A)),
      ) { MeridianScreen() }
    }
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
  // Session banner reads the rehearsal session already held by MeridianClient.
  // There is no separate auth screen and this does not add an auth request.
  var sessionLookup by remember { mutableStateOf(SessionLookup.Idle) }
  var sessionConfirmed by remember { mutableStateOf(false) }
  var connectedRoom by remember { mutableStateOf<String?>(null) }
  var dismissedBannerKeys by remember { mutableStateOf(emptySet<String>()) }
  val bannerMetrics = remember { SessionBannerMetrics() }
  var lastBannerImpression by remember { mutableStateOf<String?>(null) }
  var bannerAnnouncement by remember { mutableStateOf("") }
  val sessionSnapshot = paymentSessionSnapshot(
    clientConnected = client != null,
    lookup = sessionLookup,
    sessionId = connectedRoom,
    sessionConfirmed = sessionConfirmed,
  )
  val sessionBanner = resolveSessionBanner(sessionSnapshot, dismissedBannerKeys)
  LaunchedEffect(sessionBanner.liveIdentity) {
    when (val banner = sessionBanner) {
      is SessionBannerPresentation.Visible -> {
        bannerAnnouncement = banner.announcement
        if (banner.dismissalKey != lastBannerImpression) {
          bannerMetrics.recordImpression(banner.metricState)
          lastBannerImpression = banner.dismissalKey
        }
      }
      SessionBannerPresentation.Skeleton -> bannerAnnouncement = SessionBannerPresentation.Skeleton.announcement
      SessionBannerPresentation.Hidden -> Unit
    }
  }
  val dismissSessionBanner: () -> Unit = {
    val visible = sessionBanner as? SessionBannerPresentation.Visible
    if (visible != null && visible.dismissible) {
      val rate = bannerMetrics.recordDismissal(visible.metricState)
      Log.i("SessionBanner", rate.logLine())
      dismissedBannerKeys = dismissedBannerKeys + visible.dismissalKey
      bannerAnnouncement = SessionBannerCopy.DISMISSED
    }
  }
  LaunchedEffect(client) {
    val current=client
    while(current!=null) {
      val started=revision
      if(!busy) try {
        val fresh=current.getState(); val definitions=current.getCatalog()
        if(current===client && started==revision && !busy) {
          state=fresh
          catalog=definitions
          sessionConfirmed=true
          sessionLookup=SessionLookup.Ready
          message="Connected to shared Java API"
        }
      } catch(e:Exception) {
        if(current===client) {
          sessionLookup=SessionLookup.Failed
          message="API unavailable: ${e.message}"
        }
      }
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
      else try {
        client=MeridianClient(base,room)
        connectedRoom=room
        state=null
        catalog=null
        review=false
        revision++
        paymentKey=UUID.randomUUID().toString()
        sessionConfirmed=false
        sessionLookup=SessionLookup.Resolving
      } catch(e:Exception){message=e.message?:"Invalid configuration"}
    },enabled=!busy){Text("Connect")}
    Box {
      Text(message)
      SessionBannerAnnouncer(bannerAnnouncement)
    }
    if (state == null) PaymentSessionBanner(sessionBanner, onDismiss = dismissSessionBanner)
    state?.let { current ->
      Card(backgroundColor=Color(0xFF142C35),contentColor=Color.White,modifier=Modifier.fillMaxWidth()) {
        Column(Modifier.padding(22.dp)){Text("Everyday account");Text(money(current.balance),style=MaterialTheme.typography.h3);Text("Room: $room")}
      }
      Text("Make a payment",style=MaterialTheme.typography.h6)
      PaymentSessionBanner(sessionBanner, onDismiss = dismissSessionBanner)
      catalog?.recipients?.forEach { person ->
        Row {RadioButton(selected=recipient==person.id,onClick={recipient=person.id},enabled=!review&&!busy);Text(person.name,Modifier.padding(top=12.dp))}
      }
      OutlinedTextField(amount,{amount=it},label={Text("Amount (GBP)")},enabled=!review&&!busy)
      OutlinedTextField(note,{note=it.take(200)},label={Text("Reference")},enabled=!review&&!busy)
      // Intentional two-provider native baseline; changing it requires an app release.
      Row {RadioButton(method==PaymentMethod.card,{method=PaymentMethod.card},enabled=!review&&!busy);Text("Debit card · Adyen",Modifier.padding(top=12.dp))}
      Row {RadioButton(method==PaymentMethod.bank,{method=PaymentMethod.bank},enabled=!review&&!busy);Text("Bank payment · Worldpay",Modifier.padding(top=12.dp))}
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
