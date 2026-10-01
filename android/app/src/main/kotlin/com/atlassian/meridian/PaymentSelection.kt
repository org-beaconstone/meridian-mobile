package com.atlassian.meridian

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.MaterialTheme
import androidx.compose.material.OutlinedTextField
import androidx.compose.material.Text
import androidx.compose.material.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

private val ink = Color(0xFF142C35)
private val eligibleGreen = Color(0xFF1B7F4E)
private val unavailableBrown = Color(0xFF8A4B08)
private val skeleton = Color(0xFFE4E7EA)

@Composable
fun MethodLogo(label: String, name: String) {
  Box(
    Modifier
      .size(40.dp)
      .clip(CircleShape)
      .background(ink)
      .semantics { contentDescription = "Logo for $name" },
    contentAlignment = Alignment.Center,
  ) {
    Text(label, color = Color.White, style = MaterialTheme.typography.caption, fontWeight = FontWeight.SemiBold)
  }
}

@Composable
fun SelectorSkeleton(label: String = "Loading payment methods") {
  Column(
    Modifier.semantics { contentDescription = label },
    verticalArrangement = Arrangement.spacedBy(16.dp),
  ) {
    repeat(3) {
      Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(40.dp).clip(CircleShape).background(skeleton))
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
          Box(Modifier.height(14.dp).width(168.dp).clip(RoundedCornerShape(4.dp)).background(skeleton))
          Box(Modifier.height(10.dp).width(108.dp).clip(RoundedCornerShape(4.dp)).background(skeleton))
        }
      }
    }
  }
}

@Composable
fun SelectorEmptyState(message: String) {
  Text(
    message,
    style = MaterialTheme.typography.body1,
    color = Color.DarkGray,
    modifier = Modifier.padding(vertical = 28.dp).semantics { contentDescription = message },
  )
}

@Composable
fun SelectorOverlay(
  title: String,
  fullScreen: Boolean,
  onDismiss: () -> Unit,
  content: @Composable () -> Unit,
) {
  Box(Modifier.fillMaxSize()) {
    Box(
      Modifier
        .fillMaxSize()
        .background(Color.Black.copy(alpha = 0.42f))
        .clickable(
          indication = null,
          interactionSource = remember { MutableInteractionSource() },
          onClick = onDismiss,
        )
        .semantics { contentDescription = "Dismiss $title" },
    )
    Column(
      Modifier
        .align(if (fullScreen) Alignment.Center else Alignment.BottomCenter)
        .then(if (fullScreen) Modifier.fillMaxSize() else Modifier.fillMaxWidth().fillMaxHeight(0.78f))
        .clip(if (fullScreen) RoundedCornerShape(0.dp) else RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp))
        .background(Color.White)
        .pointerInput(Unit) { detectTapGestures { } },
    ) {
      if (!fullScreen) {
        Box(
          Modifier
            .padding(top = 10.dp)
            .size(width = 40.dp, height = 5.dp)
            .clip(RoundedCornerShape(3.dp))
            .background(Color.Gray.copy(alpha = 0.45f))
            .align(Alignment.CenterHorizontally),
        )
      }
      Row(
        Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Text(title, style = MaterialTheme.typography.h6, modifier = Modifier.weight(1f))
        TextButton(onClick = onDismiss) { Text("Close") }
      }
      Column(
        Modifier
          .fillMaxWidth()
          .weight(1f)
          .verticalScroll(rememberScrollState())
          .padding(horizontal = 20.dp)
          .padding(bottom = 28.dp),
      ) {
        content()
      }
    }
  }
}

