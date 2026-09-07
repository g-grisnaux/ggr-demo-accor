---
name: dd-check-telemetry
description: Verify Datadog telemetry is flowing correctly using MCP tools
tools:
  - file_read
---

# Verify Telemetry

Confirm that a running demo stack is sending telemetry to Datadog. Uses the Datadog MCP server — no fallback.

## Instrumentation-mode differences

Read `.d-scribe.json` for the `instrumentation` field. When OTel mode is in use, service identity is emitted via OpenTelemetry resource attributes instead of Datadog tracer tags:

| Concept | `datadog` / `ddot` | `otel` |
|---------|-------------------|--------|
| Service name | `service:<name>` | `service.name:<name>` |
| Environment | `env:<env>` | `deployment.environment:<env>` |
| Version | `version:<v>` | `service.version:<v>` |

When querying the Datadog API for APM spans or LLM Obs traces, use the appropriate tag key for the project's mode. The Datadog intake normalizes both, but pipelines that filter on `service:` will miss OTel-emitted spans unless they also filter on `service.name:`.

## Prerequisites

- Demo stack running (`docker compose up -d`)
- Datadog MCP server configured and accessible
- `.env` populated with valid `DD_API_KEY` and `DD_SITE`

## Workflow

### Step 1: Check MCP availability

Attempt to list services using the Datadog MCP tools. If MCP tools are not available, stop and inform the user:

```
Datadog MCP server is required for telemetry verification.
Setup: https://github.com/DataDog/datadog-mcp-server
```

Do not proceed without MCP — partial checks would give false confidence.

### Step 2: Read project config

Extract from project files:
- `docker-compose.yml` → list of application service names (exclude datadog-agent, traffic, postgresql, redis, keycloak)
- `.env` → `DD_ENV` value (used to scope all queries)
- `AGENTS.md` → active features (check for mentions of "Database Monitoring", "RUM", "Profiling")
- Note whether a frontend service exists

### Step 3: Check service registration

For each application service, query the Datadog service catalog via MCP.

Report: service found with correct `env` tag, or FAIL with diagnostic hint.

### Step 4: Check logs

For each service, search recent logs (last 15 minutes) via MCP. Build the query filter based on `.d-scribe.json` `instrumentation`:
  - datadog|ddot → `service:<svc> env:<dd_env>`
  - otel → `service.name:<svc> deployment.environment:<dd_env>`

Verify:
- Logs exist (count > 0)
- At least one log contains `dd.trace_id` (trace-log correlation is working)

Report: log count + correlation status, or FAIL with diagnostic hint.

### Step 5: Check traces

Search recent traces/spans via MCP. Build the query filter based on `.d-scribe.json` `instrumentation`:
  - datadog|ddot → `service:<svc>`
  - otel → `service.name:<svc>`

Verify:
- Spans exist for each service
- At least one trace contains spans from 2+ different services (distributed tracing works)

Report: trace count + multi-service trace found, or FAIL with diagnostic hint.

### Step 6: Check correlation

Perform cross-signal verification:

- **Log-to-trace**: Pick a trace_id from a log entry, fetch that trace via MCP, confirm it exists
- **Trace-to-log**: Pick a trace_id from a span, search logs for that trace_id, confirm correlated logs exist
- **RUM-to-backend** (if frontend active): Search RUM events via MCP, check they carry backend trace_ids
- **DBM** (if Database Monitoring active): Search for database query spans with DBM metadata

Report each check as PASS or FAIL with diagnostic hint.

### Step 7: Report

Present a structured checklist grouping all results:

```
Service Registration
  [PASS] api-gateway (env: my-demo-260331)
  [PASS] user-service
  ...

Logs
  [PASS] api-gateway — 142 logs, trace correlation OK
  ...

Traces
  [PASS] Distributed trace found: api-gateway → user-service → project-service

Correlation
  [PASS] Log-to-trace roundtrip
  [PASS] Trace-to-log roundtrip
  ...
```

For each FAIL, include the diagnostic hint from `references/diagnostic-hints.md`.

End with a summary: "X/Y checks passed. [All clear / N issues to fix]"

## Constraints

- **Readonly** — never modify the project, docker-compose, or Datadog configuration
- **MCP-only** — use Datadog MCP tools exclusively
- **Stop cleanly** if MCP is unavailable
- **Idempotent** — can be run repeatedly as the SE fixes issues
