---
name: dd-scaffold-demo
description: Create a Datadog demo project — scaffold infrastructure, build domain-specific microservices, and generate demo scenarios. Use when the user asks to create a demo, scaffold a project, set up a Datadog environment, or build a sample application.
tools:
  - terminal
  - file_read
  - file_write
  - ask_user
---

# Scaffold Demo

Create a Datadog demo project using the `d-scribe` CLI and domain-specific code generation. The CLI produces deterministic infrastructure (Docker, agent, instrumentation). You produce the business logic, guided by instrumentation patterns.

## Tool Mapping (if available)

| Capability | Tool | Fallback |
|------------|------|----------|
| Structured questions | `AskUserQuestion` | Ask as numbered text options, wait for response |
| Progress tracking | `TaskCreate` / `TaskUpdate` | Output checklist as text, update with checkmarks |
| Plan approval | `AskUserQuestion` (single-select: approve/adjust) | Ask as text, wait for response |

If these tools are available, use them for ALL interactive steps below.
Each `<ASK_USER>` block contains the question, options, and type needed to construct a tool call.

## Progress Tracking

At the start of this workflow, create the following tasks.
Mark each as in_progress when starting, completed when done.

1. Confirm domain & context
2. Choose instrumentation mode
3. Choose features
4. Choose app stack
5. Choose deployment target
6. Review architecture proposal
7. Build demo
8. Validate and present summary

## IMPORTANT — What This Skill Does NOT Do

- Do NOT ask about visual design, color schemes, or styling
- Do NOT brainstorm UI concepts or mockups
- Do NOT ask open-ended creative questions beyond what's needed to build the demo
- Do NOT treat this as a frontend design project
- Do NOT generate infrastructure code — the CLI handles that deterministically

This skill runs `d-scribe init demo` to generate pre-instrumented service scaffolds, then YOU write domain-specific code into those scaffolds using instrumentation patterns as reference.

## Prerequisites

- `d-scribe` CLI available via `npx @lgdd/d-scribe`
- Docker and Docker Compose V2 installed
- For K8s targets: minikube (or kind) and kubectl installed
- For AWS targets: Terraform and AWS CLI configured

## Workflow

### Step 1: Discover available options

Run `d-scribe init demo --help`, `d-scribe list deploy`, and `d-scribe list modes` to see all available backends, frontends, features, deploy targets, instrumentation modes, and options. Do NOT hardcode these — always discover dynamically.

### Step 2: Confirm domain

Infer the domain from the user's trigger message.

If the trigger message is too vague to infer a domain (e.g., "create a demo"), ask directly: "What kind of application should this demo simulate?"

<ASK_USER>
Call the `ask_user` tool with a single-select question confirming the inferred domain.

Question: "I'll build the demo around this domain — does this sound right?"
Options:
- [inferred domain, e.g., "Online banking / fintech application"] (Recommended) — "I'll tailor services, scenarios, and failure modes around this domain"
- "Something else" — "I'd like a different domain focus"

Do not proceed to Step 3 until you receive the user's response.
</ASK_USER>

### Step 3: Quick context (optional)

Give the SE one chance to share prospect context. This is optional — skipping uses smart defaults downstream.

<ASK_USER>
Call the `ask_user` tool with a single-select question.

Question: "Any quick context about this prospect? (helps tailor the demo, or skip to move fast)"
Options:
- "Skip — use smart defaults" (Recommended) — "Jump straight to picking features and stack"
- "Let me share some context" — "I'll describe their tech stack, pain points, or priorities"

If the SE chooses to share context, read their free-text input and extract:
- **Tech stack** (if mentioned) → feed into Step 5 stack inference
- **Pain points** (if mentioned) → feed into Step 4 feature inference
- **Goals** (if mentioned) → use for demo scenario flavor in Step 11

If skipped, proceed with defaults in Steps 4 and 5.

Do not proceed to Step 4 until you receive the user's response.
</ASK_USER>

