package com.atlassian.meridian

import org.junit.Assert.assertTrue
import org.junit.Test

class ContractScenarioTest {
  private val report = runParitySuite(locateContractsDirectory())

  @Test fun moneyFormatting() = assertSection("money formatting")

  @Test fun legacyIntegerPaymentIntent() = assertSection("legacy integer payment intent")

  @Test fun multiCurrencyPaymentIntent() = assertSection("multi-currency payment intent")

  @Test fun legacyCatalog() = assertSection("legacy catalog")

  @Test fun multiCurrencyCatalog() = assertSection("multi-currency catalog")

  @Test fun cacheExpiry() = assertSection("cache expiry")

  @Test fun idempotencyPersistenceAndProcessDeath() = assertSection("idempotency persistence and process death")

  @Test fun replayedDeepLinks() = assertSection("replayed deep links")

  @Test fun expiredReturnStates() = assertSection("expired return states")

  @Test fun malformedCatalogEntries() = assertSection("malformed catalog entries")

  @Test fun accessibilityAndLocalisation() = assertSection("accessibility and localisation")

  private fun assertSection(name: String) {
    val section = report.sections.single { it.name == name }
    assertTrue(section.failures.joinToString("\n"), section.failures.isEmpty())
  }
}
