---
name: dd-create-scenarios
description: Create golden paths and failure scenarios for demos, update the traffic generator, and produce DEMO-SCENARIOS.md
tools:
  - terminal
  - file_read
  - file_write
---

# Create Demo Scenarios

Create domain-specific golden paths and failure scenarios that a SE can trigger during a live demo. Update the Locust traffic generator to exercise them. Produce a `DEMO-SCENARIOS.md` reference document.

## When to Use

- Called automatically by `scaffold-demo` (step 7) after domain customization
- Called manually to refresh scenarios after project changes

## Workflow

### Step 1: Discover the project

Read `AGENTS.md` for:
- Stack: which services exist, their ports, the inter-service call graph
- Features: which Datadog features are active
- Frontend: whether a UI exists

Read service source code (controllers/routes) to find:
- Actual endpoint paths (may have been renamed by customize-domain)
- Entity names used in the code
- Magic value patterns for failure triggers (`*-fail-500`, `*-fail-timeout`)

Read `traffic/locustfile.py` to understand existing traffic patterns and task names.

### Step 2: Define the golden path

Document a step-by-step happy-path sequence that demonstrates the full distributed architecture:

1. **API calls in order** — create entities through the chain (e.g., create customer → create order → create item). Each call should hit a different service to produce distributed traces.
2. **Which services are hit** at each step — this is what the SE shows on the Datadog Service Map.
3. **UI steps** if frontend exists — show RUM → backend trace correlation.
4. **What to look at in Datadog** after running the golden path:
   - Service Map (all services connected)
   - A single trace flamegraph (spans across services)
   - Correlated logs (click from trace to logs)

Provide curl commands for each API call.

### Step 3: Define failure scenarios

For each magic value pattern found in the service code, document a scenario:

| Name | Trigger | Endpoint | Expected Behavior | Datadog Signal |
|------|---------|----------|-------------------|----------------|
| Server Error | `<entity>-fail-500` as entity name | POST /api/<entities> | 500 Internal Server Error | Error Tracking: spike in errors, trace with error span |
| Timeout | `<entity>-fail-timeout` as entity name | POST /api/<entities> | 30s hang, then timeout | APM: latency spike, trace shows long span |
| Not Found | Request nonexistent ID | GET /api/<entities>/nonexistent | 404 response | Trace with 404 status |

For each scenario, provide:
- The exact curl command to trigger it
- What the SE should show in Datadog (which page, what to look for)

### Step 4: Update locustfile.py

Adapt `traffic/locustfile.py` to match the project's current domain:

- Rename task method names to reflect domain entities (e.g., `golden_path` stays, but entity names in payloads change)
- Update endpoint paths to match actual routes (e.g., `/api/users` → `/api/customers`)
- Update magic values in failure tasks to match domain prefixes
- Keep weight distribution: golden path ~70%, failure paths ~30%
- Verify the file parses: `python3 -m py_compile traffic/locustfile.py`

### Step 5: Write DEMO-SCENARIOS.md

Create `DEMO-SCENARIOS.md` in the project root with two sections:

**Golden Path** — Step-by-step walkthrough:

```
## Golden Path

### 1. Create a customer
curl -X POST http://localhost:8080/api/customers \
  -H "Content-Type: application/json" \
  -d '{"name": "Demo Customer", "email": "demo@example.com"}'
→ Shows: api-gateway → customer-service trace

### 2. Create an order
...
```

**Failure Scenarios** — Table format:

```
## Failure Scenarios

| Scenario | Command | Expected | Datadog View |
|----------|---------|----------|-------------|
| Server Error | curl -X POST .../api/orders -d '{"name": "order-fail-500"}' | 500 error | Error Tracking → trace with error span |
| Timeout | curl -X POST .../api/orders -d '{"name": "order-fail-timeout"}' | Hangs 30s | APM → latency spike on order-service |
```

## Constraints

- **Read actual code** to discover endpoints — do not assume the default todo domain
- **All failures use magic values already in the service code** — do not create new failure mechanisms
- **Independent of customize-domain** — works whether or not domain was renamed
- **DEMO-SCENARIOS.md is the SE's demo script** — keep it concise and actionable
