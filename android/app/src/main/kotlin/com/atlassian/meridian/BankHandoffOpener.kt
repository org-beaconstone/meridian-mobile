package com.atlassian.meridian

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri

/** Opens a bank URL only after the allowlist accepts it. Refusal does not switch host. */
object BankHandoffOpener {
  fun open(activity: Activity, url: String): Boolean {
    val check = BankHandoffPolicy.inspectBankHandoff(url)
    if (check !is UrlCheck.Allowed) return false
    return try {
      activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(check.url)))
      true
    } catch (_: ActivityNotFoundException) {
      false
    }
  }
}
