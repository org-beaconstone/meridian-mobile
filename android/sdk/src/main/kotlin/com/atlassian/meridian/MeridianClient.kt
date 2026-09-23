package com.atlassian.meridian

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets

/**
 * Meridian API client for Kotlin/JVM and Android
 * Uses HttpURLConnection for universal JVM/Android compatibility
 * Coroutines for async operations with UI dispatcher where needed
 */
class MeridianClient(
  private val baseURL: String,
  private val sessionId: String,
  private val providerConfigStore: ProviderConfigStore = ProviderConfigStore.shared,
  val providerConfigHealth: ProviderConfigHealth = ProviderConfigHealth(),
  private val pickerMode: ProviderPickerMode = ProviderPickerFlags.resolve(),
) {
  private val mapper = ObjectMapper().registerKotlinModule()
  private val baseUrlNormalized = baseURL.removeSuffix("/")

  init {
    require(sessionId.isNotEmpty()) { "Session ID is required" }
    require(
      baseUrlNormalized.startsWith("http://") || baseUrlNormalized.startsWith("https://")
    ) { "Invalid URL: must start with http:// or https://" }
  }

  // MARK: - Internal Request Method

  private suspend fun <T> request(
    method: String,
    path: String,
    body: Any? = null,
    additionalHeaders: Map<String, String> = emptyMap(),
    responseType: Class<T>,
    lenientStatus: Boolean = true,
  ): T = withContext(Dispatchers.IO) {
    val fullUrl = "$baseUrlNormalized$path"
    val url = URL(fullUrl)

    val connection = url.openConnection() as HttpURLConnection
    try {
      connection.connectTimeout = 15000
      connection.readTimeout = 15000
      connection.requestMethod = method
      connection.setRequestProperty("Content-Type", "application/json")
      connection.setRequestProperty("X-Rehearsal-Session", sessionId)

      // Add additional headers (e.g., Idempotency-Key)
      additionalHeaders.forEach { (key, value) ->
        connection.setRequestProperty(key, value)
      }

      // Write body if present
      if (body != null) {
        val bodyJson = mapper.writeValueAsString(body)
        connection.doOutput = true
        connection.outputStream.use { out ->
          out.write(bodyJson.toByteArray(StandardCharsets.UTF_8))
          out.flush()
        }
      }

      // Read response
      val statusCode = connection.responseCode
      val responseStream = if (statusCode >= 400) {
        connection.errorStream
      } else {
        connection.inputStream
      }

      val responseBody = responseStream?.bufferedReader()?.use { it.readText() } ?: ""

      // Check HTTP status and handle errors
      when {
        statusCode >= 200 && statusCode < 300 -> {
          // Success
          try {
            mapper.readValue(responseBody, responseType)
          } catch (e: Exception) {
            throw MeridianError.DecodingError("Failed to parse response: ${e.message}", e)
          }
        }

        lenientStatus && (statusCode == 202 || statusCode == 400 || statusCode == 409 || statusCode == 422 || statusCode == 503) -> {
          // These are expected error statuses, parse the response
          try {
            mapper.readValue(responseBody, responseType)
          } catch (e: Exception) {
            throw MeridianError.HttpError(
              statusCode,
              responseBody.ifEmpty { "Unknown error" }
            )
          }
        }

        else -> {
          throw MeridianError.HttpError(
            statusCode,
            responseBody.ifEmpty { "Unknown error" }
          )
        }
      }
    } finally {
      connection.disconnect()
    }
  }

  // MARK: - Public API Methods

  /**
   * GET /health - Check service health
   */
  suspend fun getHealth(): HealthResponse =
    request("GET", "/health", responseType = HealthResponse::class.java)

  /**
   * GET /catalog - Fetch recipients and providers
   */
  suspend fun getCatalog(): CatalogResponse =
    request("GET", "/catalog", responseType = CatalogResponse::class.java)

  /**
   * Payment methods for [corridor].
   *
   * Remote mode calls GET /config/payment-providers with the rehearsal session header.
   * A failed or unusable response falls back to the last cached configuration for this
   * session, or the Milestone 2 Adyen/Worldpay seed when nothing has been cached.
   * Milestone 2 mode skips the network and returns that seed directly.
   */
  suspend fun loadPaymentProviders(
    corridor: String,
    mode: ProviderPickerMode = pickerMode,
  ): ProviderPickerResult {
    if (mode == ProviderPickerMode.MILESTONE_2_BASELINE) {
      val baseline = milestone2BaselineConfig()
      return ProviderPickerResult(
        providers = baseline.providersForCorridor(corridor),
        source = ProviderConfigSource.MILESTONE_2_BASELINE,
        configVersion = baseline.configVersion,
      )
    }
    return try {
      val response = request(
        method = "GET",
        path = "/config/payment-providers",
        responseType = PaymentProviderConfigResponse::class.java,
        lenientStatus = false,
      )
      val config = validatePaymentProviderConfig(response)
      providerConfigStore.put(sessionId, config)
      providerConfigHealth.recordSuccess(config.configVersion)
      ProviderPickerResult(
        providers = config.providersForCorridor(corridor),
        source = ProviderConfigSource.REMOTE,
        configVersion = config.configVersion,
      )
    } catch (cancelled: CancellationException) {
      throw cancelled
    } catch (error: Exception) {
      val cached = providerConfigStore.get(sessionId) ?: milestone2BaselineConfig()
      providerConfigHealth.recordFallback(cached.configVersion, error.message ?: "config fetch failed")
      ProviderPickerResult(
        providers = cached.providersForCorridor(corridor),
        source = ProviderConfigSource.CACHE,
        configVersion = cached.configVersion,
      )
    }
  }

  /**
   * GET /state - Fetch current bank state
   */
  suspend fun getState(): BankState =
    request("GET", "/state", responseType = BankState::class.java)

  /**
   * POST /payments - Submit a payment
   * @param recipientId Recipient ID
   * @param amountMinor Amount in GBP pence (integer)
   * @param method Payment method (card or bank)
   * @param note Optional note (max 200 chars)
   * @param scenario Simulation scenario
   * @param idempotencyKey Unique key for idempotency
   */
  suspend fun submitPayment(
    recipientId: String,
    amountMinor: Int,
    method: PaymentMethod,
    note: String = "",
    scenario: Scenario = Scenario.success,
    idempotencyKey: String,
  ): PaymentResponse {
    val payload = PaymentRequest(
      recipientId = recipientId,
      amountMinor = amountMinor,
      method = method.name,
      note = note,
      scenario = scenario.name,
    )

    return request(
      "POST",
      "/payments",
      payload,
      mapOf("Idempotency-Key" to idempotencyKey),
      PaymentResponse::class.java,
    )
  }

  /**
   * PATCH /budgets - Update budget for a category
   * @param category Budget category
   * @param limitMinor Limit in GBP pence
   */
  suspend fun updateBudget(
    category: String,
    limitMinor: Int,
  ): BudgetResponse {
    val payload = BudgetRequest(category = category, limitMinor = limitMinor)
    return request(
      "PATCH",
      "/budgets",
      payload,
      responseType = BudgetResponse::class.java,
    )
  }

  /**
   * POST /reset - Reset session state
   */
  suspend fun reset(): ResetResponse =
    request("POST", "/reset", responseType = ResetResponse::class.java)

  /**
   * GET /events - Fetch audit events
   */
  suspend fun getEvents(): EventsResponse =
    request("GET", "/events", responseType = EventsResponse::class.java)
}
