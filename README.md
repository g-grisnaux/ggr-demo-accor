# Accor BFF observability demo

A public GraphQL BFF (Apollo Server) in front of three downstream REST APIs,
instrumented with Datadog through the DDOT collector, deployed to GKE with
Terraform under service account impersonation.

Built to answer what the Accor BFF team actually asked for: end-to-end tracing
from a GraphQL operation into the faulty REST call, error rates sliced by
*business* error code, per-resolver and per-field latency, and dashboards that
are not maintained by hand in Terraform.

- **[DEMO-SCENARIOS.md](DEMO-SCENARIOS.md)** — the demo script. Start there.
- **[DEMO-DEROULE.md](DEMO-DEROULE.md)** — le déroulé minuté, clic par clic, avec
  ce qu'il y a à dire. En français, c'est le document à garder ouvert pendant la
  démo.
- **[BITS-INVESTIGATION.md](BITS-INVESTIGATION.md)** — prompts for Bits
  Investigation and the ground-truth sheet to grade its answer against.
- **[AGENTS.md](AGENTS.md)** — scaffold conventions and instrumentation notes.

---

## Architecture

```
                                  ┌──────────────────┐
  all-web (React/RUM) ──────────▶ │   graphql-bff    │  Apollo Server, TypeScript-style
                                  │  Node.js 22      │  resolvers → repositories/dataloaders
                                  └────────┬─────────┘  → API clients → DTO mappers
                                           │
                     ┌─────────────────────┼─────────────────────┐
                     ▼                     ▼                     │
           ┌──────────────────┐  ┌──────────────────┐            │
           │ hotel-search-api │  │   booking-api    │            │
           │  Java 21 Spring  │  │  Python 3.12     │            │
           └────────┬─────────┘  └────┬────────┬────┘            │
                    │                 │        │                 │
                    │                 │        ▼                 │
                    │                 │  ┌──────────────────┐    │
                    │                 │  │   payment-api    │    │
                    │                 │  │  Node.js 22      │    │
                    │                 │  └────────┬─────────┘    │
                    ▼                 ▼           ▼              │
                  ┌────────────────────────────────────┐         │
                  │      PostgreSQL 16 (DBM)           │◀────────┘
                  └────────────────────────────────────┘
```

| Service | Stack | Port | Role |
|---|---|---|---|
| `graphql-bff` | Node.js / Apollo Server 5 | 8080 | Single public entry point. Layered exactly like the Accor BFF: resolvers → repositories with dataloaders → API clients → DTO mappers. Owns the business error taxonomy. |
| `hotel-search-api` | Java 21 / Spring Boot 3.4 | 8081 | Hotel search and availability over PostgreSQL. Hosts the latency and DBM scenarios. |
| `booking-api` | Python 3.12 / Flask + gunicorn | 8082 | Booking lifecycle. Calls `payment-api`, giving the trace its third hop. |
| `payment-api` | Node.js 22 / Express | 8083 | Payment authorization. Source of the decline-rate scenario. |
| `all-web` | React 18 / Vite | 80 | Booking journey with Browser RUM, session replay and custom actions. |
| `traffic` | Locust | — | Continuous mixed load across four client platforms and versions. |

**Datadog features exercised:** APM with distributed tracing, Logs correlated
via `dd.trace_id`, Infrastructure, Browser RUM, Database Monitoring
(PostgreSQL), Continuous Profiling, App & API Protection, Feature Flags.

---

## Prerequisites

### 1. Datadog credentials — required, currently unset

`.env` shipped with placeholder values. **The demo emits no telemetry until
these are real**; a local Datadog Agent test returned `API Key invalid`.

Fill in `.env`:

```
DD_API_KEY=<32-hex-char API key>
DD_APP_KEY=<application key>
DD_RUM_APPLICATION_ID=<from RUM application setup>
DD_RUM_CLIENT_TOKEN=<from RUM application setup>
```

Create the RUM application in Datadog under **Digital Experience → Add an
Application → Browser**. Without `DD_RUM_APPLICATION_ID` and
`DD_RUM_CLIENT_TOKEN` the front end logs a warning and RUM stays inert — the
backend half of the demo still works.

### 2. IAM — one role has to be added

The deploy runs entirely under impersonation of
`gael-service-account-demo@datadog-ese-sandbox.iam.gserviceaccount.com`, which
holds `container.admin`, `compute.admin`, `iam.serviceAccountUser` and
`storage.admin`. **None of those grant Artifact Registry access** — verified:
`artifactregistry.locations.list` is denied. Grant it:

```bash
gcloud projects add-iam-policy-binding datadog-ese-sandbox \
  --member="serviceAccount:gael-service-account-demo@datadog-ese-sandbox.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.admin"
```

