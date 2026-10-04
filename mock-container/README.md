# Local Spring Boot mock container

This is a rehearsal stand-in for the shared Java `/api/v1` contract. It is not the native app and it does not call Adyen, Worldpay, or any other provider.

Amounts are integer GBP pence. Card payments are recorded as Adyen and bank payments as Worldpay. Session state is partitioned by `X-Rehearsal-Session`. Successful replays of an `Idempotency-Key` return the original transaction and the current balance.

```sh
mvn -B -f mock-container/pom.xml -DskipTests package
java -jar mock-container/target/meridian-mock-container.jar
```

`SERVER_PORT` overrides 8080. The image definition is `mock-container/Dockerfile`. A container build was not run in this workspace because Docker was unavailable; the jar is what the journey runners use.