@Composable
fun MethodSelectorContent(
  loading: Boolean,
  groups: List<MethodGroup>,
  selectedId: String?,
  onSelect: (MethodChoice) -> Unit,
) {
  when (methodSelectorState(loading, groups)) {
    SelectorContentState.loading -> SelectorSkeleton()
    SelectorContentState.empty -> SelectorEmptyState(methodSelectorEmptyMessage)
    SelectorContentState.ready -> {
      Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        groups.forEach { group ->
          Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
              group.descriptor,
              style = MaterialTheme.typography.subtitle2,
              color = Color.Gray,
              modifier = Modifier.semantics { contentDescription = group.descriptor },
            )
            group.methods.forEach { choice ->
              val enabled = choice.eligible
              Row(
                Modifier
                  .fillMaxWidth()
                  .clip(RoundedCornerShape(12.dp))
                  .background(if (choice.id == selectedId) Color(0x1F142C35) else Color(0x0D142C35))
                  .clickable(enabled = enabled) { onSelect(choice) }
                  .padding(12.dp)
                  .semantics {
                    contentDescription = "${choice.providerName}, ${choice.methodLabel}, ${eligibilityLabel(choice.eligible)}"
                  },
                verticalAlignment = Alignment.CenterVertically,
              ) {
                MethodLogo(choice.logoLabel, choice.providerName)
                Column(Modifier.padding(start = 12.dp).weight(1f)) {
                  Text(choice.providerName, fontWeight = FontWeight.Medium)
                  Text(choice.methodLabel, style = MaterialTheme.typography.caption, color = Color.Gray)
                  Text(
                    eligibilityLabel(choice.eligible),
                    style = MaterialTheme.typography.caption,
                    color = if (choice.eligible) eligibleGreen else unavailableBrown,
                    fontWeight = FontWeight.SemiBold,
                  )
                }
                if (choice.id == selectedId) {
                  Text("Selected", style = MaterialTheme.typography.caption, color = ink)
                }
              }
            }
          }
        }
      }
    }
  }
}

@Composable
fun BankSelectorContent(
  loading: Boolean,
  banks: List<BankChoice>,
  selectedId: String?,
  onSelect: (BankChoice) -> Unit,
) {
  var query by remember { mutableStateOf("") }
  val visible = filterBanks(banks, query)
  Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
    OutlinedTextField(
      value = query,
      onValueChange = { query = it },
      label = { Text("Search banks") },
      modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Search banks" },
    )
    when (bankSelectorState(loading, banks, query)) {
      SelectorContentState.loading -> SelectorSkeleton("Loading banks")
      SelectorContentState.empty -> SelectorEmptyState(bankEmptyMessage(banks, query))
      SelectorContentState.ready -> {
        visible.forEach { bank ->
          Row(
            Modifier
              .fillMaxWidth()
              .clip(RoundedCornerShape(12.dp))
              .background(if (bank.id == selectedId) Color(0x1F142C35) else Color(0x0D142C35))
              .clickable { onSelect(bank) }
              .padding(12.dp)
              .semantics { contentDescription = bank.name },
            verticalAlignment = Alignment.CenterVertically,
          ) {
            MethodLogo(logoLabel(bank.name), bank.name)
            Text(bank.name, Modifier.padding(start = 12.dp).weight(1f))
            if (bank.id == selectedId) {
              Text("Selected", style = MaterialTheme.typography.caption, color = ink)
            }
          }
        }
      }
    }
  }
}

@Composable
fun CatalogChoiceButton(
  title: String,
  subtitle: String,
  logo: String,
  enabled: Boolean,
  onClick: () -> Unit,
) {
  Row(
    Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(12.dp))
      .background(Color(0x14142C35))
      .clickable(enabled = enabled, onClick = onClick)
      .padding(12.dp)
      .semantics { contentDescription = "$title, $subtitle" },
    verticalAlignment = Alignment.CenterVertically,
  ) {
    MethodLogo(logo, title)
    Column(Modifier.padding(start = 12.dp).weight(1f)) {
      Text(title, fontWeight = FontWeight.Medium)
      Text(subtitle, style = MaterialTheme.typography.caption, color = Color.Gray)
    }
    Text("Change", style = MaterialTheme.typography.caption, color = Color.Gray)
  }
}