You also need `roles/iam.serviceAccountTokenCreator` on that service account
for your own user, which you already have — impersonation was verified working.

If you would rather not change IAM, run the deploy with
`REGISTRY_IDENTITY=user` and images are pushed with your own credentials
instead; everything else stays impersonated.

### 3. Tooling

```bash
brew install hashicorp/tap/terraform
gcloud components install gke-gcloud-auth-plugin
```

Already present on this machine: `gcloud` 583, `kubectl` 1.34, `helm` 4.0,
`docker` 29, `docker-compose`. Note that the `docker compose` **plugin** is not
installed — use the standalone `docker-compose` binary if you build by hand.

---

## Deploy

```bash
./scripts/deploy-gke.sh
```

The script refuses to start rather than half-deploy: it checks every tool,
rejects placeholder credentials, verifies impersonation, and only then applies
Terraform. It then builds and pushes all six images, points `kubectl` at the
cluster, creates the secrets (including a freshly generated database password
that never touches the repo), installs the Datadog Agent with the DDOT
collector, and applies the manifests.

Then:

```bash
kubectl port-forward -n ggr-demo-accor svc/frontend 8090:80
open http://localhost:8090
```

### What Terraform creates

A zonal GKE **Standard** cluster in `europe-west9-a` with two `e2-standard-4`
nodes, plus the Artifact Registry repository.

Standard rather than Autopilot on purpose: the Datadog Agent and DDOT collector
need host-level access (kubelet metrics, host ports, process collection) that
Autopilot restricts, and Autopilot would quietly cost the infrastructure half
of the demo. GKE's own logging and monitoring are disabled — the demo does not
use them and they are not free.

State is local by default. A commented GCS backend is in
`terraform/versions.tf`; the service account already holds `storage.admin`, so
switching is an uncomment plus `terraform init -migrate-state`.

### Teardown

```bash
terraform -chdir=terraform destroy
```

---

## Running the demo

See **[DEMO-SCENARIOS.md](DEMO-SCENARIOS.md)**. Scenarios are runtime switches,
not redeploys:

```bash
scripts/scenario.sh list
scripts/scenario.sh latency-on      # DBM plan flip + profiler flame graph
scripts/scenario.sh payment-storm   # anomaly detection on a business error code
scripts/scenario.sh n-plus-one-on   # 25 REST spans instead of 1
scripts/scenario.sh reset
```

---

## Regenerating the manifests

The service manifests are generated, because twelve lines of unified service
tagging, probes and Datadog environment repeated across four services is how a
demo ends up with one service silently missing its `DD_ENV`:

```bash
python3 scripts/render-manifests.py
```

Edit `SERVICES` in that script, not the YAML.

---

## What this demo does not cover

Worth saying out loud before the meeting:

- **Mobile RUM.** The scaffold has no mobile app, so replacing Firebase is an
  argument, not a demo.
- **The real ALL site is UJS/vanilla**, this front is React. The RUM story
  transfers; the framework does not.
- **Not a Hive replacement.** Operation-, resolver- and field-level latency,
  error codes, client versions and deprecated-field usage are all covered by
  APM spans plus the custom metrics in `src/telemetry.js`. Schema registry and
  schema-change tracking are not.
- **`payment-api` is Node, not Java.** The scaffolding CLI assigns frameworks
  to services round-robin with no per-service control; three languages and a
  three-hop chain survive intact.

## Known scaffold fixes applied

The generator produced a few things that could not work, corrected here in case
the CLI is reused:

- Namespace and image names were `demoAccor` — invalid for both Kubernetes
  (RFC 1123 requires lowercase) and Docker repositories. Now `ggr-demo-accor`.
- The PostgreSQL manifest had `imagePullPolicy: Never` on the public
  `postgres:16` image, no credentials, no `shared_preload_libraries`, and never
  mounted its init SQL — so DBM had no query metrics and the schema was never
  created.
- The seed SQL called `CREATE EXTENSION vector`, which does not exist in
  `postgres:16` and aborted the init script.
- Apollo Server 4 and the scaffold's dependency set tripped the supply-chain
  scanner on three advisories with no patched 4.x release; the BFF is on
  Apollo Server 5 with the Express 5 integration.
- `helm/datadog-values.yaml` set `datadog.dbm.enabled`, which is not a key in
  the Datadog chart and was silently ignored. Database Monitoring is switched on
  by the postgres autodiscovery annotation instead.
- The traffic generator targeted a generic CRUD API (`/api/users`,
  `/api/projects`) that does not exist here; it now drives GraphQL operations
  across four client platforms and versions.
