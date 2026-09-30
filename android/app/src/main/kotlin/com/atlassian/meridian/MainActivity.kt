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
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val snapshotFile = File(filesDir, "meridian-intent-snapshots.json")
    setContent {
      MaterialTheme(colors = lightColors(primary = Color(0xFF142C35), secondary = Color(0xFFD5B77A))) {
        MeridianScreen(snapshotFile)
      }
    }
  }
}

@Composable
fun MeridianScreen(snapshotFile: File) {
  val scope = rememberCoroutineScope()
  val store = remember(snapshotFile) { FileIntentSnapshotStore(snapshotFile) }
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
  var handoff by remember { mutableStateOf<IntentSnapshot?>(null) }

  val statusAction = handoff?.let { recoveryAction(it) }
  val statusLocked = statusAction is RecoveryAction.Poll || statusAction is RecoveryAction.HoldUnknown

  suspend fun poll(active: MeridianClient, intentId: String, ownsBusy: Boolean = true) {
    if (ownsBusy) {
      if (busy) return
      busy = true
      revision++
    }
    message = recoveryFeedback(
      if (handoff?.phase == IntentPhase.pending) IntentPhase.pending else IntentPhase.processing,
    )
    try {
      val poller = PaymentStatusPoller(getIntent = { id -> active.getPaymentIntent(id) })
      val result = poller.poll(intentId)
      val current = handoff ?: store.load(room) ?: return
      val next = applying(result, current)
      store.save(next)
      handoff = next
      message = recoveryFeedback(next.phase)
      if (result.phase == IntentPhase.succeeded) {
        review = false
        amount = ""
        note = ""
        paymentKey = UUID.randomUUID().toString()
        state = runCatching { active.getState() }.getOrNull() ?: state
      }
    } finally {
      if (ownsBusy) {
        revision++
        busy = false
      }
    }
  }

  suspend fun recover(active: MeridianClient, saved: IntentSnapshot) {
    when (val action = recoveryAction(saved)) {
      is RecoveryAction.Poll -> poll(active, action.intentId)
      RecoveryAction.ShowReceipt -> message = recoveryFeedback(IntentPhase.succeeded)
      RecoveryAction.ShowDecline -> message = recoveryFeedback(IntentPhase.declined)
      RecoveryAction.HoldUnknown -> message = recoveryFeedback(IntentPhase.unknown)
    }
  }

  suspend fun submitCurrent(active: MeridianClient, minor: Int) {
    if (handoff?.phase == IntentPhase.declined) return
    val currentHandoff = handoff
    if (currentHandoff != null && recoveryAction(currentHandoff) is RecoveryAction.Poll) return
    try {
      val result = active.submitPayment(
        recipientId = recipient,
        amountMinor = minor,
        method = method,
        note = note,
        idempotencyKey = paymentKey,
      )
      val recipientName = catalog?.recipients?.firstOrNull { it.id == recipient }?.name ?: recipient
      val snapshot = IntentSnapshot(
        intentId = result.paymentId,
        sessionId = room,
        baseURL = base,
        idempotencyKey = paymentKey,
        recipientId = recipient,
        recipientName = result.transaction?.name ?: recipientName,
        amountMinor = result.transaction?.amount ?: minor,
        method = method.name,
        note = note,
        phase = phaseFor(result),
        supportReference = result.transaction?.reference,
        transaction = result.transaction,
        provider = result.transaction?.provider ?: baselineProvider(method.name),
        detail = result.error,
        updatedAt = isoTimestamp(),
      )
      if (result.state != null) state = result.state
      store.save(snapshot)
      handoff = snapshot
      when (snapshot.phase) {
        IntentPhase.succeeded -> {
          review = false
          amount = ""
          note = ""
          paymentKey = UUID.randomUUID().toString()
          message = recoveryFeedback(IntentPhase.succeeded)
        }
        IntentPhase.declined -> message = recoveryFeedback(IntentPhase.declined)
        else -> {
          val intentId = snapshot.intentId
          if (!intentId.isNullOrEmpty()) poll(active, intentId, ownsBusy = false)
          else message = recoveryFeedback(IntentPhase.unknown)
        }
      }
    } catch (_: Exception) {
      val recipientName = catalog?.recipients?.firstOrNull { it.id == recipient }?.name ?: recipient
      val snapshot = IntentSnapshot(
        intentId = handoff?.intentId,
        sessionId = room,
        baseURL = base,
        idempotencyKey = paymentKey,
        recipientId = recipient,
        recipientName = recipientName,
        amountMinor = minor,
        method = method.name,
        note = note,
        phase = IntentPhase.unknown,
        provider = baselineProvider(method.name),
        detail = recoveryFeedback(IntentPhase.unknown),
        updatedAt = isoTimestamp(),
      )
      store.save(snapshot)
      handoff = snapshot
      message = recoveryFeedback(IntentPhase.unknown)
    }
  }

  LaunchedEffect(snapshotFile) {
    val saved = store.latestRecoverable() ?: return@LaunchedEffect
    base = saved.baseURL
    room = saved.sessionId
    paymentKey = saved.idempotencyKey
    recipient = saved.recipientId
    method = if (saved.method == "bank") PaymentMethod.bank else PaymentMethod.card
    handoff = saved
    val active = try {
      MeridianClient(saved.baseURL, saved.sessionId)
    } catch (e: Exception) {
      message = e.message ?: "Invalid configuration"
      return@LaunchedEffect
    }
    client = active
    recover(active, saved)
  }

  LaunchedEffect(client) {
    val current = client
    while (current != null) {
      val started = revision
      if (!busy) {
        try {
          val fresh = current.getState()
          val definitions = current.getCatalog()
          if (current === client && started == revision && !busy) {
            state = fresh
            catalog = definitions
            if (handoff == null) message = "Connected to shared Java API"
          }
        } catch (e: Exception) {
          if (current === client && handoff == null) message = "API unavailable: ${e.message}"
        }
      }
      kotlinx.coroutines.delay(2000)
    }
  }

  Column(
    Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
    verticalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    Text("meridian", style = MaterialTheme.typography.h4)
    Text("Native Android · simulated GBP payments", style = MaterialTheme.typography.caption)
    OutlinedTextField(base, { base = it }, label = { Text("API base URL") }, enabled = !busy)
    OutlinedTextField(room, { room = it }, label = { Text("Shared rehearsal room") }, enabled = !busy)
    Button(
      onClick = {
        if (!Regex("[A-Za-z0-9_-]{3,64}").matches(room)) {
          message = "Invalid room"
        } else {
          val saved = store.load(room)
          try {
            val active = MeridianClient(base, room)
            client = active
            state = null
            catalog = null
            revision++
            if (saved != null) {
              handoff = saved
              paymentKey = saved.idempotencyKey
              recipient = saved.recipientId
              method = if (saved.method == "bank") PaymentMethod.bank else PaymentMethod.card
              review = false
              scope.launch { recover(active, saved) }
            } else {
              handoff = null
              review = false
              paymentKey = UUID.randomUUID().toString()
            }
          } catch (e: Exception) {
            message = e.message ?: "Invalid configuration"
          }
        }
      },
      enabled = !busy,
    ) { Text("Connect") }
    Text(message)
    handoff?.let { current ->
      if (current.phase == IntentPhase.succeeded) {
        val receipt = makeReceipt(current)
        Card(modifier = Modifier.fillMaxWidth()) {
          Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Payment complete", style = MaterialTheme.typography.h6)
            Text("Recipient")
            Text(receipt.recipientName)
            Text("Amount")
            Text(money(receipt.amountMinor))
            Text("Support reference")
            Text(receipt.supportReference)
            receipt.transactionId?.let { Text("Transaction $it") }
            receipt.transactionDate?.let { Text(it) }
            Text("${if (receipt.method == "bank") "Bank payment" else "Debit card"} · ${providerLabel(receipt.provider)}")
            if (!receipt.note.isNullOrEmpty()) Text(receipt.note)
          }
        }
      }
      if (current.phase == IntentPhase.declined) {
        Text(recoveryFeedback(IntentPhase.declined))
        Button(
          onClick = {
            store.remove(room)
            handoff = null
            review = false
            amount = ""
            note = ""
            paymentKey = UUID.randomUUID().toString()
            message = "Ready for a new demo payment."
          },
          enabled = !busy,
        ) { Text("New payment") }
      }
    }
    state?.let { current ->
      Card(backgroundColor = Color(0xFF142C35), contentColor = Color.White, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(22.dp)) {
          Text("Everyday account")
          Text(money(current.balance), style = MaterialTheme.typography.h3)
          Text("Room: $room")
        }
      }
      if (handoff?.phase != IntentPhase.declined) {
        Text("Make a payment", style = MaterialTheme.typography.h6)
        catalog?.recipients?.forEach { person ->
          Row {
            RadioButton(
              selected = recipient == person.id,
              onClick = { recipient = person.id },
              enabled = !review && !busy && !statusLocked,
            )
            Text(person.name, Modifier.padding(top = 12.dp))
          }
        }
        OutlinedTextField(
          amount,
          { amount = it },
          label = { Text("Amount (GBP)") },
          enabled = !review && !busy && !statusLocked,
        )
        OutlinedTextField(
          note,
          { note = it.take(200) },
          label = { Text("Reference") },
          enabled = !review && !busy && !statusLocked,
        )
        // Intentional two-provider native baseline; changing it requires an app release.
        Row {
          RadioButton(method == PaymentMethod.card, { method = PaymentMethod.card }, enabled = !review && !busy && !statusLocked)
          Text("Debit card · Adyen", Modifier.padding(top = 12.dp))
        }
        Row {
          RadioButton(method == PaymentMethod.bank, { method = PaymentMethod.bank }, enabled = !review && !busy && !statusLocked)
          Text("Bank payment · Worldpay", Modifier.padding(top = 12.dp))
        }
        if (statusLocked) {
          Text(recoveryFeedback(handoff?.phase ?: IntentPhase.processing))
          if (handoff?.intentId != null) {
            Button(
              onClick = {
                val active = client
                val intentId = handoff?.intentId
                if (active != null && intentId != null) scope.launch { poll(active, intentId) }
              },
              enabled = !busy,
            ) { Text("Check status again") }
          } else {
            Button(
              onClick = {
                val active = client
                val minor = parseAmount(amount).first
                if (active != null && minor != null && !busy) {
                  busy = true
                  revision++
                  scope.launch {
                    try {
                      submitCurrent(active, minor)
                    } finally {
                      revision++
                      busy = false
                    }
                  }
                }
              },
              enabled = !busy,
            ) { Text("Retry this payment") }
          }
        } else if (!review) {
          Button(
            onClick = {
              val parsed = parseAmount(amount)
              if (parsed.first == null) message = parsed.second ?: "Invalid amount"
              else {
                review = true
                paymentKey = UUID.randomUUID().toString()
              }
            },
            enabled = !busy,
          ) { Text("Review payment") }
        } else {
          Text("Confirm £$amount to $recipient")
          Button(
            onClick = {
              val active = client
              val minor = parseAmount(amount).first
              if (active != null && minor != null && !busy && handoff?.phase != IntentPhase.declined && statusAction !is RecoveryAction.Poll) {
                busy = true
                revision++
                scope.launch {
                  try {
                    submitCurrent(active, minor)
                  } finally {
                    revision++
                    busy = false
                  }
                }
              }
            },
            enabled = !busy,
          ) { Text(if (busy) "Confirming…" else "Confirm payment") }
          TextButton(
            onClick = { review = false; paymentKey = UUID.randomUUID().toString() },
            enabled = !busy,
          ) { Text("Edit details") }
        }
      }
      Text("Recent activity", style = MaterialTheme.typography.h6)
      current.transactions.reversed().take(8).forEach { transaction ->
        Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")
      }
      Text("Budgets", style = MaterialTheme.typography.h6)
      current.budgets.forEach { budget -> Text("${budget.category} · ${money(budget.limit)}") }
    }
  }
}
