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
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
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
  var session by remember { mutableStateOf(AuthSession.resolving()) }
  var sessionCheck by remember { mutableStateOf(0) }
  var resetOnCheck by remember { mutableStateOf(false) }
  var connectedRoom by remember { mutableStateOf<String?>(null) }
  var connectedBase by remember { mutableStateOf<String?>(null) }
  val guard = remember { SessionRefreshGuard() }
  val roomNow by rememberUpdatedState(room)
  val baseNow by rememberUpdatedState(base)
  val resetNow by rememberUpdatedState(resetOnCheck)
  val banner = presentSessionBanner(session)

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
      } catch (e: CancellationException) {
        throw e
      } catch (e: Exception) {
        if (current === client) message = "API unavailable: ${e.message}"
      }
      delay(2000)
    }
  }

  LaunchedEffect(sessionCheck) {
    val token = guard.next()
    val sessionId = roomNow
    val baseUrl = baseNow
    val reset = resetNow
    session = AuthSession.resolving()
    val resolved = try {
      val early = classifySessionId(sessionId)
      if (early != null) {
        if (early.phase == AuthSessionPhase.UNCONFIRMED && guard.isCurrent(token)) message = "Invalid room"
        if (early.phase == AuthSessionPhase.SIGNED_OUT && guard.isCurrent(token)) {
          client = null
          state = null
          catalog = null
          connectedRoom = null
          connectedBase = null
        }
        early
      } else {
        val probed = MeridianClient(baseUrl, sessionId)
        val next = probed.probeAuthSession()
        if (guard.isCurrent(token) && roomNow == sessionId && baseNow == baseUrl) {
          when (next.phase) {
            AuthSessionPhase.ACTIVE, AuthSessionPhase.EXPIRING, AuthSessionPhase.ACTIVE_ELSEWHERE -> {
              val replace = reset || client == null || connectedRoom != sessionId || connectedBase != baseUrl
              if (replace) {
                client = probed
                state = null
                catalog = null
                connectedRoom = sessionId
                connectedBase = baseUrl
                revision++
              }
            }
            AuthSessionPhase.SIGNED_OUT -> {
              client = null
              state = null
              catalog = null
              connectedRoom = null
              connectedBase = null
              review = false
              message = "You've been signed out. Sign in to continue."
            }
            else -> Unit
          }
        }
        next
      }
    } catch (e: CancellationException) {
      throw e
    } catch (e: Exception) {
      if (guard.isCurrent(token) && client == null) {
        message = e.message ?: "Couldn't confirm the session."
      }
      AuthSession(AuthSessionPhase.UNCONFIRMED)
    }
    if (guard.isCurrent(token) && roomNow == sessionId && baseNow == baseUrl) session = resolved
  }

  Column(
    Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
    verticalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    SessionBannerView(
      banner = banner,
      onAction = {
        if (!busy) {
          resetOnCheck = false
          sessionCheck++
        }
      },
      actionEnabled = !busy,
    )
    Text("meridian", style = MaterialTheme.typography.h4)
    Text("Native Android · simulated GBP payments", style = MaterialTheme.typography.caption)
    OutlinedTextField(
      value = base,
      onValueChange = { base = it },
      label = { Text("API base URL") },
      enabled = !busy,
      modifier = Modifier.semantics { testTag = AuthScreenTags.API_BASE_URL }.fillMaxWidth(),
    )
    OutlinedTextField(
      value = room,
      onValueChange = { room = it },
      label = { Text("Shared rehearsal room") },
      enabled = !busy,
      modifier = Modifier.semantics { testTag = AuthScreenTags.ROOM }.fillMaxWidth(),
    )
    Button(
      onClick = {
        val early = classifySessionId(room)
        if (early != null) {
          guard.next()
          message = if (room.isBlank()) "You've been signed out. Sign in to continue." else "Invalid room"
          if (early.phase == AuthSessionPhase.SIGNED_OUT) {
            client = null
            state = null
            catalog = null
            connectedRoom = null
            connectedBase = null
            review = false
          }
          session = early
        } else {
          review = false
          paymentKey = UUID.randomUUID().toString()
          resetOnCheck = true
          sessionCheck++
        }
      },
      enabled = !busy,
      modifier = Modifier.semantics { testTag = AuthScreenTags.CONNECT },
    ) { Text("Connect") }
    Text(message)
    if (paymentContentAvailable(banner, state != null)) {
      state?.let { current ->
        Column(
          Modifier.semantics { testTag = AuthScreenTags.PAYMENT },
          verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
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
                if (active != null && minor != null && !busy) {
                  busy = true
                  revision++
                  scope.launch {
                    try {
                      val result = active.submitPayment(
                        recipientId = recipient,
                        amountMinor = minor,
                        method = method,
                        note = note,
                        idempotencyKey = paymentKey,
                      )
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
              },
              enabled = !busy,
            ) { Text(if (busy) "Confirming…" else "Confirm payment") }
            TextButton(
              onClick = {
                review = false
                paymentKey = UUID.randomUUID().toString()
              },
              enabled = !busy,
            ) { Text("Edit details") }
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
  }
}
