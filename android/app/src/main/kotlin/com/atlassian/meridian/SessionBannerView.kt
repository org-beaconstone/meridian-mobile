package com.atlassian.meridian

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.ButtonDefaults
import androidx.compose.material.LocalContentColor
import androidx.compose.material.MaterialTheme
import androidx.compose.material.OutlinedButton
import androidx.compose.material.RadioButton
import androidx.compose.material.Text
import androidx.compose.material.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.invisibleToUser
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

enum class MeridianScreen(val label: String) {
  Payment("Payment"),
  Authentication("Authentication"),
}

private data class BannerPalette(val background: Color, val border: Color, val content: Color)

private fun palette(tone: SessionBannerTone): BannerPalette = when (tone) {
  SessionBannerTone.SUCCESS -> BannerPalette(Color(0xFFE7F2DD), Color(0xFF7AAF78), Color(0xFF1F4D32))
  SessionBannerTone.WARNING -> BannerPalette(Color(0xFFFFF7D6), Color(0xFFE2B203), Color(0xFF533F04))
  SessionBannerTone.INFORMATION -> BannerPalette(Color(0xFFE9F2FF), Color(0xFF1868DB), Color(0xFF0C3A7A))
  SessionBannerTone.NEUTRAL -> BannerPalette(Color(0xFFF4F5F7), Color(0xFF8B9588), Color(0xFF142C35))
  SessionBannerTone.DANGER -> BannerPalette(Color(0xFFFFEDEB), Color(0xFFAE2A19), Color(0xFF8D2517))
  SessionBannerTone.ATTENTION -> BannerPalette(Color(0xFFF3EDE3), Color(0xFFD5B77A), Color(0xFF3D2E16))
}

/**
 * Persistent session banner. Text uses Compose typography (sp) so TalkBack and
 * system font scale can resize it. The action does not replace the payment form.
 */
@Composable
fun SessionBannerView(model: SessionBannerModel, onAction: (SessionBannerAction) -> Unit) {
  val colors = palette(model.tone)
  val stacked = LocalConfiguration.current.fontScale >= 1.3f
  val shape = RoundedCornerShape(12.dp)
  CompositionLocalProvider(LocalContentColor provides colors.content) {
    Column(
      Modifier
        .fillMaxWidth()
        .testTag("session-banner")
        .border(1.dp, colors.border, shape)
        .background(colors.background, shape)
        .padding(16.dp),
      verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
      if (stacked) {
        BannerTitle(model.title)
        BannerClock(model.clockLabel)
      } else {
        Row(
          Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically,
        ) {
          BannerTitle(model.title, Modifier.weight(1f, fill = false))
          BannerClock(model.clockLabel)
        }
      }
      Text(model.message, style = MaterialTheme.typography.body1)
      val action = model.action
      val actionLabel = model.actionLabel
      if (action != null && actionLabel != null) {
        TextButton(
          onClick = { onAction(action) },
          modifier = Modifier
            .defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
            .semantics {
              contentDescription =
                "$actionLabel. Keeps the amount, recipient and reference already entered."
            },
          colors = ButtonDefaults.textButtonColors(contentColor = colors.content),
        ) {
          Text(actionLabel, style = MaterialTheme.typography.button)
        }
      }
    }
  }
}

@Composable
private fun BannerTitle(title: String, modifier: Modifier = Modifier) {
  Text(
    title,
    modifier = modifier.semantics { heading() },
    style = MaterialTheme.typography.subtitle1,
  )
}

@Composable
private fun BannerClock(clockLabel: String?) {
  if (clockLabel != null) {
    Text(
      clockLabel,
      modifier = Modifier.semantics { invisibleToUser() },
      style = MaterialTheme.typography.h6,
    )
  }
}

@Composable
fun AuthenticationScreen(
  session: CustomerSession,
  nowEpochMs: Long,
  onSignOut: () -> Unit,
  onPreview: (SessionPhase) -> Unit,
) {
  val phase = presentSession(session, nowEpochMs).phase
  Text("Authentication", style = MaterialTheme.typography.h6)
  Text("Alex Morgan", style = MaterialTheme.typography.subtitle1)
  Text("Fictional rehearsal profile. No password is collected and no identity provider is called.")
  if (
    phase == SessionPhase.ACTIVE ||
    phase == SessionPhase.EXPIRING ||
    phase == SessionPhase.ACTIVE_ELSEWHERE
  ) {
    OutlinedButton(
      onClick = onSignOut,
      modifier = Modifier.defaultMinSize(minHeight = 48.dp),
    ) {
      Text("Sign out")
    }
  }
  Text("Preview session state", style = MaterialTheme.typography.subtitle1)
  SessionPhase.entries.forEach { item ->
    Row(
      Modifier
        .fillMaxWidth()
        .defaultMinSize(minHeight = 48.dp)
        .clickable { onPreview(item) }
        .semantics(mergeDescendants = true) {
          role = Role.RadioButton
          selected = phase == item
          contentDescription = "Preview session state, ${item.label}"
        },
      verticalAlignment = Alignment.CenterVertically,
    ) {
      RadioButton(selected = phase == item, onClick = null)
      Text(item.label)
    }
  }
}
