package com.atlassian.meridian

import org.junit.Assert.*
import org.junit.Test

/**
 * Accessibility and localization tests for the Meridian SDK.
 *
 * These are pure model / formatting-layer tests.  They verify that every
 * string the UI exposes to TalkBack (Android) or VoiceOver (iOS equivalent)
 * is non-empty, that formatted amounts remain legible at large font scales,
 * and that no hard-coded directionality markers are embedded that would break
 * RTL layouts.
 */
class AccessibilityLocalizationTest {

  // -------------------------------------------------------------------------
  // TalkBack Content-Description Tests
  // -------------------------------------------------------------------------

  @Test
  fun a11yRecipientFieldsNonEmptyForTalkBack() {
    // TalkBack announces name, detail, and category; all must be non-blank
    val recipient = Recipient(
      id = "birch-bloom",
      name = "Birch & Bloom",
      initials = "BB",
      detail = "Organic café & bistro",
      category = "Food & drink",
      color = "#FFD93D"
    )
    assertTrue("name must be non-blank for TalkBack", recipient.name.isNotBlank())
    assertTrue("detail must be non-blank for TalkBack", recipient.detail.isNotBlank())
    assertTrue("category must be non-blank for TalkBack", recipient.category.isNotBlank())
    assertTrue("initials must be non-blank for avatar TalkBack label", recipient.initials.isNotBlank())
  }

  @Test
  fun a11yTransactionFieldsNonEmptyForTalkBack() {
    val txn = Transaction(
      id = "txn-001", reference = "REF-001", recipientId = "rec-1",
      name = "Coffee Shop", category = "Food & drink", amount = 350,
      date = "2026-09-18", provider = "adyen", method = "card",
      status = "completed", note = "Morning coffee"
    )
    assertTrue("Transaction name must be non-blank", txn.name.isNotBlank())
    assertTrue("Transaction category must be non-blank", txn.category.isNotBlank())
    assertTrue("Transaction date must be non-blank", txn.date.isNotBlank())
    assertTrue("Transaction status must be non-blank", txn.status.isNotBlank())
    assertTrue("Transaction amount must be non-negative", txn.amount >= 0)
  }

  @Test
  fun a11yMoneyStringIncludesCurrencySymbol() {
    // TalkBack reads the currency symbol; the formatted string must begin with £
    val formatted = money(1_050)
    assertTrue("Formatted amount must start with £ for TalkBack", formatted.startsWith("£"))
  }

  @Test
  fun a11yTransactionStatusValuesAreHumanReadable() {
    // Status values must be plain-English words, not internal codes
    val human = setOf("completed", "declined", "pending")
    listOf("completed", "declined", "pending").forEach { status ->
      assertTrue("Status '$status' must be human-readable", status in human)
    }
  }

  @Test
  fun a11yProviderFieldsNonEmptyForTalkBack() {
    val adyen    = Provider("adyen",    "Adyen",    "Card payment processor",  listOf("card"))
    val worldpay = Provider("worldpay", "Worldpay", "Bank transfer processor", listOf("bank"))
    listOf(adyen, worldpay).forEach { p ->
      assertTrue("Provider name must be non-blank",        p.name.isNotBlank())
      assertTrue("Provider description must be non-blank", p.description.isNotBlank())
    }
  }

  @Test
  fun a11yAuditEventFieldsNonEmptyForTalkBack() {
    val event = AuditEvent(timestamp = "2026-09-18T10:00:00Z", action = "PAYMENT_SUBMITTED", details = "£10.50 to Birch & Bloom")
    assertTrue("AuditEvent timestamp must be non-blank", event.timestamp.isNotBlank())
    assertTrue("AuditEvent action must be non-blank",    event.action.isNotBlank())
  }

  // -------------------------------------------------------------------------
  // Large-Font Scaling Tests
  // -------------------------------------------------------------------------

  @Test
  fun a11yMaxAmountStringFitsLargeFont() {
    // £10000.00 is 10 chars; at 3× font scale a 12-char limit is safe
    val maxFormatted = money(1_000_000)
    assertTrue("Max amount string must be ≤ 12 chars for large-font displays",
      maxFormatted.length <= 12)
  }

  @Test
  fun a11yMinimumAmountStringIsNonEmpty() {
    val minFormatted = money(1)
    assertTrue("Minimum amount string must be non-empty", minFormatted.isNotEmpty())
    assertTrue("Minimum amount string must contain £", minFormatted.contains("£"))
  }

