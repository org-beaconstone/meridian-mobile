package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import java.util.UUID

data class InFlightPayment(
  val idempotencyKey: String,
  val sessionId: String,
  val recipientId: String,
  val amountMinor: Int,
  val method: String,
  val provider: String,
  val note: String,
  val outcomeUncertain: Boolean,
)

data class CachedCatalog(
  val demoDate: String,
  val currency: String,
  val recipientIds: List<String>,
  val providerIds: List<String>,
)

data class ProcessCheckpoint(
  val sessionId: String,
  val endpoint: String,
  val recipientId: String = "northline-studio",
  val amountInput: String = "",
  val note: String = "",
  val method: String = "card",
  val reviewing: Boolean = false,
  val message: String = "",
  val inFlight: InFlightPayment? = null,
  val consumedReturnNonces: List<String> = emptyList(),
  val catalog: CachedCatalog? = null,
  val catalogCachedAtMillis: Long? = null,
)

sealed class ReturnDecision {
  data class Accepted(val paymentId: String) : ReturnDecision()
  data class Rejected(val reason: String) : ReturnDecision()
}

class SessionRuntime(var checkpoint: ProcessCheckpoint) {
  constructor(sessionId: String, endpoint: String) : this(
    ProcessCheckpoint(sessionId = sessionId, endpoint = endpoint),
  )

  fun selectSession(room: String, endpoint: String) {
    val flight = checkpoint.inFlight?.copy(sessionId = room)
    checkpoint = checkpoint.copy(sessionId = room, endpoint = endpoint, inFlight = flight)
  }

  fun clearInFlight() {
    checkpoint = checkpoint.copy(inFlight = null)
  }

  fun begin(
    key: String,
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String,
    sessionId: String,
  ): InFlightPayment {
    val current = checkpoint.inFlight
    if (current != null && current.outcomeUncertain) return current
    val methodName = if (method == PaymentMethod.bank) "bank" else "card"
    val created = InFlightPayment(
      idempotencyKey = key,
      sessionId = sessionId,
      recipientId = recipientId,
      amountMinor = amountMinor,
      method = methodName,
      provider = providerForMethod(methodName) ?: "adyen",
      note = note,
      outcomeUncertain = false,
    )
    checkpoint = checkpoint.copy(inFlight = created)
    return created
  }

  fun markUncertain() {
    val flight = checkpoint.inFlight ?: return
    checkpoint = checkpoint.copy(inFlight = flight.copy(outcomeUncertain = true))
  }

  fun rememberCatalog(catalog: CachedCatalog, nowMillis: Long) {
    checkpoint = checkpoint.copy(catalog = catalog, catalogCachedAtMillis = nowMillis)
  }

  fun cachedCatalog(nowMillis: Long, ttlMillis: Long = CATALOG_TTL_MILLIS): CachedCatalog? {
    val catalog = checkpoint.catalog ?: return null
    val storedAt = checkpoint.catalogCachedAtMillis ?: return null
    if (ttlMillis <= 0 || nowMillis >= storedAt + ttlMillis) return null
    return catalog
  }

  fun evaluateReturn(url: String, nowMillis: Long): ReturnDecision {
    val parsed = parseReturnLink(url) ?: return ReturnDecision.Rejected("malformed")
    if (nowMillis >= parsed.exp) return ReturnDecision.Rejected("expired")
    if (parsed.nonce in checkpoint.consumedReturnNonces) return ReturnDecision.Rejected("replayed")
    checkpoint = checkpoint.copy(consumedReturnNonces = (checkpoint.consumedReturnNonces + parsed.nonce).sorted())
    return ReturnDecision.Accepted(parsed.paymentId)
  }

  fun requestHeaders(includeIdempotency: Boolean): Map<String, String> {
    val headers = linkedMapOf(
      "Content-Type" to "application/json",
      "X-Rehearsal-Session" to checkpoint.sessionId,
    )
    if (includeIdempotency) {
      checkpoint.inFlight?.let { headers["Idempotency-Key"] = it.idempotencyKey }
    }
    return headers
  }

