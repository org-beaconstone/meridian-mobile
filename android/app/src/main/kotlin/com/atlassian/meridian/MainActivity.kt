package com.atlassian.meridian

import android.content.Context
import android.content.Intent
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
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

class MainActivity : ComponentActivity() {
  private val returnUrl = mutableStateOf<String?>(null)

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    returnUrl.value = intent?.dataString
    setContent { MaterialTheme(colors = lightColors(primary = Color(0xFF142C35), secondary = Color(0xFFD5B77A))) { MeridianScreen(returnUrl) } }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    returnUrl.value = intent.dataString
  }
}

@Composable fun MeridianScreen(returnUrl: MutableState<String?>) {
  val scope = rememberCoroutineScope()
  val context = LocalContext.current
  val prefs = remember { context.getSharedPreferences("meridian", Context.MODE_PRIVATE) }
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
  val journal = remember {
    IdempotencyJournal.restore(prefs.getString(IdempotencyJournal.snapshotDefaultsKey, IdempotencyJournal.emptySnapshot) ?: IdempotencyJournal.emptySnapshot)
  }
  val returns = remember { ReturnStateGuard() }
  val catalogCache = remember { CatalogCache() }
  fun persist() {
    prefs.edit().putString(IdempotencyJournal.snapshotDefaultsKey, journal.snapshot()).apply()
  }
  fun unfinishedElsewhere() = journal.status == "uncertain" && journal.sessionId != room
  LaunchedEffect(returnUrl.value) {
    val link = returnUrl.value ?: return@LaunchedEffect
    returns.select(room)
    message = returns.userMessage(returns.openUrl(link, System.currentTimeMillis()))
    returnUrl.value = null
  }
  LaunchedEffect(client) {
    val current = client
    while (current != null) {
      val started = revision
      val now = System.currentTimeMillis()
      if (!busy) try {
        val fresh = current.getState()
        val definitions = current.getCatalog()
        if (current === client && started == revision && !busy) {
          when (val decoded = decodeLiveCatalog(definitions)) {
            is Decoded.Err -> message = "Catalog rejected: ${decoded.error.code}"
            is Decoded.Ok -> {
              catalogCache.store(room, decoded.value, now, CatalogCache.defaultTtlMillis)
              state = fresh
              catalog = definitions
              message = if (unfinishedElsewhere()) "An unfinished payment is still open in ${journal.sessionId}. Reconnect to that room to retry it." else "Connected to shared Java API"
            }
          }
        }
      } catch (e: Exception) {
        if (current === client) {
          when (catalogCache.read(room, now)) {
            "expired" -> {
              catalog = null
              message = "Catalog cache expired. Reconnect before paying."
            }
            "hit" -> message = "API unavailable. Cached catalog is still inside its lifetime."
            else -> message = "API unavailable: ${e.message}"
          }
        }
      }
      delay(2000)
    }
  }
  Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
    Text("meridian", style = MaterialTheme.typography.h4)
    Text("Native Android · simulated GBP payments", style = MaterialTheme.typography.caption)
    OutlinedTextField(base, { base = it }, label = { Text("API base URL") }, enabled = !busy)
    OutlinedTextField(room, { room = it }, label = { Text("Shared rehearsal room") }, enabled = !busy)
    Button(
      onClick = {
        if (!Regex("[A-Za-z0-9_-]{3,64}").matches(room)) message = "Invalid room"
        else {
          returns.select(room)
          client = try {
            MeridianClient(base, room)
          } catch (e: Exception) {
            message = e.message ?: "Invalid configuration"
            null
          }
          if (client != null) {
            state = null
            catalog = null
            review = false
            revision++
            if (unfinishedElsewhere()) message = "An unfinished payment is still open in ${journal.sessionId}. Reconnect to that room to retry it."
          }
        }
      },
      enabled = !busy,
      modifier = Modifier.defaultMinSize(minHeight = 48.dp).semantics { contentDescription = AccessibilityCatalog.node("connect")!!.talkBackDescription },
    ) { Text(AccessibilityCatalog.node("connect")!!.talkBackDescription) }
    Text(message)
    state?.let { current ->
      Card(backgroundColor = Color(0xFF142C35), contentColor = Color.White, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(22.dp)) {
          Text("Everyday account")
          CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
            Text(
              money(current.balance),
              style = MaterialTheme.typography.h3,
              modifier = Modifier.semantics { contentDescription = "${AccessibilityCatalog.node("balance")!!.talkBackDescription}, ${money(current.balance)}" },
            )
          }
          Text("Room: $room")
        }
      }
      Text("Make a payment", style = MaterialTheme.typography.h6)
      catalog?.recipients?.forEach { person ->
        Row { RadioButton(selected = recipient == person.id, onClick = { recipient = person.id }, enabled = !review && !busy); Text(person.name, Modifier.padding(top = 12.dp)) }
      }
      OutlinedTextField(
        amount,
        { amount = it },
        label = { Text("Amount (GBP)") },
        enabled = !review && !busy,
        modifier = Modifier.semantics { contentDescription = AccessibilityCatalog.node("amount-input")!!.talkBackDescription },
      )
      OutlinedTextField(note, { note = it.take(200) }, label = { Text("Reference") }, enabled = !review && !busy)
      // Intentional two-provider native baseline; changing it requires an app release.
      Row(Modifier.defaultMinSize(minHeight = 48.dp).semantics { contentDescription = AccessibilityCatalog.node("method-card")!!.talkBackDescription }) {
        RadioButton(method == PaymentMethod.card, { method = PaymentMethod.card }, enabled = !review && !busy)
        Text(AccessibilityCatalog.node("method-card")!!.talkBackDescription, Modifier.padding(top = 12.dp))
      }
      Row(Modifier.defaultMinSize(minHeight = 48.dp).semantics { contentDescription = AccessibilityCatalog.node("method-bank")!!.talkBackDescription }) {
        RadioButton(method == PaymentMethod.bank, { method = PaymentMethod.bank }, enabled = !review && !busy)
        Text(AccessibilityCatalog.node("method-bank")!!.talkBackDescription, Modifier.padding(top = 12.dp))
      }
      if (!review) Button(
        onClick = {
          val parsed = parseAmount(amount)
          if (parsed.first == null) message = parsed.second ?: "Invalid amount"
          else if (unfinishedElsewhere()) message = "Finish the unfinished payment in ${journal.sessionId} before starting another."
          else if (journal.status == "uncertain") {
            paymentKey = journal.key ?: paymentKey
            review = true
            message = "Retry uses the original payment key."
          } else {
            if (journal.status == "draft") journal.discardDraft()
            val next = UUID.randomUUID().toString()
            val failure = journal.begin(room, next, recipient, "GBP", parsed.first!!, 2, method.name, note)
            if (failure != null) message = failure.message
            else {
              persist()
              paymentKey = next
              review = true
            }
          }
        },
        enabled = !busy,
        modifier = Modifier.defaultMinSize(minHeight = 48.dp).semantics { contentDescription = AccessibilityCatalog.node("review-payment")!!.talkBackDescription },
      ) { Text(AccessibilityCatalog.node("review-payment")!!.talkBackDescription) }
      else {
        Text("Confirm £$amount to $recipient")
        Button(
          onClick = {
            val active = client
            val minor = parseAmount(amount).first
            if (unfinishedElsewhere()) message = "Finish the unfinished payment in ${journal.sessionId} before paying here."
            else if (active != null && minor != null && !busy && (journal.status == "draft" || journal.status == "uncertain")) {
              val retained = journal.retry(note, recipient, minor, method.name, "GBP")
              if (retained is Decoded.Err) {
                message = "Retry the same payment. The payment key is unchanged."
              } else if (retained is Decoded.Ok) {
                busy = true
                revision++
                paymentKey = retained.value
                journal.markUncertain()
                persist()
                scope.launch {
                  try {
                    val result = active.submitPayment(recipientId = recipient, amountMinor = minor, method = method, note = note, idempotencyKey = paymentKey)
                    if (result.ok) {
                      state = result.state
                      journal.markCompleted()
                      persist()
                      review = false
                      amount = ""
                      note = ""
                      paymentKey = UUID.randomUUID().toString()
                      message = "Demo payment complete"
                    } else {
                      result.paymentId?.let { paymentId ->
                        returns.select(room)
                        returns.arm(room, paymentId, paymentKey, System.currentTimeMillis() + 300_000, paymentKey)
                      }
                      message = result.error ?: "Awaiting confirmation. Retry the same payment."
                    }
                  } catch (e: Exception) {
                    message = "Outcome may be unknown: ${e.message}. Retry keeps the same key."
                  } finally {
                    revision++
                    busy = false
                  }
                }
              }
            }
          },
          enabled = !busy,
          modifier = Modifier.defaultMinSize(minHeight = 48.dp).semantics { contentDescription = AccessibilityCatalog.node("confirm-payment")!!.talkBackDescription },
        ) { Text(if (busy) "Confirming…" else AccessibilityCatalog.node("confirm-payment")!!.talkBackDescription) }
        TextButton(
          onClick = {
            if (journal.status == "uncertain") message = "Retry the same payment. The payment key is unchanged."
            else {
              journal.discardDraft()
              persist()
              review = false
              paymentKey = UUID.randomUUID().toString()
            }
          },
          enabled = !busy,
          modifier = Modifier.semantics { contentDescription = "Edit details" },
        ) { Text("Edit details") }
      }
      Text("Recent activity", style = MaterialTheme.typography.h6)
      current.transactions.reversed().take(8).forEach { transaction ->
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
          Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")
        }
      }
      Text("Budgets", style = MaterialTheme.typography.h6)
      current.budgets.forEach { budget ->
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
          Text("${budget.category} · ${money(budget.limit)}")
        }
      }
    }
  }
}
