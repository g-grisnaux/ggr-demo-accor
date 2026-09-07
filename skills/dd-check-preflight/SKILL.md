---
name: dd-check-preflight
description: Build, deploy, smoke test, and validate a demo project before presenting it. Use after scaffolding or modifying services to ensure everything works end-to-end.
tools:
  - terminal
  - file_read
---

# Preflight Check

Validate that a d-scribe demo project builds, deploys, and responds correctly before the SE presents it. This is a structured verification — not a design or coding skill.

## When to Use

- Called automatically by `dd-scaffold-demo` (step 8) after building all services
- Called manually any time the SE wants to verify the demo still works after changes

## Prerequisites

- Docker and Docker Compose V2 installed
- Project directory contains `docker-compose.yml` and `services/`

## Workflow

### Step 1: Read project structure

Read `docker-compose.yml` to extract:
- All application service names (exclude `datadog-agent`, `traffic`, `postgresql`, `redis`, `keycloak`, `frontend`)
- The first service name and its exposed port (the entry point)
- Whether a frontend exists (port 3000)
- Whether PostgreSQL, Redis, or Keycloak are included

Read `.env` to check:
- `DD_API_KEY` is set (not a placeholder like `your_api_key_here`)
- `DD_ENV` is set

Report what was found before proceeding.

### Step 2: Build all services

Run:

    docker compose build

If build fails:
1. Read the error output carefully
2. Identify which service failed and why
3. Report the error with the service name and the relevant log lines
4. Do NOT attempt to fix — this is a read-only validation skill. Stop and report.

If build succeeds, report success with build time.

### Step 3: Start the stack

Run:

    docker compose up -d

Wait 10 seconds for services to initialize, then check container health:

    docker compose ps

Verify:
- All containers are in `running` state (not `restarting` or `exited`)

### Collector health

Read `.d-scribe.json` to determine the instrumentation mode.

- If `instrumentation == "datadog"`: verify the Datadog Agent container is healthy.
  - Compose: `docker compose ps datadog-agent` → STATE includes `healthy`.
  - K8s: `kubectl get pods -l app=datadog -n {namespace}` → at least one pod Ready.

- If `instrumentation == "otel"` and deploy is Compose: verify the OTel Collector and its OTLP endpoint.
  - `docker compose ps otel-collector` → STATE is `Up` / `running`.
  - `docker compose exec service-1 sh -lc 'curl -sf -o /dev/null -w "%{http_code}" http://otel-collector:4318/v1/traces -X POST -H "Content-Type: application/json" -d "{\"resourceSpans\":[]}"'` → expect 200 or 400 (reachable; 400 OK for empty payload).

- If `instrumentation == "otel"` and deploy is K8s, or `instrumentation == "ddot"`: verify the Datadog Agent pod has DDOT enabled.
  - `kubectl get pods -l app=datadog -n {namespace} -o yaml | grep -i otelCollector` → shows `enabled: true`.

Report `[PASS]` / `[FAIL]` / `[SKIP]` consistently with other checks.

If any container is not running:
1. Check logs: `docker compose logs <service-name> --tail 30`
2. Report the error
3. Do NOT attempt to fix — stop and report

### Step 4: Smoke test — health endpoints

For each application service, hit its `/health` endpoint:

    curl -sf http://localhost:<port>/health

The first service (entry point) is accessible on its exposed port. Other services are only accessible through the Docker network, so test them via the entry point if it proxies, or via `docker compose exec`:

    docker compose exec <service-name> curl -sf http://localhost:<internal-port>/health

Report each service's health check result: PASS or FAIL.

If any health check fails:
1. Check service logs: `docker compose logs <service-name> --tail 30`
2. Report the error with context

### Step 5: Smoke test — inter-service communication

If the project has 2+ services, verify distributed tracing works by making a request that crosses service boundaries. Read the service code or `AGENTS.md` to find an endpoint that calls another service.

If no cross-service endpoint exists yet (services are still scaffolds), skip this step and note it.

If a cross-service endpoint exists:

    curl -sf http://localhost:<entry-port>/<cross-service-endpoint>

Report: PASS if 2xx response, FAIL with status code and response body otherwise.

### Step 6: Smoke test — traffic generator

Check if the Locust container is running:

    docker compose ps traffic

If running, verify it's generating load:

    docker compose logs traffic --tail 10

Look for request log lines. Report: PASS if requests are flowing, FAIL if errors or no output.

### Step 7: Validate .env configuration

Check the `.env` file for common issues:

- `DD_API_KEY` is not a placeholder → if placeholder, WARN (telemetry won't reach Datadog)
- `DD_ENV` follows the `{project}-{YYMMDD}` convention → if not, WARN
- If frontend exists: `DD_RUM_APPLICATION_ID` and `DD_RUM_CLIENT_TOKEN` are not placeholders → if placeholders, WARN (RUM won't work)

Report each as OK or WARN with what to fix.

### Step 8: Report summary

Present a structured checklist:

    ## Preflight Results

    ### Build
    [PASS] All services built successfully (Xs)

    ### Containers
    [PASS] service-1 — running
    [PASS] service-2 — running
    [PASS] datadog-agent — healthy
    [PASS] traffic — running

    ### Health checks
    [PASS] service-1 /health — 200 OK
    [PASS] service-2 /health — 200 OK

    ### Inter-service
    [PASS] service-1 → service-2 — 200 OK
    (or [SKIP] No cross-service endpoints yet)

    ### Traffic
    [PASS] Locust generating requests

    ### Configuration
    [OK] DD_API_KEY set
    [WARN] DD_RUM_APPLICATION_ID is a placeholder — RUM won't send data

    ---
    **Result: X/Y checks passed, Z warnings**

### Step 9: Teardown (optional)

If called with teardown requested (or called manually outside scaffold-demo):

    docker compose down

If called from scaffold-demo step 8: **SKIP teardown** — leave the stack running.

## Constraints

- **Read-only** — never modify source code, docker-compose, or .env
- **Report, don't fix** — if something fails, report what failed and why, don't attempt repairs
- **Idempotent** — can be run repeatedly
- **Fast** — total runtime should be under 2 minutes for a healthy stack
