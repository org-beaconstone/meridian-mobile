package com.atlassian.meridian

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val link = intent?.data?.toString()
    setContent {
      MaterialTheme(colors = lightColors(primary = Color(0xFF142C35), secondary = Color(0xFFD5B77A))) {
        MeridianScreen(initialLink = link)
      }
    }
  }
}

@Composable fun MeridianScreen(initialLink: String? = null) {
  val scope = rememberCoroutineScope()
  val saver = Saver<PaymentScreenModel, String>(
    save = { it.checkpointJson() },
    restore = { saved ->
      PaymentScreenModel.restore(saved) ?: PaymentScreenModel(
        endpoint = "http://10.0.2.2:8080/api/v1",
        room = "meridian-rehearsal",
      )
    },
  )
  var model by rememberSaveable(stateSaver = saver) {
    mutableStateOf(
      PaymentScreenModel(
        endpoint = "http://10.0.2.2:8080/api/v1",
        room = "meridian-rehearsal",
      )
    )
  }
  var revision by remember { mutableStateOf(0) }
  var client by remember { mutableStateOf<MeridianClient?>(null) }
  var state by remember { mutableStateOf<BankState?>(null) }
  var catalog by remember { mutableStateOf<CatalogResponse?>(null) }
  fun mutate(block: () -> Unit) {
    block()
    revision++
  }
  LaunchedEffect(initialLink) {
    if (!initialLink.isNullOrBlank()) {
      model.openReturn(initialLink, System.currentTimeMillis())
      revision++
    }
  }
  LaunchedEffect(client) {
    val current = client
    while (current != null && current === client) {
      val started = model.generation
      if (!model.busy) try {
        val fresh = current.getState()
        val definitions = current.getCatalog()
        if (current === client && started == model.generation && !model.busy) {
          state = fresh
          catalog = definitions
          model.rememberCatalog(
            CachedCatalog(
              demoDate = definitions.demoDate,
              currency = definitions.currency,
              recipientIds = definitions.recipients.map { it.id },
              providerIds = definitions.providers.map { it.id },
            ),
            nowMillis = System.currentTimeMillis(),
          )
          model.message = "Connected to shared Java API"
          revision++
        }
      } catch (e: Exception) {
        if (current === client) {
          model.message = "API unavailable: ${e.message}"
          revision++
        }
      }
      delay(2000)
    }
  }
  if (revision < 0) return
  val language = java.util.Locale.getDefault().toLanguageTag()
  val direction = if (layoutDirectionForLanguage(language) == "rtl") LayoutDirection.Rtl else LayoutDirection.Ltr
  val fontScale = LocalDensity.current.fontScale
  val bucket = when {
    fontScale >= 1.6f -> "accessibility"
    fontScale >= 1.15f -> "large"
    else -> "standard"
  }
  val balanceSize = scaledFontSize(38.0, fontScaleFor(bucket))
  CompositionLocalProvider(LocalLayoutDirection provides direction) {
    Column(
      Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
      verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
      Text("meridian", style = MaterialTheme.typography.h4)
      Text("Native Android · simulated GBP payments", style = MaterialTheme.typography.caption)
      OutlinedTextField(model.endpoint, { mutate { model.endpoint = it } }, label = { Text("API base URL") }, enabled = !model.busy)
      OutlinedTextField(model.room, { mutate { model.room = it } }, label = { Text("Shared rehearsal room") }, enabled = !model.busy)
      Button(
        onClick = {
          mutate {
            if (model.connect()) {
              try {
                client = MeridianClient(model.endpoint, model.runtime.checkpoint.sessionId)
                state = null
                catalog = null
              } catch (e: Exception) {
                model.message = e.message ?: "Invalid configuration"
              }
            }
          }
        },
        enabled = !model.busy,
        modifier = Modifier.heightIn(min = 48.dp),
      ) { Text("Connect") }
      Text(model.message)
      state?.let { current ->
        Card(backgroundColor = Color(0xFF142C35), contentColor = Color.White, modifier = Modifier.fillMaxWidth()) {
          Column(Modifier.padding(22.dp).semantics { contentDescription = "Everyday account balance ${money(current.balance)}" }) {
            Text("Everyday account")
            Text(money(current.balance), fontSize = balanceSize.sp)
            Text("Room: ${model.runtime.checkpoint.sessionId}")
          }
        }
        Text("Make a payment", style = MaterialTheme.typography.h6)
        catalog?.recipients?.forEach { person ->
          Row {
            RadioButton(
              selected = model.recipientId == person.id,
              onClick = { mutate { model.recipientId = person.id } },
              enabled = !model.reviewing && !model.busy,
            )
            Text(person.name, Modifier.padding(top = 12.dp))
          }
        }
        OutlinedTextField(
          model.amountInput,
          { mutate { model.amountInput = it } },
          label = { Text("Amount (GBP)") },
          enabled = !model.reviewing && !model.busy,
        )
        OutlinedTextField(
          model.note,
          { mutate { model.note = it.take(200) } },
          label = { Text("Reference") },
          enabled = !model.reviewing && !model.busy,
        )
        Row {
          RadioButton(
            model.method == PaymentMethod.card,
            { mutate { model.method = PaymentMethod.card } },
            enabled = !model.reviewing && !model.busy,
          )
          Text("Debit card · Adyen", Modifier.padding(top = 12.dp))
        }
        Row {
          RadioButton(
            model.method == PaymentMethod.bank,
            { mutate { model.method = PaymentMethod.bank } },
            enabled = !model.reviewing && !model.busy,
          )
          Text("Bank payment · Worldpay", Modifier.padding(top = 12.dp))
        }
        val recipientName = catalog?.recipients?.firstOrNull { it.id == model.recipientId }?.name ?: model.recipientId
        val a11y = model.confirmationAccessibility(recipientName, language, fontScaleFor(bucket), "talkback")
        if (!model.reviewing) {
          Button(
            onClick = { mutate { model.review() } },
            enabled = !model.busy,
            modifier = Modifier.heightIn(min = 48.dp),
          ) { Text("Review payment") }
        } else {
          Text("Confirm £${model.amountInput} to ${model.recipientId}")
          Button(
            onClick = {
              val active = client
              val draft = model.submitInstruction()
              if (active != null && draft != null && !model.busy) {
                mutate {
                  model.busy = true
                  model.generation++
                }
                scope.launch {
                  try {
                    val payMethod = if (draft.method == "bank") PaymentMethod.bank else PaymentMethod.card
                    val result = active.submitPayment(
                      recipientId = draft.recipientId,
                      amountMinor = draft.amountMinor,
                      method = payMethod,
                      note = draft.note,
                      idempotencyKey = draft.idempotencyKey,
                    )
                    if (result.ok) {
                      state = result.state
                      model.markSettled()
                    } else {
                      model.markUncertain(result.error ?: "Awaiting confirmation. Retry the same payment.")
                    }
                  } catch (e: Exception) {
                    model.markUncertain("Outcome may be unknown: ${e.message}. Retry keeps the same key.")
                  } finally {
                    model.generation++
                    model.busy = false
                    revision++
                  }
                }
              }
            },
            enabled = !model.busy,
            modifier = Modifier.heightIn(min = a11y.minimumTouchTargetPt.dp).semantics {
              contentDescription = a11y.label
            },
          ) { Text(if (model.busy) "Confirming…" else "Confirm payment") }
          TextButton(
            onClick = { mutate { model.edit() } },
            enabled = !model.busy,
            modifier = Modifier.heightIn(min = 48.dp),
          ) { Text("Edit details") }
        }
        Text("Recent activity", style = MaterialTheme.typography.h6)
        current.transactions.reversed().take(8).forEach { transaction ->
          Text(
            "${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}",
            modifier = Modifier.semantics {
              contentDescription = "${transaction.name}, ${money(transaction.amount)}"
            },
          )
        }
        Text("Budgets", style = MaterialTheme.typography.h6)
        current.budgets.forEach { budget -> Text("${budget.category} · ${money(budget.limit)}") }
      }
    }
  }
}
