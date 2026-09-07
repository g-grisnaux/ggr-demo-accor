---
name: dd-generate-traffic
description: Configure the Locust traffic generator with domain-specific scenarios that exercise all services, demo golden paths, and trigger failure modes for Datadog visibility.
tools:
  - terminal
  - file_read
  - file_write
  - ask_user
---

# Generate Traffic

Adapt the Locust traffic generator (`traffic/locustfile.py`) to produce realistic, domain-specific traffic that exercises the full service architecture and triggers Datadog-visible behaviors.

## When to Use

- Called after `dd-create-scenarios` to implement the scenarios as automated traffic
- Called manually when the SE wants to refresh or customize traffic patterns
- Called after `dd-customize-domain` when services and endpoints have been renamed

## Prerequisites

- Project scaffolded with services built and running (or at least code is finalized)
- `traffic/locustfile.py` exists (included by default via d-scribe)
- `traffic/scenario-templates/` contains reusable patterns

## Workflow

### Step 1: Discover the project

Read `AGENTS.md` for:
- Service names, ports, and backends
- Active Datadog features
- Whether a frontend exists

Read service source code (controllers/routes) to find:
- Actual endpoint paths (e.g., `/api/accounts`, `/api/transactions`)
- Entity field names and required payloads (what JSON body each POST expects)
- Magic value patterns for failure triggers (`*-fail-500`, `*-fail-timeout`)
- Any feature-specific endpoints (search for SQL injection, SSRF fetch-url, aggregation)

Read `DEMO-SCENARIOS.md` if it exists — use the golden path and failure scenarios as the basis for traffic tasks.

### Step 2: Design traffic tasks

Map the discovered endpoints to Locust task methods with these weight distributions:

| Task | Weight | Purpose | Datadog signal |
|------|--------|---------|----------------|
| `golden_path` | 70 | Full CRUD cycle through multiple services | Distributed traces, Service Map |
| `error_500` | 5 | Trigger 500 via magic value | Error Tracking |
| `slow_request` | 5 | Trigger timeout via magic value | APM latency spike |
| `not_found` | 10 | Hit nonexistent resource | 404 traces |
| `search_injection` | 5 | SQL injection attempt (if security:code active) | Code Security findings |
| `ssrf_attempt` | 5 | SSRF attempt (if security:code active) | Code Security findings |
| `kafka_produce` | 5 | Produce messages to Kafka (if dsm:kafka active) | DSM pipeline visibility |
| `llm_chat` | 5 | Send chat requests to LLM endpoint (if ai:llmobs active) | LLM Observability traces |

Omit tasks for features that aren't active. Adjust weights so they sum to 100.

**Stop here.** Use `ask_user` to present the task design and wait for user confirmation. Do not write any files until they reply.

### Step 3: Write the locustfile

Replace `traffic/locustfile.py` with a domain-specific version:

```python
import os
from locust import HttpUser, task, between

class DemoUser(HttpUser):
    wait_time = between(1, 3)

    @task(70)
    def golden_path(self):
        """Full CRUD cycle exercising distributed traces"""
        # Step 1: Create entity through first service
        resp = self.client.post("/api/<entities>", json={<domain fields>})
        if resp.status_code not in (200, 201):
            return
        entity_id = resp.json().get("id")

        # Step 2: Create related entity through second service
        ...

        # Step 3: Read operations
        self.client.get("/api/<entities>")
        ...

    @task(5)
    def error_500(self):
        """Trigger 500 error via magic value"""
        self.client.post("/api/<entities>", json={"name": "<entity>-fail-500"})

    # ... additional tasks per design
```

Rules:
- Use actual endpoint paths discovered in Step 1
- Use actual entity field names from the service code
- Golden path should hit at least 2 different services to produce distributed traces
- Magic values must match what the service code expects
- All requests go through the entry point (first service, port 8080 by default)
- Keep `wait_time = between(1, 3)` for realistic pacing

### Step 4: Validate the locustfile

Verify the Python file parses:

    python3 -m py_compile traffic/locustfile.py

If syntax errors, fix them and re-validate.

### Step 5: Test the traffic (if stack is running)

If the demo stack is already running (`docker compose ps` shows services up):

    docker compose restart traffic

Wait 10 seconds, then check logs:

    docker compose logs traffic --tail 20

Verify:
- Requests are being sent
- Golden path requests succeed (2xx responses)
- Failure tasks produce expected error codes (500, timeout)

If the stack isn't running, skip this step.

### Step 6: Report

Tell the user:
1. What traffic tasks were configured (name, weight, purpose)
2. Which endpoints and magic values are being exercised
3. Whether validation passed
4. How to start/stop traffic:
   - Start: `docker compose up -d traffic`
   - Stop: `docker compose stop traffic`
   - Logs: `docker compose logs -f traffic`
   - Scale: `LOCUST_USERS=10 docker compose up -d traffic`

## Constraints

- **Read actual code** to discover endpoints — do not assume default paths
- **All failures use magic values already in the service code** — do not create new failure mechanisms
- **Golden path must cross service boundaries** — single-service traffic doesn't demonstrate distributed tracing
- **Keep it simple** — 5-7 tasks max. The SE needs predictable traffic, not a stress test
- **Locustfile must parse** — always validate with `py_compile` before reporting success
