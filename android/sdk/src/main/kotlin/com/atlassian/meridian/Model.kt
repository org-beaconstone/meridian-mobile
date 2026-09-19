package com.atlassian.meridian

import com.fasterxml.jackson.annotation.JsonProperty
import java.io.Serializable

// MARK: - Domain Enums

enum class Category(val displayName: String) {
  Shopping("Shopping"),
  FoodDrink("Food & drink"),
  Transport("Transport"),
  Bills("Bills"),
  Lifestyle("Lifestyle");

  companion object {
    fun fromValue(value: String): Category? {
      return values().firstOrNull { it.displayName == value }
    }
  }
}

enum class PaymentMethod {
  card, bank
}

enum class ProviderId {
  adyen, worldpay
}

enum class Scenario {
  success, declined, unavailable, pending
}

enum class TransactionStatus {
  completed, declined, pending
}

// MARK: - Models

data class Recipient(
  val id: String,
  val name: String,
  val initials: String,
  val detail: String,
  val category: String,
  val color: String,
) : Serializable

data class Transaction(
  val id: String,
  val reference: String,
  val recipientId: String,
  val name: String,
  val category: String,
  val amount: Int, // integer GBP pence, positive (outgoing)
  val date: String, // ISO 8601
  val provider: String,
  val method: String,
  val status: String,
  val note: String,
) : Serializable

data class Budget(
  val category: String,
  val limit: Int, // integer GBP pence
) : Serializable

data class BankState(
  val version: Int,
  val balance: Int, // integer GBP pence
  val transactions: List<Transaction>,
  val budgets: List<Budget>,
) : Serializable

data class Provider(
  val id: String,
  val name: String,
  val description: String,
  val methods: List<String>,
) : Serializable

// MARK: - API Response Types

data class HealthResponse(
  val status: String,
  val service: String,
  val simulation: Boolean,
) : Serializable

data class CatalogResponse(
  val demoDate: String,
  val recipients: List<Recipient>,
  val providers: List<Provider>,
) : Serializable

data class PaymentResponse(
  val ok: Boolean,
  val state: BankState? = null,
  val transaction: Transaction? = null,
  val error: String? = null,
  val code: String? = null,
  @JsonProperty("paymentId")
  val paymentId: String? = null,
) : Serializable

data class BudgetResponse(
  val ok: Boolean,
  val state: BankState? = null,
  val error: String? = null,
) : Serializable

data class ResetResponse(
  val ok: Boolean,
  val state: BankState? = null,
  val error: String? = null,
) : Serializable

data class EventsResponse(
  val events: List<AuditEvent>,
) : Serializable

data class AuditEvent(
  val timestamp: String,
  val action: String,
  val details: String? = null,
) : Serializable

// MARK: - Request Payloads

data class PaymentRequest(
  val recipientId: String,
  val amountMinor: Int,
  val method: String,
  val note: String,
  val scenario: String,
) : Serializable

data class BudgetRequest(
  val category: String,
  val limitMinor: Int,
) : Serializable

// MARK: - Error Types

sealed class MeridianError(message: String?, cause: Throwable? = null) : Exception(message, cause) {
  class NetworkError(msg: String, cause: Throwable? = null) : MeridianError(msg, cause)
  class InvalidURL(msg: String = "Invalid URL") : MeridianError(msg)
  class DecodingError(msg: String, cause: Throwable? = null) : MeridianError(msg, cause)
  class HttpError(val statusCode: Int, msg: String) : MeridianError("HTTP $statusCode: $msg")
  class MissingSession(msg: String = "Session ID is required") : MeridianError(msg)
  class InvalidAmount(msg: String) : MeridianError(msg)
  class ValidationError(msg: String) : MeridianError(msg)
}

// MARK: - Amount Formatting

fun money(pence: Int): String {
  val pounds = pence / 100.0
  return "£%.2f".format(pounds)
}

/**
 * Parse amount string to integer pence
 * @param input Amount string (e.g., "10.50", "10", "10.5")
 * @return Pair of (pence: Int?, error: String?)
 */
fun parseAmount(input: String): Pair<Int?, String?> {
  val trimmed = input.trim()

  // Empty or whitespace only
  if (trimmed.isEmpty()) {
    return Pair(null, "Amount is required")
  }

  // Check for sign, exponent, or invalid characters
  if (trimmed.contains("-") || trimmed.contains("+") || trimmed.lowercase().contains("e")) {
    return Pair(null, "Amount cannot contain sign or exponent notation")
  }

  // Must be numeric with optional decimal point
  val pattern = "^\\d+(\\.\\d*)?$".toRegex()
  if (!pattern.matches(trimmed)) {
    return Pair(null, "Amount must be a valid number")
  }

  // Check decimal places and parse
  val parts = trimmed.split(".", limit = 2)
  if (parts.size == 2 && parts[1].length > 2) {
    return Pair(null, "Amount must have at most 2 decimal places")
  }

  val poundsStr = parts[0]
  val penceStr = if (parts.size == 2) {
    parts[1].padEnd(2, '0')
  } else {
    "00"
  }

  val pounds = poundsStr.toIntOrNull() ?: return Pair(null, "Amount is not a valid integer")
  val pence = penceStr.toIntOrNull() ?: return Pair(null, "Amount is not a valid integer")

  if (pounds > 10000) return Pair(null, "Amount cannot exceed £10,000")
  val totalPence = pounds * 100 + pence

  // Validate range: 1 to 1,000,000 pence (£10,000)
  if (totalPence <= 0) {
    return Pair(null, "Amount must be greater than zero")
  }

  if (totalPence > 1_000_000) {
    return Pair(null, "Amount cannot exceed £10,000")
  }

  return Pair(totalPence, null)
}
