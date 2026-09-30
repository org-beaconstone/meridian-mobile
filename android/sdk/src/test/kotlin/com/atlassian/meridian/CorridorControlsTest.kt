package com.atlassian.meridian

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CorridorControlsTest {
  private val euCatalog = """
    "catalogVersion": 2,
    "catalogs": [
      {"version": 1, "corridors": ["GB"]},
      {"version": 2, "corridors": ["GB", "EU"]}
    ]
  """.trimIndent()

  private fun ids(controls: CorridorControls, account: String = "acct") =
    controls.visibleMethods(account).map { it.id }

  @Test
  fun testDefaultRailsAreAdyenAndWorldpay() {
    val controls = CorridorControls()
    assertEquals(listOf("adyen-card-gb", "worldpay-bank-gb"), ids(controls))
    assertTrue(controls.visibleMethods("acct").all { it.provider == ProviderId.adyen || it.provider == ProviderId.worldpay })
  }

  @Test
  fun testFlagsAreIndependent() {
    val controls = CorridorControls()
    assertTrue(
      controls.applyServerPayload(
        """{"flags":{"multi_provider_selection":false,"european_corridor":true},$euCatalog}"""
      )
    )
    assertFalse(controls.flags.multiProviderSelection)
    assertTrue(controls.flags.europeanCorridorEnabled)
    assertEquals(listOf("adyen-card-gb", "adyen-card-eu"), ids(controls))

    controls.applyServerPayload("""{"flags":{"multi_provider_selection":true,"european_corridor":false}}""")
    assertTrue(controls.flags.multiProviderSelection)
    assertFalse(controls.flags.europeanCorridorEnabled)
    assertEquals(listOf("adyen-card-gb", "worldpay-bank-gb"), ids(controls))
    assertEquals(2, controls.activeCatalog.version)
  }

  @Test
  fun testDarkLaunchHidesEuropeAndRecordsTelemetry() {
    val controls = CorridorControls()
    controls.applyServerPayload(
      """{"flags":{"multi_provider_selection":true,"european_corridor":true,"dark_launch":true},$euCatalog}"""
    )
    assertEquals(listOf(PaymentCorridor.GB, PaymentCorridor.GB), controls.resolve("acct").map { it.corridor })
    assertEquals(2, controls.resolve("acct").size)
    assertEquals(1, controls.telemetry.size)
    val event = controls.telemetry.single()
    assertEquals(1, event.generation)
    assertEquals("acct", event.accountId)
    assertEquals(2, event.catalogVersion)
    assertEquals("EU", event.corridor)
    assertTrue(event.europeanMethodsHidden)
  }

  @Test
  fun testCanaryAccounts() {
    val controls = CorridorControls()
    controls.applyServerPayload(
      """{"flags":{"european_corridor":true,"multi_provider_selection":true},"controlledAccounts":["controlled-eu"],$euCatalog}"""
    )
    assertTrue(ids(controls, "controlled-eu").contains("adyen-card-eu"))
    assertFalse(ids(controls, "everyone-else").contains("adyen-card-eu"))

    controls.applyServerPayload(
      """{"flags":{"european_corridor":true,"dark_launch":true,"multi_provider_selection":true},"canaryAccounts":["controlled-eu"]}"""
    )
    assertFalse(ids(controls, "controlled-eu").contains("adyen-card-eu"))
    controls.resolve("controlled-eu")
    assertTrue(controls.telemetry.last().europeanMethodsHidden)
  }

  @Test
  fun testKillSwitchPreservesStatusAndReceipt() {
    val controls = CorridorControls()
    val created = controls.createIntent("key-1", "acct", "northline-studio", 2500, "Studio", "adyen-card-gb")
    assertTrue(created is IntentResult.Created)
    val intent = (created as IntentResult.Created).intent
    assertEquals(2500, controls.complete(intent.id, "REF-1")?.amountMinor)
    assertTrue(controls.applyServerPayload("""{"flags":{"payments_kill_switch":true}}"""))
    val blocked = controls.createIntent("key-2", "acct", "northline-studio", 100, methodId = "adyen-card-gb")
    assertTrue(blocked is IntentResult.Rejected)
    val rejection = blocked as IntentResult.Rejected
    assertEquals(IntentRejection.KILL_SWITCH, rejection.reason)
    assertEquals(PAYMENTS_PAUSED_MESSAGE, rejection.reason.message)
    assertEquals(IntentStatus.completed, controls.status(intent.id))
    assertEquals("REF-1", controls.receipt(intent.id)?.reference)
    val retry = controls.createIntent("key-1", "acct", "other", 1, methodId = "worldpay-bank-gb") as IntentResult.Created
    assertEquals(intent.id, retry.intent.id)
    assertEquals(ProviderId.adyen, retry.intent.provider)
  }

  @Test
  fun testCatalogRollbackKeepsIntentSnapshot() {
    val controls = CorridorControls()
    controls.applyServerPayload(
      """{"flags":{"european_corridor":true,"multi_provider_selection":true},$euCatalog}"""
    )
    val created = controls.createIntent(
      "eu-key",
      "acct",
      "northline-studio",
      1_000_000,
      methodId = "worldpay-bank-eu",
    ) as IntentResult.Created
    val snapshot = created.intent.snapshot.copy(methods = created.intent.snapshot.methods.toList())
    assertTrue(
      controls.applyServerPayload(
        """{"flags":{"european_corridor":true,"multi_provider_selection":true},"catalogVersion":1}"""
      )
    )
    assertEquals(1, controls.activeCatalog.version)
    assertTrue(controls.activeCatalog.methods.none { it.id == "worldpay-bank-eu" })
    assertEquals(snapshot, controls.intent(created.intent.id)?.snapshot)
    assertTrue(controls.snapshotRemainsValid(created.intent.id))
    assertEquals(IntentStatus.inFlight, controls.status(created.intent.id))
    assertFalse(controls.rollbackCatalog(99))
    assertEquals(1, controls.activeCatalog.version)
    assertTrue(controls.rollbackCatalog(2))
    assertEquals(2, controls.intent(created.intent.id)?.snapshot?.version)
  }

  @Test
  fun testNumericFlagsAndCorruptPayloads() {
    val controls = CorridorControls()
    controls.applyServerPayload("""{"flags":{"payments_kill_switch":true}}""")
    assertFalse(controls.applyServerPayload("nope"))
    assertFalse(controls.applyServerPayload("[]"))
    assertTrue(controls.flags.killSwitch)
    assertTrue(controls.blocksNewIntent("fresh"))

    assertTrue(
      controls.applyServerPayload(
        """{"flags":{"payments_kill_switch":1,"european_corridor":1,"dark_launch":1,"multi_provider_selection":0}}"""
      )
    )
    assertFalse(controls.flags.killSwitch)
    assertFalse(controls.flags.europeanCorridorEnabled)
    assertFalse(controls.flags.darkLaunch)
    assertFalse(controls.flags.multiProviderSelection)
    assertEquals(listOf("adyen-card-gb"), ids(controls))

    controls.applyServerPayload(
      """{"payments_kill_switch":true,"flags":{"payments_kill_switch":false},"dark_launch":"TRUE","european_corridor":"true"}"""
    )
    assertFalse(controls.flags.killSwitch)
    assertTrue(controls.flags.darkLaunch)
    assertTrue(controls.flags.europeanCorridorEnabled)
  }

  @Test
  fun testHiddenMethodAndAmount() {
    val controls = CorridorControls()
    val hidden = controls.createIntent("hidden", "acct", "northline-studio", 100, methodId = "adyen-card-eu")
    assertTrue(hidden is IntentResult.Rejected)
    assertEquals(IntentRejection.METHOD_UNAVAILABLE, (hidden as IntentResult.Rejected).reason)
    assertNull(controls.intent("intent-1"))
    val amount = controls.createIntent("amount", "acct", "northline-studio", 1_000_001, methodId = "adyen-card-gb")
    assertEquals(IntentRejection.INVALID_AMOUNT, (amount as IntentResult.Rejected).reason)
  }

  @Test
  fun testFetchConfigKeepsSessionHeader() = runBlocking {
    val server = com.sun.net.httpserver.HttpServer.create(java.net.InetSocketAddress("127.0.0.1", 0), 0)
    val port = server.address.port
    server.createContext("/api/v1/config") { exchange ->
      assertEquals("test-session", exchange.requestHeaders.getFirst("X-Rehearsal-Session"))
      val body = """{"flags":{"payments_kill_switch":true}}"""
      exchange.responseHeaders.add("Content-Type", "application/json")
      exchange.sendResponseHeaders(200, body.length.toLong())
      exchange.responseBody.write(body.toByteArray())
      exchange.close()
    }
    server.start()
    try {
      val client = MeridianClient("http://127.0.0.1:$port/api/v1", "test-session")
      val controls = CorridorControls()
      assertTrue(controls.applyServerPayload(client.fetchConfig()))
      assertTrue(controls.flags.killSwitch)
      val blocked = controls.createIntent("new", "acct", "northline-studio", 100, methodId = "adyen-card-gb")
      assertEquals(IntentRejection.KILL_SWITCH, (blocked as IntentResult.Rejected).reason)
      assertNotNull(controls)
    } finally {
      server.stop(0)
    }
  }
}
