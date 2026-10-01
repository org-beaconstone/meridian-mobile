package com.atlassian.meridian

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
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
    val intents = PaymentIntentSnapshotRepository(
      EncryptedPaymentIntentSnapshotStore(applicationContext),
    )
    setContent {
      MaterialTheme(colors = lightColors(primary = Color(0xFF142C35), secondary = Color(0xFFD5B77A))) {
        MeridianScreen(intents)
      }
    }
  }
}

@Composable
fun MeridianScreen(intents: PaymentIntentSnapshotRepository) {
  val scope = rememberCoroutineScope()
  var base by remember { mutableStateOf("http://10.0.2.2:8080/api/v1") }
  var room by remember { mutableStateOf("meridian-rehearsal") }
  var customerAccount by remember { mutableStateOf("everyday-gbp") }
  var intentAccount by remember { mutableStateOf("everyday-gbp") }
  var client by remember { mutableStateOf<MeridianClient?>(null) }
  var state by remember { mutableStateOf<BankState?>(null) }
  var catalog by remember { mutableStateOf<CatalogResponse?>(null) }
  var recipient by remember { mutableStateOf("northline-studio") }
  var amount by remember { mutableStateOf("") }
  var note by remember { mutableStateOf("") }
  var method by remember { mutableStateOf(PaymentMethod.card) }
  var review by remember { mutableStateOf(false) }
  var busy by remember { mutableStateOf(false) }
  var resumed by remember { mutableStateOf(false) }
  var paymentKey by remember { mutableStateOf(UUID.randomUUID().toString()) }
  var paymentIntentId by remember { mutableStateOf(UUID.randomUUID().toString()) }
  var message by remember { mutableStateOf("Fictional payment rehearsal. Connect to the Java API.") }
  var revision by remember { mutableStateOf(0) }

  fun nowMs() = System.currentTimeMillis()

  fun rotateKeys() {
    paymentKey = UUID.randomUUID().toString()
    paymentIntentId = UUID.randomUUID().toString()
    intentAccount = customerAccount
    resumed = false
  }

  fun applyIntent(intent: PaymentIntentSnapshot) {
    intentAccount = intent.customerAccountId
    customerAccount = intent.customerAccountId
    recipient = intent.recipientId
    amount = "%d.%02d".format(intent.amountMinor / 100, intent.amountMinor % 100)
    note = intent.note
    method = intent.method
    paymentKey = intent.idempotencyKey
    paymentIntentId = intent.paymentIntentId
    resumed = true
    review = true
  }

  fun activeIntent(): PaymentIntentSnapshot? {
    if (!PaymentIntentAccounts.isValidAccount(customerAccount)) return null
    return runCatching { intents.resumeActive(customerAccount, nowMs()).firstOrNull() }.getOrNull()
  }

  fun restoreActiveIntent() {
    val intent = activeIntent() ?: return
    applyIntent(intent)
    message = "In-progress payment intent restored. Retry uses the same payment key."
  }

  LaunchedEffect(Unit) { restoreActiveIntent() }
  LaunchedEffect(client) {
    val current = client
    while (current != null) {
      val started = revision
      if (!busy) try {
        val fresh = current.getState()
        val definitions = current.getCatalog()
        if (current === client && started == revision && !busy) {
          state = fresh
          catalog = definitions
          if (!resumed) message = "Connected to shared Java API"
        }
      } catch (e: Exception) {
        if (current === client) message = "API unavailable: ${e.message}"
      }
      delay(2000)
    }
  }

  Column(
    Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
    verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(14.dp),
  ) {
    Text("meridian", style = MaterialTheme.typography.h4)
    Text("Native Android · simulated GBP payments", style = MaterialTheme.typography.caption)
    OutlinedTextField(base, { base = it }, label = { Text("API base URL") }, enabled = !busy)
    OutlinedTextField(room, { room = it }, label = { Text("Shared rehearsal room") }, enabled = !busy)
    OutlinedTextField(
      customerAccount,
      {
        if (it != customerAccount && it != intentAccount) {
          resumed = false
          review = false
          paymentKey = UUID.randomUUID().toString()
          paymentIntentId = UUID.randomUUID().toString()
          intentAccount = it
          message = "Customer account changed. In-progress payments stay with the previous account."
        }
        customerAccount = it
      },
      label = { Text("Customer account") },
      enabled = !busy,
    )
    Button(
      onClick = {
        if (!Regex("[A-Za-z0-9_-]{3,64}").matches(room)) message = "Invalid room"
        else if (!PaymentIntentAccounts.isValidAccount(customerAccount)) message = "Customer account id is required"
        else try {
          client = MeridianClient(base, room)
          state = null
          catalog = null
          revision++
          val intent = activeIntent()
          if (intent != null) {
            applyIntent(intent)
            message = "In-progress payment intent restored. Retry uses the same payment key."
          } else {
            rotateKeys()
          }
        } catch (e: Exception) {
          message = e.message ?: "Invalid configuration"
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
      catalog?.recipients?.forEach { person ->
        Row {
          RadioButton(selected = recipient == person.id, onClick = { recipient = person.id }, enabled = !review && !busy)
          Text(person.name, Modifier.padding(top = 12.dp))
        }
      }
      OutlinedTextField(amount, { amount = it }, label = { Text("Amount (GBP)") }, enabled = !review && !busy)
      OutlinedTextField(note, { note = it.take(200) }, label = { Text("Reference") }, enabled = !review && !busy)
      // Intentional two-provider native baseline; changing it requires an app release.
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
            val existing = activeIntent()
            if (existing != null) {
              applyIntent(existing)
              message = "In-progress payment restored. Confirm retries the same payment key."
              return@Button
            }
            val parsed = parseAmount(amount)
            if (parsed.first == null) message = parsed.second ?: "Invalid amount"
            else if (!PaymentIntentAccounts.isValidAccount(customerAccount)) message = "Customer account id is required"
            else {
              rotateKeys()
              review = true
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
            if (!PaymentIntentAccounts.isValidAccount(customerAccount)) {
              message = "Customer account id is required"
            } else if (active != null && minor != null && !busy) {
              busy = true
              revision++
              scope.launch {
                val began = try {
                  intents.begin(
                    PaymentIntentDraft(
                      customerAccountId = customerAccount,
                      paymentIntentId = paymentIntentId,
                      idempotencyKey = paymentKey,
                      recipientId = recipient,
                      amountMinor = minor,
                      method = method,
                      note = note,
                    ),
                    nowMs(),
                  )
                } catch (e: Exception) {
                  message = e.message ?: "Payment intent could not be stored."
                  revision++
                  busy = false
                  return@launch
                }
                if (!began.payloadMatches) {
                  applyIntent(began.snapshot)
                  message = "An in-progress payment must be retried with its original details."
                  revision++
                  busy = false
                  return@launch
                }
                paymentKey = began.snapshot.idempotencyKey
                paymentIntentId = began.snapshot.paymentIntentId
                intentAccount = began.snapshot.customerAccountId
                resumed = true
                try {
                  val result = active.submitPayment(
                    recipientId = began.snapshot.recipientId,
                    amountMinor = began.snapshot.amountMinor,
                    method = began.snapshot.method,
                    note = began.snapshot.note,
                    idempotencyKey = began.snapshot.idempotencyKey,
                  )
                  val updated = intents.recordOutcome(
                    began.snapshot.customerAccountId,
                    began.snapshot.paymentIntentId,
                    result,
                    nowMs(),
                  )
                  if (updated.status == PaymentIntentStatus.succeeded) {
                    state = result.state
                    review = false
                    amount = ""
                    note = ""
                    rotateKeys()
                    message = "Demo payment complete"
                  } else if (updated.status.isTerminal) {
                    review = false
                    rotateKeys()
                    message = result.error ?: "Payment was not completed."
                  } else {
                    result.state?.let { state = it }
                    resumed = true
                    review = true
                    message = result.error ?: "Awaiting confirmation. Retry the same payment."
                  }
                } catch (e: Exception) {
                  runCatching {
                    intents.markUncertain(
                      began.snapshot.customerAccountId,
                      began.snapshot.paymentIntentId,
                      nowMs(),
                    )
                  }
                  resumed = true
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
        TextButton(
          onClick = {
            if (resumed) message = "This payment is still in progress. Abandon it before changing details."
            else {
              review = false
              rotateKeys()
            }
          },
          enabled = !busy,
        ) { Text("Edit details") }
        if (resumed) {
          TextButton(
            onClick = {
              runCatching { intents.cancel(customerAccount, paymentIntentId, nowMs()) }
              review = false
              rotateKeys()
              message = "In-progress payment abandoned. A new payment key will be used."
            },
            enabled = !busy,
          ) { Text("Abandon in-progress payment") }
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
