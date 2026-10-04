package com.atlassian.meridian

/** £0.01 in integer pence. */
const val gbpMinMinor = 1

/** £10,000.00 in integer pence. */
const val gbpMaxMinor = 1_000_000

/** Canonical major-unit text for integer pence, without grouping separators. */
fun formatMinorUnits(pence: Int): String {
  val negative = pence < 0
  val absolute = kotlin.math.abs(pence)
  val text = "${absolute / 100}.${(absolute % 100).toString().padStart(2, '0')}"
  return if (negative) "-$text" else text
}

/**
 * Convert a major-unit decimal string to integer pence.
 * Two fractional digits are kept. Further digits round half up, including exact halves.
 * Results of 0 or above £10,000.00 are rejected. Signs and exponents are rejected.
 */
fun roundMajorToMinor(input: String): Pair<Int?, String?> {
  val trimmed = input.trim()
  if (trimmed.isEmpty()) return Pair(null, "Amount is required")
  if (trimmed.contains("-") || trimmed.contains("+") || trimmed.lowercase().contains("e")) {
    return Pair(null, "Amount cannot contain sign or exponent notation")
  }
  if (!Regex("^\\d+(\\.\\d*)?$").matches(trimmed)) {
    return Pair(null, "Amount must be a valid number")
  }

  val parts = trimmed.split(".", limit = 2)
  val poundsStr = parts[0]
  if (poundsStr.length > 5) return Pair(null, "Amount cannot exceed £10,000")
  val pounds = poundsStr.toLongOrNull() ?: return Pair(null, "Amount is not a valid integer")
  if (pounds > 10_000L) return Pair(null, "Amount cannot exceed £10,000")

  val fraction = if (parts.size == 2) parts[1] else ""
  if (fraction.length > 12) return Pair(null, "Amount has too many decimal places")
  val padded = fraction.padEnd(2, '0')
  var pence = padded.substring(0, 2).toInt()
  val rest = if (padded.length > 2) padded.substring(2) else ""
  if (rest.isNotEmpty() && rest[0] >= '5') pence += 1

  var poundsTotal = pounds
  if (pence >= 100) {
    poundsTotal += pence / 100
    pence %= 100
  }
  if (poundsTotal > 10_000L || (poundsTotal == 10_000L && pence > 0)) {
    return Pair(null, "Amount cannot exceed £10,000")
  }
  val total = poundsTotal * 100 + pence
  if (total <= 0L) return Pair(null, "Amount must be greater than zero")
  if (total > gbpMaxMinor) return Pair(null, "Amount cannot exceed £10,000")
  return Pair(total.toInt(), null)
}
