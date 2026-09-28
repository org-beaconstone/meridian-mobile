package com.atlassian.meridian

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
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
    setContent { MaterialTheme(colors = lightColors(primary = Color(0xFF142C35), secondary = Color(0xFFD5B77A))) { MeridianScreen() } }
  }
}

@Composable fun MeridianScreen() {
  val scope = rememberCoroutineScope()
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
  var showMethods by remember { mutableStateOf(false) }
  val rails = catalog?.let { resolvePaymentRails(it.providers) }
  val selectedRail = rails?.firstOrNull { it.method == method }
  val methodReady = selectedRail?.selectable == true
  LaunchedEffect(client) {
    val current = client
    while (current != null) {
      val started = revision
      if (!busy) {
        try {
          val fresh = current.getState()
          if (current === client && started == revision && !busy) state = fresh
        } catch (e: Exception) {
          if (current === client) message = "API unavailable: ${e.message}"
          delay(2000)
          continue
        }
        try {
          val definitions = current.getCatalog()
          if (current === client && started == revision && !busy) {
            catalog = definitions
            message = "Connected to shared Java API"
          }
        } catch (e: Exception) {
          if (current === client) message = "API unavailable: ${e.message}"
        }
      }
      delay(2000)
    }
  }
  Box(Modifier.fillMaxSize()) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
      Text("meridian", style = MaterialTheme.typography.h4)
      Text("Native Android · simulated GBP payments", style = MaterialTheme.typography.caption)
      OutlinedTextField(base, { base = it }, label = { Text("API base URL") }, enabled = !busy)
      OutlinedTextField(room, { room = it }, label = { Text("Shared rehearsal room") }, enabled = !busy)
      Button(onClick = {
        if (!Regex("[A-Za-z0-9_-]{3,64}").matches(room)) message = "Invalid room"
        else try {
          client = MeridianClient(base, room)
          state = null
          catalog = null
          review = false
          showMethods = false
          revision++
          paymentKey = UUID.randomUUID().toString()
        } catch (e: Exception) {
          message = e.message ?: "Invalid configuration"
        }
      }, enabled = !busy) { Text("Connect") }
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
        catalog?.recipients?.forEach { person ->
          Row {
            RadioButton(selected = recipient == person.id, onClick = { recipient = person.id }, enabled = !review && !busy)
            Text(person.name, Modifier.padding(top = 12.dp))
          }
        }
        OutlinedTextField(amount, { amount = it }, label = { Text("Amount (GBP)") }, enabled = !review && !busy)
        OutlinedTextField(note, { note = it.take(200) }, label = { Text("Reference") }, enabled = !review && !busy)
        PaymentMethodSelector(
          loading = catalog == null,
          rails = rails ?: emptyList(),
          selected = method,
          enabled = !review && !busy,
          onOpen = { showMethods = true },
        )
        if (!review) {
          Button(onClick = {
            val parsed = parseAmount(amount)
            if (parsed.first == null) message = parsed.second ?: "Invalid amount"
            else if (!methodReady) message = if (catalog == null) "Payment methods are still loading." else regionalUnavailabilityWarning
            else {
              review = true
              showMethods = false
              paymentKey = UUID.randomUUID().toString()
            }
          }, enabled = !busy) { Text("Review payment") }
        } else {
          Text("Confirm £$amount to $recipient")
          selectedRail?.let { Text(it.badge) }
          Button(onClick = {
            val active = client
            val minor = parseAmount(amount).first
            if (selectedRail?.selectable != true) {
              message = regionalUnavailabilityWarning
              return@Button
            }
            if (active != null && minor != null && !busy) {
              busy = true
              revision++
              scope.launch {
                try {
                  val result = active.submitPayment(recipientId = recipient, amountMinor = minor, method = method, note = note, idempotencyKey = paymentKey)
                  if (result.ok) {
                    state = result.state
                    review = false
                    amount = ""
                    note = ""
                    paymentKey = UUID.randomUUID().toString()
                    message = "Demo payment complete"
                  } else message = result.error ?: "Awaiting confirmation. Retry the same payment."
                } catch (e: Exception) {
                  message = "Outcome may be unknown: ${e.message}. Retry keeps the same key."
                } finally {
                  revision++
                  busy = false
                }
              }
            }
          }, enabled = !busy && methodReady) { Text(if (busy) "Confirming…" else "Confirm payment") }
          TextButton(onClick = { review = false; paymentKey = UUID.randomUUID().toString() }, enabled = !busy) { Text("Edit details") }
        }
        Text("Recent activity", style = MaterialTheme.typography.h6)
        current.transactions.reversed().take(8).forEach { transaction ->
          Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")
        }
        Text("Budgets", style = MaterialTheme.typography.h6)
        current.budgets.forEach { budget -> Text("${budget.category} · ${money(budget.limit)}") }
      }
    }
    PaymentMethodBottomSheet(
      visible = showMethods,
      loading = catalog == null,
      rails = rails ?: emptyList(),
      selected = method,
      onSelect = { rail ->
        if (rail.selectable) {
          method = rail.method
          showMethods = false
        }
      },
      onDismiss = { showMethods = false },
    )
  }
}
