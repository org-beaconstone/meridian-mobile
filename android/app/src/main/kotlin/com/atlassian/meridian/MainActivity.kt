package com.atlassian.meridian

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.UUID
import kotlin.coroutines.resume

class MainActivity : ComponentActivity() {

    // Pending return URL delivered via onNewIntent while the composable is alive.
    private val pendingReturnUri = mutableStateOf<Uri?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Handle a return URL that launched this activity from a cold start.
        pendingReturnUri.value = intent?.data
        setContent {
            MaterialTheme(colors = lightColors(primary = Color(0xFF142C35), secondary = Color(0xFFD5B77A))) {
                MeridianScreen(
                    pendingReturnUri = pendingReturnUri,
                    biometricAuthenticator = AndroidBiometricSCAHandler(this),
                )
            }
        }
    }

    /** Called when the activity is already running and a new deep-link intent arrives. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingReturnUri.value = intent.data
    }
}

// MARK: - Android Biometric SCA Handler

/**
 * Production [SCAAuthenticating] backed by [BiometricPrompt].
 *
 * Falls back to device credential (PIN / pattern / password) for `.Pin` and `.Any` challenges.
 */
class AndroidBiometricSCAHandler(private val activity: ComponentActivity) : SCAAuthenticating {

    override suspend fun authenticate(challenge: SCAChallenge): SCAResult {
        val allowedAuthenticators = when (challenge) {
            is SCAChallenge.Biometric ->
                BiometricManager.Authenticators.BIOMETRIC_STRONG
            is SCAChallenge.Pin ->
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
            is SCAChallenge.Any ->
                BiometricManager.Authenticators.BIOMETRIC_STRONG or
                        BiometricManager.Authenticators.DEVICE_CREDENTIAL
        }

        val biometricManager = BiometricManager.from(activity)
        val canAuthenticate = biometricManager.canAuthenticate(allowedAuthenticators)
        if (canAuthenticate != BiometricManager.BIOMETRIC_SUCCESS) {
            return SCAResult.Failed("Authenticator not available (code $canAuthenticate)")
        }

        return suspendCancellableCoroutine { continuation ->
            val executor = ContextCompat.getMainExecutor(activity)
            val prompt = BiometricPrompt(
                activity,
                executor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        if (continuation.isActive) continuation.resume(SCAResult.Success)
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        val result = if (errorCode == BiometricPrompt.ERROR_USER_CANCELED ||
                            errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON
                        ) {
                            SCAResult.Cancelled
                        } else {
                            SCAResult.Failed(errString.toString())
                        }
                        if (continuation.isActive) continuation.resume(result)
                    }

                    override fun onAuthenticationFailed() {
                        // Biometric did not match; the prompt stays visible for retries.
                        // We don't resolve the coroutine here.
                    }
                },
            )

            val info = BiometricPrompt.PromptInfo.Builder()
                .setTitle("Confirm payment")
                .setSubtitle(challenge.reason)
                .setAllowedAuthenticators(allowedAuthenticators)
                .build()

            prompt.authenticate(info)

            continuation.invokeOnCancellation { prompt.cancelAuthentication() }
        }
    }
}

// MARK: - Composable Screen

