package com.atlassian.meridian

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Search
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
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

// Which sheet is currently active in the single ModalBottomSheetLayout
private enum class ActiveSheet { Method, Bank }

@Composable
fun MeridianScreen() {
  val scope = rememberCoroutineScope()
  val configuration = LocalConfiguration.current
  val fontScale = LocalDensity.current.fontScale
  // Promote sheet to full-screen on tablets (≥600 dp) or large accessibility text (≥1.5×)
  val expandFull = configuration.screenWidthDp >= 600 || fontScale >= 1.5f

  var base by remember { mutableStateOf("http://10.0.2.2:8080/api/v1") }
  var room by remember { mutableStateOf("meridian-rehearsal") }
  var client by remember { mutableStateOf<MeridianClient?>(null) }
  var state by remember { mutableStateOf<BankState?>(null) }
  var catalog by remember { mutableStateOf<CatalogResponse?>(null) }
  var recipient by remember { mutableStateOf("northline-studio") }
  var amount by remember { mutableStateOf("") }
  var note by remember { mutableStateOf("") }
  var selectedMethod by remember { mutableStateOf<PaymentMethodDescriptor?>(null) }
  var selectedBank by remember { mutableStateOf<BankOption?>(null) }
  var review by remember { mutableStateOf(false) }
  var busy by remember { mutableStateOf(false) }
  var paymentKey by remember { mutableStateOf(UUID.randomUUID().toString()) }
  var message by remember { mutableStateOf("Fictional payment rehearsal. Connect to the Java API.") }
  var revision by remember { mutableStateOf(0) }

  var activeSheet by remember { mutableStateOf<ActiveSheet?>(null) }
  val sheetState = rememberModalBottomSheetState(
    initialValue = ModalBottomSheetValue.Hidden,
    skipHalfExpanded = expandFull,
  )

  // Synchronise sheet visibility with activeSheet state
  LaunchedEffect(activeSheet) {
    if (activeSheet != null) sheetState.show() else sheetState.hide()
  }
  // Clear activeSheet when the sheet is dismissed by swipe
  LaunchedEffect(sheetState.currentValue) {
    if (sheetState.currentValue == ModalBottomSheetValue.Hidden) activeSheet = null
  }

  LaunchedEffect(client) {
    val current = client
    while (current != null) {
      val started = revision
      if (!busy) try {
        val fresh = current.getState()
        val definitions = current.getCatalog()
        if (current === client && started == revision && !busy) {
          state = fresh; catalog = definitions; message = "Connected to shared Java API"
          // Auto-select first eligible method when catalog loads
          if (selectedMethod == null) {
            selectedMethod = paymentMethodDescriptors(definitions.providers).firstOrNull { it.eligible }
          }
        }
      } catch (e: Exception) {
        if (current === client) message = "API unavailable: ${e.message}"
      }
      delay(2000)
    }
  }

  val descriptors = remember(catalog) { paymentMethodDescriptors(catalog?.providers ?: emptyList()) }

  ModalBottomSheetLayout(
    sheetState = sheetState,
    sheetShape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp),
    sheetContent = {
      when (activeSheet) {
        ActiveSheet.Method -> PaymentMethodSheetContent(
          methods = descriptors,
          selected = selectedMethod,
          onSelect = { descriptor ->
            selectedMethod = descriptor
            if (!descriptor.requiresBankChoice) selectedBank = null
            scope.launch { sheetState.hide() }
          },
          onDismiss = { scope.launch { sheetState.hide() } },
        )
        ActiveSheet.Bank -> BankSelectorSheetContent(
          selected = selectedBank,
          onSelect = { bank ->
            selectedBank = bank
            scope.launch { sheetState.hide() }
          },
          onDismiss = { scope.launch { sheetState.hide() } },
        )
        null -> Spacer(Modifier.height(1.dp)) // sheetContent must not be empty
      }
    },
  ) {
    Column(
      Modifier
        .fillMaxSize()
        .verticalScroll(rememberScrollState())
        .padding(24.dp),
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
            state = null; catalog = null; review = false; revision++
            selectedMethod = null; selectedBank = null
            paymentKey = UUID.randomUUID().toString()
          } catch (e: Exception) { message = e.message ?: "Invalid configuration" }
        },
        enabled = !busy,
      ) { Text("Connect") }
      Text(message)

      state?.let { current ->
        Card(
          backgroundColor = Color(0xFF142C35),
          contentColor = Color.White,
          modifier = Modifier.fillMaxWidth(),
        ) {
          Column(Modifier.padding(22.dp)) {
            Text("Everyday account")
            Text(money(current.balance), style = MaterialTheme.typography.h3)
            Text("Room: $room")
          }
        }

        Text("Make a payment", style = MaterialTheme.typography.h6)
        catalog?.recipients?.forEach { person ->
          Row(verticalAlignment = Alignment.CenterVertically) {
            RadioButton(
              selected = recipient == person.id,
              onClick = { recipient = person.id },
              enabled = !review && !busy,
            )
            Text(person.name, Modifier.padding(start = 4.dp))
          }
        }
        OutlinedTextField(
          amount, { amount = it },
          label = { Text("Amount (GBP)") },
          enabled = !review && !busy,
        )
        OutlinedTextField(
          note, { note = it.take(200) },
          label = { Text("Reference") },
          enabled = !review && !busy,
        )

        // Dynamic payment-method selector — replaces fixed Adyen/Worldpay rows
        MethodSelectorButton(
          selected = selectedMethod,
          catalogLoaded = catalog != null,
          hasDescriptors = descriptors.isNotEmpty(),
          disabled = review || busy,
        ) {
          activeSheet = ActiveSheet.Method
          scope.launch { sheetState.show() }
        }

        // Bank selector — only visible when the chosen method requires a bank choice
        if (selectedMethod?.requiresBankChoice == true) {
          BankSelectorButton(selected = selectedBank, disabled = review || busy) {
            activeSheet = ActiveSheet.Bank
            scope.launch { sheetState.show() }
          }
        }

        if (!review) {
          Button(
            onClick = {
              val parsed = parseAmount(amount)
              when {
                parsed.first == null -> message = parsed.second ?: "Invalid amount"
                selectedMethod == null -> message = "Please select a payment method"
                selectedMethod?.requiresBankChoice == true && selectedBank == null ->
                  message = "Please select a bank"
                else -> {
                  review = true; paymentKey = UUID.randomUUID().toString()
                }
              }
            },
            enabled = !busy,
          ) { Text("Review payment") }
        } else {
          Text("Confirm £$amount to $recipient")
          selectedMethod?.let { m -> Text("via ${m.label} · ${m.providerName}", style = MaterialTheme.typography.caption) }
          selectedBank?.let { b -> Text("Bank: ${b.name}", style = MaterialTheme.typography.caption) }
          Button(
            onClick = {
              val active = client
              val minor = parseAmount(amount).first
              val descriptor = selectedMethod
              if (active != null && minor != null && descriptor != null && !busy) {
                busy = true; revision++
                scope.launch {
                  try {
                    val result = active.submitPayment(
                      recipientId = recipient,
                      amountMinor = minor,
                      method = descriptor.method,
                      note = note,
                      idempotencyKey = paymentKey,
                    )
                    if (result.ok) {
                      state = result.state; review = false; amount = ""; note = ""
                      paymentKey = UUID.randomUUID().toString()
                      message = "Demo payment complete"
                    } else {
                      message = result.error ?: "Awaiting confirmation. Retry the same payment."
                    }
                  } catch (e: Exception) {
                    message = "Outcome may be unknown: ${e.message}. Retry keeps the same key."
                  } finally {
                    revision++; busy = false
                  }
                }
              }
            },
            enabled = !busy,
          ) { Text(if (busy) "Confirming…" else "Confirm payment") }
          TextButton(
            onClick = { review = false; paymentKey = UUID.randomUUID().toString() },
            enabled = !busy,
          ) { Text("Edit details") }
        }

        Text("Recent activity", style = MaterialTheme.typography.h6)
        current.transactions.reversed().take(8).forEach { txn ->
          Text("${txn.name} · ${money(txn.amount)} · ${txn.provider}")
        }
        Text("Budgets", style = MaterialTheme.typography.h6)
        current.budgets.forEach { budget -> Text("${budget.category} · ${money(budget.limit)}") }
      }
    }
  }
}

