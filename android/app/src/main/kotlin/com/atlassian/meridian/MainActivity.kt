package com.atlassian.meridian

import android.content.Intent
import android.os.Bundle
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.launch
import java.util.UUID

class MainActivity : FragmentActivity() {
  private val incomingReturn = mutableStateOf<String?>(null)

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    acceptIntent(intent)
    setContentView(
      ComposeView(this).apply {
        setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
        setContent {
          MaterialTheme(colors = lightColors(primary = Color(0xFF142C35), secondary = Color(0xFFD5B77A))) {
            MeridianScreen(this@MainActivity, incomingReturn)
          }
        }
      },
    )
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    acceptIntent(intent)
  }

  private fun acceptIntent(intent: Intent?) {
    if (intent?.action != Intent.ACTION_VIEW) return
    val data = intent.dataString ?: return
    incomingReturn.value = data
  }
}

@Composable fun MeridianScreen(activity: FragmentActivity, incomingReturn: MutableState<String?>) {
  val scope = rememberCoroutineScope()
  var base by remember { mutableStateOf("http://10.0.2.2:8080/api/v1") }
  var room by remember { mutableStateOf("meridian-rehearsal") }
  var connectedRoom by remember { mutableStateOf(room) }
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
  var vault by remember { mutableStateOf(ReturnStateVault()) }
  var attempt by remember { mutableStateOf<PaymentAttempt?>(null) }
  var handoff by remember { mutableStateOf<IssuedBankHandoff?>(null) }
  var pin by remember { mutableStateOf("") }
  var pinRepeat by remember { mutableStateOf("") }
  var pastedReturn by remember { mutableStateOf("") }

  fun clearHandoff(rotateKey: Boolean) {
    handoff?.let { vault.cancel(it.state) }
    handoff = null
    attempt = null
    pin = ""
    pinRepeat = ""
    pastedReturn = ""
    if (rotateKey) paymentKey = UUID.randomUUID().toString()
  }

  fun submitPayment() {
    val active = client
    val minor = parseAmount(amount).first
    val current = attempt
    if (active == null || minor == null || busy) return
    if (current == null || !current.readyToSubmit || current.idempotencyKey != paymentKey) {
      message = "Authentication is still required. The payment was not sent."
      return
    }
    busy = true
    revision++
    scope.launch {
      try {
        val result = active.submitPayment(
          recipientId = recipient,
          amountMinor = minor,
          method = method,
          note = note,
          idempotencyKey = current.idempotencyKey,
        )
        if (result.ok) {
          state = result.state
          review = false
          amount = ""
          note = ""
          attempt = null
          handoff = null
          paymentKey = UUID.randomUUID().toString()
          message = "Demo payment complete"
        } else {
          message = (result.error ?: "Awaiting confirmation. Retry the same payment.") + " Payment key kept."
        }
      } catch (e: Exception) {
        message = "Outcome may be unknown: ${e.message}. Retry keeps the same key."
      } finally {
        revision++
        busy = false
      }
    }
  }

  fun handleReturn(url: String) {
    val decision = vault.intercept(url, connectedRoom, paymentKey)
    val waiting = method == PaymentMethod.bank && review && handoff != null
    if (!waiting) {
      if (decision.outcome != ReturnOutcome.ignored) {
        message = if (decision.outcome == ReturnOutcome.accepted) {
          "Bank return was not applied. The payment was not sent."
        } else {
          decision.outcome.userMessage()
        }
      }
      return
    }
    val before = attempt?.bankAccepted == true
    val updated = (attempt ?: PaymentAttempt(paymentKey, PaymentMethod.bank)).applying(decision)
    attempt = updated
    if (!before && updated.bankAccepted) submitPayment()
    else if (decision.outcome != ReturnOutcome.accepted) message = decision.outcome.userMessage()
  }

  fun beginAuth() {
    attempt = PaymentAttempt(paymentKey, method)
    pin = ""
    pinRepeat = ""
    if (method == PaymentMethod.card) {
      message = "Use biometrics, device PIN, or an app PIN. Nothing is sent until that succeeds."
      return
    }
    try {
      val issued = vault.issue(connectedRoom, paymentKey)
      handoff = issued
      val opened = BankHandoffOpener.open(activity, issued.handoffUrl)
      message = if (opened) {
        "Opened the allowlisted rehearsal bank handoff. The payment waits for a valid return."
      } else {
        "Rehearsal bank handoff is ready, but this device did not open it. Apply the return link below. The payment has not been sent."
      }
    } catch (e: Exception) {
      handoff = null
      message = "Could not start the bank handoff. The payment was not sent and the payment key was kept."
    }
  }

  LaunchedEffect(incomingReturn.value) {
    val link = incomingReturn.value ?: return@LaunchedEffect
    incomingReturn.value = null
    handleReturn(link)
  }
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
          if (!review) message = "Connected to shared Java API"
        }
      } catch (e: Exception) {
        if (current === client) message = "API unavailable: ${e.message}"
      }
      kotlinx.coroutines.delay(2000)
    }
  }
  Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
    Text("meridian", style = MaterialTheme.typography.h4)
    Text("Native Android · simulated GBP payments", style = MaterialTheme.typography.caption)
    OutlinedTextField(base, { base = it }, label = { Text("API base URL") }, enabled = !busy)
    OutlinedTextField(room, { room = it }, label = { Text("Shared rehearsal room") }, enabled = !busy)
    Button(onClick = {
      if (!Regex("[A-Za-z0-9_-]{3,64}").matches(room)) message = "Invalid room"
      else try {
        client = MeridianClient(base, room)
        connectedRoom = room
        state = null
        catalog = null
        review = false
        revision++
        vault = ReturnStateVault()
        clearHandoff(true)
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
        Button(onClick = {
          val parsed = parseAmount(amount)
          if (parsed.first == null) message = parsed.second ?: "Invalid amount"
          else {
            clearHandoff(true)
            review = true
          }
        }, enabled = !busy) { Text("Review payment") }
      } else if (method == PaymentMethod.card && attempt != null && attempt?.readyToSubmit != true) {
        Text("Strong Customer Authentication", style = MaterialTheme.typography.h6)
        Text("Confirm with biometrics or device PIN, or enter a 4–6 digit app PIN. The PIN stays on this device.")
        Button(onClick = {
          ScaPrompt.authenticate(activity) { success ->
            if (success) {
              attempt = attempt?.confirmingBiometric(true)
              submitPayment()
            } else {
              message = "Device authentication was not confirmed. The payment was not sent. You can try again or use a PIN."
            }
          }
        }, enabled = !busy) { Text("Confirm with biometrics or device PIN") }
        OutlinedTextField(
          pin,
          { pin = it.filter(Char::isDigit).take(6) },
          label = { Text("App PIN") },
          visualTransformation = PasswordVisualTransformation(),
          enabled = !busy,
        )
        OutlinedTextField(
          pinRepeat,
          { pinRepeat = it.filter(Char::isDigit).take(6) },
          label = { Text("Repeat app PIN") },
          visualTransformation = PasswordVisualTransformation(),
          enabled = !busy,
        )
        Button(onClick = {
          val current = attempt ?: return@Button
          val (updated, error) = current.confirmingPin(pin, pinRepeat)
          pin = ""
          pinRepeat = ""
          attempt = updated
          if (error != null) message = "$error The payment was not sent."
          else submitPayment()
        }, enabled = !busy) { Text("Confirm with PIN") }
        TextButton(onClick = {
          attempt = null
          pin = ""
          pinRepeat = ""
          message = "Authentication cancelled. The payment was not sent and the payment key was kept."
        }, enabled = !busy) { Text("Back") }
      } else if (method == PaymentMethod.bank && handoff != null && attempt?.readyToSubmit != true) {
        Text("Bank handoff", style = MaterialTheme.typography.h6)
        Text("Opens only https://${BankHandoffPolicy.bankHost}. This rehearsal link does not contact a live bank.")
        Button(onClick = {
          val link = handoff?.handoffUrl ?: return@Button
          if (!BankHandoffOpener.open(activity, link)) {
            message = "This device did not open the allowlisted handoff. Apply the return link below. The payment has not been sent."
          }
        }, enabled = !busy) { Text("Open bank handoff") }
        handoff?.let { Text(it.returnUrl, style = MaterialTheme.typography.caption) }
        OutlinedTextField(pastedReturn, { pastedReturn = it }, label = { Text("Return link") }, enabled = !busy)
        Button(onClick = {
          val link = pastedReturn.ifBlank { handoff?.returnUrl.orEmpty() }
          if (link.isNotEmpty()) handleReturn(link)
        }, enabled = !busy) { Text("Apply return link") }
        TextButton(onClick = {
          handoff?.let { vault.cancel(it.state) }
          handoff = null
          attempt = null
          message = "Bank handoff cancelled. The payment was not sent and the payment key was kept."
        }, enabled = !busy) { Text("Cancel handoff") }
      } else if (attempt?.readyToSubmit == true) {
        Text("Authentication is in place. Retry keeps payment key $paymentKey.")
        Button(onClick = { submitPayment() }, enabled = !busy) { Text(if (busy) "Confirming…" else "Retry same payment") }
        TextButton(onClick = { clearHandoff(true); review = false }, enabled = !busy) { Text("Edit details") }
      } else {
        Text("Confirm £$amount to $recipient")
        Button(onClick = { beginAuth() }, enabled = !busy) {
          Text(if (method == PaymentMethod.card) "Continue to authentication" else "Continue to your bank")
        }
        TextButton(onClick = { clearHandoff(true); review = false }, enabled = !busy) { Text("Edit details") }
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
