package com.atlassian.meridian

import java.util.UUID

/**
 * Outcome of one rehearsal payment attempt.
 * The idempotency key and method are the ones actually sent. Retries do not change either.
 */
sealed class Submission {
  abstract val idempotencyKey: String
  abstract val method: PaymentMethod

  data class Settled(
    val response: PaymentResponse,
    override val idempotencyKey: String,
    override val method: PaymentMethod,
  ) : Submission()

  data class Pending(
    val response: PaymentResponse,
    override val idempotencyKey: String,
    override val method: PaymentMethod,
  ) : Submission()

  data class Declined(
    val response: PaymentResponse,
    override val idempotencyKey: String,
    override val method: PaymentMethod,
  ) : Submission()

  data class Unavailable(
    val response: PaymentResponse,
    override val idempotencyKey: String,
    override val method: PaymentMethod,
  ) : Submission()

  data class Uncertain(
    override val idempotencyKey: String,
    override val method: PaymentMethod,
    val message: String,
  ) : Submission()

  data class Rejected(
    val response: PaymentResponse?,
    override val idempotencyKey: String,
    override val method: PaymentMethod,
    val message: String,
  ) : Submission()
}

/**
 * Client-side rehearsal session: last-known catalogue and same-provider retries.
 * This is a fictional GBP ledger client. It does not collect credentials or call a live provider.
 */
class RehearsalClient(private val api: MeridianClient) {
  private val cacheLock = Any()
  private var cachedCatalog: CatalogResponse? = null

  var usingCatalogFallback: Boolean = false
    private set

  fun hasCatalog(): Boolean = synchronized(cacheLock) { cachedCatalog != null }

  suspend fun hydrateCatalog(): CatalogResponse {
    try {
      val fresh = api.getCatalog()
      validateBaseline(fresh)
      synchronized(cacheLock) { cachedCatalog = fresh }
      usingCatalogFallback = false
      return fresh
    } catch (error: MeridianError.ValidationError) {
      throw error
    } catch (error: Exception) {
      val cached = synchronized(cacheLock) { cachedCatalog }
      if (cached != null) {
        usingCatalogFallback = true
        return cached
      }
      throw error
    }
  }

  /**
   * Submit a payment. Provider-unavailable and transport failures retry the same key and method.
   * HTTP 202 pending is returned immediately so the caller keeps that payment instead of starting another.
   */
  suspend fun submit(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = Scenario.success,
    idempotencyKey: String,
    maxAttempts: Int = 2,
  ): Submission {
    require(maxAttempts >= 1) { "At least one attempt is required" }
    require(idempotencyKey.isNotEmpty()) { "Idempotency key is required" }
    var networkMessage = "Outcome unknown"
    for (attempt in 1..maxAttempts) {
      try {
        val response = api.submitPayment(
          recipientId = recipientId,
          amountMinor = amountMinor,
          method = method,
          note = note,
          scenario = scenario,
          idempotencyKey = idempotencyKey,
        )
        if (response.ok) {
          return Submission.Settled(response, idempotencyKey, method)
        }
        when (response.code) {
          "PAYMENT_PENDING" -> return Submission.Pending(response, idempotencyKey, method)
          "PAYMENT_DECLINED" -> return Submission.Declined(response, idempotencyKey, method)
          "PROVIDER_UNAVAILABLE" -> {
            if (attempt == maxAttempts) {
              return Submission.Unavailable(response, idempotencyKey, method)
            }
          }
          else -> return Submission.Rejected(
            response,
            idempotencyKey,
            method,
            response.error ?: "Payment rejected",
          )
        }
      } catch (error: MeridianError.NetworkError) {
        networkMessage = error.message ?: networkMessage
        if (attempt == maxAttempts) {
          return Submission.Uncertain(idempotencyKey, method, networkMessage)
        }
      } catch (error: MeridianError.HttpError) {
        if (error.statusCode == 408 || error.statusCode == 503 || error.statusCode == 504) {
          networkMessage = error.message ?: networkMessage
          if (attempt == maxAttempts) {
            return Submission.Uncertain(idempotencyKey, method, networkMessage)
          }
        } else {
          return Submission.Rejected(null, idempotencyKey, method, error.message ?: "HTTP error")
        }
      }
    }
    return Submission.Uncertain(idempotencyKey, method, networkMessage)
  }

  private fun validateBaseline(catalog: CatalogResponse) {
    val ids = catalog.providers.map { it.id }.toSet()
    if (ids != setOf("adyen", "worldpay") || catalog.providers.size != 2) {
      throw MeridianError.ValidationError("Catalogue must contain only Adyen card and Worldpay bank")
    }
    val byId = catalog.providers.associateBy { it.id }
    if (byId["adyen"]?.methods != listOf("card") || byId["worldpay"]?.methods != listOf("bank")) {
      throw MeridianError.ValidationError("Provider methods must stay Adyen/card and Worldpay/bank")
    }
  }
}

/**
 * Release-gate journey against the shared Java rehearsal contract.
 * Amounts are GBP pence. Pending confirmation does not debit. Retries keep the original key.
 */
object RehearsalJourney {
  const val OPENING_BALANCE = 1_248_050

