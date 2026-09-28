package com.atlassian.meridian
import kotlinx.coroutines.runBlocking
import java.util.UUID
fun main()=runBlocking {
  val base=System.getenv("MERIDIAN_TEST_API")?:"http://127.0.0.1:8080/api/v1"
  val client=MeridianClient(base,"kotlin-check-"+UUID.randomUUID())
  val rehearsal=RehearsalSession(client)
  check(client.getState().balance==1248050)
  val hydration=rehearsal.hydrateCatalog()
  check(!hydration.degraded && hydration.source==CatalogSource.LIVE)
  val providers=hydration.catalog?.providers ?: error("missing catalog")
  check(providers.map { it.id }==listOf("adyen","worldpay"))
  check(providers[0].methods==listOf("card") && providers[1].methods==listOf("bank"))
  val pence=PaymentAttempt("northline-studio",1,PaymentMethod.card,"One pence",Scenario.success,"k-"+UUID.randomUUID())
  val paid=rehearsal.submit(pence) as PaymentOutcome.Settled
  check(paid.response.ok && paid.response.state?.balance==1248049 && paid.response.transaction?.provider=="adyen")
  val replay=rehearsal.submit(pence) as PaymentOutcome.Settled
  check(replay.response.transaction?.id==paid.response.transaction?.id && replay.response.state?.balance==1248049)
  val bankKey="k-"+UUID.randomUUID()
  val down=PaymentAttempt("northline-studio",100,PaymentMethod.bank,"Unavailable",Scenario.unavailable,bankKey)
  val failed=rehearsal.submit(down) as PaymentOutcome.Retryable
  check(failed.attempt.method==PaymentMethod.bank && failed.attempt.provider=="worldpay" && failed.attempt.idempotencyKey==bankKey)
  check(client.getState().balance==1248049)
  val recovered=rehearsal.submit(PaymentAttempt("northline-studio",100,PaymentMethod.bank,"Unavailable",Scenario.success,bankKey)) as PaymentOutcome.Settled
  check(recovered.response.ok && recovered.response.state?.balance==1247949 && recovered.response.transaction?.provider=="worldpay")
  val pending=rehearsal.submit(PaymentAttempt("northline-studio",50,PaymentMethod.card,"Pending",Scenario.pending,"k-"+UUID.randomUUID())) as PaymentOutcome.Pending
  check(!pending.response.ok && pending.response.code=="PAYMENT_PENDING" && pending.response.paymentId!=null)
  check(client.getState().balance==1247949)
  check(client.reset().state?.balance==1248050)
  println("PASS: Kotlin rehearsal against Java API, catalog, GBP pence, idempotency, unavailable retry, pending and reset")
}
