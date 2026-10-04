package com.atlassian.meridian

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.Card
import androidx.compose.material.MaterialTheme
import androidx.compose.material.OutlinedTextField
import androidx.compose.material.RadioButton
import androidx.compose.material.Text
import androidx.compose.material.lightColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
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

@Composable
fun MeridianScreen() {
  val scope = rememberCoroutineScope()
  var base by rememberSaveable { mutableStateOf("http://10.0.2.2:8080/api/v1") }
  var room by rememberSaveable { mutableStateOf("meridian-rehearsal") }
  var connectedRoom by rememberSaveable { mutableStateOf("") }
  var client by remember { mutableStateOf<MeridianClient?>(null) }
  var state by remember { mutableStateOf<BankState?>(null) }
  var catalog by remember { mutableStateOf<CatalogResponse?>(null) }
  var recipient by rememberSaveable { mutableStateOf("northline-studio") }
  var amount by rememberSaveable { mutableStateOf("") }
  var iban by rememberSaveable { mutableStateOf("") }
  var note by rememberSaveable { mutableStateOf("") }
  var methodName by rememberSaveable { mutableStateOf(PaymentMethod.card.name) }
  var review by rememberSaveable { mutableStateOf(false) }
  var busy by remember { mutableStateOf(false) }
  var paymentKey by rememberSaveable { mutableStateOf(UUID.randomUUID().toString()) }
  var message by rememberSaveable { mutableStateOf("Fictional payment rehearsal. Connect to the Java API.") }
  var revision by remember { mutableStateOf(0) }
  val balanceScroll = rememberScrollState()

  fun snapshot() = PaymentEntry(
    amount = amount,
    iban = iban,
    reference = note,
    recipientId = recipient,
    method = methodName,
    idempotencyKey = paymentKey,
    reviewing = review,
  )

  fun apply(entry: PaymentEntry) {
    amount = entry.amount
    iban = entry.iban
    note = entry.reference
    recipient = entry.recipientId
    methodName = entry.method
    paymentKey = entry.idempotencyKey
    review = entry.reviewing
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
            message = "Connected to shared Java API"
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
    verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(14.dp),
  ) {
    Text("meridian", style = MaterialTheme.typography.h4)
    Text("Native Android · simulated GBP payments", style = MaterialTheme.typography.caption)
    OutlinedTextField(
      value = base,
      onValueChange = { base = it },
      label = { Text("API base URL") },
      enabled = !busy,
      modifier = Modifier.fillMaxWidth(),
      textStyle = MaterialTheme.typography.body1,
      maxLines = 3,
    )
    OutlinedTextField(
      value = room,
      onValueChange = { room = it },
      label = { Text("Shared rehearsal room") },
      enabled = !busy,
      modifier = Modifier.fillMaxWidth(),
      textStyle = MaterialTheme.typography.body1,
      maxLines = 2,
    )
    GrowingButton(title = "Connect", enabled = !busy, onClick = {
      if (!Regex("^[A-Za-z0-9_-]{3,64}$").matches(room)) {
        message = "Invalid room"
      } else {
        try {
          client = MeridianClient(base, room)
          state = null
          catalog = null
          revision++
          if (connectedRoom != room) {
            apply(reducePaymentEntry(snapshot(), PaymentEntryEvent.SessionChanged(UUID.randomUUID().toString())))
            connectedRoom = room
          }
        } catch (e: Exception) {
          message = e.message ?: "Invalid configuration"
        }
      }
    })
    Text(message, style = MaterialTheme.typography.body1)
    state?.let { current ->
      Card(backgroundColor = Color(0xFF142C35), contentColor = Color.White, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(22.dp)) {
          Text("Everyday account")
          Text(
            money(current.balance),
            style = MaterialTheme.typography.h3,
            maxLines = 1,
            softWrap = false,
            modifier = Modifier.horizontalScroll(balanceScroll),
          )
          Text("Room: $room")
        }
      }
      Text("Make a payment", style = MaterialTheme.typography.h6)
      Text("Recipient", style = MaterialTheme.typography.subtitle1)
      catalog?.recipients?.forEach { person ->
        Row(
          Modifier.fillMaxWidth().clickable(enabled = !review && !busy) { recipient = person.id },
          verticalAlignment = Alignment.Top,
        ) {
          RadioButton(
            selected = recipient == person.id,
            onClick = { recipient = person.id },
            enabled = !review && !busy,
          )
          Text(person.name, modifier = Modifier.weight(1f).padding(top = 12.dp))
        }
      }
      AmountInputField(text = amount, onTextChange = { amount = it }, enabled = !review && !busy)
      OutlinedTextField(
        value = note,
        onValueChange = { note = it.take(200) },
        label = { Text("Reference") },
        enabled = !review && !busy,
        modifier = Modifier.fillMaxWidth(),
        textStyle = MaterialTheme.typography.body1,
        maxLines = 4,
      )
      Text("Method", style = MaterialTheme.typography.subtitle1)
      Row(
        Modifier.fillMaxWidth().clickable(enabled = !review && !busy) { methodName = PaymentMethod.card.name },
        verticalAlignment = Alignment.Top,
      ) {
        RadioButton(
          selected = methodName == PaymentMethod.card.name,
          onClick = { methodName = PaymentMethod.card.name },
          enabled = !review && !busy,
        )
        Text("Debit card · Adyen", modifier = Modifier.weight(1f).padding(top = 12.dp))
      }
      Row(
        Modifier.fillMaxWidth().clickable(enabled = !review && !busy) { methodName = PaymentMethod.bank.name },
        verticalAlignment = Alignment.Top,
      ) {
        RadioButton(
          selected = methodName == PaymentMethod.bank.name,
          onClick = { methodName = PaymentMethod.bank.name },
          enabled = !review && !busy,
        )
        Text("Bank payment · Worldpay", modifier = Modifier.weight(1f).padding(top = 12.dp))
      }
      if (methodName == PaymentMethod.bank.name) {
        IbanInputField(text = iban, onTextChange = { iban = it }, enabled = !review && !busy)
      }
      if (!review) {
        GrowingButton(title = "Review payment", enabled = !busy, onClick = {
          val entry = snapshot()
          val error = paymentReviewError(entry)
          if (error != null) {
            message = error
          } else {
            apply(reducePaymentEntry(entry, PaymentEntryEvent.Review(UUID.randomUUID().toString())))
            message = "Review before confirming. No real money moves."
          }
        })
      } else {
        val spoken = evaluateAmount(amount).spoken
        val confirmation = if (methodName == PaymentMethod.bank.name) {
          "Confirm $spoken to $recipient using IBAN ${formatIbanGroups(validateIban(iban).normalized)}"
        } else {
          "Confirm $spoken to $recipient"
        }
        Text(confirmation, style = MaterialTheme.typography.h6)
        GrowingButton(
          title = if (busy) "Confirming…" else "Confirm payment",
          enabled = !busy,
          onClick = {
            val active = client
            val entry = snapshot()
            val minor = evaluateAmount(entry.amount).minorUnits
            val method = if (entry.method == PaymentMethod.bank.name) PaymentMethod.bank else PaymentMethod.card
            if (active != null && minor != null && !busy) {
              busy = true
              revision++
              scope.launch {
                try {
                  val result = active.submitPayment(
                    recipientId = entry.recipientId,
                    amountMinor = minor,
                    method = method,
                    note = entry.reference,
                    idempotencyKey = entry.idempotencyKey,
                  )
                  if (result.ok) {
                    state = result.state
                    apply(reducePaymentEntry(entry, PaymentEntryEvent.Completed(UUID.randomUUID().toString())))
                    message = "Demo payment complete"
                  } else {
                    apply(reducePaymentEntry(entry, PaymentEntryEvent.Pending))
                    message = result.error ?: "Awaiting confirmation. Retry the same payment."
                  }
                } catch (e: Exception) {
                  apply(reducePaymentEntry(entry, PaymentEntryEvent.NetworkFailure))
                  message = "Outcome may be unknown: ${e.message}. Retry keeps the same key."
                } finally {
                  revision++
                  busy = false
                }
              }
            }
          },
        )
        GrowingTextButton(title = "Edit details", enabled = !busy, onClick = {
          apply(reducePaymentEntry(snapshot(), PaymentEntryEvent.Edit(UUID.randomUUID().toString())))
        })
      }
      Text("Recent activity", style = MaterialTheme.typography.h6)
      current.transactions.reversed().take(8).forEach { transaction ->
        Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")
      }
      Text("Budgets", style = MaterialTheme.typography.h6)
      current.budgets.forEach { budget ->
        Text("${budget.category} · ${money(budget.limit)}")
      }
    }
  }
}
