package com.atlassian.meridian

// Payment amounts stay integer GBP pence (£0.01...£10,000.00). The IBAN check is a
// client-side format check for the existing Worldpay bank method. It does not add a
// provider and it is not sent to the payment API.

data class AmountEvaluation(
  val minorUnits: Int?,
  val isValid: Boolean,
  val helper: String,
  val spoken: String,
  val prefix: String,
)

data class IbanCheck(
  val normalized: String,
  val isValid: Boolean,
  val helper: String,
)

data class PaymentEntry(
  val amount: String = "",
  val iban: String = "",
  val reference: String = "",
  val recipientId: String = "",
  val method: String = "card",
  val idempotencyKey: String = "",
  val reviewing: Boolean = false,
)

sealed class PaymentEntryEvent {
  data class Review(val newKey: String) : PaymentEntryEvent()
  data class Edit(val newKey: String) : PaymentEntryEvent()
  data class Completed(val newKey: String) : PaymentEntryEvent()
  data class SessionChanged(val newKey: String) : PaymentEntryEvent()
  object Pending : PaymentEntryEvent()
  object NetworkFailure : PaymentEntryEvent()
  object Rejected : PaymentEntryEvent()
}

private data class IbanCountry(val name: String, val length: Int)

private val europeanIbans = mapOf(
  "AD" to IbanCountry("Andorra", 24),
  "AT" to IbanCountry("Austria", 20),
  "BE" to IbanCountry("Belgium", 16),
  "BG" to IbanCountry("Bulgaria", 22),
  "CH" to IbanCountry("Switzerland", 21),
  "CY" to IbanCountry("Cyprus", 28),
  "CZ" to IbanCountry("Czechia", 24),
  "DE" to IbanCountry("Germany", 22),
  "DK" to IbanCountry("Denmark", 18),
  "EE" to IbanCountry("Estonia", 20),
  "ES" to IbanCountry("Spain", 24),
  "FI" to IbanCountry("Finland", 18),
  "FR" to IbanCountry("France", 27),
  "GB" to IbanCountry("the United Kingdom", 22),
  "GI" to IbanCountry("Gibraltar", 23),
  "GR" to IbanCountry("Greece", 27),
  "HR" to IbanCountry("Croatia", 21),
  "HU" to IbanCountry("Hungary", 28),
  "IE" to IbanCountry("Ireland", 22),
  "IS" to IbanCountry("Iceland", 26),
  "IT" to IbanCountry("Italy", 27),
  "LI" to IbanCountry("Liechtenstein", 21),
  "LT" to IbanCountry("Lithuania", 20),
  "LU" to IbanCountry("Luxembourg", 20),
  "LV" to IbanCountry("Latvia", 21),
  "MC" to IbanCountry("Monaco", 27),
  "MT" to IbanCountry("Malta", 31),
  "NL" to IbanCountry("the Netherlands", 18),
  "NO" to IbanCountry("Norway", 15),
  "PL" to IbanCountry("Poland", 28),
  "PT" to IbanCountry("Portugal", 25),
  "RO" to IbanCountry("Romania", 24),
  "SE" to IbanCountry("Sweden", 24),
  "SI" to IbanCountry("Slovenia", 19),
  "SK" to IbanCountry("Slovakia", 24),
  "SM" to IbanCountry("San Marino", 27),
  "VA" to IbanCountry("Vatican City", 22),
  "XK" to IbanCountry("Kosovo", 20),
)

/** en_GB currency prefix for the amount field. The rehearsal ledger is GBP. */
fun currencyPrefixSymbol(): String = "£"

/** TalkBack phrase for an amount in integer pence, for example "10 pounds and 50 pence". */
fun amountSpokenLabel(minorUnits: Int): String {
  val pounds = minorUnits / 100
  val pence = kotlin.math.abs(minorUnits % 100)
  val poundUnit = if (pounds == 1) "pound" else "pounds"
  val penceUnit = if (pence == 1) "penny" else "pence"
  return "$pounds $poundUnit and $pence $penceUnit"
}