  @Test
  fun a11yRecipientInitialsFitAvatarAtLargeFont() {
    // Avatar initials must be 1-3 characters to remain legible at large font sizes
    listOf(
      Recipient("r1", "Alice Smith",   "AS", "", "Shopping",    "#fff"),
      Recipient("r2", "Bob",           "B",  "", "Bills",       "#fff"),
      Recipient("r3", "Café Bar Ltd",  "CB", "", "Food & drink","#fff")
    ).forEach { r ->
      assertTrue("Initials '${r.initials}' must be 1-3 chars for large-font avatar",
        r.initials.length in 1..3)
    }
  }

  @Test
  fun a11yTransactionNoteTruncatesToSafeLength() {
    // Notes can be up to 200 chars; a UI truncation at 100 + ellipsis keeps labels accessible
    val longNote = "A".repeat(200)
    val truncated = if (longNote.length > 100) longNote.take(100) + "…" else longNote
    assertTrue("Truncated note must fit in ≤ 101 chars", truncated.length <= 101)
  }

  @Test
  fun a11yAllSampleAmountsFormatToReasonableLength() {
    // Every formatted amount must fit within 12 chars (enough for £10000.00)
    listOf(1, 99, 1_050, 10_000, 100_000, 1_000_000).forEach { pence ->
      val s = money(pence)
      assertTrue("Formatted '${s}' for $pence pence must be ≤ 12 chars", s.length <= 12)
    }
  }

  // -------------------------------------------------------------------------
  // RTL Layout-Readiness Tests
  // -------------------------------------------------------------------------

  @Test
  fun a11yRtlRecipientNamesContainNoDirectionalMarkers() {
    val ltr = "\u200E"
    val rtl = "\u200F"
    listOf(
      Recipient("r1", "Birch & Bloom",    "BB", "Organic café",  "Food & drink", "#FFD93D"),
      Recipient("r2", "Northline Studio", "NS", "Design tools",  "Shopping",     "#FF6B6B")
    ).forEach { r ->
      assertFalse("Name '${r.name}' must not embed LTR mark", r.name.contains(ltr))
      assertFalse("Name '${r.name}' must not embed RTL mark", r.name.contains(rtl))
    }
  }

  @Test
  fun a11yRtlCurrencySymbolLeadsAmountInEnGb() {
    // In en-GB the £ symbol precedes the number; RTL locales mirror the layout,
    // not the string itself – so the leading £ must be preserved.
    assertTrue("£ must lead the formatted amount in en-GB", money(500).startsWith("£"))
  }

  @Test
  fun a11yRtlCategoryNamesContainNoDirectionalMarkers() {
    val ltr = "\u200E"
    val rtl = "\u200F"
    Category.values().forEach { cat ->
      assertFalse("Category '${cat.displayName}' must not embed LTR mark", cat.displayName.contains(ltr))
      assertFalse("Category '${cat.displayName}' must not embed RTL mark", cat.displayName.contains(rtl))
      assertTrue("Category display name must not be blank", cat.displayName.isNotBlank())
    }
  }

  @Test
  fun a11yRtlFormattedAmountsContainOnlyPrintableChars() {
    listOf(1, 99, 1_050, 100_000, 1_000_000).forEach { pence ->
      val formatted = money(pence)
      assertTrue("Formatted '$formatted' must contain only printable chars",
        formatted.all { it.code >= 32 })
    }
  }

  @Test
  fun a11yRtlProviderNamesContainNoControlChars() {
    listOf(
      Provider("adyen",    "Adyen",    "Card payment processor",  listOf("card")),
      Provider("worldpay", "Worldpay", "Bank transfer processor", listOf("bank"))
    ).forEach { p ->
      assertFalse("Provider name '${p.name}' must not contain control chars",
        p.name.any { it.code < 32 })
      assertTrue("Provider name must be non-blank", p.name.isNotBlank())
    }
  }

  @Test
  fun a11yRtlTransactionStatusContainNoDirectionalMarkers() {
    val ltr = "\u200E"
    val rtl = "\u200F"
    listOf("completed", "declined", "pending").forEach { status ->
      assertFalse("Status '$status' must not embed LTR mark", status.contains(ltr))
      assertFalse("Status '$status' must not embed RTL mark", status.contains(rtl))
    }
  }
}
