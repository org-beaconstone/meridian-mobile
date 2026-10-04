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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
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
  var presence by remember { mutableStateOf(SessionPresence.SIGNED_OUT) }
  var expiresAt by remember { mutableStateOf(0L) }
  var now by remember { mutableStateOf(System.currentTimeMillis()) }
  val phase = sessionPhase(presence, expiresAt, now)
  val sessionAllowsPayment = when (phase) {
    is SessionPhase.Banner -> phase.state != SessionBannerState.SIGNED_OUT
    SessionPhase.Reauthenticate -> false
  }
  fun refreshSessionFromBanner() {
    if (client == null && !Regex("[A-Za-z0-9_-]{3,64}").matches(room)) {
      message = "Invalid room"
      return
    }
    val refreshed = refreshSessionInPlace(
      PaymentFormDraft(recipient, amount, note, method, review, paymentKey),
      PaymentSessionClock(presence, expiresAt),
      System.currentTimeMillis(),
    )
    recipient = refreshed.draft.recipientId
    amount = refreshed.draft.amount
    note = refreshed.draft.reference
    method = refreshed.draft.method
    review = refreshed.draft.reviewing
    paymentKey = refreshed.draft.idempotencyKey
    presence = refreshed.session.presence
    expiresAt = refreshed.session.expiresAtEpochMs
    now = System.currentTimeMillis()
    if (client == null) {
      try {
        client = MeridianClient(base, room)
      } catch (e: Exception) {
        message = e.message ?: "Invalid configuration"
        return
      }
    }
    message = "Session refreshed. Payment details are unchanged."
  }
  fun applyPresence(next: SessionPresence) {
    when (next) {
      SessionPresence.SIGNED_OUT -> presence = SessionPresence.SIGNED_OUT
      SessionPresence.HERE -> refreshSessionFromBanner()
      SessionPresence.ELSEWHERE -> {
        if (presence == SessionPresence.SIGNED_OUT || now >= expiresAt) {
          refreshSessionFromBanner()
          presence = SessionPresence.ELSEWHERE
        } else {
          presence = SessionPresence.ELSEWHERE
        }
      }
    }
  }
  LaunchedEffect(Unit) {
    while (true) {
      now = System.currentTimeMillis()
      delay(1000)
    }
  }
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
  if (phase is SessionPhase.Reauthenticate) {
    AlertDialog(
      onDismissRequest = {},
      confirmButton = {
        Button(onClick = { refreshSessionFromBanner() }) { Text("Sign in again") }
      },
      title = { Text("Session expired") },
      text = { Text("Sign in again to continue this payment. Entered details stay on this screen.") },
      properties = DialogProperties(dismissOnBackPress = false, dismissOnClickOutside = false),
    )
  }
  Column(Modifier.fillMaxSize()) {
    if (phase is SessionPhase.Banner) {
      SessionStatusBanner(
        state = phase.state,
        remainingMillis = expiresAt - now,
        onRefresh = { refreshSessionFromBanner() },
      )
    }
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(24.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
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
          presence = SessionPresence.HERE
          expiresAt = System.currentTimeMillis() + PAYMENT_SESSION_TTL_MS
          now = System.currentTimeMillis()
        }catch(e:Exception){message=e.message?:"Invalid configuration"}
      },enabled=!busy){Text("Connect")}
      Text("Session", style = MaterialTheme.typography.caption)
      TextButton(onClick = { applyPresence(SessionPresence.HERE) }, modifier = Modifier.fillMaxWidth()) {
        Text("This device", fontWeight = if (presence == SessionPresence.HERE) FontWeight.Bold else FontWeight.Normal)
      }
      TextButton(onClick = { applyPresence(SessionPresence.ELSEWHERE) }, modifier = Modifier.fillMaxWidth()) {
        Text("Another device", fontWeight = if (presence == SessionPresence.ELSEWHERE) FontWeight.Bold else FontWeight.Normal)
      }
      TextButton(onClick = { applyPresence(SessionPresence.SIGNED_OUT) }, modifier = Modifier.fillMaxWidth()) {
        Text("Signed out", fontWeight = if (presence == SessionPresence.SIGNED_OUT) FontWeight.Bold else FontWeight.Normal)
      }
      TextButton(onClick = {
        presence = SessionPresence.HERE
        expiresAt = System.currentTimeMillis() - 1000
        now = System.currentTimeMillis()
      }) { Text("End session") }
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
        // Intentional two-provider native baseline; changing it requires an app release.
        Row {RadioButton(method==PaymentMethod.card,{method=PaymentMethod.card},enabled=!review&&!busy);Text("Debit card · Adyen",Modifier.padding(top=12.dp))}
        Row {RadioButton(method==PaymentMethod.bank,{method=PaymentMethod.bank},enabled=!review&&!busy);Text("Bank payment · Worldpay",Modifier.padding(top=12.dp))}
        if(!review) Button(onClick={val parsed=parseAmount(amount);if(parsed.first==null)message=parsed.second?:"Invalid amount" else {review=true;paymentKey=UUID.randomUUID().toString()}},enabled=!busy){Text("Review payment")}
        else {
          Text("Confirm £$amount to $recipient")
          Button(onClick={
            if (!sessionAllowsPayment) {
              message = "Restore the session before confirming this payment."
              return@Button
            }
            val active=client;val minor=parseAmount(amount).first;if(active!=null&&minor!=null&&!busy){busy=true;revision++;scope.launch{
            try {val result=active.submitPayment(recipientId=recipient,amountMinor=minor,method=method,note=note,idempotencyKey=paymentKey)
              if(result.ok){state=result.state;review=false;amount="";note="";paymentKey=UUID.randomUUID().toString();message="Demo payment complete"}
              else message=result.error?:"Awaiting confirmation. Retry the same payment."
            }catch(e:Exception){message="Outcome may be unknown: ${e.message}. Retry keeps the same key."}finally{revision++;busy=false}
          }}},enabled=!busy && sessionAllowsPayment){Text(if(busy)"Confirming…" else "Confirm payment")}
          TextButton(onClick={review=false;paymentKey=UUID.randomUUID().toString()},enabled=!busy){Text("Edit details")}
        }
        Text("Recent activity",style=MaterialTheme.typography.h6)
        current.transactions.reversed().take(8).forEach {transaction->Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")}
        Text("Budgets",style=MaterialTheme.typography.h6)
        current.budgets.forEach {budget->Text("${budget.category} · ${money(budget.limit)}")}
      }
    }
  }
}
