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
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.compose.runtime.rememberCoroutineScope
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

@Composable
fun MeridianScreen() {
  val scope = rememberCoroutineScope()
  val context = LocalContext.current
  var base by remember { mutableStateOf("http://10.0.2.2:8080/api/v1") }
  var room by remember { mutableStateOf("meridian-rehearsal") }
  var customerAccount by remember { mutableStateOf("demo-customer") }
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
  var resumedIntentId by remember { mutableStateOf<String?>(null) }
  var ledger by remember { mutableStateOf<PaymentIntentLedger?>(null) }
  val accountNow = rememberUpdatedState(customerAccount)
  val amountNow = rememberUpdatedState(amount)
  val reviewNow = rememberUpdatedState(review)

  fun apply(intent: PaymentIntentSnapshot) {
    recipient = intent.recipientId
    amount = formatAmountInput(intent.amountMinor)
    note = intent.note
    method = paymentMethod(intent.method)
    paymentKey = intent.idempotencyKey
    review = true
    resumedIntentId = intent.paymentIntentId
  }

  LaunchedEffect(Unit) {
    try {
      val directory = withContext(Dispatchers.IO) { PaymentIntentLedger(EncryptedPaymentIntentStore(context)) }
      ledger = directory
      val saved = withContext(Dispatchers.IO) { directory.lastCustomerAccountId() }
      if (saved != null && accountNow.value == "demo-customer" && amountNow.value.isEmpty() && !reviewNow.value) {
        customerAccount = saved
        val active = withContext(Dispatchers.IO) { directory.activeIntents(saved) }
        val intent = active.firstOrNull()
        if (intent != null && amountNow.value.isEmpty() && !reviewNow.value) {
          apply(intent)
          message = "Active payment intent ${intent.paymentIntentId} is stored for $saved. Connect to resume it."
        }
      }
    } catch (e: Exception) {
      message = "Protected storage is unavailable: ${e.message}"
    }
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
            if (resumedIntentId == null) message = "Connected to shared Java API"
          }
        } catch (e: Exception) {
          if (current === client) message = "API unavailable: ${e.message}"
        }
      }
      delay(2000)
    }
  }

  Column(
    Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
    verticalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    Text("meridian", style = MaterialTheme.typography.h4)
    Text("Native Android · simulated GBP payments", style = MaterialTheme.typography.caption)
    Text(
      "Payment intents are stored in EncryptedSharedPreferences for this customer account.",
      style = MaterialTheme.typography.caption,
    )
    OutlinedTextField(base, { base = it }, label = { Text("API base URL") }, enabled = !busy)
    OutlinedTextField(room, { room = it }, label = { Text("Shared rehearsal room") }, enabled = !busy)
    OutlinedTextField(customerAccount, { customerAccount = it }, label = { Text("Customer account") }, enabled = !busy)
    Button(
      onClick = {
        if (!Regex("[A-Za-z0-9_-]{3,64}").matches(room)) {
          message = "Invalid room"
          return@Button
        }
        if (!PaymentIntentIds.isValidCustomerAccountId(customerAccount)) {
          message = "Invalid customer account"
          return@Button
        }
        val directory = ledger
        if (directory == null) {
          message = "Protected storage is not ready"
          return@Button
        }
        try {
          client = MeridianClient(base, room)
        } catch (e: Exception) {
          message = e.message ?: "Invalid configuration"
          return@Button
        }
        state = null
        catalog = null
        resumedIntentId = null
        revision++
        try {
          directory.rememberCustomerAccount(customerAccount)
          val active = directory.activeIntents(customerAccount)
          val intent = active.firstOrNull()
          if (intent != null) {
            apply(intent)
            message = "Resumed active payment intent ${intent.paymentIntentId} (${intent.status}). Retry uses the same idempotency key."
          } else {
            review = false
            resumedIntentId = null
            paymentKey = UUID.randomUUID().toString()
          }
        } catch (e: Exception) {
          message = "Could not read protected payment intent storage: ${e.message}"
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
          Text("Customer account: $customerAccount")
        }
      }
      Text("Make a payment", style = MaterialTheme.typography.h6)
      resumedIntentId?.let { id ->
        Text("Resuming $id. The idempotency key stays in protected storage.")
      }
      catalog?.recipients?.forEach { person ->
        Row {
          RadioButton(selected = recipient == person.id, onClick = { recipient = person.id }, enabled = !review && !busy)
          Text(person.name, Modifier.padding(top = 12.dp))
        }
      }
      OutlinedTextField(amount, { amount = it }, label = { Text("Amount (GBP)") }, enabled = !review && !busy)
      OutlinedTextField(note, { note = it.take(200) }, label = { Text("Reference") }, enabled = !review && !busy)
      Row {
        RadioButton(method == PaymentMethod.card, { method = PaymentMethod.card }, enabled = !review && !busy)
        Text("Debit card · Adyen", Modifier.padding(top = 12.dp))
      }
      Row {
        RadioButton(method == PaymentMethod.bank, { method = PaymentMethod.bank }, enabled = !review && !busy)
        Text("Bank payment · Worldpay", Modifier.padding(top = 12.dp))
      }
      if (!review) {
        Button(
          onClick = {
            val parsed = parseAmount(amount)
            if (parsed.first == null) {
              message = parsed.second ?: "Invalid amount"
              return@Button
            }
            val directory = ledger
            if (directory == null) {
              message = "Protected storage is not ready"
              return@Button
            }
            try {
              val prepared = directory.begin(
                customerAccountId = customerAccount,
                recipientId = recipient,
                amountMinor = parsed.first!!,
                method = method.name,
                note = note,
                scenario = Scenario.success.name,
              )
              val token = prepared.returnState
              if (token != null && !directory.verifyReturnState(prepared.snapshot, token)) {
                message = "Return state could not be verified."
                return@Button
              }
              paymentKey = prepared.snapshot.idempotencyKey
              resumedIntentId = prepared.snapshot.paymentIntentId
              review = true
              message = if (token == null) {
                "Review before confirming. The existing idempotency key will be reused."
              } else {
                "Review before confirming. No real money moves."
              }
            } catch (e: ActivePaymentIntentException) {
              val existing = runCatching { directory.snapshot(customerAccount, e.paymentIntentId) }.getOrNull()
              if (existing != null) {
                apply(existing)
                message = "Finish payment intent ${e.paymentIntentId} before starting a different one. The same idempotency key will be reused."
              } else {
                message = e.message ?: "Another payment intent is still active."
              }
            } catch (e: Exception) {
              message = "Could not store the payment intent: ${e.message}"
            }
          },
          enabled = !busy,
        ) { Text("Review payment") }
      } else {
        Text("Confirm £$amount to $recipient")
        Button(
          onClick = {
            val active = client
            val directory = ledger
            val intentId = resumedIntentId
            val account = customerAccount
            if (active == null || directory == null || intentId == null || busy) {
              message = "Review the payment before confirming."
              return@Button
            }
            busy = true
            revision++
            scope.launch {
              var submitted = false
              try {
                val snapshot = directory.markSubmitted(account, intentId)
                submitted = true
                paymentKey = snapshot.idempotencyKey
                val result = active.submitPayment(
                  recipientId = snapshot.recipientId,
                  amountMinor = snapshot.amountMinor,
                  method = paymentMethod(snapshot.method),
                  note = snapshot.note,
                  scenario = paymentScenario(snapshot.scenario),
                  idempotencyKey = snapshot.idempotencyKey,
                )
                val updated = directory.record(result, account, intentId)
                when {
                  updated.status == PaymentIntentStatus.completed -> {
                    state = result.state
                    review = false
                    amount = ""
                    note = ""
                    resumedIntentId = null
                    paymentKey = UUID.randomUUID().toString()
                    message = "Demo payment complete"
                  }
                  updated.status.isTerminal -> {
                    review = false
                    resumedIntentId = null
                    paymentKey = UUID.randomUUID().toString()
                    message = result.error ?: "Payment was declined."
                  }
                  else -> {
                    review = true
                    resumedIntentId = updated.paymentIntentId
                    paymentKey = updated.idempotencyKey
                    message = result.error ?: "Awaiting confirmation. Retry the same payment."
                  }
                }
              } catch (e: Exception) {
                if (submitted) {
                  runCatching { directory.markUncertain(account, intentId) }.getOrNull()?.let { uncertain ->
                    paymentKey = uncertain.idempotencyKey
                    resumedIntentId = uncertain.paymentIntentId
                    review = true
                  }
                  message = "Outcome may be unknown: ${e.message}. Retry keeps the same key."
                } else {
                  message = "Could not store the payment intent: ${e.message}"
                }
              } finally {
                revision++
                busy = false
              }
            }
          },
          enabled = !busy,
        ) { Text(if (busy) "Confirming…" else "Confirm payment") }
        TextButton(
          onClick = {
            val directory = ledger
            val intentId = resumedIntentId
            if (directory == null || intentId == null) {
              review = false
              paymentKey = UUID.randomUUID().toString()
              return@TextButton
            }
            try {
              val current = directory.snapshot(customerAccount, intentId)
              if (current.status != PaymentIntentStatus.created) {
                message = "This payment was already submitted. Retry uses the same idempotency key."
                return@TextButton
              }
              directory.cancel(customerAccount, intentId)
              review = false
              resumedIntentId = null
              paymentKey = UUID.randomUUID().toString()
            } catch (e: Exception) {
              message = "Could not update the payment intent: ${e.message}"
            }
          },
          enabled = !busy,
        ) { Text("Edit details") }
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

private fun formatAmountInput(pence: Int): String = "%d.%02d".format(pence / 100, Math.floorMod(pence, 100))

private fun paymentMethod(value: String): PaymentMethod =
  if (value == PaymentMethod.bank.name) PaymentMethod.bank else PaymentMethod.card

private fun paymentScenario(value: String): Scenario =
  runCatching { Scenario.valueOf(value) }.getOrDefault(Scenario.success)