// MARK: - Method Selector Button

@Composable
private fun MethodSelectorButton(
  selected: PaymentMethodDescriptor?,
  catalogLoaded: Boolean,
  hasDescriptors: Boolean,
  disabled: Boolean,
  onClick: () -> Unit,
) {
  val icon: ImageVector = when (selected?.method) {
    PaymentMethod.bank -> Icons.Filled.AccountBalance
    else -> Icons.Filled.CreditCard
  }
  Surface(
    shape = RoundedCornerShape(8.dp),
    color = MaterialTheme.colors.surface,
    elevation = 1.dp,
    modifier = Modifier
      .fillMaxWidth()
      .clickable(enabled = !disabled && (hasDescriptors || !catalogLoaded), onClick = onClick),
  ) {
    Row(
      Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      Icon(
        imageVector = icon,
        contentDescription = null,
        tint = if (selected != null) MaterialTheme.colors.primary else Color.Gray,
      )
      Column(Modifier.weight(1f)) {
        if (selected != null) {
          Text(selected.label, style = MaterialTheme.typography.body1)
          Text(selected.providerName, style = MaterialTheme.typography.caption, color = Color.Gray)
        } else if (!catalogLoaded) {
          // Skeleton placeholder while catalog loads
          SkeletonBlock(width = 140.dp, height = 14.dp)
          Spacer(Modifier.height(4.dp))
          SkeletonBlock(width = 80.dp, height = 10.dp)
        } else {
          Text("Select payment method", color = Color.Gray)
        }
      }
    }
  }
}

