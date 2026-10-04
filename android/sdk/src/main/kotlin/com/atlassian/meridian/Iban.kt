package com.atlassian.meridian

/** ISO 13616 MOD-97. Rehearsal checksum only; no bank or provider call. */
fun ibanNormalize(raw: String): String = raw.uppercase().filter { !it.isWhitespace() }

fun ibanMod97(iban: String): Int {
  val rearranged = iban.drop(4) + iban.take(4)
  var remainder = 0
  for (character in rearranged) {
    val digits = when {
      character.isDigit() -> character.toString()
      character in 'A'..'Z' -> (character.code - 'A'.code + 10).toString()
      else -> return -1
    }
    for (digit in digits) {
      remainder = (remainder * 10 + (digit.code - '0'.code)) % 97
    }
  }
  return remainder
}

fun ibanIsValid(raw: String): Boolean {
  val iban = ibanNormalize(raw)
  if (iban.length !in 15..34) return false
  if (iban[0] !in 'A'..'Z' || iban[1] !in 'A'..'Z') return false
  if (!iban[2].isDigit() || !iban[3].isDigit()) return false
  if (iban.any { it !in 'A'..'Z' && !it.isDigit() }) return false
  return ibanMod97(iban) == 1
}

fun ibanCheckDigits(country: String, bban: String): String {
  val remainder = ibanMod97(country.uppercase() + "00" + bban.uppercase())
  return "%02d".format(98 - remainder)
}

fun ibanCompose(country: String, bban: String): String {
  val code = country.uppercase()
  val body = bban.uppercase()
  return code + ibanCheckDigits(code, body) + body
}
