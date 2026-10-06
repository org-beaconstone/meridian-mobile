package com.atlassian.meridian

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ConsumerContractTest {
  @Test
  fun consumerContractMatchesSharedFixture() {
    val failures = MeridianSuites.contractFailures(fixture("consumer-contract.json"))
    assertTrue(failures.joinToString("\n"), failures.isEmpty())
  }

  private fun fixture(name: String): String {
    var dir: File? = File(System.getProperty("user.dir"))
    while (dir != null) {
      val candidate = File(dir, "shared/$name")
      if (candidate.isFile) return candidate.readText()
      dir = dir.parentFile
    }
    error("missing shared/$name from ${System.getProperty("user.dir")}")
  }
}
