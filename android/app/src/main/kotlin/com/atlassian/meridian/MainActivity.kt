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
  val scope = rememberCoroutineScope()
  var base by remember { mutableStateOf("http://10.0.2.2:8080/api/v1") }
  var room by remember { mutableStateOf("meridian-rehearsal") }
  var client by remember { mutableStateOf<MeridianClient?>(null) }
  var state by remember { mutableStateOf<BankState?>(null) }
  var catalog by remember { mutableStateOf<CatalogResponse?>(null) }
  var recipient by remember { mutableStateOf("northline-studio") }
  var amount by remember { mutableStateOf("") }
  var note by remember { mutableStateOf("") }
  // Dynamic provider/method selection driven by the server catalog.
  var selectedProvider by remember { mutableStateOf<Provider?>(null) }
  var selectedMethod by remember { mutableStateOf<String?>(null) }
  var showMethodSheet by remember { mutableStateOf(false) }
  var showBankSheet by remember { mutableStateOf(false) }
  var review by remember { mutableStateOf(false) }
  var busy by remember { mutableStateOf(false) }
  var paymentKey by remember { mutableStateOf(UUID.randomUUID().toString()) }
  var message by remember { mutableStateOf("Fictional payment rehearsal. Connect to the Java API.") }
  var revision by remember { mutableStateOf(0) }

  val methodLabel = when {
    selectedProvider != null && selectedMethod != null -> {
      val methodName = if (selectedMethod == "card") "Card" else "Bank transfer"
      "$methodName · ${selectedProvider!!.name}"
    }
    else -> "Choose payment method"
  }

  LaunchedEffect(client) {
    val current = client
    while (current != null) {
      val started = revision
      if (!busy) try {
        val fresh = current.getState(); val definitions = current.getCatalog()
        if (current === client && started == revision && !busy) {
          state = fresh; catalog = definitions; message = "Connected to shared Java API"
        }
      } catch (e: Exception) { if (current === client) message = "API unavailable: ${e.message}" }
      delay(2000)
    }
  }

  // Payment method bottom sheet
  val methodSheetState = rememberModalBottomSheetState(ModalBottomSheetValue.Hidden, skipHalfExpanded = false)
  val bankSheetState = rememberModalBottomSheetState(ModalBottomSheetValue.Hidden, skipHalfExpanded = false)

  // Bank selector wrapping the method selector
  ModalBottomSheetLayout(
    sheetState = bankSheetState,
    sheetContent = {
      BankSelectorContent(
        providers = catalog?.providers ?: emptyList(),
        onSelect = { provider ->
          selectedProvider = provider
          selectedMethod = "bank"
          scope.launch { bankSheetState.hide() }
        },
      )
    },
  ) {
    ModalBottomSheetLayout(
      sheetState = methodSheetState,
      sheetContent = {
        PaymentMethodSheetContent(
          catalog = catalog,
          onSelect = { provider, method ->
            selectedProvider = provider
            selectedMethod = method
            scope.launch {
              methodSheetState.hide()
              // When bank is chosen and multiple bank providers exist, open bank selector.
              if (method == "bank") {
                val bankCount = catalog?.providers?.count { "bank" in it.methods } ?: 0
                if (bankCount > 1) bankSheetState.show()
              }
            }
          },
        )
      },
    ) {
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
            if (!Regex("[A-Za-z0-9_-]{3,64}").matches(room)) { message = "Invalid room" }
            else try {
              client = MeridianClient(base, room)
              state = null; catalog = null; review = false; revision++
              selectedProvider = null; selectedMethod = null
              paymentKey = UUID.randomUUID().toString()
            } catch (e: Exception) { message = e.message ?: "Invalid configuration" }
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
          catalog?.recipients?.forEach { person ->
            Row { RadioButton(selected = recipient == person.id, onClick = { recipient = person.id }, enabled = !review && !busy); Text(person.name, Modifier.padding(top = 12.dp)) }
          }
          OutlinedTextField(amount, { amount = it }, label = { Text("Amount (GBP)") }, enabled = !review && !busy)
          OutlinedTextField(note, { note = it.take(200) }, label = { Text("Reference") }, enabled = !review && !busy)
          // Dynamic payment method selector – populated from server catalog.
          OutlinedButton(
            onClick = { scope.launch { methodSheetState.show() } },
            enabled = !review && !busy,
            modifier = Modifier.fillMaxWidth(),
          ) { Text(methodLabel) }
          if (selectedMethod == "bank") {
            TextButton(
              onClick = { scope.launch { bankSheetState.show() } },
              enabled = !review && !busy,
            ) { Text("Change bank") }
          }
          if (!review) {
            Button(
              onClick = {
                if (selectedMethod == null) { message = "Choose a payment method to continue." }
                else {
                  val parsed = parseAmount(amount)
                  if (parsed.first == null) message = parsed.second ?: "Invalid amount"
                  else { review = true; paymentKey = UUID.randomUUID().toString() }
                }
              },
              enabled = !busy,
            ) { Text("Review payment") }
          } else {
            Text("Confirm £$amount to $recipient")
            selectedProvider?.let { provider ->
              val methodName = if (selectedMethod == "card") "Card" else "Bank transfer"
              Text("$methodName via ${provider.name}", style = MaterialTheme.typography.caption)
            }
            Button(
              onClick = {
                val active = client; val minor = parseAmount(amount).first
                val method = selectedMethod
                if (active != null && minor != null && method != null && !busy) {
                  busy = true; revision++
                  scope.launch {
                    try {
                      val payMethod = if (method == "card") PaymentMethod.card else PaymentMethod.bank
                      val result = active.submitPayment(
                        recipientId = recipient, amountMinor = minor,
                        method = payMethod, note = note, idempotencyKey = paymentKey,
                      )
                      if (result.ok) {
                        state = result.state; review = false; amount = ""; note = ""
                        paymentKey = UUID.randomUUID().toString(); message = "Demo payment complete"
                      } else message = result.error ?: "Awaiting confirmation. Retry the same payment."
                    } catch (e: Exception) {
                      message = "Outcome may be unknown: ${e.message}. Retry keeps the same key."
                    } finally { revision++; busy = false }
                  }
                }
              },
              enabled = !busy,
            ) { Text(if (busy) "Confirming…" else "Confirm payment") }
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
    }
  }
}
