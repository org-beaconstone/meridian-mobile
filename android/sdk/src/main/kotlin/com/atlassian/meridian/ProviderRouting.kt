package com.atlassian.meridian

/** Card stays on Adyen and bank stays on Worldpay. */
fun providerFor(method: PaymentMethod): ProviderId = when (method) {
  PaymentMethod.card -> ProviderId.adyen
  PaymentMethod.bank -> ProviderId.worldpay
}

fun refuseProviderSwitch(original: ProviderId, attempted: ProviderId) {
  if (original != attempted) {
    throw MeridianError.ValidationError("Refusing to switch provider after an uncertain outcome")
  }
}
