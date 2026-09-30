package com.atlassian.meridian

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent {
      MaterialTheme(
        colors = lightColors(
          primary = Color(PaymentTextColors.action.argb),
          onPrimary = Color(PaymentTextColors.onInk.argb),
          surface = Color(PaymentTextColors.surface.argb),
          background = Color(PaymentTextColors.canvas.argb),
          onSurface = Color(PaymentTextColors.ink.argb),
          onBackground = Color(PaymentTextColors.ink.argb),
        ),
      ) { MeridianScreen() }
    }
  }
}

@Composable
fun MeridianScreen() {
  val scope = rememberCoroutineScope()
  val ink = Color(PaymentTextColors.ink.argb)
  val secondary = Color(PaymentTextColors.secondary.argb)
  val onInk = Color(PaymentTextColors.onInk.argb)
  val onInkMuted = Color(PaymentTextColors.onInkMuted.argb)
  var base by remember { mutableStateOf("http://10.0.2.2:8080/api/v1") }
  var room by remember { mutableStateOf("meridian-rehearsal") }
  var client by remember { mutableStateOf<MeridianClient?>(null) }
  var state by remember { mutableStateOf<BankState?>(null) }
  var catalog by remember { mutableStateOf<CatalogResponse?>(null) }
  var catalogLoading by remember { mutableStateOf(false) }
  var catalogFailed by remember { mutableStateOf(false) }
  var recipient by remember { mutableStateOf("northline-studio") }
  var amount by remember { mutableStateOf("") }
  var note by remember { mutableStateOf("") }
  var corridor by remember { mutableStateOf(PaymentCorridor.EUROZONE) }
  var method by remember { mutableStateOf<PaymentMethod?>(PaymentMethod.card) }
  var review by remember { mutableStateOf(false) }
  var busy by remember { mutableStateOf(false) }
  var paymentKey by remember { mutableStateOf(UUID.randomUUID().toString()) }
  var message by remember { mutableStateOf("Fictional payment rehearsal. Connect to the Java API.") }
  var revision by remember { mutableStateOf(0) }
  val phase = paymentMethodPhase(catalog, catalogLoading, catalogFailed, corridor)

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
          catalogLoading = false
          catalogFailed = false
          message = "Connected to shared Java API"
        }
      } catch (e: Exception) {
        if (current === client) {
          catalogLoading = false
          if (catalog == null) catalogFailed = true
          message = "API unavailable: ${e.message}"
        }
      }
      delay(2000)
    }
  }

  LaunchedEffect(catalog, corridor, busy, review) {
    // A payment already under review keeps its rail and idempotency key.
    if (busy || review) return@LaunchedEffect
    when (val current = paymentMethodPhase(catalog, catalogLoading, catalogFailed, corridor)) {
      is PaymentMethodPhase.Ready -> {
        val chosen = method
        if (chosen != null && current.options.any { it.method == chosen }) return@LaunchedEffect
        method = current.options.first().method
      }
      is PaymentMethodPhase.Empty -> method = null
      else -> Unit
    }
  }

  BoxWithConstraints(
    Modifier
      .fillMaxSize()
      .background(Color(PaymentTextColors.canvas.argb)),
  ) {
    val wide = usesSideBySideRails(maxWidth.value.toDouble(), fontScale().toDouble())
    Column(
      Modifier
        .fillMaxSize()
        .verticalScroll(rememberScrollState())
        .padding(horizontal = if (wide) 32.dp else 20.dp, vertical = 24.dp),
      horizontalAlignment = Alignment.CenterHorizontally,
    ) {
      Column(
        Modifier.widthIn(max = 720.dp).fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(14.dp),
      ) {
        Text("meridian", color = ink, style = MaterialTheme.typography.h4)
        Text("Native Android · simulated GBP payments", color = secondary, style = MaterialTheme.typography.caption)
        OutlinedTextField(
          value = base,
          onValueChange = { base = it },
          label = { Text("API base URL") },
          enabled = !busy,
          modifier = Modifier.fillMaxWidth().semantics { contentDescription = "API base URL" },
        )
        OutlinedTextField(
          value = room,
          onValueChange = { room = it },
          label = { Text("Shared rehearsal room") },
          enabled = !busy,
          modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Shared rehearsal room" },
        )
        Button(
          onClick = {
            if (!Regex("[A-Za-z0-9_-]{3,64}").matches(room)) {
              message = "Invalid room"
            } else try {
              catalog = null
              catalogLoading = true
              catalogFailed = false
              state = null
              review = false
              revision++
              paymentKey = UUID.randomUUID().toString()
              client = MeridianClient(base, room)
            } catch (e: Exception) {
              catalogLoading = false
              catalogFailed = true
              message = e.message ?: "Invalid configuration"
            }
          },
          enabled = !busy,
        ) { Text("Connect") }
        Text(message, color = secondary, style = MaterialTheme.typography.body1)
        if (client != null) {
          state?.let { current -> BalanceCard(current, room, onInk, onInkMuted) }
          Text(
            "Make a payment",
            color = ink,
            style = MaterialTheme.typography.h6,
            modifier = Modifier.semantics { heading() },
          )
          catalog?.recipients?.forEach { person ->
            Row(
              Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .semantics(mergeDescendants = true) {
                  contentDescription = "Recipient ${person.name}" + if (recipient == person.id) ". Selected" else ""
                },
              verticalAlignment = Alignment.CenterVertically,
            ) {
              RadioButton(
                selected = recipient == person.id,
                onClick = { recipient = person.id },
                enabled = !review && !busy,
              )
              Text(person.name, color = ink, modifier = Modifier.padding(start = 8.dp))
            }
          }
          OutlinedTextField(
            value = amount,
            onValueChange = { amount = it },
            label = { Text("Amount (GBP)") },
            enabled = !review && !busy,
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Amount in British pounds, GBP" },
          )
          OutlinedTextField(
            value = note,
            onValueChange = { note = it.take(200) },
            label = { Text("Reference") },
            enabled = !review && !busy,
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Payment reference" },
          )
          PaymentCorridorSelection(
            selected = corridor,
            enabled = !review && !busy,
            onSelect = { corridor = it },
          )
          PaymentMethodSelection(
            phase = phase,
            selected = method,
            enabled = !review && !busy,
            onSelect = { method = it },
          )
          if (!review) {
            Button(
              onClick = {
                val parsed = parseAmount(amount)
                when {
                  parsed.first == null -> message = parsed.second ?: "Invalid amount"
                  method == null -> message = "Choose a payment method"
                  phase !is PaymentMethodPhase.Ready -> message = "Payment methods are not available for this corridor"
                  else -> {
                    review = true
                    paymentKey = UUID.randomUUID().toString()
                  }
                }
              },
              enabled = !busy && method != null && phase is PaymentMethodPhase.Ready,
            ) { Text("Review payment") }
          } else {
            val rail = method?.let { railLabel(it) } ?: "No rail"
            Text(
              "Confirm £$amount to $recipient via $rail",
              color = ink,
              fontWeight = FontWeight.SemiBold,
              modifier = Modifier.semantics {
                contentDescription = "Confirm $amount British pounds, GBP, to $recipient. " +
                  (method?.let { railAccessibilityLabel(it) } ?: "No payment rail selected.")
              },
            )
            Button(
              onClick = {
                val active = client
                val minor = parseAmount(amount).first
                val chosen = method
                if (active != null && minor != null && chosen != null && !busy) {
                  busy = true
                  revision++
                  scope.launch {
                    try {
                      val result = active.submitPayment(
                        recipientId = recipient,
                        amountMinor = minor,
                        method = chosen,
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
              enabled = !busy && method != null,
            ) { Text(if (busy) "Confirming…" else "Confirm payment") }
            TextButton(
              onClick = {
                review = false
                paymentKey = UUID.randomUUID().toString()
              },
              enabled = !busy,
            ) { Text("Edit details") }
          }
          state?.let { current ->
            Text("Recent activity", color = ink, style = MaterialTheme.typography.h6, modifier = Modifier.semantics { heading() })
            current.transactions.reversed().take(8).forEach { transaction ->
              Text(
                "${transaction.name} · ${money(transaction.amount)} · ${railLabelForMethodName(transaction.method)}",
                color = ink,
                modifier = Modifier.semantics {
                  contentDescription = "${transaction.name}. ${money(transaction.amount)}. Currency British pounds, GBP. ${railLabelForMethodName(transaction.method)}"
                },
              )
            }
            Text("Budgets", color = ink, style = MaterialTheme.typography.h6, modifier = Modifier.semantics { heading() })
            current.budgets.forEach { budget ->
              Text(
                "${budget.category} · ${money(budget.limit)}",
                color = ink,
                modifier = Modifier.semantics {
                  contentDescription = "${budget.category}. ${money(budget.limit)}. Currency British pounds, GBP"
                },
              )
            }
          }
        }
      }
    }
  }
}

@Composable
private fun BalanceCard(current: BankState, room: String, onInk: Color, onInkMuted: Color) {
  Card(
    backgroundColor = Color(PaymentTextColors.ink.argb),
    contentColor = onInk,
    modifier = Modifier.fillMaxWidth().semantics(mergeDescendants = true) {
      contentDescription = "Everyday account. Balance ${money(current.balance)}. Currency British pounds, GBP. Shared room $room"
    },
  ) {
    Column(Modifier.padding(22.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
      Text("Everyday account", color = onInkMuted, style = MaterialTheme.typography.body2)
      Text(
        money(current.balance),
        color = onInk,
        fontSize = 34.sp,
        fontWeight = FontWeight.Medium,
        maxLines = 1,
        softWrap = false,
        modifier = Modifier.horizontalScroll(rememberScrollState()),
      )
      Text("Room: $room", color = onInkMuted, style = MaterialTheme.typography.body2)
    }
  }
}

@Composable
private fun fontScale(): Float = androidx.compose.ui.platform.LocalDensity.current.fontScale
