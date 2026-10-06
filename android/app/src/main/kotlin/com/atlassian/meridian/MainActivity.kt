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
import androidx.compose.ui.platform.testTag
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
  var review by remember { mutableStateOf(false) }
  var busy by remember { mutableStateOf(false) }
  var paymentKey by remember { mutableStateOf(UUID.randomUUID().toString()) }
  var message by remember { mutableStateOf("Fictional payment rehearsal. Connect to the Java API.") }
  var revision by remember { mutableStateOf(0) }
  var sessionExpiresAtMs by remember { mutableStateOf<Long?>(null) }
  var sessionElsewhere by remember { mutableStateOf(false) }
  var sessionProbe by remember { mutableStateOf(SessionProbeResult.NotSignedIn) }
  var nowMs by remember { mutableStateOf(SessionBanner.nowMs()) }
  var refreshingSession by remember { mutableStateOf(false) }

  fun snapshotContext() = PaymentContext(
    recipientId = recipient,
    amount = amount,
    reference = note,
    method = method,
    reviewing = review,
    idempotencyKey = paymentKey,
  )

  fun currentClock() = SessionClock(
    sessionId = if (client == null) null else room,
    expiresAtMs = sessionExpiresAtMs,
    activeElsewhere = sessionElsewhere,
    probe = if (client == null) SessionProbeResult.NotSignedIn else sessionProbe,
  )

  fun applyClock(clock: SessionClock) {
    sessionExpiresAtMs = clock.expiresAtMs
    sessionElsewhere = clock.activeElsewhere
    sessionProbe = clock.probe
  }

  val presentation = SessionBanner.present(nowMs, currentClock())

  fun connect(preserve: Boolean) {
    if (!Regex("[A-Za-z0-9_-]{3,64}").matches(room)) {
      message = "Invalid room"
      return
    }
    try {
      val kept = snapshotContext()
      client = MeridianClient(base, room)
      if (!preserve) {
        state = null
        catalog = null
        review = false
        paymentKey = UUID.randomUUID().toString()
      }
      val signedIn = SessionActions.signIn(
        nowMs = SessionBanner.nowMs(),
        sessionId = room,
        context = if (preserve) kept else snapshotContext(),
      )
      applyClock(signedIn.clock)
      revision++
    } catch (e: Exception) {
      message = e.message ?: "Invalid configuration"
    }
  }

  // Session recovery updates the clock only. Amount, recipient, reference, method, review, and the payment key stay as entered.
  fun extendCurrentSession() {
    val active = client ?: return
    if (refreshingSession) return
    val clock = currentClock()
    val kept = snapshotContext()
    refreshingSession = true
    scope.launch {
      try {
        val payload = active.refreshSession()
        val updated = SessionActions.refresh(
          nowMs = SessionBanner.nowMs(),
          clock = clock,
          context = kept,
          activeElsewhere = payload.activeElsewhere,
        )
        applyClock(updated.clock)
      } catch (e: Exception) {
        val updated = SessionActions.noteFailure(clock, kept, SessionActions.classify(e))
        applyClock(updated.clock)
      } finally {
        refreshingSession = false
      }
    }
  }

  LaunchedEffect(Unit) {
    while (true) {
      nowMs = SessionBanner.nowMs()
      delay(1000)
    }
  }
  LaunchedEffect(client) {
    val current=client
    while(current!=null) {
      val started=revision
      if(!busy && !refreshingSession) try {
        val fresh=current.getState(); val definitions=current.getCatalog()
        if(current===client && started==revision && !busy && !refreshingSession) {
          state=fresh
          catalog=definitions
          message="Connected to shared Java API"
          if (sessionProbe != SessionProbeResult.Rejected) sessionProbe = SessionProbeResult.Confirmed
        }
      } catch(e:Exception) {
        if(current===client && !refreshingSession) {
          message="API unavailable: ${e.message}"
          val updated = SessionActions.noteFailure(currentClock(), snapshotContext(), SessionActions.classify(e))
          applyClock(updated.clock)
        }
      }
      delay(2000)
    }
  }
  Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
    Text("meridian",style=MaterialTheme.typography.h4)
    Text("Native Android · simulated GBP payments",style=MaterialTheme.typography.caption)
    SessionStatusBanner(presentation, refreshingSession) {
      when (presentation.state) {
        SessionVisualState.SignedOut -> connect(preserve = true)
        SessionVisualState.Expiring, SessionVisualState.Expired, SessionVisualState.Unknown -> extendCurrentSession()
        SessionVisualState.Active, SessionVisualState.ActiveElsewhere -> Unit
      }
    }
    OutlinedTextField(base,{base=it},label={Text("API base URL")},enabled=!busy,modifier=Modifier.fillMaxWidth().testTag(SessionAccessibility.endpoint))
    OutlinedTextField(room,{room=it},label={Text("Shared rehearsal room")},enabled=!busy,modifier=Modifier.fillMaxWidth().testTag(SessionAccessibility.room))
    Button(onClick={ connect(preserve = false) },enabled=!busy,modifier=Modifier.testTag(SessionAccessibility.connect)){Text("Connect")}
    Text(message)
    state?.let { current ->
      Column(Modifier.testTag(SessionAccessibility.paymentForm), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Card(backgroundColor=Color(0xFF142C35),contentColor=Color.White,modifier=Modifier.fillMaxWidth()) {
          Column(Modifier.padding(22.dp)){Text("Everyday account");Text(money(current.balance),style=MaterialTheme.typography.h3);Text("Room: $room")}
        }
        Text("Make a payment",style=MaterialTheme.typography.h6)
        catalog?.recipients?.forEach { person ->
          Row {RadioButton(selected=recipient==person.id,onClick={recipient=person.id},enabled=!review&&!busy&&!presentation.blocksPaymentEntry);Text(person.name,Modifier.padding(top=12.dp))}
        }
        OutlinedTextField(amount,{amount=it},label={Text("Amount (GBP)")},enabled=!review&&!busy&&!presentation.blocksPaymentEntry)
        OutlinedTextField(note,{note=it.take(200)},label={Text("Reference")},enabled=!review&&!busy&&!presentation.blocksPaymentEntry)
        // Intentional two-provider native baseline; changing it requires an app release.
        Row {RadioButton(method==PaymentMethod.card,{method=PaymentMethod.card},enabled=!review&&!busy&&!presentation.blocksPaymentEntry);Text("Debit card · Adyen",Modifier.padding(top=12.dp))}
        Row {RadioButton(method==PaymentMethod.bank,{method=PaymentMethod.bank},enabled=!review&&!busy&&!presentation.blocksPaymentEntry);Text("Bank payment · Worldpay",Modifier.padding(top=12.dp))}
        if(!review) Button(onClick={val parsed=parseAmount(amount);if(parsed.first==null)message=parsed.second?:"Invalid amount" else {review=true;paymentKey=UUID.randomUUID().toString()}},enabled=!busy&&!presentation.blocksPaymentEntry){Text("Review payment")}
        else {
          Text("Confirm £$amount to $recipient")
          Button(onClick={val active=client;val minor=parseAmount(amount).first;if(active!=null&&minor!=null&&!busy){busy=true;revision++;scope.launch{
            try {val result=active.submitPayment(recipientId=recipient,amountMinor=minor,method=method,note=note,idempotencyKey=paymentKey)
              if(result.ok){state=result.state;review=false;amount="";note="";paymentKey=UUID.randomUUID().toString();message="Demo payment complete"}
              else message=result.error?:"Awaiting confirmation. Retry the same payment."
            }catch(e:Exception){message="Outcome may be unknown: ${e.message}. Retry keeps the same key."}finally{revision++;busy=false}
          }}},enabled=!busy&&!presentation.blocksPaymentEntry){Text(if(busy)"Confirming…" else "Confirm payment")}
          TextButton(onClick={review=false;paymentKey=UUID.randomUUID().toString()},enabled=!busy&&!presentation.blocksPaymentEntry){Text("Edit details")}
        }
        Text("Recent activity",style=MaterialTheme.typography.h6)
        current.transactions.reversed().take(8).forEach {transaction->Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")}
        Text("Budgets",style=MaterialTheme.typography.h6)
        current.budgets.forEach {budget->Text("${budget.category} · ${money(budget.limit)}")}
      }
    }
  }
}