  fun syncForm(
    recipientId: String,
    amountInput: String,
    note: String,
    method: String,
    reviewing: Boolean,
    message: String,
    endpoint: String,
  ) {
    checkpoint = checkpoint.copy(
      recipientId = recipientId,
      amountInput = amountInput,
      note = note,
      method = method,
      reviewing = reviewing,
      message = message,
      endpoint = endpoint,
      consumedReturnNonces = checkpoint.consumedReturnNonces.sorted(),
    )
  }

  fun encode(): String = checkpointMapper.writeValueAsString(checkpoint)

  companion object {
    const val CATALOG_TTL_MILLIS: Long = 30_000
    private val checkpointMapper = ObjectMapper().registerKotlinModule()

    fun failureIsUncertain(statusCode: Int?): Boolean {
      if (statusCode == null) return true
      return statusCode == 202 || statusCode >= 500
    }

    fun decode(json: String): ProcessCheckpoint? = try {
      checkpointMapper.readValue(json, ProcessCheckpoint::class.java)
    } catch (_: Exception) {
      null
    }
  }
}

private data class ParsedReturn(val paymentId: String, val nonce: String, val exp: Long)

private fun parseReturnLink(raw: String): ParsedReturn? {
  val prefix = "meridian://return?"
  if (!raw.startsWith(prefix)) return null
  val query = raw.substring(prefix.length)
  if (query.isEmpty() || query.contains("#") || query.contains(" ")) return null
  val values = linkedMapOf<String, String>()
  for (part in query.split("&")) {
    val bits = part.split("=", limit = 2)
    if (bits.size != 2) return null
    val key = bits[0]
    val value = bits[1]
    if (key.isEmpty() || value.isEmpty() || values.containsKey(key)) return null
    values[key] = value
  }
  if (values.keys != setOf("paymentId", "nonce", "exp")) return null
  val paymentId = values.getValue("paymentId")
  val nonce = values.getValue("nonce")
  val expText = values.getValue("exp")
  val token = Regex("^[A-Za-z0-9_-]{1,64}$")
  if (!token.matches(paymentId) || !token.matches(nonce) || !Regex("^[0-9]{1,15}$").matches(expText)) return null
  val exp = expText.toLongOrNull() ?: return null
  return ParsedReturn(paymentId, nonce, exp)
}