### Step 3.5: Instrumentation mode

Determine the instrumentation path before features and stack — this gates what's available downstream.

<ASK_USER>
Call the `ask_user` tool with a single-select question.

Question: "Does this demo need to showcase OpenTelemetry instrumentation?"
Options:
- "No — standard Datadog instrumentation (Recommended)" — "All Datadog features supported. Default, most battle-tested."
- "Yes — I need to demo OTel" — "Some Datadog features will be unavailable; choose the OTel variant next."

Do not proceed until you receive the user's response.
</ASK_USER>

**If the user chose No:**
- Set `instrumentation = datadog`
- Proceed to Step 3.6.

**If the user chose Yes:**

<ASK_USER>
Call the `ask_user` tool with a single-select question.

Question: "Which OTel approach fits this demo?"
Options:
- "DDOT — maximum Datadog feature compatibility (Recommended if prospect runs Kubernetes)" — "Datadog SDK with OTel-compatible collector pipeline. All Datadog features supported. **Requires Kubernetes — Compose is not available.**"
- "OTel SDK — pure OpenTelemetry stack" — "OpenTelemetry SDK throughout. Limited Datadog feature set — DBM, Profiling, App & API Protection, Workload Protection, DSM, DJM, Feature Flags, and Code Security are unavailable. On Compose, host-level Infra Monitoring is also unavailable (no Datadog Agent)."

Do not proceed until you receive the user's response.
</ASK_USER>

Map the response to the CLI flag and downstream settings:
- DDOT → `instrumentation = ddot`, `deploy = k8s:local:minikube` (fixed — inform user: "DDOT requires Kubernetes. Deploy target set to k8s:local:minikube automatically.")
- OTel SDK → `instrumentation = otel`

Proceed to Step 3.6.

Pass `--instrumentation <instrumentation>` into the final `d-scribe init demo` call.

### Step 3.6: Discover mode-filtered options

Run:

    d-scribe list backends --instrumentation <instrumentation>
    d-scribe list features --instrumentation <instrumentation>

Save both outputs. Use:
- The backends list in Step 5 to constrain stack inference (do not suggest backends absent from this list).
- The features list in Step 4 to populate the multi-select (do not present features absent from this list).

If `instrumentation = otel`, note which feature categories are absent from the returned list and include a brief inline note in the Step 4 question explaining what's excluded and why (e.g. "DBM and DSM aren't available in OTel mode — those features require the Datadog Agent.").

### Step 4: Infer features

If the SE shared prospect context in Step 3, use it to infer which Datadog features to showcase. If skipped, recommend defaults. Map pain points to features:
- "slow MTTR" / "incident response" / "bottlenecks" → `apm:profiling`
- "database performance" / "slow queries" → `dbm:postgresql`
- "MySQL" / "document store" → `dbm:mysql` or `dbm:mongodb`
- "security" / "compliance" / "vulnerabilities" → `security:code`
- "SIEM migration" / "security operations" / "threat detection" → `security:siem`
- "WAF" / "threat detection" / "API protection" → `security:app`
- "container security" / "runtime protection" → `security:workload`
- "static analysis" / "code quality" / "SAST" → `security:sast`
- "AI" / "LLM" / "chatbot" / "generative AI" → `ai:llmobs`
- "data pipeline" / "Spark" / "batch processing" → `djm:spark`
- "workflow orchestration" / "Airflow" / "DAGs" → `djm:airflow`
- "event streaming" / "Kafka" / "message queue" → `dsm:kafka`
- If no pain points were provided, recommend `dbm:postgresql` as the default — it produces the most visually compelling Datadog demo with minimal setup

**Worked examples:**

> Prospect says: "Java shop migrating SIEM tooling, slow incident resolution, no visibility into PostgreSQL performance."
> → Check: `dbm:postgresql` (no DB visibility), `apm:profiling` (slow incident resolution / MTTR)
> → Uncheck: `security:code`, `security:siem`
> → Note in `security:siem` line: "SIEM migration may indicate future Cloud SIEM interest — worth flagging"