// MARK: - Bank Selector Button

@Composable
private fun BankSelectorButton(
  selected: BankOption?,
  disabled: Boolean,
  onClick: () -> Unit,
) {
  Surface(
    shape = RoundedCornerShape(8.dp),
    color = MaterialTheme.colors.surface,
    elevation = 1.dp,
    modifier = Modifier
      .fillMaxWidth()
      .clickable(enabled = !disabled, onClick = onClick),
  ) {
    Row(
      Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      Icon(
        imageVector = Icons.Filled.AccountBalance,
        contentDescription = null,
        tint = MaterialTheme.colors.primary,
      )
      Column(Modifier.weight(1f)) {
        if (selected != null) {
          Text(selected.name, style = MaterialTheme.typography.body1)
          Text(selected.sortCode, style = MaterialTheme.typography.caption, color = Color.Gray)
        } else {
          Text("Select bank", color = Color.Gray)
        }
      }
    }
  }
}

// MARK: - Payment Method Sheet Content

@Composable
private fun PaymentMethodSheetContent(
  methods: List<PaymentMethodDescriptor>,
  selected: PaymentMethodDescriptor?,
  onSelect: (PaymentMethodDescriptor) -> Unit,
  onDismiss: () -> Unit,
) {
  Column(Modifier.fillMaxWidth()) {
    // Sheet handle
    Box(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 6.dp), contentAlignment = Alignment.Center) {
      Box(Modifier.width(40.dp).height(4.dp).background(Color.LightGray, RoundedCornerShape(2.dp)))
    }
    Row(
      Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
      horizontalArrangement = Arrangement.SpaceBetween,
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Text("Payment method", style = MaterialTheme.typography.h6)
      IconButton(onClick = onDismiss) { Icon(Icons.Filled.Close, contentDescription = "Close") }
    }
    Divider()
    if (methods.isEmpty()) {
      // Empty state
      Box(Modifier.fillMaxWidth().padding(48.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
          Icon(Icons.Filled.CreditCard, contentDescription = null, modifier = Modifier.size(52.dp), tint = Color.LightGray)
          Text("No payment methods available", style = MaterialTheme.typography.body1, color = Color.Gray)
          Text("Please try again later.", style = MaterialTheme.typography.caption, color = Color.LightGray)
        }
      }
    } else {
      LazyColumn(Modifier.fillMaxWidth()) {
        items(methods, key = { it.id }) { descriptor ->
          val icon = if (descriptor.method == PaymentMethod.bank) Icons.Filled.AccountBalance else Icons.Filled.CreditCard
          ListItem(
            modifier = Modifier
              .fillMaxWidth()
              .clickable(enabled = descriptor.eligible) { onSelect(descriptor) }
              .then(if (!descriptor.eligible) Modifier.then(Modifier) else Modifier),
            icon = {
              Icon(
                imageVector = icon,
                contentDescription = null,
                tint = if (descriptor.eligible) MaterialTheme.colors.primary else Color.LightGray,
              )
            },
            text = {
              Text(
                descriptor.label,
                color = if (descriptor.eligible) Color.Unspecified else Color.LightGray,
              )
            },
            secondaryText = {
              Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(descriptor.providerName, color = Color.Gray)
                if (!descriptor.eligible) {
                  Text(
                    "Unavailable",
                    style = MaterialTheme.typography.overline,
                    color = Color.Gray,
                    modifier = Modifier
                      .background(Color(0xFFF0F0F0), RoundedCornerShape(4.dp))
                      .padding(horizontal = 4.dp, vertical = 2.dp),
                  )
                }
              }
            },
            trailing = {
              if (selected?.id == descriptor.id) {
                Text("✓", color = MaterialTheme.colors.primary, style = MaterialTheme.typography.h6)
              }
            },
          )
          Divider(startIndent = 56.dp)
        }
      }
    }
  }
}