fun evaluateAmount(input: String): AmountEvaluation {
  val prefix = currencyPrefixSymbol()
  val (minor, error) = parseAmount(input)
  if (minor != null) {
    val spoken = amountSpokenLabel(minor)
    return AmountEvaluation(minor, true, spoken, spoken, prefix)
  }
  val trimmed = input.trim()
  if (trimmed.isEmpty() || trimmed == "£") {
    return AmountEvaluation(
      null,
      false,
      "Enter an amount from £0.01 to £10,000.00",
      "No amount entered",
      prefix,
    )
  }
  return AmountEvaluation(
    null,
    false,
    error ?: "Enter an amount from £0.01 to £10,000.00",
    "Invalid amount",
    prefix,
  )
}

fun formatIbanGroups(compact: String): String = compact.chunked(4).joinToString(" ")

fun validateIban(raw: String): IbanCheck {
  val compact = raw.uppercase().filter { !it.isWhitespace() && it != '-' }
  if (compact.isEmpty()) {
    return IbanCheck("", false, "Enter the recipient IBAN")
  }
  if (compact.any { !it.isDigit() && it !in 'A'..'Z' }) {
    return IbanCheck(compact, false, "IBAN can contain only letters and numbers")
  }
  if (compact.length < 2 || compact[0] !in 'A'..'Z' || compact[1] !in 'A'..'Z') {
    return IbanCheck(compact, false, "IBAN must start with a two-letter country code")
  }
  val country = compact.substring(0, 2)
  val spec = europeanIbans[country]
    ?: return IbanCheck(
      compact,
      false,
      "Enter a European IBAN. $country is not a supported country code",
    )
  if (compact.length >= 4 && (!compact[2].isDigit() || !compact[3].isDigit())) {
    return IbanCheck(compact, false, "The two characters after the country code must be digits")
  }
  if (compact.length < spec.length) {
    val missing = spec.length - compact.length
    val noun = if (missing == 1) "character" else "characters"
    return IbanCheck(
      compact,
      false,
      "IBANs for ${spec.name} are ${spec.length} characters. Enter $missing more $noun",
    )
  }
  if (compact.length > spec.length) {
    return IbanCheck(compact, false, "IBANs for ${spec.name} are ${spec.length} characters")
  }
  if (!ibanChecksumValid(compact)) {
    return IbanCheck(
      compact,
      false,
      "IBAN checksum is invalid. Check the account number and try again",
    )
  }
  return IbanCheck(compact, true, "IBAN checksum is valid")
}

fun paymentReviewError(entry: PaymentEntry): String? {
  val amount = evaluateAmount(entry.amount)
  if (!amount.isValid) return amount.helper
  if (entry.reference.length > 200) return "Reference is too long"
  if (entry.method == PaymentMethod.bank.name) {
    val iban = validateIban(entry.iban)
    if (!iban.isValid) return iban.helper
  }
  return null
}

/**
 * Keeps the typed amount, IBAN, and reference unless the payment completed.
 * Network failures, pending responses, and review/edit transitions keep the draft
 * and, except for a fresh review or edit, the same idempotency key.
 */
fun reducePaymentEntry(entry: PaymentEntry, event: PaymentEntryEvent): PaymentEntry = when (event) {
  is PaymentEntryEvent.Review -> entry.copy(reviewing = true, idempotencyKey = event.newKey)
  is PaymentEntryEvent.Edit -> entry.copy(reviewing = false, idempotencyKey = event.newKey)
  is PaymentEntryEvent.Completed -> entry.copy(
    amount = "",
    iban = "",
    reference = "",
    reviewing = false,
    idempotencyKey = event.newKey,
  )
  is PaymentEntryEvent.SessionChanged -> entry.copy(reviewing = false, idempotencyKey = event.newKey)
  PaymentEntryEvent.Pending,
  PaymentEntryEvent.NetworkFailure,
  PaymentEntryEvent.Rejected -> entry
}

private fun ibanChecksumValid(compact: String): Boolean {
  val rearranged = compact.drop(4) + compact.take(4)
  var remainder = 0
  for (character in rearranged) {
    val value = when {
      character.isDigit() -> character.toString()
      character in 'A'..'Z' -> (character.code - 'A'.code + 10).toString()
      else -> return false
    }
    for (digit in value) {
      remainder = (remainder * 10 + (digit.code - '0'.code)) % 97
    }
  }
  return remainder == 1
}