> Prospect says: "Python/React on K8s, worried about security compliance."
> → Check: `security:code` (security/compliance concern)
> → Uncheck: `dbm:postgresql`, `apm:profiling`, `security:siem`

Before calling `ask_user`, output a short text message listing the baseline: "**Baseline:** APM with distributed tracing, Log Management with trace correlation, Infrastructure Monitoring [+ RUM if a frontend is likely]."

Then use `ask_user` for the additional features.

<ASK_USER>
Call the `ask_user` tool with a **multi-select** question. Do NOT present the features as text.
**Build the options list exclusively from the features returned by `d-scribe list features --instrumentation <instrumentation>` in Step 3.6.** Do not present features that were not in that list.

Question: "Which additional features should this demo showcase? (Baseline: APM, Logs, Infra, RUM)"
Options (with descriptions that include your reasoning tied to the prospect's context):
- Database Monitoring — PostgreSQL (dbm:postgresql) — [reason tied to prospect context]
- Database Monitoring — MySQL (dbm:mysql) — [reason tied to prospect context]
- Database Monitoring — MongoDB (dbm:mongodb) — [reason tied to prospect context]
- Continuous Profiling (apm:profiling) — [reason tied to prospect context]
- Code Security / IAST (security:code) — [reason tied to prospect context]
- Static Analysis / SAST (security:sast) — [reason tied to prospect context]
- App & API Protection / WAF (security:app) — [reason tied to prospect context]
- Workload Protection (security:workload) — [reason tied to prospect context]
- Cloud SIEM (security:siem) — [reason tied to prospect context]
- LLM Observability (ai:llmobs) — [reason tied to prospect context]
- Data Streams — Kafka (dsm:kafka) — [reason tied to prospect context]
- Data Jobs — Spark (djm:spark) — [reason tied to prospect context]
- Data Jobs — Airflow (djm:airflow) — [reason tied to prospect context]

Mark recommended options with "(Recommended)" in the label.
Do not proceed to Step 5 until you receive the user's response.
</ASK_USER>

### Step 5: Infer app stack

If the SE shared tech stack context in Step 3, use it to infer backends, frontend, and service count. Otherwise, use smart defaults.

**Only suggest backends that appear in the list returned by `d-scribe list backends --instrumentation <instrumentation>` in Step 3.6.** Do not infer or propose backends absent from that list, even if they match the prospect's tech stack — explain the limitation if relevant (e.g. "Go isn't supported in OTel mode yet; using Node.js as the closest alternative.").

Inference guidelines:
- If the prospect runs a specific language/framework, use the matching backend (e.g., Java Spring → `java:spring`)
- Always include at least 2 different backend languages to demonstrate cross-language distributed tracing
- If the prospect has a web app/portal, include a frontend matching their stack (React → `react:vite`, Angular → `angular:esbuild`, Vue → `vue:vite`)
- If the prospect's tech stack is unknown, default to `java:spring` + `python:flask` (best cross-language tracing story) and `react:vite`
- Service count: 3 for simple domains, 4 for moderate, 5+ for complex. This is the count of **backend services only** — the frontend is scaffolded separately via `--frontend` and does NOT count toward this number.

**Worked examples:**

> Prospect runs: "Java Spring monolith, migrating to microservices, React frontend"
> → Backends: `java:spring` (matches their primary stack) + `python:flask` (cross-language tracing)
> → Frontend: `react:vite` (matches their React stack, enables RUM)
> → Services: 4 (moderate complexity for a migration story)

> Prospect runs: "Go + Python data pipeline, no frontend"
> → Backends: `go:gin` (matches Go stack) + `python:flask` (matches Python stack)
> → Frontend: none (backend-only pipeline)
> → Services: 3 (pipeline is inherently linear)

> Unknown tech stack or too vague:
> → Default to `java:spring` + `python:flask` + `react:vite` with 4 services — the most battle-tested combination for cross-language tracing demos.

Based on the domain (Step 2) and any tech stack context from Step 3, infer concrete service names and assign each a backend framework. Also infer whether a frontend is needed.

Output the recommended stack as a text message. Example for a fintech domain:

"Here's what I'd build:

**Backends:** `java:spring` + `python:flask` (cross-language distributed tracing)
**Frontend:** `react:vite` (RUM for browser monitoring)"

Then use `ask_user` with a **multi-select** question listing the proposed services. The user selects the ones they want to keep.

<ASK_USER>
Call the `ask_user` tool with a **multi-select** question.

Question: "Select the services to include in the demo (minimum 2 with a dependency between them):"
Options (all proposed services, each with its framework and role):
- "[service-name] ([framework]) (Recommended)" — "[domain role + dependency info, e.g., 'Routes requests to account-service and transaction-service']"
- (repeat for each proposed service)

Mark all recommended services with "(Recommended)" in the label. Always propose at least 3 services.

**Validation after user responds:**
- If fewer than 2 **backend** services are selected: stop and tell the user "At least 2 backend services with a dependency between them are required for distributed tracing. Please select more backend services." A frontend alone does not satisfy this requirement. Then re-ask.
- If the selected services have no inter-service dependency (e.g., two completely independent services): stop and tell the user which services call which, and ask them to include at least one caller-callee pair.

Do not proceed to Step 6 until you receive a valid selection.
</ASK_USER>

### Step 6: Deploy stack

**If `instrumentation = ddot`:** DDOT requires Kubernetes. Tell the user: "DDOT requires Kubernetes — deploy target is set to `k8s:local:minikube` automatically." Set `deploy = k8s:local:minikube` and skip to Step 7.

**Otherwise (instrumentation = datadog or otel):** Ask how to package the demo. Use the deploy targets discovered in Step 1 via `d-scribe list deploy`.

<ASK_USER>
Call the `ask_user` tool with a single-select question.

Question: "How should we package the demo?"
Options:
- "Docker Compose (Recommended)" — "Simplest setup, runs with `docker compose up`" [If prospect runs K8s, swap recommendation to Kubernetes instead]
- "Kubernetes" — "Runs on Minikube, closer to production K8s environments"

Do not proceed to Step 7 until you receive the user's response.
</ASK_USER>

### Step 7: Deploy location

Based on the deploy stack confirmed in Steps 3.5 or 6, ask where it should run. Show only the relevant subset from `d-scribe list deploy`.

**If `instrumentation = ddot`:** deploy stack is already `k8s` — show only the Kubernetes location options below.

<ASK_USER>
Call the `ask_user` tool with a single-select question. Show only the options relevant to the deploy stack (from Step 6, or k8s if DDOT was chosen in Step 3.5).

If Docker Compose was chosen:
  Question: "Where should the demo run? (Output directory: [. if CWD is empty, or ./suggested-name])"
  Options:
  - "Local (compose:local) (Recommended)" — "Runs on your laptop with Docker"
  - "AWS EC2 (compose:aws:ec2)" — "Provisions an EC2 instance with Terraform"

If Kubernetes was chosen:
  Question: "Where should the Kubernetes cluster run? (Namespace: [default to project dir name]. Output directory: [. if CWD is empty, or ./suggested-name])"
  Options:
  - "Local Minikube (k8s:local:minikube) (Recommended)" — "Runs on your laptop"
  - "AWS EC2 (k8s:aws:ec2)" — "Minikube on an EC2 instance"
  - "AWS EKS (k8s:aws:eks)" — "Managed EKS cluster (coming soon)"

Do not proceed to Step 8 until you receive the user's response.
</ASK_USER>

### Step 8: Review architecture (PLAN GATE)

Based on all confirmed choices from Steps 2-7, present a structured architecture summary. This is a hard gate — no execution begins until the user approves.

#### Summary template

Present the following sections as a text message:

**Domain:** [confirmed domain from Step 2]
**Prospect context:** [context from Step 3 — omit this line if Step 3 was skipped]

**Stack:**
- Backends: [list with frameworks]
- Frontend: [framework or "none"]
- Services: [count]
- Deploy: [target from Steps 6-7]

**Services:**
| Name | Framework | Domain Role |
|------|-----------|-------------|
| [service-name] | [framework] | [role + dependencies] |

**Features:**
- Baseline: APM, Logs, Infra [+ RUM if frontend]
- Configured: [selected features from Step 4 with brief rationale]

**Demo scenarios:**
- Golden path: [description]
- Failure scenarios: [list, each mapped to a feature]

**Tailored to prospect:** [how scenarios map to pain points — only if Step 3 context was gathered]

#### Gate rule

**HARD GATE:** Do NOT run `d-scribe init`, generate code, or modify any files until the user explicitly approves this summary. If the user says "adjust," loop back to the relevant gathering step (2-7).

<ASK_USER>
Output the full architecture summary as a text message using the template above, then immediately call the `ask_user` tool with a single-select question.

Question: "Does this architecture look right?"
Options:
- "Looks good, let's build it (Recommended)" — "Proceed to scaffolding and code generation"
- "Adjust something" — "I want to change services, scenarios, or focus areas"

If the user selects "Adjust something," ask which section they want to change (domain, stack, services, features, deploy, or scenarios) and loop back to the corresponding step.

Do not proceed to Step 9 until you receive the user's confirmation.
</ASK_USER>

### Step 9: Execute the CLI

Map the confirmed choices from Steps 2-8 to CLI arguments and run:

    d-scribe init demo --backend java:spring,python:flask --frontend react:vite --features dbm:postgresql,security:code,apm:profiling --services 4 --deploy k8s --dest .

**IMPORTANT — `--services` is the count of backend services only.** The `--frontend` flag handles the frontend separately. If the user selected 3 backend services and 1 frontend, pass `--services 3 --frontend react:vite` — do NOT add the frontend to the services count.

**IMPORTANT — `--backend` takes deduplicated values only.** List each unique backend spec once, even if multiple services share the same framework. The CLI distributes services across backends using round-robin. Example: 3 services all using `python:flask` → `--backend python:flask --services 3`, NOT `--backend python:flask,python:flask,python:flask --services 3`.

### Step 10: Read the generated context

Read the generated `AGENTS.md` to understand the project structure, available patterns, and features configured.

### Step 11: Build the application

Read `references/patterns/index.md` to see available instrumentation patterns.

For each service, one at a time:
1. Rename the service directory to the domain name you assigned in Step 5 (e.g., `service-1/` → `account-service/`, `service-2/` → `transaction-service/`). Use the exact names from the architecture summary in Step 8 — do not leave any service named `service-{N}`.
2. Create domain entities, endpoints, and business logic appropriate to the service's role
3. For each Datadog feature in scope, load the relevant pattern from `references/patterns/` and adapt it to the domain context:
   - A slow query pattern becomes a slow query on the `transactions` table, not a generic example
   - A SQL injection pattern targets a domain-relevant search endpoint
   - A profiling pattern simulates a domain-relevant computation
4. Ensure inter-service calls use HTTP with proper service naming (DD_SERVICE env var matches the service name)
5. Run the build command (`docker compose build <service-name>` or framework-specific build) to verify compilation
6. Fix any errors before moving to the next service

**Do NOT start the next service until the current one compiles.**

After all services are built, update `docker-compose.yml` (or the K8s manifests in `k8s/` if using a K8s deploy target) to reflect the renamed services.

### Step 12: Create demo scenarios (if available)

Read `skills/dd-create-scenarios/SKILL.md`. If it contains actual instructions, follow them to create golden paths and failure scenarios.

If the skill is a stub (contains "coming in a future release"), skip this step.

### Step 13: Validate the demo

1. Read and follow `skills/dd-check-preflight/SKILL.md` but SKIP the teardown step — leave the stack running.

2. If preflight passed:
   Check if `DD_API_KEY` is set in `.env` (not a placeholder).
   - If yes and Datadog MCP is available: read and follow `skills/dd-check-telemetry/SKILL.md`
   - If not: skip telemetry verification, mention it in the summary

3. If preflight failed: attempt to fix, re-run. After 2 failed attempts, stop and present the errors to the user instead of continuing.

### Step 14: Present the summary

Tell the user:
1. What was created: list each service with its domain role and which Datadog features it demonstrates
2. The demo scenarios created (or note that the skill was skipped)
3. Preflight result: passed or failed (with details)
4. Telemetry verification result: passed, skipped (with reason), or issues found
5. How to launch: refer to the Launch section in AGENTS.md (stack is already running if preflight passed)
6. Available skills they can run manually:
   - `dd-create-runbook` — produce DEMO-RUNBOOK.md with talking points
   - `dd-check-telemetry` — if it was skipped: explain what's needed (configure MCP, set DD_API_KEY in .env)
   - `dd-check-preflight` — to re-run the full validation cycle
   - Datadog-as-Code: `dd-add-monitor` → `dd-add-slo` → `dd-add-dashboard` — generate Terraform for monitors, SLOs, and dashboards
7. Key talking points tailored to the prospect's pain points
8. Estimated AI cost — read `skills/dd-scaffold-demo/references/pricing.md`, then:
   a. Identify your own model name from self-knowledge (e.g., `claude-sonnet-4-6`).
   b. Count what was built in this session: N backend services, frontend yes/no, M additional features selected in Step 4 (exclude baseline APM/Logs/Infra/RUM), whether preflight ran, whether telemetry ran.
   c. Sum token estimates using the Token Unit Estimates table:
      - total = 20K (base) + N × 60K (backends) + 30K if frontend + M × 10K (features) + 20K if preflight ran + 15K if telemetry ran
   d. Split 70/30: input_tokens = total × 0.7, output_tokens = total × 0.3
   e. Match your model name against the Model Pricing Table top-to-bottom (first match wins). Apply the ordering rules listed in the table header.
   f. If matched: cost = (input_tokens × input_price + output_tokens × output_price) / 1,000,000. Print:
      ```
      💰 Estimated AI cost
         Model:    <model-name>
         Tokens:   ~<total>K  (<input>K input / <output>K output)
         Cost:     ~$<amount>
         Note:     Heuristic estimate — check your AI tool's cost display for the actual figure.
      ```
   g. If no match: print:
      ```
      💰 Estimated AI cost
         Model:    <model-name>
         Cost:     unable to estimate (model not in pricing table)
      ```

## Notes

- Step 1 executes automatically
- Steps 2-8 are a progressive conversation — each step (and sub-step) uses `ask_user` and waits for a response before continuing
- Steps 3.5 and 3.6 are part of the instrumentation selection flow — 3.5 has one or two `ask_user` stops (one if Datadog, two if OTel), 3.6 executes automatically
- Step 8 is a formal plan gate — no execution until the user approves the architecture summary
- Steps 9-13 execute automatically after the architecture is confirmed in Step 8
- Step 14 hands control back to the user
- Steps 4-5 use inference: the agent proposes based on prospect context, the user confirms or adjusts
- If the SE gives minimal input, the agent makes reasonable assumptions, states them explicitly, and asks for confirmation
- The prospect context in Step 3 is optional but significantly improves demo relevance
- The CLI handles all infrastructure deterministically — this skill adds AI judgment for domain modeling, code generation, and scenario design
- The CLI auto-populates `.env` from host environment variables ($DD_API_KEY, $DD_SITE, $DD_APP_KEY) — most SEs already have these set on their machine
