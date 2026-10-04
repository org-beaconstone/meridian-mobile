package com.atlassian.meridian

import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.UUID

class ContainerJourneyTest {
  @Test
  fun paymentJourneyAgainstSpringBootMock() {
    val base = System.getenv("MERIDIAN_TEST_API")
    if (base.isNullOrBlank()) {
      if (System.getenv("MERIDIAN_REQUIRE_CONTAINER") == "1") {
        fail("MERIDIAN_TEST_API is required for the Spring Boot mock journey")
      }
      assumeTrue("Set MERIDIAN_TEST_API to run the Spring Boot mock journey", false)
      return
    }
    JourneyRunner.run(base, "kotlin-journey-" + UUID.randomUUID())
  }
}
