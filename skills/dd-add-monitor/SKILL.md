---
name: dd-add-monitor
description: Generate Terraform for Datadog monitors tailored to a project's services and active features, using real telemetry baselines when available.
tools:
  - terminal
  - file_read
  - file_write
  - ask_user
---

# Add Monitor

Generate `terraform/monitors.tf` with `datadog_monitor` resources for every service in the project. Monitors are scoped to `var.dd_env`, thresholds use real telemetry baselines when Datadog MCP is available, and demo-friendly defaults otherwise. Exports monitor IDs as Terraform outputs for use by `dd-add-slo`.

## When to Use

- Called after the demo stack is running and telemetry is flowing
- Called manually when the SE wants to add alerting to an existing demo
- Called after `dd-check-telemetry` confirms data is reaching Datadog

## Prerequisites

- Project scaffolded with `AGENTS.md`, `docker-compose.yml`, and `.env`
- Terraform CLI available (`terraform version`)
- Datadog MCP server configured and accessible (optional — enriches thresholds; skill proceeds without it)

## Workflow

### Step 1: Ensure Terraform scaffolding

Check whether `terraform/provider.tf` exists.

If it does **not** exist, create the following files:

**terraform/provider.tf:**
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

**terraform/variables.tf:**
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

**terraform/terraform.tfvars.example:**
```hcl
# Copy to terraform.tfvars and populate from your .env file
dd_api_key = ""  # DD_API_KEY from .env
dd_app_key = ""  # DD_APP_KEY from .env
dd_api_url = "https://api.datadoghq.com/"  # adjust for your Datadog site
dd_env     = ""  # DD_ENV from .env
services   = []  # list of service names from docker-compose.yml
```

**terraform/outputs.tf:**
```hcl
# Monitor IDs — populated by dd-add-monitor, consumed by dd-add-slo
```

If `terraform/provider.tf` already exists, skip creation and proceed. This step is idempotent.

### Step 2: Discover the project

Read the following files:

- `AGENTS.md` → service names, active Datadog features (APM, DBM, RUM, apm:profiling, security:code, security:siem), whether a frontend exists
- `docker-compose.yml` → canonical list of application service names (exclude `datadog-agent`, `traffic`, `postgresql`, `redis`, `keycloak`)
- `.env` → `DD_ENV` value (used to scope all queries and Terraform variables)

Build a working model:
- **Services**: list of application service names
- **DD_ENV**: environment tag value
- **Active features**: which of `dbm:postgresql`, `security:code`, `apm:profiling`, `security:siem`, `rum` are enabled
- **Frontend**: whether a frontend service exists (for RUM monitor)

### Step 3: Enrich with real telemetry (soft — proceed with defaults if unavailable)

Attempt to query the Datadog MCP for each service, scoped to `env:<dd_env>`:

- **Error rate** per service: `trace.http.request.errors / trace.http.request.hits` over the last hour
- **p95 latency** per service: `trace.http.request.duration.by.service.95p` over the last hour
- **Request volume** per service: `trace.http.request.hits` over the last hour
- **Log error count** (global): count of `status:error` logs in the last hour

Use these baselines to inform thresholds:
- Error rate threshold = max(observed_p95_error_rate × 2, 0.05) — keeps monitors silent during normal demo traffic
- Latency threshold = max(observed_p95_latency × 1.5, 2.0) — seconds

If Datadog MCP is unavailable or returns no data, log "Datadog MCP unavailable — using demo-friendly defaults" and proceed. Do not stop.

Demo-friendly defaults (used when real telemetry is absent):
- Error rate threshold: 5% (`> 0.05`)
- Latency p95 threshold: 2 seconds (`> 2`)
- Error log spike: 50 errors in 5 minutes

### Step 4: Query Datadog provider schema

Obtain the `datadog_monitor` resource schema to ensure generated HCL uses correct argument names:

1. **Try Terraform MCP**: call `get_provider_details` for the `DataDog/datadog` provider, requesting details for `datadog_monitor`
2. **Fallback**: fetch the Terraform provider docs via `dd-lookup-docs` (llms.txt path: `https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/monitor`)
3. **Last resort**: use training knowledge. Add a comment to `monitors.tf`:
   ```hcl
   # WARNING: provider schema fetched from training data — verify argument names against
   # https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/monitor
   ```

### Step 5: Propose monitors

Based on the discovered services and active features, compose the monitor plan using the following mapping:

