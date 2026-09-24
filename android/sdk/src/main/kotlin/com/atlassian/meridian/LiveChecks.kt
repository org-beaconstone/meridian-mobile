package com.atlassian.meridian
import kotlinx.coroutines.runBlocking
import java.util.UUID
fun main()=runBlocking {
  val base=System.getenv("MERIDIAN_TEST_API")?:"http://127.0.0.1:8080/api/v1"
  val client=MeridianClient(base,"kotlin-check-"+UUID.randomUUID())
  check(client.getState().balance==1248050)
  check(client.getCatalog().providers.size==2)
  val key=UUID.randomUUID().toString()
  val paid=client.submitPayment("northline-studio",1000,"bank","Native Kotlin transport",idempotencyKey=key)
  check(paid.ok&&paid.state?.balance==1247050)
  val repeated=client.submitPayment("northline-studio",1000,"bank","Native Kotlin transport",idempotencyKey=key)
  check(repeated.ok&&repeated.state?.balance==1247050)
  val pending=client.submitPayment("northline-studio",100,"card","Pending",Scenario.pending,UUID.randomUUID().toString())
  check(!pending.ok&&pending.code=="PAYMENT_PENDING")
  check(client.getState().balance==1247050)
  check(client.reset().state?.balance==1248050)
  println("PASS: Kotlin SDK real Java transport, bank payment, idempotency, pending and reset")
}
