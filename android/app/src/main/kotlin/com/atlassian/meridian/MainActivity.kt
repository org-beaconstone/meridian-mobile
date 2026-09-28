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
  var base by remember { mutableStateOf("http://10.0.2.2:8080/api/v1") }
  var room by remember { mutableStateOf("meridian-rehearsal") }
  var client by remember { mutableStateOf<MeridianClient?>(null) }
  var state by remember { mutableStateOf<BankState?>(null) }
  var catalog by remember { mutableStateOf<CatalogResponse?>(null) }
  var recipient by remember { mutableStateOf("northline-studio") }
  var amount by remember { mutableStateOf("") }
  var note by remember { mutableStateOf("") }
  var iban by remember { mutableStateOf("") }
  var method by remember { mutableStateOf(PaymentMethod.card) }
  var currency by remember { mutableStateOf(PayCurrency.GBP) }
  var review by remember { mutableStateOf(false) }
  var busy by remember { mutableStateOf(false) }
  var quoteBusy by remember { mutableStateOf(false) }
  var paymentKey by remember { mutableStateOf(makeIdempotencyKey()) }
  var quote by remember { mutableStateOf<FxQuoteLock?>(null) }
  var quoteSeconds by remember { mutableStateOf(0) }
  var message by remember { mutableStateOf("Fictional payment rehearsal. Connect to the Java API.") }
  var revision by remember { mutableStateOf(0) }

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
          message = "Connected to shared Java API"
        }
      } catch (e: Exception) {
        if (current === client) message = "API unavailable: ${e.message}"
      }
      delay(2000)
    }
  }

  LaunchedEffect(quote?.quoteId, review) {
    val active = quote
    if (active == null || !review) return@LaunchedEffect
    while (true) {
      val left = active.remainingSeconds(System.currentTimeMillis())
      quoteSeconds = left
      if (left == 0) break
      delay(250)
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
        } else try {
          client = MeridianClient(base, room)
          state = null
          catalog = null
          review = false
          quote = null
          revision++
          paymentKey = makeIdempotencyKey()
        } catch (e: Exception) {
          message = e.message ?: "Invalid configuration"
        }
      },
      enabled = !busy,
    ) { Text("Connect") }
    Text(message)
    state?.let { current ->
      val minorNow = parseAmount(amount).first
      val blocked = if (review && minorNow != null) {
        submissionBlockReason(currency, method, iban, quote, minorNow, System.currentTimeMillis())
      } else {
        null
      }
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
          RadioButton(
            selected = recipient == person.id,
            onClick = { recipient = person.id },
            enabled = !review && !busy,
          )
          Text(person.name, Modifier.padding(top = 12.dp))
        }
      }
      OutlinedTextField(amount, { amount = it }, label = { Text("Amount (GBP)") }, enabled = !review && !busy)
      if (currency == PayCurrency.EUR) {
        Text("GBP amount to convert. The account is debited in pence.", style = MaterialTheme.typography.caption)
      }
      Row {
        RadioButton(currency == PayCurrency.GBP, { currency = PayCurrency.GBP }, enabled = !review && !busy)
        Text("GBP · no conversion", Modifier.padding(top = 12.dp))
      }
      Row {
        RadioButton(currency == PayCurrency.EUR, { currency = PayCurrency.EUR }, enabled = !review && !busy)
        Text("EUR · convert from GBP", Modifier.padding(top = 12.dp))
      }
      if (ibanRequired(currency, method)) {
        OutlinedTextField(iban, { iban = it.uppercase() }, label = { Text("Recipient IBAN") }, enabled = !review && !busy)
      }
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
            val parsed = parseAmount(amount)
            val minor = parsed.first
            if (minor == null) {
              message = parsed.second ?: "Invalid amount"
            } else if (ibanBlockReason(currency, method, iban) != null) {
              message = INVALID_IBAN_MESSAGE
            } else if (currency == PayCurrency.EUR) {
              val active = client
              if (active != null && !quoteBusy) {
                quoteBusy = true
                scope.launch {
                  try {
                    val locked = lockQuote(active.requestFxQuote(minor), System.currentTimeMillis())
                    quote = locked
                    quoteSeconds = locked.remainingSeconds(System.currentTimeMillis())
                    paymentKey = makeIdempotencyKey()
                    review = true
                    message = "Rate locked for 60 seconds. No real money moves."
                  } catch (e: Exception) {
                    message = "Could not lock a conversion rate: ${e.message}"
                  } finally {
                    quoteBusy = false
                  }
                }
              }
            } else {
              quote = null
              paymentKey = makeIdempotencyKey()
              review = true
              message = "Review before confirming. No real money moves."
            }
          },
          enabled = !busy && !quoteBusy,
        ) { Text(if (quoteBusy) "Locking rate…" else "Review payment") }
      } else {
        Text("Confirm £$amount to $recipient")
        if (currency == PayCurrency.EUR && quote != null) {
          Text("Recipient gets ${moneyEur(quote!!.targetAmountMinor)} at ${quote!!.rate}")
          Text(
            if (quoteSeconds == 0) QUOTE_EXPIRED_MESSAGE else "Rate locked for ${quoteSeconds}s",
            color = if (quoteSeconds == 0) Color(0xFFAE2A19) else Color.Unspecified,
          )
          Button(
            onClick = {
              val active = client
              val minor = parseAmount(amount).first
              if (active != null && minor != null && !busy && !quoteBusy) {
                quoteBusy = true
                scope.launch {
                  try {
                    val locked = lockQuote(active.requestFxQuote(minor), System.currentTimeMillis())
                    quote = locked
                    quoteSeconds = locked.remainingSeconds(System.currentTimeMillis())
                    message = "Conversion rate refreshed. The payment key is unchanged."
                  } catch (e: Exception) {
                    message = "Could not refresh the conversion rate: ${e.message}"
                  } finally {
                    quoteBusy = false
                  }
                }
              }
            },
            enabled = !busy && !quoteBusy,
          ) { Text("Refresh conversion rate") }
        }
        if (blocked != null && (blocked != QUOTE_EXPIRED_MESSAGE || quote == null)) {
          Text(blocked, color = Color(0xFFAE2A19))
        }
        Button(
          onClick = {
            val active = client
            val minor = parseAmount(amount).first
            val reason = if (minor == null) {
              "Invalid amount"
            } else {
              submissionBlockReason(currency, method, iban, quote, minor, System.currentTimeMillis())
            }
            if (reason != null) {
              message = reason
            } else if (active != null && minor != null && !busy) {
              busy = true
              revision++
              scope.launch {
                try {
                  val result = submitPaymentWithRetry(paymentKey, method) { attemptKey, attemptMethod ->
                    active.submitPayment(
                      recipientId = recipient,
                      amountMinor = minor,
                      method = attemptMethod,
                      note = note,
                      idempotencyKey = attemptKey,
                    )
                  }
                  if (result.ok) {
                    state = result.state
                    review = false
                    amount = ""
                    note = ""
                    iban = ""
                    quote = null
                    paymentKey = makeIdempotencyKey()
                    message = "Demo payment complete"
                  } else {
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
          },
          enabled = !busy && !quoteBusy && blocked == null,
        ) { Text(if (busy) "Confirming…" else "Confirm payment") }
        TextButton(
          onClick = {
            review = false
            quote = null
            paymentKey = makeIdempotencyKey()
          },
          enabled = !busy && !quoteBusy,
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
