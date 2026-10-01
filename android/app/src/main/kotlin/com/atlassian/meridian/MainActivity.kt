package com.atlassian.meridian

import android.content.Intent
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
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

class MainActivity : ComponentActivity() {
  private val returnLink = mutableStateOf<String?>(null)

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    returnLink.value = intent?.dataString
    setContent {
      MaterialTheme(colors = lightColors(primary = Color(0xFF142C35), secondary = Color(0xFFD5B77A))) {
        MeridianScreen(
          activity = this,
          returnLink = returnLink.value,
          onReturnConsumed = { returnLink.value = null },
          onDeliverReturn = { returnLink.value = it },
        )
      }
    }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    returnLink.value = intent.dataString
  }
}

@Composable
fun MeridianScreen(
  activity: FragmentActivity,
  returnLink: String?,
  onReturnConsumed: () -> Unit,
  onDeliverReturn: (String) -> Unit,
) {
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
  var enrolledPin by remember { mutableStateOf("") }
  var challengePin by remember { mutableStateOf("") }
  var signer by remember { mutableStateOf(ReturnStateSigner(ReturnStateSigner.randomSecret())) }
  var attempt by remember { mutableStateOf<PaymentAttempt?>(null) }
  var allowRetry by remember { mutableStateOf(false) }
  val reviewing = rememberUpdatedState(review)

  fun prepareAttempt(): PaymentAttempt {
    val existing = attempt
    if (existing != null && existing.idempotencyKey == paymentKey && existing.method == method) return existing
    val created = PaymentAttempt(paymentKey, method, signer, enrolledPin)
    attempt = created
    return created
  }

  fun sendPayment(idempotencyKey: String) {
    val active = client
    val current = attempt
    val minor = parseAmount(amount).first
    if (active == null || current == null || minor == null || idempotencyKey != paymentKey || idempotencyKey != current.idempotencyKey) {
      if (current != null && idempotencyKey == current.idempotencyKey) current.releaseForRetry()
      allowRetry = current?.canRetry == true
      message = "The payment was not sent again."
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
          idempotencyKey = idempotencyKey,
        )
        if (result.ok) {
          current.markCompleted()
          state = result.state
          review = false
          amount = ""
          note = ""
          challengePin = ""
          paymentKey = UUID.randomUUID().toString()
          attempt = null
          allowRetry = false
          message = "Demo payment complete"
        } else {
          current.releaseForRetry()
          allowRetry = current.canRetry
          message = result.error ?: "Awaiting confirmation. Retry the same payment."
        }
      } catch (e: Exception) {
        current.releaseForRetry()
        allowRetry = current.canRetry
        message = "Outcome may be unknown: ${e.message}. Retry keeps the same key."
      } finally {
        revision++
        busy = false
      }
    }
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
          if (!reviewing.value) message = "Connected to shared Java API"
        }
      } catch (e: Exception) {
        if (current === client) message = "API unavailable: ${e.message}"
      }
      delay(2000)
    }
  }

  LaunchedEffect(returnLink) {
    val link = returnLink ?: return@LaunchedEffect
    val current = attempt
    if (current == null) {
      message = "No bank payment is waiting for this return. Nothing was sent."
      onReturnConsumed()
      return@LaunchedEffect
    }
    var started = false
    val outcome = current.resumeAfterReturn(link) { key ->
      started = true
      sendPayment(key)
    }
    when (outcome) {
      is ReturnOutcome.Cleared -> if (!started) message = "This payment is already in progress."
      is ReturnOutcome.SafeFailure -> {
        allowRetry = current.canRetry
        message = returnFailureMessage(outcome.reason)
      }
      ReturnOutcome.Ignored -> Unit
    }
    onReturnConsumed()
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
        if (!Regex("[A-Za-z0-9_-]{3,64}").matches(room)) message = "Invalid room"
        else try {
          client = MeridianClient(base, room)
          state = null
          catalog = null
          review = false
          revision++
          paymentKey = UUID.randomUUID().toString()
          signer = ReturnStateSigner(ReturnStateSigner.randomSecret())
          attempt = null
          allowRetry = false
          challengePin = ""
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
      OutlinedTextField(
        enrolledPin,
        { enrolledPin = it.take(8) },
        label = { Text("Rehearsal PIN (4–8 digits)") },
        enabled = !review && !busy,
        visualTransformation = PasswordVisualTransformation(),
      )
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
            if (parsed.first == null) message = parsed.second ?: "Invalid amount"
            else {
              review = true
              paymentKey = UUID.randomUUID().toString()
              attempt = null
              allowRetry = false
              challengePin = ""
              message = "Review before confirming. No real money moves."
            }
          },
          enabled = !busy,
        ) { Text("Review payment") }
      } else {
        Text("Confirm £$amount to $recipient")
        if (method == PaymentMethod.card) {
          Text("Strong customer authentication")
          Button(
            onClick = {
              val currentAttempt = prepareAttempt()
              confirmDeviceBiometric(activity) { ok ->
                var started = false
                val decision = currentAttempt.resumeAfterSca(ok, "") { key ->
                  started = true
                  sendPayment(key)
                }
                message = when {
                  decision is ScaDecision.Confirmed && started -> "Biometric confirmation accepted. Sending the same payment."
                  decision is ScaDecision.Confirmed -> "This payment is already in progress."
                  else -> "Biometric confirmation was not completed. The payment was not sent."
                }
                allowRetry = currentAttempt.canRetry
              }
            },
            enabled = !busy,
          ) { Text("Confirm with biometrics") }
          OutlinedTextField(
            challengePin,
            { challengePin = it.take(8) },
            label = { Text("Enter rehearsal PIN") },
            enabled = !busy,
            visualTransformation = PasswordVisualTransformation(),
          )
          Button(
            onClick = {
              val currentAttempt = prepareAttempt()
              var started = false
              val decision = currentAttempt.resumeAfterSca(false, challengePin) { key ->
                started = true
                sendPayment(key)
              }
              message = when {
                decision is ScaDecision.Confirmed && started -> "PIN confirmation accepted. Sending the same payment."
                decision is ScaDecision.Confirmed -> "This payment is already in progress."
                else -> "PIN confirmation did not match. The payment was not sent."
              }
              allowRetry = currentAttempt.canRetry
            },
            enabled = !busy,
          ) { Text("Confirm with PIN") }
        } else {
          Text("Worldpay bank handoff uses the allowlisted rehearsal host.")
          Button(
            onClick = {
              val currentAttempt = prepareAttempt()
              val url = currentAttempt.startHandoff { openAllowlistedBank(activity, it) }
              allowRetry = currentAttempt.canRetry
              message = when {
                url != null -> "Continue at your bank. This payment is sent only after the signed return is valid."
                currentAttempt.isSubmitting -> "This payment is already in progress."
                else -> "The bank page was not opened. The payment was not sent."
              }
            },
            enabled = !busy,
          ) { Text("Continue at your bank") }
          Button(
            onClick = {
              val link = attempt?.rehearsalReturnUrl()
              if (link == null) message = "Open the bank handoff before delivering a return."
              else onDeliverReturn(link)
            },
            enabled = !busy,
          ) { Text("Deliver signed bank return") }
        }
        if (allowRetry) {
          Button(
            onClick = {
              val currentAttempt = attempt
              if (currentAttempt != null && currentAttempt.submitIfCleared { sendPayment(it) }) {
                allowRetry = false
                message = "Retrying the same payment."
              } else message = "The payment was not sent again."
            },
            enabled = !busy,
          ) { Text("Retry same payment") }
        }
        TextButton(
          onClick = {
            review = false
            paymentKey = UUID.randomUUID().toString()
            attempt = null
            allowRetry = false
            challengePin = ""
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
