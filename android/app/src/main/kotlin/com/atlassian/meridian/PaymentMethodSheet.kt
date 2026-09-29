package com.atlassian.meridian

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// MARK: - Payment Method Bottom Sheet Content
// Renders dynamic payment methods grouped from the server catalog.
// Callers embed this inside a ModalBottomSheetLayout or equivalent.
// Shows a loading skeleton while catalog is null, and an empty state
// when no providers are returned by the server.

@Composable
fun PaymentMethodSheetContent(
  catalog: CatalogResponse?,
  onSelect: (Provider, String) -> Unit,
) {
  val isLargeScreen = LocalConfiguration.current.screenWidthDp >= 600
  val sheetHeight = if (isLargeScreen) Modifier.fillMaxHeight() else Modifier.fillMaxHeight(0.6f)

  Column(
    modifier = Modifier
      .fillMaxWidth()
      .then(sheetHeight)
      .padding(bottom = 24.dp),
  ) {
    // Drag handle
    Box(
      modifier = Modifier
        .align(Alignment.CenterHorizontally)
        .padding(top = 12.dp, bottom = 8.dp)
        .size(width = 40.dp, height = 4.dp)
        .clip(RoundedCornerShape(2.dp))
        .background(Color.LightGray),
    )
    Text(
      "Payment method",
      style = MaterialTheme.typography.h6,
      modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
    )
    Divider()
    when {
      catalog == null -> PaymentMethodSkeleton()
      catalog.providers.isEmpty -> PaymentMethodEmptyState()
      else -> PaymentMethodList(providers = catalog.providers, onSelect = onSelect)
    }
  }
}

// MARK: - Provider List

@Composable
private fun PaymentMethodList(
  providers: List<Provider>,
  onSelect: (Provider, String) -> Unit,
) {
  val cardProviders = providers.filter { "card" in it.methods }
  val bankProviders = providers.filter { "bank" in it.methods }
  LazyColumn {
    if (cardProviders.isNotEmpty()) {
      item {
        Text(
          "Card payments",
          style = MaterialTheme.typography.caption,
          color = MaterialTheme.colors.onSurface.copy(alpha = 0.6f),
          modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
        )
      }
      items(cardProviders) { provider ->
        ProviderRow(provider = provider, method = "card", onSelect = onSelect)
      }
    }
    if (bankProviders.isNotEmpty()) {
      item {
        Divider(modifier = Modifier.padding(vertical = 4.dp))
        Text(
          "Bank payments",
          style = MaterialTheme.typography.caption,
          color = MaterialTheme.colors.onSurface.copy(alpha = 0.6f),
          modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
        )
      }
      items(bankProviders) { provider ->
        ProviderRow(provider = provider, method = "bank", onSelect = onSelect)
      }
    }
  }
}

// MARK: - Provider Row

@Composable
private fun ProviderRow(
  provider: Provider,
  method: String,
  onSelect: (Provider, String) -> Unit,
) {
  val isEligible = provider.methods.isNotEmpty()
  val accentColor = when (provider.id.lowercase()) {
    "adyen"    -> Color(0xFF0072E5)
    "worldpay" -> Color(0xFF128773)
    else       -> MaterialTheme.colors.primary
  }
  TextButton(
    onClick = { if (isEligible) onSelect(provider, method) },
    enabled = isEligible,
    modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
  ) {
    Row(
      verticalAlignment = Alignment.CenterVertically,
      modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
    ) {
      Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
          .size(40.dp)
          .clip(RoundedCornerShape(8.dp))
          .background(accentColor.copy(alpha = if (isEligible) 1f else 0.3f)),
      ) {
        Icon(
          imageVector = if (method == "card") Icons.Filled.CreditCard else Icons.Filled.AccountBalance,
          contentDescription = null,
          tint = Color.White,
          modifier = Modifier.size(20.dp),
        )
      }
      Spacer(Modifier.width(12.dp))
      Column(modifier = Modifier.weight(1f)) {
        Text(
          provider.name,
          style = MaterialTheme.typography.body1,
          color = if (isEligible) MaterialTheme.colors.onSurface else MaterialTheme.colors.onSurface.copy(alpha = 0.4f),
        )
        Text(
          provider.description,
          style = MaterialTheme.typography.caption,
          color = MaterialTheme.colors.onSurface.copy(alpha = 0.6f),
          maxLines = 2,
        )
      }
      if (!isEligible) {
        Text(
          "Unavailable",
          fontSize = 10.sp,
          color = MaterialTheme.colors.onSurface.copy(alpha = 0.4f),
        )
      }
    }
  }
}

// MARK: - Loading Skeleton

@Composable
private fun PaymentMethodSkeleton() {
  Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
    repeat(4) {
      Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.padding(vertical = 10.dp),
      ) {
        Box(
          modifier = Modifier
            .size(40.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(Color.LightGray.copy(alpha = 0.4f)),
        )
        Spacer(Modifier.width(12.dp))
        Column {
          Box(
            modifier = Modifier
              .height(14.dp).width(120.dp)
              .clip(RoundedCornerShape(4.dp))
              .background(Color.LightGray.copy(alpha = 0.4f)),
          )
          Spacer(Modifier.height(6.dp))
          Box(
            modifier = Modifier
              .height(12.dp).width(180.dp)
              .clip(RoundedCornerShape(4.dp))
              .background(Color.LightGray.copy(alpha = 0.3f)),
          )
        }
      }
    }
  }
}

// MARK: - Empty State

@Composable
private fun PaymentMethodEmptyState() {
  Box(
    contentAlignment = Alignment.Center,
    modifier = Modifier.fillMaxSize().padding(32.dp),
  ) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
      Icon(
        Icons.Filled.CreditCard,
        contentDescription = null,
        tint = Color.Gray,
        modifier = Modifier.size(48.dp),
      )
      Spacer(Modifier.height(16.dp))
      Text("No payment methods available", style = MaterialTheme.typography.h6)
      Spacer(Modifier.height(8.dp))
      Text(
        "Check back later or contact support.",
        style = MaterialTheme.typography.body2,
        color = MaterialTheme.colors.onSurface.copy(alpha = 0.6f),
      )
    }
  }
}
