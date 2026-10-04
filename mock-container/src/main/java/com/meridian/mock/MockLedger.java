package com.meridian.mock;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * In-memory rehearsal ledger for the shared /api/v1 contract.
 * Amounts are integer GBP pence. Card maps to Adyen and bank maps to Worldpay.
 */
@RestController
@RequestMapping("/api/v1")
public class MockLedger {
  private static final Set<String> SCENARIOS = Set.of("success", "declined", "unavailable", "pending");
  private final ObjectMapper mapper = new ObjectMapper();
  private final ObjectNode fixture;
  private final Map<String, ObjectNode> states = new HashMap<>();
  private final Map<String, ObjectNode> intents = new HashMap<>();

  public MockLedger() throws Exception {
    try (InputStream input = MockLedger.class.getResourceAsStream("/fixture.json")) {
      if (input == null) throw new IllegalStateException("fixture.json is missing");
      fixture = (ObjectNode) mapper.readTree(input);
    }
  }

  @GetMapping("/health")
  public Map<String, Object> health() {
    return Map.of("status", "UP", "service", "meridian-api", "simulation", true);
  }

  @GetMapping("/catalog")
  public ObjectNode catalog() {
    ObjectNode body = mapper.createObjectNode();
    body.put("demoDate", "2026-09-18");
    body.set("recipients", fixture.get("recipients"));
    body.set("providers", fixture.get("providers"));
    return body;
  }

  @GetMapping("/state")
  public synchronized ResponseEntity<JsonNode> state(@RequestHeader(value = "X-Rehearsal-Session", required = false) String room) {
    ResponseEntity<JsonNode> invalid = roomError(room);
    if (invalid != null) return invalid;
    return ResponseEntity.ok(stateFor(room).deepCopy());
  }

  @PostMapping("/reset")
  public synchronized ResponseEntity<JsonNode> reset(@RequestHeader(value = "X-Rehearsal-Session", required = false) String room) {
    ResponseEntity<JsonNode> invalid = roomError(room);
    if (invalid != null) return invalid;
    states.remove(room);
    intents.keySet().removeIf(key -> key.startsWith(room + "\0"));
    ObjectNode body = mapper.createObjectNode();
    body.put("ok", true);
    body.set("state", stateFor(room).deepCopy());
    return ResponseEntity.ok(body);
  }

  @PatchMapping("/budgets")
  public synchronized ResponseEntity<JsonNode> budget(
    @RequestHeader(value = "X-Rehearsal-Session", required = false) String room,
    @RequestBody JsonNode body
  ) {
    ResponseEntity<JsonNode> invalid = roomError(room);
    if (invalid != null) return invalid;
    if (body == null || !body.hasNonNull("category") || !body.has("limitMinor") || !body.get("limitMinor").isIntegralNumber()) {
      return error(400, "HTTP_400", "Invalid budget limit");
    }
    long limit = body.get("limitMinor").asLong();
    if (limit <= 0 || limit > 1_000_000) return error(400, "HTTP_400", "Invalid budget limit");
    ObjectNode state = stateFor(room);
    String category = body.get("category").asText();
    boolean found = false;
    for (JsonNode budget : state.get("budgets")) {
      if (category.equals(budget.get("category").asText())) {
        ((ObjectNode) budget).put("limit", limit);
        found = true;
      }
    }
    if (!found) return error(400, "HTTP_400", "Unknown category");
    ObjectNode response = mapper.createObjectNode();
    response.put("ok", true);
    response.set("state", state.deepCopy());
    return ResponseEntity.ok(response);
  }