  suspend fun run(api: MeridianClient) {
    val rehearsal = RehearsalClient(api)
    val health = api.getHealth()
    check(health.status == "UP" && health.service == "meridian-api" && health.simulation) {
      "health"
    }

    val catalog = rehearsal.hydrateCatalog()
    check(catalog.demoDate == "2026-09-18") { "demo date" }
    check(catalog.recipients.size == 5) { "recipient count" }
    check(catalog.recipients.any { it.id == "northline-studio" }) { "recipient" }
    check(catalog.providers.map { it.id }.toSet() == setOf("adyen", "worldpay")) { "providers" }
    val providers = catalog.providers.associateBy { it.id }
    check(providers["adyen"]?.methods == listOf("card")) { "adyen method" }
    check(providers["worldpay"]?.methods == listOf("bank")) { "worldpay method" }

    val state = api.getState()
    check(state.balance == OPENING_BALANCE) { "opening balance ${state.balance}" }

    val (pence, penceError) = minorUnits("GBP", "0.01")
    check(pence == 1 && penceError == null) { "minimum pence" }
    val (pounds, poundsError) = minorUnits("GBP", "10000.00")
    check(pounds == 1_000_000 && poundsError == null) { "maximum pounds" }
    check(minorUnits("GBP", "10000.01").first == null) { "over maximum" }
    check(minorUnits("EUR", "10.00").first == null) { "non-GBP currency" }
    check(baselineProvider(PaymentMethod.card) == ProviderId.adyen) { "card provider" }
    check(baselineProvider(PaymentMethod.bank) == ProviderId.worldpay) { "bank provider" }

    val settlementKey = UUID.randomUUID().toString()
    val paid = rehearsal.submit(
      recipientId = "northline-studio",
      amountMinor = 2599,
      method = PaymentMethod.card,
      note = "rehearsal settlement",
      idempotencyKey = settlementKey,
    ) as? Submission.Settled ?: error("expected settlement")
    check(paid.idempotencyKey == settlementKey && paid.method == PaymentMethod.card) { "settlement identity" }
    check(paid.response.state?.balance == OPENING_BALANCE - 2599) { "settlement balance" }
    check(paid.response.transaction?.provider == "adyen") { "settlement provider" }
    check(paid.response.transaction?.method == "card") { "settlement method" }
    val settledId = paid.response.transaction?.id ?: error("missing transaction")

    val replay = rehearsal.submit(
      recipientId = "northline-studio",
      amountMinor = 2599,
      method = PaymentMethod.card,
      note = "rehearsal settlement",
      idempotencyKey = settlementKey,
    ) as? Submission.Settled ?: error("expected idempotent replay")
    check(replay.response.transaction?.id == settledId) { "idempotent transaction" }
    check(replay.response.state?.balance == OPENING_BALANCE - 2599) { "idempotent balance" }

    val mismatch = rehearsal.submit(
      recipientId = "northline-studio",
      amountMinor = 2600,
      method = PaymentMethod.card,
      note = "rehearsal settlement",
      idempotencyKey = settlementKey,
      maxAttempts = 1,
    )
    check(mismatch is Submission.Rejected) { "idempotency mismatch" }
    check(api.getState().balance == OPENING_BALANCE - 2599) { "mismatch balance" }

    val pendingKey = UUID.randomUUID().toString()
    val pending = rehearsal.submit(
      recipientId = "northline-studio",
      amountMinor = 100,
      method = PaymentMethod.card,
      note = "pending confirmation",
      scenario = Scenario.pending,
      idempotencyKey = pendingKey,
    ) as? Submission.Pending ?: error("expected pending")
    check(pending.response.code == "PAYMENT_PENDING" && pending.response.paymentId != null) { "pending payload" }
    check(pending.idempotencyKey == pendingKey) { "pending key retained" }
    check(!pending.response.ok) { "pending is not settled" }
    check(api.getState().balance == OPENING_BALANCE - 2599) { "pending balance" }

    val pendingAgain = rehearsal.submit(
      recipientId = "northline-studio",
      amountMinor = 100,
      method = PaymentMethod.card,
      note = "pending confirmation",
      scenario = Scenario.pending,
      idempotencyKey = pendingKey,
    ) as? Submission.Pending ?: error("pending retry created a new outcome")
    check(pendingAgain.response.paymentId == pending.response.paymentId) { "pending identity" }
    check(api.getState().balance == OPENING_BALANCE - 2599) { "pending retry balance" }

    val outageKey = UUID.randomUUID().toString()
    val unavailable = rehearsal.submit(
      recipientId = "northline-studio",
      amountMinor = 500,
      method = PaymentMethod.bank,
      note = "provider outage",
      scenario = Scenario.unavailable,
      idempotencyKey = outageKey,
      maxAttempts = 1,
    ) as? Submission.Unavailable ?: error("expected unavailable")
    check(unavailable.method == PaymentMethod.bank) { "outage kept bank method" }
    check(api.getState().balance == OPENING_BALANCE - 2599) { "outage balance" }

    val recovered = rehearsal.submit(
      recipientId = "northline-studio",
      amountMinor = 500,
      method = PaymentMethod.bank,
      note = "provider outage",
      scenario = Scenario.success,
      idempotencyKey = outageKey,
      maxAttempts = 1,
    ) as? Submission.Settled ?: error("expected recovery with the same key")
    check(recovered.method == PaymentMethod.bank) { "recovery method" }
    check(recovered.response.transaction?.provider == "worldpay") { "recovery provider" }
    check(recovered.response.transaction?.method == "bank") { "recovery rail" }
    check(api.getState().balance == OPENING_BALANCE - 2599 - 500) { "recovery balance" }

    val declined = rehearsal.submit(
      recipientId = "birch-bloom",
      amountMinor = 125,
      method = PaymentMethod.card,
      note = "declined",
      scenario = Scenario.declined,
      idempotencyKey = UUID.randomUUID().toString(),
      maxAttempts = 1,
    ) as? Submission.Declined ?: error("expected decline")
    check(declined.response.code == "PAYMENT_DECLINED") { "decline code" }
    check(api.getState().balance == OPENING_BALANCE - 2599 - 500) { "decline balance" }

    val reset = api.reset()
    check(reset.ok && reset.state?.balance == OPENING_BALANCE) { "reset" }
  }
}
