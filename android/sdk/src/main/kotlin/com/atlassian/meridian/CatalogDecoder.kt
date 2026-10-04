package com.atlassian.meridian

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule

/**
 * Decodes either the legacy two-provider catalog or the dynamic methods catalog.
 * Unknown provider ids are dropped so a newer document cannot crash the client
 * or introduce a provider outside the Adyen card / Worldpay bank baseline.
 */
object CatalogDecoder {
  private val mapper = ObjectMapper().registerKotlinModule()

  fun decode(json: String): CatalogResponse? {
    val root = try {
      mapper.readTree(json)
    } catch (_: Exception) {
      return null
    }
    if (!root.isObject) return null
    return decodeObject(root)
  }

  fun decodeObject(root: JsonNode): CatalogResponse {
    val dynamic = isDynamic(root)
    val rows = when {
      dynamic && root.path("methods").isArray -> root.path("methods")
      root.path("providers").isArray -> root.path("providers")
      else -> mapper.createArrayNode()
    }
    val providers = mutableListOf<Provider>()
    for (row in rows) {
      decodeProvider(row)?.let { providers.add(it) }
    }
    return CatalogResponse(
      demoDate = root.path("demoDate").asText(""),
      recipients = decodeRecipients(root.path("recipients")),
      providers = providers,
      schema = if (dynamic) "dynamic" else "legacy",
      currencies = decodeCurrencies(root.get("currencies"), dynamic),
    )
  }

  private fun isDynamic(root: JsonNode): Boolean {
    val marker = (root.path("schema").asText("").ifEmpty { root.path("model").asText("") })
      .trim()
      .lowercase()
    if (marker == "dynamic") return true
    if (marker == "legacy") return false
    return root.path("methods").isArray && !root.has("providers")
  }

  private fun decodeRecipients(node: JsonNode): List<Recipient> {
    if (!node.isArray) return emptyList()
    val recipients = mutableListOf<Recipient>()
    for (row in node) {
      val id = row.path("id").asText("")
      val name = row.path("name").asText("")
      val initials = row.path("initials").asText("")
      val detail = row.path("detail").asText("")
      val category = row.path("category").asText("")
      val color = row.path("color").asText("")
      if (id.isEmpty() || name.isEmpty() || initials.isEmpty() || detail.isEmpty() || category.isEmpty() || color.isEmpty()) {
        continue
      }
      recipients.add(Recipient(id, name, initials, detail, category, color))
    }
    return recipients
  }

  private fun decodeProvider(row: JsonNode): Provider? {
    if (!row.isObject) return null
    val idRaw = text(row, "providerId") ?: text(row, "provider") ?: text(row, "id") ?: return null
    if (idRaw != "adyen" && idRaw != "worldpay") return null
    val fallbackName = if (idRaw == "adyen") "Adyen" else "Worldpay"
    val name = text(row, "name") ?: text(row, "label") ?: fallbackName
    val description = text(row, "description") ?: ""
    val single = text(row, "method") ?: text(row, "rail")
    val methods = if (single == "card" || single == "bank") {
      listOf(single)
    } else {
      row.path("methods").mapNotNull { method ->
        val value = method.asText("")
        if (value == "card" || value == "bank") value else null
      }.take(1)
    }
    val method = methods.firstOrNull() ?: return null
    return Provider(id = idRaw, name = name, description = description, methods = listOf(method))
  }

  private fun decodeCurrencies(node: JsonNode?, dynamic: Boolean): List<String> {
    if (!dynamic || node == null || node.isNull) return listOf("GBP")
    val codes = if (node.isArray) {
      node.mapNotNull { item ->
        when {
          item.isTextual -> item.asText()
          item.isObject -> text(item, "code")
          else -> null
        }
      }
    } else {
      emptyList()
    }
    val recognized = mutableListOf<String>()
    for (code in codes) {
      val normalized = code.trim().uppercase()
      if ((normalized == "GBP" || normalized == "EUR") && normalized !in recognized) {
        recognized.add(normalized)
      }
    }
    if ("GBP" !in recognized) recognized.add(0, "GBP")
    return recognized
  }

  private fun text(node: JsonNode, field: String): String? {
    if (!node.has(field) || node.get(field).isNull) return null
    val value = node.get(field).asText().trim()
    return value.ifEmpty { null }
  }
}
