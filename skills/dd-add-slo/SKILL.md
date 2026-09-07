---
name: dd-add-slo
description: Generate Terraform for Datadog SLOs tailored to the project's services and active features, either wrapping existing monitors (monitor-based) or querying APM metrics directly (metric-based).
tools:
  - terminal
  - file_read
  - file_write
  - ask_user
---

# Add SLO

Generate `terraform/slos.tf` with Datadog SLO definitions for every service and active feature in the project. Chooses between monitor-based SLOs (when `terraform/monitors.tf` already exists) and metric-based SLOs (when it doesn't), then validates and reports what was created.

## When to Use

- Called after `dd-add-monitor` to layer SLOs on top of existing monitors
- Called standalone to add metric-based SLOs to a project that has no monitors yet
- Called after new services are added and SLO coverage needs to be extended

## Prerequisites

- Project scaffolded with `AGENTS.md` present
- `.env` populated with `DD_API_KEY`, `DD_APP_KEY`, and `DD_ENV`
- Terraform CLI installed (`terraform version`)

## Workflow

### Step 1: Ensure Terraform scaffolding

Check whether `terraform/provider.tf` exists.

**If it already exists**, skip to Step 2 — do not overwrite existing scaffolding.

**If it does not exist**, create the four foundation files:

**terraform/provider.tf**
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

**terraform/variables.tf**
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

**terraform/terraform.tfvars.example**
```hcl
# Copy to terraform.tfvars and fill in your values.
# These values correspond to the variables in variables.tf.
# Do NOT commit terraform.tfvars — it contains secrets.

dd_api_key = ""  # from .env DD_API_KEY
dd_app_key = ""  # from .env DD_APP_KEY
dd_api_url = "https://api.datadoghq.com/"  # adjust for your Datadog site

dd_env  = ""     # from .env DD_ENV
services = []    # e.g. ["api-gateway", "user-service", "order-service"]
```

**terraform/outputs.tf**
```hcl
# SLO outputs will be added here as slos.tf is extended.
```

### Step 2: Discover project state

Read project files to understand what exists:

- `AGENTS.md` → service names, active Datadog features (RUM, DBM, Profiling, Code Security), whether a frontend service is present
- `.env` → `DD_ENV` value for scoping all metric queries
- `docker-compose.yml` → confirm service names and exclude infrastructure containers (datadog-agent, postgresql, redis, traffic, keycloak)
- `terraform/monitors.tf` → if present, extract monitor resource names (e.g. `datadog_monitor.api_gateway_availability`) to use as SLO sources

Determine mode:
- **Monitor-based**: `terraform/monitors.tf` exists and contains at least one `datadog_monitor` resource → reference those monitors in SLO definitions
- **Metric-based**: no `terraform/monitors.tf` → build SLOs directly from APM metrics

### Step 3: Enrich with real telemetry via Datadog MCP

If the Datadog MCP server is available, query actual availability and latency per service over the past 30 days:

- **Availability**: percentage of 5xx-free requests for `service:<name> env:<dd_env>`
- **Latency**: p99 latency for `service:<name> env:<dd_env>`

Use the results to validate proposed SLO targets:
- If current availability is already above 99.95%, a 99.9% target is safe and realistic — note that to the user
- If current p99 latency regularly exceeds 2s, flag it and suggest a more realistic latency target
- If data shows the service hasn't received traffic yet, note that and use standard demo targets

If MCP is unavailable, proceed with standard demo targets (99.9% availability, 99% latency under 2s) and note the fallback.

### Step 4: Query provider schema for `datadog_service_level_objective`

Obtain the current argument schema before writing any Terraform:

1. Try Terraform MCP: `get_provider_details` for resource `datadog_service_level_objective` from `DataDog/datadog`
2. If unavailable, try `dd-lookup-docs` for the Terraform resource documentation
3. Last resort: use training knowledge and add a comment in the generated file:
   ```hcl
   # Schema sourced from training data — verify against registry.terraform.io/providers/DataDog/datadog
   ```

Pay attention to required vs optional arguments, especially:
- `monitor_ids` (monitor-based) vs `query` block (metric-based)
- `thresholds` block: `target`, `timeframe`, `warning`
- `tags` list

### Step 5: Propose SLOs

Build the SLO list based on services, active features, and mode:

| Condition | SLO | Mode | Target | Timeframe |
|-----------|-----|------|--------|-----------|
| Every service | Availability | monitor-based or metric | 99.9% | 30d |
| Every service | Latency p99 | monitor-based or metric | 99% requests under 2s | 30d |
| DBM feature active (`dbm:postgresql`) | DB Query Performance | metric-based | 99% queries under 1s | 30d |
| RUM feature active + frontend present | Frontend Availability | monitor-based or metric | 99.9% | 30d |

**Monitor-based** SLOs reference existing monitors via Terraform expressions:
```hcl
monitor_ids = [datadog_monitor.<resource_name>.id]
```

**Metric-based** SLOs use APM spans metrics:
- Availability numerator: `sum:trace.web.request.hits{service:<name>,env:<dd_env>,http.status_code:2*}.as_count()`
- Availability denominator: `sum:trace.web.request.hits{service:<name>,env:<dd_env>}.as_count()`
- Latency numerator: `sum:trace.web.request.duration{service:<name>,env:<dd_env>}.as_count()` with `<2s` filter
- Latency denominator: `sum:trace.web.request.hits{service:<name>,env:<dd_env>}.as_count()`

Present the full proposal to the user before writing any files. Include:
- SLO name, type (monitor-based / metric-based), target, timeframe
- Which services are covered
- Which features are covered (DBM, RUM)
- Any target adjustments suggested by real telemetry (Step 3)

**Stop here.** Use `ask_user` to present the SLO proposal and wait for explicit user confirmation. Do not proceed to Step 6 until they reply.

### Step 6: Generate `terraform/slos.tf`

Write the confirmed SLO definitions. One `datadog_service_level_objective` resource per SLO.

Resource naming convention: `<service_slug>_<slo_type>` — e.g. `api_gateway_availability`, `user_service_latency`.

All resources must include:
```hcl
tags = ["managed_by:terraform", "env:${var.dd_env}"]
```

**Monitor-based example:**
```hcl
resource "datadog_service_level_objective" "api_gateway_availability" {
  name        = "API Gateway Availability"
  type        = "monitor"
  description = "99.9% of requests to api-gateway are successful over 30 days"

  monitor_ids = [datadog_monitor.api_gateway_availability.id]

  thresholds {
    timeframe = "30d"
    target    = 99.9
    warning   = 99.95
  }

  tags = ["managed_by:terraform", "env:${var.dd_env}"]
}
```

**Metric-based example:**
```hcl
resource "datadog_service_level_objective" "user_service_availability" {
  name        = "User Service Availability"
  type        = "metric"
  description = "99.9% of requests to user-service return non-5xx responses over 30 days"

  query {
    numerator   = "sum:trace.web.request.hits{service:user-service,env:${var.dd_env},http.status_code:2*}.as_count()"
    denominator = "sum:trace.web.request.hits{service:user-service,env:${var.dd_env}}.as_count()"
  }

  thresholds {
    timeframe = "30d"
    target    = 99.9
    warning   = 99.95
  }

  tags = ["managed_by:terraform", "env:${var.dd_env}"]
}
```

After writing `slos.tf`, append corresponding output blocks to `terraform/outputs.tf`:
```hcl
output "slo_api_gateway_availability_id" {
  value = datadog_service_level_objective.api_gateway_availability.id
}
```

### Step 7: Validate

Run Terraform validation from the `terraform/` directory:

```bash
terraform init -backend=false
terraform validate
```

If `validate` fails:
- Read the error message carefully
- Fix the specific resource or argument that caused the error
- Re-run `terraform validate`
- Do not proceed to Step 8 until validation passes

If `terraform` is not installed, skip validation and note it in the report.

### Step 8: Report

Tell the user:

1. **Scaffolding**: whether `terraform/` files were created or already existed
2. **Mode**: monitor-based (referencing N monitors) or metric-based
3. **SLOs generated**: list each SLO with name, type, target, and timeframe
4. **Telemetry enrichment**: whether real metrics were used to validate targets, or standard demo targets were applied
5. **Validation**: `terraform validate` passed, failed (with error), or skipped (Terraform not installed)
6. **Next steps**:
   ```
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   # Fill in dd_api_key, dd_app_key, dd_env, services
   terraform init
   terraform plan
   terraform apply
   ```

## Constraints

- **Idempotent scaffolding** — never overwrite existing `terraform/provider.tf`, `variables.tf`, or `outputs.tf`
- **Do not hardcode monitor IDs** — always use Terraform expressions (`datadog_monitor.<name>.id`) to maintain the dependency graph
- **Confirm before writing** — use `ask_user` to present the full SLO proposal and wait for user confirmation before generating `slos.tf`
- **Demo-appropriate targets** — use 99.9% availability and 99% latency (under 2s) as defaults; adjust only if real telemetry clearly shows a different baseline
- **30-day windows only** — SLO timeframes are always `30d` for demo consistency
- **Tag every resource** — all SLOs must carry `managed_by:terraform` and `env:${var.dd_env}`
- **Feature-gated SLOs** — only generate DBM and RUM SLOs when those features are active in `AGENTS.md`
- **Read actual project files** — discover service names from `AGENTS.md` and `docker-compose.yml`; do not assume generic names
