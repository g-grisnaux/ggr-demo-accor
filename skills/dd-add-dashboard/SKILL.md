---
name: dd-add-dashboard
description: Generate Terraform for Datadog dashboards tailored to a project's services and active features, enriched with real telemetry data from the Datadog MCP server.
tools:
  - terminal
  - file_read
  - file_write
  - ask_user
---

# Add Dashboard

Generate `terraform/dashboards.tf` with Datadog dashboard definitions scoped to the project's services and active features. Uses real telemetry from the Datadog MCP server to populate widget queries with meaningful data, then writes Terraform using the `datadog_dashboard_json` resource.

## When to Use

- Called after a demo project is scaffolded and running to add dashboards to the Datadog org
- Called when the SE wants a pre-built dashboard tailored to the demo domain
- Called after `dd-customize-domain` to regenerate dashboards for the new domain
- Called after adding a new feature (DBM, RUM, Security) to add feature-specific dashboards

## Prerequisites

- Project scaffolded with `AGENTS.md` present
- `docker-compose.yml` exists with service definitions
- `.env` populated with `DD_API_KEY`, `DD_APP_KEY`, and `DD_ENV`
- Terraform CLI installed (`terraform version`)
- Datadog MCP server configured (optional but strongly recommended)

## Workflow

### Step 1: Ensure Terraform scaffolding

Check whether `terraform/provider.tf` exists.

**If it does not exist**, create the following files:

**`terraform/provider.tf`:**
```hcl
terraform {
  required_providers {
    datadog = {
      source = "DataDog/datadog"
    }
  }
}

provider "datadog" {
  api_key = var.dd_api_key
  app_key = var.dd_app_key
  api_url = var.dd_api_url
}
```

**`terraform/variables.tf`:**
```hcl
variable "dd_api_key" {
  description = "Datadog API key"
  type        = string
  sensitive   = true
}

variable "dd_app_key" {
  description = "Datadog Application key"
  type        = string
  sensitive   = true
}

variable "dd_api_url" {
  description = "Datadog API URL (e.g., https://api.datadoghq.com/ for US1, https://api.us5.datadoghq.com/ for US5)"
  type        = string
  default     = "https://api.datadoghq.com/"
}

variable "dd_env" {
  description = "DD_ENV tag value for scoping queries"
  type        = string
}

variable "services" {
  description = "List of application service names"
  type        = list(string)
}
```

**`terraform/terraform.tfvars.example`:**
```hcl
# Copy this file to terraform.tfvars and populate from your .env
dd_api_key = "YOUR_DD_API_KEY"
dd_app_key = "YOUR_DD_APP_KEY"
dd_api_url = "https://api.datadoghq.com/"
dd_env     = "YOUR_DD_ENV"   # e.g., "my-demo-260331"
services   = ["service-a", "service-b"]  # match DD_SERVICE tags in docker-compose.yml
```

**`terraform/outputs.tf`:**
```hcl
# Outputs will be added as resources are created
```

If `terraform/provider.tf` already exists, skip file creation but confirm its presence before proceeding.

### Step 2: Discover project

Read `AGENTS.md` for:
- Project name (used in dashboard titles for identification in shared orgs)
- Service names and what each service does
- Active Datadog features (APM, Logs, DBM, RUM, security:code, apm:profiling, security:siem)
- Whether a frontend exists

Read `docker-compose.yml` for:
- Application service names (exclude: `datadog-agent`, `traffic`, `postgresql`, `redis`, `keycloak`)
- Confirm service names match `DD_SERVICE` labels

Read `.env` for:
- `DD_ENV` — used to scope all dashboard queries
- `DD_SITE` — used to confirm the correct `dd_api_url` default

### Step 3: Enrich with real telemetry via Datadog MCP

Attempt to query the Datadog MCP server. If MCP is unavailable, note it and proceed with sensible defaults — do not stop.

