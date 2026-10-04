#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${SERVER_PORT:-8080}"
export SERVER_PORT="$PORT"
cd "$ROOT"
mvn -B -f mock-container/pom.xml -DskipTests package
java -jar mock-container/target/meridian-mock-container.jar &
PID=$!
cleanup() { kill "$PID" >/dev/null 2>&1 || true; }
trap cleanup EXIT
for _ in $(seq 1 90); do
  if curl -sf "http://127.0.0.1:${PORT}/api/v1/health" >/dev/null; then
    break
  fi
  sleep 1
done
curl -sf "http://127.0.0.1:${PORT}/api/v1/health" >/dev/null
export MERIDIAN_TEST_API="http://127.0.0.1:${PORT}/api/v1"
export MERIDIAN_REQUIRE_CONTAINER=1
mvn -B -f android/pom.xml -Dtest=ContainerJourneyTest test
if command -v swift >/dev/null 2>&1; then
  (
    cd ios
    swift build --product MeridianContainerChecks
    .build/debug/MeridianContainerChecks
  )
fi
echo "Container journey passed"