// MARK: - Bank Selector Sheet Content

@Composable
private fun BankSelectorSheetContent(
  selected: BankOption?,
  onSelect: (BankOption) -> Unit,
  onDismiss: () -> Unit,
) {
  var query by remember { mutableStateOf("") }
  val filtered = remember(query) {
    demoBanks.filter { query.isBlank() || it.name.contains(query, ignoreCase = true) }
  }

  Column(Modifier.fillMaxWidth()) {
    // Sheet handle
    Box(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 6.dp), contentAlignment = Alignment.Center) {
      Box(Modifier.width(40.dp).height(4.dp).background(Color.LightGray, RoundedCornerShape(2.dp)))
    }
    Row(
      Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
      horizontalArrangement = Arrangement.SpaceBetween,
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Text("Select bank", style = MaterialTheme.typography.h6)
      IconButton(onClick = onDismiss) { Icon(Icons.Filled.Close, contentDescription = "Close") }
    }
    // Search field
    OutlinedTextField(
      value = query,
      onValueChange = { query = it },
      modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
      label = { Text("Search banks") },
      leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
      singleLine = true,
    )
    Divider()
    if (filtered.isEmpty()) {
      Box(Modifier.fillMaxWidth().padding(48.dp), contentAlignment = Alignment.Center) {
        Text("No banks match \"$query\"", color = Color.Gray, style = MaterialTheme.typography.body2)
      }
    } else {
      LazyColumn(Modifier.fillMaxWidth()) {
        items(filtered, key = { it.id }) { bank ->
          ListItem(
            modifier = Modifier.fillMaxWidth().clickable { onSelect(bank) },
            icon = { Icon(Icons.Filled.AccountBalance, contentDescription = null, tint = MaterialTheme.colors.primary) },
            text = { Text(bank.name) },
            secondaryText = { Text(bank.sortCode, color = Color.Gray) },
            trailing = {
              if (selected?.id == bank.id) {
                Text("✓", color = MaterialTheme.colors.primary, style = MaterialTheme.typography.h6)
              }
            },
          )
          Divider(startIndent = 56.dp)
        }
      }
    }
  }
}

// MARK: - Skeleton Loading Block

@Composable
private fun SkeletonBlock(width: androidx.compose.ui.unit.Dp, height: androidx.compose.ui.unit.Dp) {
  var alpha by remember { mutableStateOf(0.6f) }
  LaunchedEffect(Unit) {
    while (true) {
      alpha = if (alpha > 0.4f) 0.3f else 0.6f
      delay(700)
    }
  }
  Box(
    Modifier
      .width(width)
      .height(height)
      .background(Color.LightGray.copy(alpha = alpha), RoundedCornerShape(4.dp)),
  )
}