When MCP is available, query for each discovered service:
- **Request rates**: `sum:trace.request.hits{env:<dd_env>,service:<name>}.as_rate()`
- **Error rates**: `sum:trace.request.errors{env:<dd_env>,service:<name>}.as_rate()`
- **Latency percentiles**: p50, p95, p99 from APM spans
- **Top endpoints**: search recent traces for distinct `resource_name` values
- **Log volume**: log count by service in the last hour
- **Error log patterns**: top error messages by count

Use the real data to:
- Confirm actual service names match what's in Datadog (adjust if there are discrepancies)
- Select appropriate time ranges (e.g., if data is sparse, widen to last 4h)
- Identify which endpoints to highlight in widget titles

If MCP is unavailable, use `env:${var.dd_env}` scoped queries with generic APM metric names and note in a comment that the dashboard was generated without live data enrichment.

### Step 4: Query provider schema for `datadog_dashboard_json`

Try in order:

1. **Terraform MCP** — call `get_provider_details` for the `datadog` provider, look up `datadog_dashboard_json`
2. **Fallback: dd-lookup-docs** — search Datadog docs for `datadog_dashboard_json` Terraform resource
3. **Last resort: training knowledge** — use known schema and add a warning comment:
   ```hcl
   # WARNING: Schema fetched from training data — verify against
   # https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/dashboard_json
   ```

Key schema point: `datadog_dashboard_json` takes a single `dashboard` argument containing the full dashboard definition as a JSON string. This matches the format exported by the Datadog UI (Infrastructure → Dashboards → Export).

### Step 5: Propose dashboards

Based on the discovered services and active features, determine which dashboards to generate using this mapping:

| Condition | Dashboard | Key Widgets |
|-----------|-----------|-------------|
| Always (APM active) | `[<project>] Service Overview` | Request rate, error rate, latency p50/p95/p99 per service, service map |
| Always (Logs active) | `[<project>] Log Analytics` | Log volume by service, error log rate, top error patterns |
| `dbm:postgresql` active | `[<project>] Database Performance` | Query throughput, slow queries, wait events, connections |
| `security:code` active | `[<project>] Application Security` | ASM threat signals, IAST vulnerabilities, attack attempts |
| `apm:profiling` active | `[<project>] Continuous Profiling` | CPU/memory profile top functions per service |
| `security:siem` active | `[<project>] Security Signals` | Auth events, failed logins, suspicious activity |
| `security:app` active | `[<project>] App & API Protection` | ASM threat signals, WAF events, IP blocking |
| `security:workload` active | `[<project>] Workload Protection` | Container vulnerabilities, runtime threats |
| `ai:llmobs` active | `[<project>] LLM Observability` | LLM call latency, token usage, error rate |
| `dsm:kafka` active | `[<project>] Data Streams` | Pipeline latency, consumer lag, throughput |
| `djm:spark` active | `[<project>] Data Jobs (Spark)` | Job duration, stage performance, executor metrics |
| `djm:airflow` active | `[<project>] Data Jobs (Airflow)` | DAG duration, task success rate, scheduler performance |
| Frontend service present (RUM) | `[<project>] Frontend Performance` | Page load time, Core Web Vitals, RUM error rate |

Rules for the proposal:
- Always generate at least Service Overview and Log Analytics (APM and Logs are default Datadog features)
- Dashboard titles include the project name in brackets for easy identification in shared orgs
- Present the list of dashboards and their key widgets to the user for confirmation before writing

Present the proposal like:

```
Dashboards to generate for project "<project-name>":

1. [<project>] Service Overview
   - Timeseries: request rate per service (APM)
   - Timeseries: error rate per service (APM)
   - Timeseries: p50/p95/p99 latency per service (APM)
   - Service Map widget scoped to env:<dd_env>

2. [<project>] Log Analytics
   - Timeseries: log volume by service
   - Timeseries: error log rate
   - Top List: top error patterns

3. [<project>] Database Performance  ← (only if dbm:postgresql active)
   ...

Confirm? [y/n]
```

