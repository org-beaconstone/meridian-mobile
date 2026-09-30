package com.atlassian.meridian

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.Button
import androidx.compose.material.Card
import androidx.compose.material.MaterialTheme
import androidx.compose.material.OutlinedTextField
import androidx.compose.material.RadioButton
import androidx.compose.material.Text
import androidx.compose.material.TextButton
import androidx.compose.material.lightColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent {
      MaterialTheme(colors = lightColors(primary = Color(0xFF142C35), secondary = Color(0xFFD5B77A))) {
        MeridianScreen()
      }
    }
  }
}

@Composable fun MeridianScreen() {
  val scope = rememberCoroutineScope()
  val controls = remember { CorridorControls() }
  var base by remember { mutableStateOf("http://10.0.2.2:8080/api/v1") }
  var room by remember { mutableStateOf("meridian-rehearsal") }
  var accountId by remember { mutableStateOf(room) }
  var client by remember { mutableStateOf<MeridianClient?>(null) }
  var state by remember { mutableStateOf<BankState?>(null) }
  var catalog by remember { mutableStateOf<CatalogResponse?>(null) }
  var recipient by remember { mutableStateOf("northline-studio") }
  var amount by remember { mutableStateOf("") }
  var note by remember { mutableStateOf("") }
  var methodId by remember { mutableStateOf("adyen-card-gb") }
  var review by remember { mutableStateOf(false) }
  var busy by remember { mutableStateOf(false) }
  var paymentKey by remember { mutableStateOf(UUID.randomUUID().toString()) }
  var message by remember { mutableStateOf("Fictional payment rehearsal. Connect to the Java API.") }
  var revision by remember { mutableStateOf(0) }
  var flagRevision by remember { mutableStateOf(0) }

  LaunchedEffect(client) {
    val current = client ?: return@LaunchedEffect
    val sessionAccount = accountId
    while (true) {
      val started = revision
      if (!busy) {
        try {
          val fresh = current.getState()
          val definitions = current.getCatalog()
          if (current === client && started == revision && !busy) {
            state = fresh
            catalog = definitions
            if (applyConfig(current, controls, sessionAccount)) flagRevision++
            message = if (controls.flags.killSwitch) PAYMENTS_PAUSED_MESSAGE else "Connected to shared Java API"
          }
        } catch (e: Exception) {
          if (current === client) message = "API unavailable: ${e.message}"
        }
      }
      delay(2000)
    }
  }

  LaunchedEffect(flagRevision, accountId) {
    val visible = controls.visibleMethods(accountId)
    if (visible.none { it.id == methodId }) {
      methodId = visible.firstOrNull()?.id ?: "adyen-card-gb"
    }
  }

  val methods = controls.visibleMethods(accountId)
  val killSwitch = controls.flags.killSwitch
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
          try {
            accountId = room
            client = MeridianClient(base, room)
            state = null
            catalog = null
            review = false
            revision++
            paymentKey = UUID.randomUUID().toString()
            controls.reset()
            methodId = "adyen-card-gb"
            flagRevision++
          } catch (e: Exception) {
            message = e.message ?: "Invalid configuration"
          }
        }
      },
      enabled = !busy,
    ) { Text("Connect") }
    Text(message)
    state?.let { current ->
      Card(backgroundColor = Color(0xFF142C35), contentColor = Color.White, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(22.dp)) {
          Text("Everyday account")
          Text(money(current.balance), style = MaterialTheme.typography.h3)
          Text("Room: $room")
        }
      }
      Text("Make a payment", style = MaterialTheme.typography.h6)
      if (killSwitch) Text(PAYMENTS_PAUSED_MESSAGE)
      catalog?.recipients?.forEach { person ->
        Row {
          RadioButton(
            selected = recipient == person.id,
            onClick = { recipient = person.id },
            enabled = !review && !busy && !killSwitch,
          )
          Text(person.name, Modifier.padding(top = 12.dp))
        }
      }
      OutlinedTextField(amount, { amount = it }, label = { Text("Amount (GBP)") }, enabled = !review && !busy && !killSwitch)
      OutlinedTextField(note, { note = it.take(200) }, label = { Text("Reference") }, enabled = !review && !busy && !killSwitch)
      // Adyen card and Worldpay bank stay hardcoded. Flags only show or hide those rails.
      if (methods.isEmpty()) Text("No payment methods are available for this account.")
      methods.forEach { rail ->
        Row {
          RadioButton(methodId == rail.id, { methodId = rail.id }, enabled = !review && !busy && !killSwitch)
          Text(rail.label, Modifier.padding(top = 12.dp))
        }
      }
      if (killSwitch) {
        Text("Status and receipts stay available below.")
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
          enabled = !busy && methods.isNotEmpty(),
        ) { Text("Review payment") }
      } else {
        Text("Confirm £$amount to $recipient")
        Button(
          onClick = {
            val active = client
            val minor = parseAmount(amount).first
            if (active != null && minor != null && !busy) {
              busy = true
              revision++
              val sessionAccount = accountId
              val keyAtConfirm = paymentKey
              scope.launch {
                try {
                  if (applyConfig(active, controls, sessionAccount)) flagRevision++
                  if (controls.blocksNewIntent(keyAtConfirm)) {
                    message = PAYMENTS_PAUSED_MESSAGE
                    return@launch
                  }
                  when (
                    val created = controls.createIntent(
                      keyAtConfirm,
                      sessionAccount,
                      recipient,
                      minor,
                      note,
                      methodId,
                    )
                  ) {
                    is IntentResult.Rejected -> message = created.reason.message
                    is IntentResult.Created -> {
                      val intent = created.intent
                      val result = active.submitPayment(
                        recipientId = intent.recipientId,
                        amountMinor = intent.amountMinor,
                        method = intent.method,
                        note = intent.note,
                        idempotencyKey = intent.idempotencyKey,
                      )
                      if (result.ok) {
                        controls.complete(intent.id, result.transaction?.reference ?: intent.id)
                        state = result.state
                        review = false
                        amount = ""
                        note = ""
                        paymentKey = UUID.randomUUID().toString()
                        message = "Demo payment complete"
                      } else if (result.code == "PAYMENT_PENDING") {
                        message = result.error ?: "Awaiting confirmation. Retry the same payment."
                      } else {
                        controls.markDeclined(intent.id)
                        message = result.error ?: "Awaiting confirmation. Retry the same payment."
                      }
                    }
                  }
                } catch (e: Exception) {
                  message = "Outcome may be unknown: ${e.message}. Retry keeps the same key."
                } finally {
                  revision++
                  busy = false
                }
              }
            }
          },
          enabled = !busy,
        ) { Text(if (busy) "Confirming…" else "Confirm payment") }
        TextButton(onClick = { review = false; paymentKey = UUID.randomUUID().toString() }, enabled = !busy) {
          Text("Edit details")
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

private suspend fun applyConfig(client: MeridianClient, controls: CorridorControls, accountId: String): Boolean {
  return try {
    val config = client.fetchConfig()
    if (!controls.applyServerPayload(config)) return false
    controls.resolve(accountId)
    true
  } catch (_: Exception) {
    false
  }
}