| Condition | Monitor name | Type | Query pattern | Threshold (default) |
|-----------|-------------|------|---------------|---------------------|
| Always — per service | `[service] High Error Rate` | `metric alert` | `sum(last_5m):sum:trace.http.request.errors{env:<dd_env>,service:<svc>}.as_rate() / sum:trace.http.request.hits{env:<dd_env>,service:<svc>}.as_rate() > 0.05` | 0.05 |
| Always — per service | `[service] High Latency p95` | `metric alert` | `avg(last_5m):avg:trace.http.request.duration.by.service.95p{env:<dd_env>,service:<svc>} > 2` | 2 |
| Always — global | `[env] Error Log Spike` | `log alert` | `logs("env:<dd_env> status:error").index("*").rollup("count").last("5m") > 50` | 50 |
| `dbm:postgresql` active | `[env] Slow Query` | `metric alert` | `avg(last_5m):avg:postgresql.queries.duration{env:<dd_env>} > 1000` | 1000 ms |
| `dbm:postgresql` active | `[env] Connection Pool Near Limit` | `metric alert` | `avg(last_5m):avg:postgresql.connections{env:<dd_env>} > 80` | 80 |
| `security:code` active | `[env] Security Threat Signal` | `event-v2 alert` | ASM threat signal on `env:<dd_env>` | any |
| `apm:profiling` active | `[env] CPU Anomaly` | `metric alert` | `avg(last_15m):anomalies(avg:runtime.cpu.utilization{env:<dd_env>}, "basic", 2) >= 1` | anomaly |
| `security:siem` active | `[env] Failed Auth Spike` | `log alert` | `logs("env:<dd_env> @source:keycloak @outcome:failure").index("*").rollup("count").last("5m") > 20` | 20 |
| `security:app` active | `[env] Security Threat Signal` | `event-v2 alert` | ASM threat signal on `env:<dd_env>` | any |
| `ai:llmobs` active | `[env] LLM Error Rate` | `metric alert` | LLM error rate on `env:<dd_env>` | 5% |
| `dsm:kafka` active | `[env] Consumer Lag` | `metric alert` | Kafka consumer lag on `env:<dd_env>` | 1000 |
| Frontend (RUM) active | `[env] Frontend Error Rate` | `rum alert` | `rum("env:<dd_env> @type:error").rollup("count").last("5m") > 10` | 10 |

Replace `<dd_env>` and `<svc>` with actual values. When real telemetry baselines are available from Step 3, substitute the computed thresholds.

Present the full monitor list to the user with:
- Monitor name, type, service (or "global"), and proposed threshold
- Note which thresholds come from real telemetry vs. defaults

**Stop here.** Use `ask_user` to present the monitor proposal and wait for explicit user confirmation. Do not write any files until they reply.

### Step 6: Generate `terraform/monitors.tf`

Write `terraform/monitors.tf` with one `datadog_monitor` resource per proposed monitor.

Rules:
- Use `for_each` over `var.services` for per-service monitors (error rate, latency) to avoid duplication
- Scope every query to `var.dd_env` using Terraform string interpolation: `env:${var.dd_env}`
- Set `message` to include the service/monitor name and escalation hint using Terraform template syntax
- Tag every monitor with `managed_by:terraform` and `env:${var.dd_env}`
- Use `require_full_window = false` for demo monitors (data may be sparse)
- Set `notify_no_data = false` unless the monitor is a heartbeat-style check

Example skeleton for a per-service metric alert:

```hcl
resource "datadog_monitor" "high_error_rate" {
  for_each = toset(var.services)

  name    = "[${each.key}] High Error Rate"
  type    = "metric alert"
  message = "High error rate on ${each.key} in env:${var.dd_env}. Investigate recent deployments or upstream dependencies."

  query = "sum(last_5m):sum:trace.http.request.errors{env:${var.dd_env},service:${each.key}}.as_rate() / sum:trace.http.request.hits{env:${var.dd_env},service:${each.key}}.as_rate() > ${var.error_rate_threshold}"

  monitor_thresholds {
    critical = var.error_rate_threshold
  }

  require_full_window = false
  notify_no_data      = false

  tags = [
    "managed_by:terraform",
    "env:${var.dd_env}",
    "service:${each.key}",
  ]
}
```

Add corresponding output blocks to `terraform/outputs.tf` for every monitor resource, exporting IDs for use by `dd-add-slo`:

```hcl
output "monitor_ids_high_error_rate" {
  description = "Monitor IDs for high error rate alerts, keyed by service"
  value       = { for k, v in datadog_monitor.high_error_rate : k => v.id }
}
```

### Step 7: Validate

Run Terraform formatting and validation:

```bash
cd terraform && terraform fmt monitors.tf
cd terraform && terraform init -backend=false
cd terraform && terraform validate
```

If `terraform fmt` produces changes, those are cosmetic — apply them silently.

If `terraform validate` reports errors:
- Read the error message carefully
- Fix the offending argument or block in `monitors.tf`
- Re-run `terraform validate` until it passes
- Do not report success until validation is clean

If `terraform` is not installed, note it in the report and skip this step.

### Step 8: Report

Tell the user:

1. **Scaffolding**: whether `terraform/` files were created or already existed
2. **Telemetry enrichment**: "Used real baselines for [N] services" or "Used demo-friendly defaults (MCP unavailable)"
3. **Monitors generated**: table of monitor name, type, service/scope, and threshold
4. **Validation**: `terraform validate` passed / skipped (terraform not installed)
5. **Next steps**:
   - Populate `terraform/terraform.tfvars` from the example file and `.env`
   - Run `terraform plan` to preview changes
   - Run `terraform apply` to create monitors in Datadog
   - Use `dd-add-slo` to create SLOs backed by these monitors

## Constraints

- **Idempotent scaffolding** — never overwrite `terraform/provider.tf` or `terraform/variables.tf` if they exist
- **Confirmation before writing** — use `ask_user` to present the full monitor proposal and wait for explicit user approval before generating `terraform/monitors.tf`
- **Soft MCP dependency** — Datadog MCP enriches thresholds but is not required; always fall back to demo-friendly defaults
- **Query scoping** — every monitor query must include `env:${var.dd_env}`; never hardcode environment names
- **Tag every monitor** with `managed_by:terraform`
- **Export all monitor IDs** in `terraform/outputs.tf` so `dd-add-slo` can reference them
- **Thresholds are demo-friendly** — lower than production to trigger during demo traffic; document this in a comment at the top of `monitors.tf`
- **Feature-gated monitors** — only generate monitors for active features; check `AGENTS.md` before adding DBM, security, apm:profiling, security:siem, or RUM monitors
