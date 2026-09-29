package com.atlassian.meridian

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Search
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp

// MARK: - Searchable Bank Selector Content
// Displayed when the user's chosen method requires a bank choice.
// Filters providers from the catalog to those advertising "bank" in their
// methods list, then applies a live text search over name and description.
// Promotes to full-height on large-screen devices (≥600 dp wide).

@Composable
fun BankSelectorContent(
  providers: List<Provider>,
  onSelect: (Provider) -> Unit,
) {
  val isLargeScreen = LocalConfiguration.current.screenWidthDp >= 600
  val sheetHeight = if (isLargeScreen) Modifier.fillMaxHeight() else Modifier.fillMaxHeight(0.7f)

  var query by remember { mutableStateOf("") }

  val bankProviders = remember(providers) { providers.filter { "bank" in it.methods } }
  val filtered = remember(query, bankProviders) {
    if (query.isBlank()) bankProviders
    else bankProviders.filter {
      it.name.contains(query, ignoreCase = true) || it.description.contains(query, ignoreCase = true)
    }
  }

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
      "Select bank",
      style = MaterialTheme.typography.h6,
      modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
    )
    OutlinedTextField(
      value = query,
      onValueChange = { query = it },
      label = { Text("Search banks") },
      leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
      singleLine = true,
      modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
    )
    Spacer(Modifier.height(8.dp))
    when {
      bankProviders.isEmpty -> BankEmptyState()
      filtered.isEmpty -> BankNoResultsState(query = query)
      else -> BankList(providers = filtered, onSelect = onSelect)
    }
  }
}

// MARK: - Bank List

@Composable
private fun BankList(providers: List<Provider>, onSelect: (Provider) -> Unit) {
  LazyColumn {
    items(providers, key = { it.id }) { provider ->
      TextButton(
        onClick = { onSelect(provider) },
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
              .clip(CircleShape)
              .background(Color(0xFF128773)),
          ) {
            Text(
              provider.name.take(2).uppercase(),
              style = MaterialTheme.typography.caption.copy(
                color = Color.White,
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
              ),
            )
          }
          Spacer(Modifier.width(12.dp))
          Column(modifier = Modifier.weight(1f)) {
            Text(provider.name, style = MaterialTheme.typography.body1)
            Text(
              provider.description,
              style = MaterialTheme.typography.caption,
              color = MaterialTheme.colors.onSurface.copy(alpha = 0.6f),
              maxLines = 2,
            )
          }
          Icon(
            Icons.Filled.AccountBalance,
            contentDescription = null,
            tint = MaterialTheme.colors.onSurface.copy(alpha = 0.3f),
            modifier = Modifier.size(16.dp),
          )
        }
      }
      Divider(modifier = Modifier.padding(start = 68.dp))
    }
  }
}

// MARK: - No Search Results

@Composable
private fun BankNoResultsState(query: String) {
  Box(
    contentAlignment = Alignment.Center,
    modifier = Modifier.fillMaxSize().padding(32.dp),
  ) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
      Icon(
        Icons.Filled.Search,
        contentDescription = null,
        tint = Color.Gray,
        modifier = Modifier.size(40.dp),
      )
      Spacer(Modifier.height(12.dp))
      Text(
        "No banks matching \"$query\"",
        style = MaterialTheme.typography.body2,
        color = MaterialTheme.colors.onSurface.copy(alpha = 0.6f),
      )
    }
  }
}

// MARK: - Empty State

@Composable
private fun BankEmptyState() {
  Box(
    contentAlignment = Alignment.Center,
    modifier = Modifier.fillMaxSize().padding(32.dp),
  ) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
      Icon(
        Icons.Filled.AccountBalance,
        contentDescription = null,
        tint = Color.Gray,
        modifier = Modifier.size(48.dp),
      )
      Spacer(Modifier.height(16.dp))
      Text("No bank payment methods available", style = MaterialTheme.typography.h6)
      Spacer(Modifier.height(8.dp))
      Text(
        "No providers currently support bank payments.",
        style = MaterialTheme.typography.body2,
        color = MaterialTheme.colors.onSurface.copy(alpha = 0.6f),
      )
    }
  }
}