@Composable
fun MeridianScreen(
    pendingReturnUri: MutableState<Uri?>,
    biometricAuthenticator: SCAAuthenticating,
) {
    val scope = rememberCoroutineScope()
    var base by remember { mutableStateOf("http://10.0.2.2:8080/api/v1") }
    var room by remember { mutableStateOf("meridian-rehearsal") }
    var client by remember { mutableStateOf<MeridianClient?>(null) }
    var handoffManager by remember { mutableStateOf<BankHandoffManager?>(null) }
    var state by remember { mutableStateOf<BankState?>(null) }
    var catalog by remember { mutableStateOf<CatalogResponse?>(null) }
    var recipient by remember { mutableStateOf("northline-studio") }
    var amount by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var method by remember { mutableStateOf(PaymentMethod.card) }
    var review by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var paymentKey by remember { mutableStateOf(UUID.randomUUID().toString()) }
    var pendingPaymentId by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf("Fictional payment rehearsal. Connect to the Java API.") }
    var revision by remember { mutableStateOf(0) }

    // Handle return URL from bank handoff (universal/app link or custom scheme).
    LaunchedEffect(pendingReturnUri.value) {
        val returnUri = pendingReturnUri.value ?: return@LaunchedEffect
        val manager = handoffManager
        if (manager == null) {
            pendingReturnUri.value = null
            return@LaunchedEffect
        }
        pendingReturnUri.value = null

        busy = true
        try {
            val payload = manager.handleReturnURL(returnUri.toString())
            if (payload.paymentId == pendingPaymentId) {
                message = "Bank handoff returned. Finalising payment…"
                // The payment was already submitted; update state.
                val fresh = client?.getState()
                if (fresh != null) {
                    state = fresh
                    review = false
                    amount = ""
                    note = ""
                    pendingPaymentId = null
                    paymentKey = UUID.randomUUID().toString()
                    message = "Bank payment confirmed."
                }
            } else {
                message = "Return state mismatch – payment not confirmed."
            }
        } catch (e: HandoffError.ExpiredReturnState) {
            message = "Bank return expired. Please retry – no duplicate payment will be created."
        } catch (e: HandoffError.ReplayedReturnState) {
            message = "Return token already used. Ignoring to prevent replay."
        } catch (e: HandoffError) {
            message = "Invalid bank return: ${e.message}. Payment not confirmed."
        } finally {
            busy = false
        }
    }

    LaunchedEffect(client) {
        val current = client
        while (current != null) {
            val started = revision
            if (!busy) try {
                val fresh = current.getState()
                val definitions = current.getCatalog()
                if (current === client && started == revision && !busy) {
                    state = fresh
                    catalog = definitions
                    message = "Connected to shared Java API"
                }
            } catch (e: Exception) {
                if (current === client) message = "API unavailable: ${e.message}"
            }
            delay(2000)
        }
    }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("meridian", style = MaterialTheme.typography.h4)
        Text("Native Android · simulated GBP payments", style = MaterialTheme.typography.caption)
        OutlinedTextField(base, { base = it }, label = { Text("API base URL") }, enabled = !busy)
        OutlinedTextField(room, { room = it }, label = { Text("Shared rehearsal room") }, enabled = !busy)
        Button(onClick = {
            if (!Regex("[A-Za-z0-9_-]{3,64}").matches(room)) {
                message = "Invalid room"
            } else try {
                client = MeridianClient(base, room)
                handoffManager = BankHandoffManager(sessionId = room)
                state = null
                catalog = null
                review = false
                revision++
                paymentKey = UUID.randomUUID().toString()
                pendingPaymentId = null
            } catch (e: Exception) {
                message = e.message ?: "Invalid configuration"
            }
        }, enabled = !busy) { Text("Connect") }
        Text(message)
        state?.let { current ->
            Card(
                backgroundColor = Color(0xFF142C35),
                contentColor = Color.White,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(Modifier.padding(22.dp)) {
                    Text("Everyday account")
                    Text(money(current.balance), style = MaterialTheme.typography.h3)
                    Text("Room: $room")
                }
            }
            Text("Make a payment", style = MaterialTheme.typography.h6)
            catalog?.recipients?.forEach { person ->
                Row {
                    RadioButton(
                        selected = recipient == person.id,
                        onClick = { recipient = person.id },
                        enabled = !review && !busy,
                    )
                    Text(person.name, Modifier.padding(top = 12.dp))
                }
            }
            OutlinedTextField(amount, { amount = it }, label = { Text("Amount (GBP)") }, enabled = !review && !busy)
            OutlinedTextField(note, { note = it.take(200) }, label = { Text("Reference") }, enabled = !review && !busy)
            // Intentional two-provider native baseline; changing it requires an app release.
            Row {
                RadioButton(method == PaymentMethod.card, { method = PaymentMethod.card }, enabled = !review && !busy)
                Text("Debit card · Adyen", Modifier.padding(top = 12.dp))
            }
            Row {
                RadioButton(method == PaymentMethod.bank, { method = PaymentMethod.bank }, enabled = !review && !busy)
                Text("Bank payment · Worldpay", Modifier.padding(top = 12.dp))
            }
            if (!review) {
                Button(onClick = {
                    val parsed = parseAmount(amount)
                    if (parsed.first == null) message = parsed.second ?: "Invalid amount"
                    else { review = true; paymentKey = UUID.randomUUID().toString() }
                }, enabled = !busy) { Text("Review payment") }
            } else {
                Text("Confirm £$amount to $recipient")
                Button(onClick = {
                    val active = client
                    val minor = parseAmount(amount).first
                    if (active != null && minor != null && !busy) {
                        busy = true
                        revision++
                        scope.launch {
                            try {
                                // SCA challenge before confirming payment.
                                val scaChallenge = SCAChallenge.Any("Confirm payment of £$amount to $recipient")
                                when (val scaResult = biometricAuthenticator.authenticate(scaChallenge)) {
                                    is SCAResult.Success -> Unit
                                    is SCAResult.Cancelled -> {
                                        message = "Authentication cancelled."
                                        return@launch
                                    }
                                    is SCAResult.Failed -> {
                                        message = "Authentication failed: ${scaResult.reason}"
                                        return@launch
                                    }
                                }

                                val result = active.submitPayment(
                                    recipientId = recipient,
                                    amountMinor = minor,
                                    method = method,
                                    note = note,
                                    idempotencyKey = paymentKey,
                                )
                                if (result.ok) {
                                    state = result.state
                                    review = false
                                    amount = ""
                                    note = ""
                                    paymentKey = UUID.randomUUID().toString()
                                    pendingPaymentId = null
                                    message = "Demo payment complete"
                                } else if (result.code == "PAYMENT_PENDING" && result.paymentId != null &&
                                    method == PaymentMethod.bank
                                ) {
                                    // Bank payment requires external handoff.
                                    pendingPaymentId = result.paymentId
                                    val manager = handoffManager
                                    if (manager != null) {
                                        try {
                                            val bankHost = "secure.worldpay.com"
                                            val handoffUrl = manager.buildHandoffURL(
                                                bankURL = "https://$bankHost/checkout",
                                                paymentId = result.paymentId,
                                                returnScheme = "meridian",
                                            )
                                            message = "Redirecting to bank: $handoffUrl"
                                        } catch (e: HandoffError) {
                                            message = "Handoff error: ${e.message}"
                                        }
                                    } else {
                                        message = result.error ?: "Awaiting bank confirmation."
                                    }
                                } else {
                                    message = result.error ?: "Awaiting confirmation. Retry the same payment."
                                }
                            } catch (e: Exception) {
                                message = "Outcome may be unknown: ${e.message}. Retry keeps the same key."
                            } finally {
                                revision++
                                busy = false
                            }
                        }
                    }
                }, enabled = !busy) { Text(if (busy) "Confirming…" else "Confirm payment") }
                TextButton(onClick = { review = false; paymentKey = UUID.randomUUID().toString() }, enabled = !busy) {
                    Text("Edit details")
                }
            }
            Text("Recent activity", style = MaterialTheme.typography.h6)
            current.transactions.reversed().take(8).forEach { transaction ->
                Text("${transaction.name} · ${money(transaction.amount)} · ${transaction.provider}")
            }
            Text("Budgets", style = MaterialTheme.typography.h6)
            current.budgets.forEach { budget ->
                Text("${budget.category} · ${money(budget.limit)}")
            }
        }
    }
}
