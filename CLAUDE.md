@AGENTS.md

## Instrumentation mode: `ddot`

This project uses the Datadog SDK with the DDOT Collector. Custom spans in generated business logic may use either the DD tracer API or the OTel API — both flow through the DDOT pipeline.