  @PostMapping("/payments")
  public synchronized ResponseEntity<JsonNode> payment(
    @RequestHeader(value = "X-Rehearsal-Session", required = false) String room,
    @RequestHeader(value = "Idempotency-Key", required = false) String key,
    @RequestBody JsonNode body
  ) {
    ResponseEntity<JsonNode> invalid = roomError(room);
    if (invalid != null) return invalid;
    if (key == null || !key.matches("[A-Za-z0-9_-]{1,100}")) {
      return error(400, "HTTP_400", "Invalid Idempotency-Key");
    }
    if (body == null || !body.hasNonNull("recipientId") || !body.has("amountMinor") || !body.get("amountMinor").isIntegralNumber()) {
      return error(400, "HTTP_400", "Amount must be integer pence from 1 to 1000000");
    }
    long amount = body.get("amountMinor").asLong();
    if (amount < 1 || amount > 1_000_000) {
      return error(400, "HTTP_400", "Amount must be integer pence from 1 to 1000000");
    }
    String method = body.path("method").asText("");
    if (!method.equals("card") && !method.equals("bank")) return error(400, "HTTP_400", "Unknown payment method");
    String note = body.hasNonNull("note") ? body.get("note").asText() : "";
    if (note.length() > 200) return error(400, "HTTP_400", "Reference exceeds 200 characters");
    String scenario = body.hasNonNull("scenario") ? body.get("scenario").asText() : "success";
    if (!SCENARIOS.contains(scenario)) return error(400, "HTTP_400", "Unknown simulation scenario");
    String recipientId = body.get("recipientId").asText();
    ObjectNode recipient = recipient(recipientId);
    if (recipient == null) return error(400, "HTTP_400", "Unknown recipient");

    String fingerprint = fingerprint(recipientId, amount, method, note);
    String intentId = room + "\0" + key;
    ObjectNode existing = intents.get(intentId);
    if (existing != null) {
      if (!fingerprint.equals(existing.get("fingerprint").asText())) {
        return error(409, "HTTP_409", "Idempotency key belongs to a different payment");
      }
      return stored(existing, stateFor(room));
    }

    ObjectNode state = stateFor(room);
    if (state.get("balance").asLong() < amount) return error(400, "HTTP_400", "Insufficient available balance");
    String provider = method.equals("card") ? "adyen" : "worldpay";
    String id = UUID.randomUUID().toString();
    ObjectNode intent = mapper.createObjectNode();
    intent.put("fingerprint", fingerprint);
    intent.put("phase", scenario);
    intent.put("paymentId", id);

    if (!scenario.equals("success")) {
      if (scenario.equals("pending")) {
        intent.put("code", "PAYMENT_PENDING");
        intent.put("error", "Payment pending confirmation. Do not create another payment.");
      } else if (scenario.equals("declined")) {
        intent.put("code", "PAYMENT_DECLINED");
        intent.put("error", "Payment declined. No debit was made.");
      } else {
        intent.put("code", "PROVIDER_UNAVAILABLE");
        intent.put("error", "Provider unavailable before authorization. No debit was made.");
      }
      intents.put(intentId, intent);
      return stored(intent, state);
    }

    ObjectNode transaction = mapper.createObjectNode();
    transaction.put("id", id);
    transaction.put("reference", "MER-" + id.substring(0, 8).toUpperCase());
    transaction.put("recipientId", recipientId);
    transaction.put("name", recipient.get("name").asText());
    transaction.put("category", recipient.get("category").asText());
    transaction.put("amount", amount);
    transaction.put("date", "2026-09-18");
    transaction.put("provider", provider);
    transaction.put("method", method);
    transaction.put("status", "completed");
    transaction.put("note", note);
    state.put("balance", state.get("balance").asLong() - amount);
    ((ArrayNode) state.get("transactions")).add(transaction);
    intent.set("transaction", transaction.deepCopy());
    intents.put(intentId, intent);

    ObjectNode response = mapper.createObjectNode();
    response.put("ok", true);
    response.set("state", state.deepCopy());
    response.set("transaction", transaction.deepCopy());
    return ResponseEntity.ok(response);
  }

  private ResponseEntity<JsonNode> stored(ObjectNode intent, ObjectNode state) {
    String phase = intent.get("phase").asText();
    if (phase.equals("success")) {
      ObjectNode response = mapper.createObjectNode();
      response.put("ok", true);
      response.set("state", state.deepCopy());
      response.set("transaction", intent.get("transaction").deepCopy());
      return ResponseEntity.ok(response);
    }
    if (phase.equals("pending")) {
      ObjectNode response = mapper.createObjectNode();
      response.put("ok", false);
      response.put("error", intent.get("error").asText());
      response.put("code", "PAYMENT_PENDING");
      response.put("paymentId", intent.get("paymentId").asText());
      return ResponseEntity.status(202).body(response);
    }
    int status = switch (phase) {
      case "declined" -> 422;
      case "unavailable" -> 503;
      default -> 400;
    };
    return error(status, intent.get("code").asText(), intent.get("error").asText());
  }

  private String fingerprint(String recipientId, long amount, String method, String note) {
    ArrayNode parts = mapper.createArrayNode();
    parts.add(recipientId);
    parts.add(amount);
    parts.add(method);
    parts.add(note);
    return parts.toString();
  }

  private ObjectNode recipient(String id) {
    for (JsonNode recipient : fixture.get("recipients")) {
      if (id.equals(recipient.get("id").asText())) return (ObjectNode) recipient;
    }
    return null;
  }

  private ObjectNode stateFor(String room) {
    return states.computeIfAbsent(room, ignored -> (ObjectNode) fixture.get("state").deepCopy());
  }

  private ResponseEntity<JsonNode> roomError(String room) {
    if (room != null && room.matches("[A-Za-z0-9_-]{3,64}")) return null;
    return error(400, "HTTP_400", "Invalid rehearsal session");
  }

  private ResponseEntity<JsonNode> error(int status, String code, String message) {
    ObjectNode body = mapper.createObjectNode();
    body.put("ok", false);
    body.put("error", message);
    body.put("code", code);
    return ResponseEntity.status(status).body(body);
  }
}
