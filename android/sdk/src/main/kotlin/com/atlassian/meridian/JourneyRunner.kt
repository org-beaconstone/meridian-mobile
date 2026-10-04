package com.atlassian.meridian

import kotlinx.coroutines.runBlocking
import java.util.UUID

/**
 * End-to-end rehearsal journey against the local Spring Boot mock.
 * Amounts are integer GBP pence. Card stays on Adyen and bank stays on Worldpay.
 */
object JourneyRunner {
  fun run(baseUrl: String, sessionId: String = "journey-" + UUID.randomUUID()) = runBlocking {
    assertSimulatedScaFlows()
    val client = MeridianClient(baseUrl, sessionId)
    val health = client.getHealth()
    check(health.status == "UP" && health.simulation && health.service == "meridian-api") {
      "Unexpected health payload"
    }
    val catalog = client.getCatalog()
    val ids = catalog.providers.map { it.id }.toSet()
    check(ids == setOf("adyen", "worldpay")) { "Provider registry drifted: $ids" }
    check(catalog.providers.first { it.id == "adyen" }.methods == listOf("card"))
    check(catalog.providers.first { it.id == "worldpay" }.methods == listOf("bank"))
    check(client.getState().balance == 1_248_050) { "Opening balance" }

    val minimum = client.submitPayment(
      recipientId = "northline-studio",
      amountMinor = gbpMinMinor,
      method = PaymentMethod.card,
      note = "boundary-0.01",
      scenario = Scenario.success,
      idempotencyKey = "boundary-min",
    )
    check(minimum.ok && minimum.state?.balance == 1_248_049) {
      "£0.01 card payment failed: ${minimum.error}"
    }
    val minimumTransaction = checkNotNull(minimum.transaction)
    check(minimumTransaction.amount == gbpMinMinor)
    check(minimumTransaction.provider == "adyen" && minimumTransaction.method == "card")
    val minimumId = minimumTransaction.id

    val middle = client.submitPayment(
      recipientId = "northline-studio",
      amountMinor = 100,
      method = PaymentMethod.card,
      note = "mid",
      scenario = Scenario.success,
      idempotencyKey = "mid-100",
    )
    check(middle.ok && middle.state?.balance == 1_247_949) { "Second debit failed: ${middle.error}" }

    val replay = client.submitPayment(
      recipientId = "northline-studio",
      amountMinor = gbpMinMinor,
      method = PaymentMethod.card,
      note = "boundary-0.01",
      scenario = Scenario.success,
      idempotencyKey = "boundary-min",
    )
    check(replay.ok && replay.transaction?.id == minimumId && replay.state?.balance == 1_247_949) {
      "Idempotency replay debited again or lost the original transaction"
    }

    val maximum = client.submitPayment(
      recipientId = "northline-studio",
      amountMinor = gbpMaxMinor,
      method = PaymentMethod.bank,
      note = "boundary-10000.00",
      scenario = Scenario.success,
      idempotencyKey = "boundary-max",
    )
    check(maximum.ok && maximum.state?.balance == 247_949) {
      "£10,000.00 bank payment failed: ${maximum.error} balance=${maximum.state?.balance}"
    }
    val maximumTransaction = checkNotNull(maximum.transaction)
    check(maximumTransaction.amount == gbpMaxMinor)
    check(maximumTransaction.provider == "worldpay" && maximumTransaction.method == "bank")
    val maximumId = maximumTransaction.id
    val maximumReplay = client.submitPayment(
      recipientId = "northline-studio",
      amountMinor = gbpMaxMinor,
      method = PaymentMethod.bank,
      note = "boundary-10000.00",
      scenario = Scenario.success,
      idempotencyKey = "boundary-max",
    )
    check(maximumReplay.ok && maximumReplay.transaction?.id == maximumId && maximumReplay.state?.balance == 247_949)

    val pending = client.submitPayment(
      recipientId = "northline-studio",
      amountMinor = 50,
      method = PaymentMethod.card,
      note = "pending",
      scenario = Scenario.pending,
      idempotencyKey = "pending-key",
    )
    check(!pending.ok && pending.code == "PAYMENT_PENDING" && !pending.paymentId.isNullOrBlank())
    check(client.getState().balance == 247_949) { "Pending payment debited the balance" }

    val declined = client.submitPayment(
      recipientId = "northline-studio",
      amountMinor = 50,
      method = PaymentMethod.card,
      note = "declined",
      scenario = Scenario.declined,
      idempotencyKey = "declined-key",
    )
    check(!declined.ok && declined.code == "PAYMENT_DECLINED")
    check(client.getState().balance == 247_949) { "Declined payment debited the balance" }

    val mismatch = client.submitPayment(
      recipientId = "northline-studio",
      amountMinor = 2,
      method = PaymentMethod.bank,
      note = "boundary-10000.00",
      scenario = Scenario.success,
      idempotencyKey = "boundary-max",
    )
    check(!mismatch.ok) { "Reused key with a different amount was accepted" }
    check(client.getState().balance == 247_949)

    val reset = client.reset()
    check(reset.ok && reset.state?.balance == 1_248_050) { "Reset did not restore the fixture balance" }
  }
}