**Stop here.** Use `ask_user` to present the dashboard proposal and wait for user confirmation. Do not proceed to Step 6 until they reply.

### Step 6: Generate `terraform/dashboards.tf`

Write `terraform/dashboards.tf` with one `datadog_dashboard_json` resource per confirmed dashboard.

Each resource follows this structure:

```hcl
resource "datadog_dashboard_json" "<snake_case_title>" {
  dashboard = jsonencode({
    title       = "[<project>] <Dashboard Title>"
    description = "<one-line description>"
    layout_type = "ordered"
    tags        = ["env:${var.dd_env}", "managed-by:terraform"]

    widgets = [
      # ... widget definitions
    ]
  })
}
```

Widget guidelines:
- Use `timeseries` type for rate/latency metrics with `display_type = "line"`
- Use `toplist` type for ranked lists (top endpoints, top error patterns)
- Use `servicemap` type for the service topology widget in Service Overview
- Use `log_stream` type for recent error logs widget
- Scope **all** metric and log queries to `env:${var.dd_env}`
- For per-service widgets, use `service:<name>` filter or a template variable
- Add a dashboard-level template variable for `env` defaulting to `var.dd_env`

Example timeseries widget (request rate for a single service):
```json
{
  "definition": {
    "type": "timeseries",
    "title": "Request Rate — <service-name>",
    "requests": [
      {
        "q": "sum:trace.request.hits{env:$env,service:<service-name>}.as_rate()",
        "display_type": "line",
        "style": { "palette": "dog_classic" }
      }
    ],
    "yaxis": { "include_zero": true }
  }
}
```

Include a comment block at the top of the file:
```hcl
# dashboards.tf — Generated by dd-add-dashboard
# Dashboards are scoped to env var dd_env.
# To import an existing dashboard: terraform import datadog_dashboard_json.<name> <dashboard_id>
# To export a UI dashboard for editing: Dashboards → gear icon → Export dashboard JSON
```

### Step 7: Validate

Run:

    cd terraform && terraform init -upgrade
    cd terraform && terraform validate

If `terraform init` fails because provider credentials aren't set, that is expected — init only needs registry access. The validate step checks HCL syntax without connecting to Datadog.

If `terraform validate` reports errors:
- Fix syntax errors (mismatched brackets, invalid JSON in `jsonencode`)
- Re-run validate
- Do not proceed to Step 8 until validate passes

If Terraform CLI is not installed, skip validation and note it in the report.

### Step 8: Report

Tell the user:

1. **Scaffolding**: whether `terraform/` files were created or already existed
2. **Dashboards generated**: list each dashboard resource name and title
3. **MCP enrichment**: whether live telemetry was used or defaults were applied
4. **Validation**: `terraform validate` result (passed / skipped / error message)
5. **Next steps**:
   ```
   To apply:
     cp terraform/terraform.tfvars.example terraform/terraform.tfvars
     # Edit terraform.tfvars with your API/APP keys and dd_env
     cd terraform && terraform apply

   To import an existing Datadog dashboard instead of creating a new one:
     terraform import datadog_dashboard_json.<resource_name> <dashboard_id>
   ```

## Constraints

- **Use `datadog_dashboard_json`, not `datadog_dashboard`** — the JSON resource accepts the Datadog API export format and is easier for SEs to maintain
- **All queries scoped to `env:${var.dd_env}`** — never hardcode env tag values
- **Dashboard titles include project name** — required for identification in shared Datadog orgs
- **Never hardcode API keys** — all credentials go through Terraform variables
- **Feature-gated dashboards** — only generate dashboards for active features discovered in `AGENTS.md`
- **Present and confirm before writing** — use `ask_user` to show the dashboard proposal and wait for user confirmation before generating `dashboards.tf`
- **Idempotent scaffolding** — Step 1 must not overwrite existing `terraform/` files
- **Read actual project files** — do not assume service names or features; discover them from `AGENTS.md` and `docker-compose.yml`
