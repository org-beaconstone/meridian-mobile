package com.atlassian.meridian

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/**
 * A persistent banner displayed on the payment / authentication screen that communicates
 * the current [SessionState] without blocking entered payment data.
 *
 * The banner is invisible when [sessionState] is [SessionState.Active].
 * All other states render a colour-coded surface containing an icon, a heading,
 * optional recovery guidance, and — for [SessionState.Expiring] — a non-blocking
 * Refresh button.
 *
 * Accessibility: the composable merges its descendants under a single TalkBack
 * content description so the banner reads as one item. Dynamic text scaling is
 * inherited from the [MaterialTheme] typography, which respects the system font scale.
 *
 * @param sessionState The current session state.
 * @param onRefresh Called when the user taps Refresh; only shown in the expiring state.
 * @param modifier Optional [Modifier].
 */
@Composable
fun SessionBanner(
  sessionState: SessionState,
  onRefresh: (() -> Unit)? = null,
  modifier: Modifier = Modifier,
) {
  // Active state is healthy – no visual affordance needed.
  if (sessionState is SessionState.Active) return

  val backgroundColor = when (sessionState) {
    is SessionState.Expiring        -> Color(0xFFFFF3CD)
    is SessionState.ActiveElsewhere -> Color(0xFFFFF8E1)
    is SessionState.SignedOut       -> Color(0xFFFFEBEE)
    is SessionState.Unknown         -> Color(0xFFFFEBEE)
    else                            -> Color.Transparent
  }

  val accentColor = when (sessionState) {
    is SessionState.Expiring        -> Color(0xFFE65100)
    is SessionState.ActiveElsewhere -> Color(0xFFF57F17)
    is SessionState.SignedOut       -> Color(0xFFC62828)
    is SessionState.Unknown         -> Color(0xFFC62828)
    else                            -> Color.Unspecified
  }

  val labelColor = when (sessionState) {
    is SessionState.Expiring,
    is SessionState.ActiveElsewhere -> Color(0xFF5D3A00)
    is SessionState.SignedOut,
    is SessionState.Unknown         -> Color(0xFF7F0000)
    else                            -> Color.Unspecified
  }

  val icon: ImageVector = when (sessionState) {
    is SessionState.Expiring        -> Icons.Default.Warning
    is SessionState.ActiveElsewhere -> Icons.Default.People
    is SessionState.SignedOut       -> Icons.Default.Lock
    is SessionState.Unknown         -> Icons.Default.Info
    else                            -> Icons.Default.CheckCircle
  }

  val recoveryText: String? = when (sessionState) {
    is SessionState.SignedOut -> "Sign in again to continue. Your payment details are preserved."
    is SessionState.Unknown   -> "Check your connection. Your payment details are preserved."
    else                      -> null
  }

  // Single TalkBack announcement for the entire banner.
  val talkBackDescription = buildString {
    append(sessionState.label)
    recoveryText?.let { append(". $it") }
    if (sessionState.allowsRefresh) append(". Refresh session available.")
  }

  Surface(
    color = backgroundColor,
    shape = RoundedCornerShape(10.dp),
    modifier = modifier
      .fillMaxWidth()
      .semantics { contentDescription = talkBackDescription },
  ) {
    Row(
      modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
      horizontalArrangement = Arrangement.spacedBy(10.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Icon(
        imageVector = icon,
        contentDescription = null, // covered by merged banner description
        tint = accentColor,
        modifier = Modifier.size(20.dp),
      )

      Column(modifier = Modifier.weight(1f)) {
        Text(
          text = sessionState.label,
          style = MaterialTheme.typography.subtitle2,
          color = labelColor,
        )
        recoveryText?.let {
          Text(
            text = it,
            style = MaterialTheme.typography.caption,
            color = labelColor.copy(alpha = 0.85f),
          )
        }
      }

      if (sessionState.allowsRefresh && onRefresh != null) {
        TextButton(
          onClick = onRefresh,
          modifier = Modifier.semantics {
            contentDescription =
              "Refresh session. Extends your current session without leaving this screen."
          },
        ) {
          Text(
            text = "Refresh",
            style = MaterialTheme.typography.button,
            color = accentColor,
          )
        }
      }
    }
  }
}
