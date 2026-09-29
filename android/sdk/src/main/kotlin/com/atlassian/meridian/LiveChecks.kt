package com.atlassian.meridian
import kotlinx.coroutines.runBlocking
import java.util.UUID
fun main()=runBlocking {
  val base=System.getenv("MERIDIAN_TEST_API")?:"http://127.0.0.1:8080/api/v1"
  val client=MeridianClient(base,"kotlin-check-"+UUID.randomUUID())
  RehearsalJourney.run(client)
  println("PASS: Kotlin rehearsal journey against the Java contract, catalogue, GBP pence, idempotency, pending, outage retry and reset")
}