class PaymentScreenModel(
  var endpoint: String,
  var room: String,
  var recipientId: String = "northline-studio",
  var message: String = "Fictional payment rehearsal. Connect to the Java API.",
  var keyFactory: () -> String = { UUID.randomUUID().toString() },
) {
  var amountInput: String = ""
  var note: String = ""
  var method: PaymentMethod = PaymentMethod.card
  var reviewing: Boolean = false
  var busy: Boolean = false
  var generation: Int = 0
  var runtime: SessionRuntime = SessionRuntime(room, endpoint)

  fun connect(): Boolean {
    if (!Regex("^[A-Za-z0-9_-]{3,64}$").matches(room)) {
      message = "Invalid room"
      return false
    }
    val inFlight = runtime.checkpoint.inFlight
    if (inFlight != null && inFlight.outcomeUncertain && room != runtime.checkpoint.sessionId) {
      room = runtime.checkpoint.sessionId
      message = "Payment outcome is unknown. Stay in this room and retry the same payment."
      return false
    }
    runtime.selectSession(room, endpoint)
    reviewing = false
    if (runtime.checkpoint.inFlight?.outcomeUncertain != true) runtime.clearInFlight()
    generation += 1
    message = "Connecting"
    return true
  }

  fun review(): Boolean {
    val parsed = parseAmount(amountInput)
    val minor = parsed.first
    if (minor == null) {
      message = parsed.second ?: "Invalid amount"
      return false
    }
    if (note.length > 200) {
      message = "Reference is too long"
      return false
    }
    reviewing = true
    if (runtime.checkpoint.inFlight?.outcomeUncertain == true) {
      message = "Payment outcome is unknown. Retry keeps the same payment key."
      return true
    }
    runtime.begin(keyFactory(), recipientId, minor, method, note, runtime.checkpoint.sessionId)
    message = "Review before confirming. No real money moves."
    return true
  }

  fun edit() {
    if (runtime.checkpoint.inFlight?.outcomeUncertain == true) {
      message = "Payment outcome is unknown. Retry the same payment before editing."
      return
    }
    reviewing = false
    runtime.clearInFlight()
    message = "Edit the payment. A new confirmation will use a new payment key."
  }

  fun submitInstruction(): InFlightPayment? = runtime.checkpoint.inFlight

  fun markUncertain(reason: String) {
    runtime.markUncertain()
    message = reason
  }

  fun markSettled() {
    runtime.clearInFlight()
    reviewing = false
    amountInput = ""
    note = ""
    message = "Demo payment completed. Other clients will refresh."
  }

  fun rememberCatalog(catalog: CachedCatalog, nowMillis: Long) {
    runtime.rememberCatalog(catalog, nowMillis)
  }

  fun cachedCatalog(nowMillis: Long, ttlMillis: Long = SessionRuntime.CATALOG_TTL_MILLIS): CachedCatalog? =
    runtime.cachedCatalog(nowMillis, ttlMillis)

  fun openReturn(url: String, nowMillis: Long): ReturnDecision {
    val decision = runtime.evaluateReturn(url, nowMillis)
    message = when (decision) {
      is ReturnDecision.Accepted -> "Return accepted for ${decision.paymentId}."
      is ReturnDecision.Rejected -> "Return rejected: ${decision.reason}."
    }
    return decision
  }

  fun requestHeaders(includeIdempotency: Boolean): Map<String, String> =
    runtime.requestHeaders(includeIdempotency)

  fun confirmationAccessibility(
    recipientName: String,
    language: String,
    fontScale: Double,
    platform: String,
  ): AccessibilityDescriptor {
    val minor = runtime.checkpoint.inFlight?.amountMinor ?: parseAmount(amountInput).first ?: 0
    val methodName = runtime.checkpoint.inFlight?.method ?: if (method == PaymentMethod.bank) "bank" else "card"
    return paymentConfirmationAccessibility(money(minor), recipientName, methodName, language, fontScale, platform)
  }

  fun checkpointJson(): String {
    runtime.syncForm(
      recipientId = recipientId,
      amountInput = amountInput,
      note = note,
      method = if (method == PaymentMethod.bank) "bank" else "card",
      reviewing = reviewing,
      message = message,
      endpoint = endpoint,
    )
    return runtime.encode()
  }

  companion object {
    fun failureIsUncertain(statusCode: Int?): Boolean = SessionRuntime.failureIsUncertain(statusCode)

    fun restore(json: String, keyFactory: () -> String = { UUID.randomUUID().toString() }): PaymentScreenModel? {
      val decoded = SessionRuntime.decode(json) ?: return null
      val flight = decoded.inFlight?.copy(outcomeUncertain = true)
      val checkpoint = decoded.copy(inFlight = flight)
      val model = PaymentScreenModel(
        endpoint = checkpoint.endpoint,
        room = checkpoint.sessionId,
        recipientId = checkpoint.recipientId,
        message = checkpoint.message,
        keyFactory = keyFactory,
      )
      model.runtime = SessionRuntime(checkpoint)
      model.amountInput = checkpoint.amountInput
      model.note = checkpoint.note
      model.method = if (checkpoint.method == "bank") PaymentMethod.bank else PaymentMethod.card
      model.reviewing = checkpoint.reviewing
      if (flight != null) {
        model.method = if (flight.method == "bank") PaymentMethod.bank else PaymentMethod.card
        model.recipientId = flight.recipientId
        model.note = flight.note
        model.reviewing = true
        model.message = "Restored after process interruption. Retry keeps the same payment key."
      }
      model.busy = false
      return model
    }
  }
}
