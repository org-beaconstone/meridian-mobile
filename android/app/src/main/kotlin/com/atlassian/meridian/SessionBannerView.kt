package com.atlassian.meridian

import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Button
import androidx.compose.material.ButtonDefaults
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Surface
import androidx.compose.material.Text
import androidx.compose.material.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * Session banner for the auth screen. Place this composable before the rest
 * of the auth content so the banner and its action are first in tab order.
 * The status node stays in place across states so its live region announces changes.
 */
@Composable
fun SessionBannerView(
  banner: SessionBanner,
  onAction: () -> Unit,
  modifier: Modifier = Modifier,
  actionEnabled: Boolean = true,
) {
  val shape = RoundedCornerShape(12.dp)
  val background = Color(banner.backgroundArgb)
  val foreground = Color(banner.foregroundArgb)
  Surface(
    color = if (banner.showSkeleton) Color(0xFFF3F5F3) else background,
    contentColor = foreground,
    shape = shape,
    elevation = 0.dp,
    modifier = modifier.fillMaxWidth().semantics { testTag = AuthScreenTags.BANNER },
  ) {
    Column(
      Modifier.padding(horizontal = 16.dp, vertical = if (banner.minimal) 10.dp else 12.dp),
      verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
      Column(
        Modifier
          .fillMaxWidth()
          .focusable()
          .semantics {
            testTag = AuthScreenTags.BANNER_STATUS
            liveRegion = LiveRegionMode.Polite
            contentDescription = banner.announcement
          },
        verticalArrangement = Arrangement.spacedBy(6.dp),
      ) {
        if (banner.showSkeleton) {
          Box(
            Modifier
              .height(14.dp)
              .fillMaxWidth(0.42f)
              .background(Color(0xFFD5DDD6), shape)
              .clearAndSetSemantics { },
          )
          Box(
            Modifier
              .height(12.dp)
              .fillMaxWidth()
              .background(Color(0xFFE3E8E4), shape)
              .clearAndSetSemantics { },
          )
        } else if (banner.minimal) {
          Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
              Modifier
                .size(8.dp)
                .background(foreground, CircleShape)
                .clearAndSetSemantics { },
            )
            Spacer(Modifier.width(8.dp))
            Text(
              banner.title,
              color = foreground,
              style = MaterialTheme.typography.caption,
              maxLines = 1,
              overflow = TextOverflow.Ellipsis,
              modifier = Modifier.clearAndSetSemantics { },
            )
          }
        } else {
          Text(
            banner.title,
            color = foreground,
            style = MaterialTheme.typography.subtitle1,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.clearAndSetSemantics { },
          )
          if (banner.body.isNotEmpty()) {
            Text(
              banner.body,
              color = foreground,
              style = MaterialTheme.typography.body2,
              maxLines = 3,
              overflow = TextOverflow.Ellipsis,
              modifier = Modifier.fillMaxWidth().clearAndSetSemantics { },
            )
          }
        }
      }
      if (banner.actionLabel != null) {
        val actionModifier = Modifier
          .semantics { testTag = AuthScreenTags.BANNER_ACTION }
          .defaultMinSize(minHeight = 48.dp)
        if (banner.blocking) {
          Button(
            onClick = onAction,
            enabled = actionEnabled,
            modifier = actionModifier,
            colors = ButtonDefaults.buttonColors(backgroundColor = foreground, contentColor = background),
          ) {
            Text(banner.actionLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
          }
        } else {
          TextButton(onClick = onAction, enabled = actionEnabled, modifier = actionModifier) {
            Text(banner.actionLabel, color = foreground, maxLines = 1, overflow = TextOverflow.Ellipsis)
          }
        }
      }
    }
  }
}
