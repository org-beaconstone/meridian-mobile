package com.atlassian.meridian

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

/**
 * Android instrumented journey against the local Spring Boot mock.
 * Pass meridianApi=http://10.0.2.2:8080/api/v1 when the mock runs on the host.
 * This source is not executed by Maven. A device or emulator run was not available here.
 */
@RunWith(AndroidJUnit4::class)
class PaymentJourneyInstrumentedTest {
  @Test
  fun endToEndPaymentJourney() {
    val base = InstrumentationRegistry.getArguments().getString("meridianApi")
      ?: "http://10.0.2.2:8080/api/v1"
    JourneyRunner.run(base, "android-journey-" + UUID.randomUUID())
  }
}
