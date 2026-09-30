package com.atlassian.meridian

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Button
import androidx.compose.material.Card
import androidx.compose.material.MaterialTheme
import androidx.compose.material.OutlinedTextField
import androidx.compose.material.RadioButton
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import java.util.UUID

@Composable
fun WhiteboardSection() {
  var colourId by remember { mutableStateOf(StickyPalette.defaultColourId) }
  var text by remember { mutableStateOf("") }
  var notes by remember { mutableStateOf(listOf<StickyNote>()) }
  var message by remember { mutableStateOf("Choose a colour, then add a sticky note.") }
  var messageIsError by remember { mutableStateOf(false) }

  Text("Whiteboard", style = MaterialTheme.typography.h6)
  Text("Native Android. Sticky notes stay on this device.", style = MaterialTheme.typography.caption)
  Text("Sticky note colour", style = MaterialTheme.typography.subtitle1)
  StickyPalette.colours.chunked(2).forEach { row ->
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      row.forEach { colour ->
        val selected = colourId == colour.id
        Row(
          Modifier
            .weight(1f)
            .border(
              width = if (selected) 2.dp else 1.dp,
              color = if (selected) Color(0xFF1868DB) else Color(0xFFD7DED0),
              shape = RoundedCornerShape(8.dp),
            )
            .selectable(
              selected = selected,
              role = Role.RadioButton,
              onClick = { colourId = colour.id },
            )
            .padding(8.dp),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          RadioButton(selected = selected, onClick = null)
          Box(
            Modifier
              .padding(start = 6.dp)
              .size(width = 28.dp, height = 18.dp)
              .background(stickyFill(colour.fill), RoundedCornerShape(4.dp))
              .border(1.dp, Color(0x22142C35), RoundedCornerShape(4.dp)),
          )
          Text(colour.name, Modifier.padding(start = 8.dp), style = MaterialTheme.typography.caption)
        }
      }
    }
  }
  OutlinedTextField(
    value = text,
    onValueChange = { text = it.take(StickyPalette.maxTextLength) },
    label = { Text("Sticky note") },
    modifier = Modifier.fillMaxWidth(),
  )
  Button(onClick = {
    when (val draft = StickyPalette.createNote(text, colourId, UUID.randomUUID().toString())) {
      is StickyDraft.Created -> {
        notes = listOf(draft.note) + notes
        text = ""
        messageIsError = false
        message = "Added a ${StickyPalette.colour(draft.note.colourId).name.lowercase()} sticky note."
      }
      is StickyDraft.Rejected -> {
        messageIsError = true
        message = when (draft.error) {
          StickyDraftError.Empty -> "Write a sticky note before adding it."
          StickyDraftError.TooLong -> "Sticky notes can be up to ${StickyPalette.maxTextLength} characters."
          StickyDraftError.UnknownColour -> "Choose a colour from the palette."
        }
      }
    }
  }) { Text("Add sticky note") }
  Text(message, color = if (messageIsError) Color(0xFF8D2517) else Color.Unspecified)
  notes.forEach { note ->
    val colour = StickyPalette.colour(note.colourId)
    Card(backgroundColor = stickyFill(colour.fill), modifier = Modifier.fillMaxWidth()) {
      Column(Modifier.padding(12.dp)) {
        Text(note.text)
        Text(colour.name, style = MaterialTheme.typography.caption)
      }
    }
  }
}

private fun stickyFill(hex: String): Color {
  val rgb = hex.removePrefix("#").toLong(16)
  return Color(0xFF000000L or rgb)
}
