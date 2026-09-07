---
name: dd-create-runbook
description: Generate DEMO-RUNBOOK.md with step-by-step talking points, Datadog UI navigation, and audience-tailored messaging for presenting a demo to a prospect.
tools:
  - file_read
  - file_write
---

# Generate Runbook

Produce a `DEMO-RUNBOOK.md` that guides a Datadog SE through a live demo presentation. The runbook combines the technical demo scenarios with narrative talking points, Datadog UI navigation steps, and prospect-tailored messaging.

## When to Use

- Called manually after the demo is built and validated
- Called when the SE wants to prepare for a specific prospect meeting
- Called after `dd-customize-domain` to update talking points for a new domain

## Prerequisites

- Project scaffolded and built (services exist with domain-specific code)
- `AGENTS.md` exists with the project architecture
- `DEMO-SCENARIOS.md` exists (or demo scenarios can be inferred from code)

## Workflow

### Step 1: Gather context

Read project files:
- `AGENTS.md` → service architecture, active features, baseline instrumentation
- `DEMO-SCENARIOS.md` → golden path and failure scenarios (if exists)
- `docker-compose.yml` → service names, ports, dependencies
- `.env` → DD_ENV value (used in Datadog queries)

Read service code (briefly) to understand:
- The business domain and entity names
- Key endpoints and their purpose

Ask the user (optional — proceed without if not provided):
- **Prospect name/company**: for personalizing the runbook header
- **Prospect pain points**: for tailoring which scenarios to emphasize
- **Time budget**: 15min, 30min, or 60min — determines depth of coverage
- **Audience**: technical (engineers), business (VPs), or mixed

If the user doesn't provide this, generate a generic runbook and note that it can be personalized.

### Step 2: Structure the runbook

The runbook follows this structure:

```markdown
# Demo Runbook — [Domain] Demo

**Prospect:** [name or "Generic"]
**Duration:** [15/30/60 min]
**Environment:** DD_ENV=`<dd_env>`
**Datadog site:** [from .env]

## Pre-Demo Checklist

- [ ] Stack is running (`docker compose ps` — all services up)
- [ ] Traffic generator is active (`docker compose logs traffic --tail 5`)
- [ ] Datadog org is accessible (login verified)
- [ ] Browser tabs open: Service Catalog, APM Traces, Logs

## Act 1: The Happy Path ([X] min)

### Talking point
[What to say to the prospect — frame the value]

### Show
1. **Service Catalog** → Navigate to [dd_env] environment
   - Point out: all [N] services auto-discovered, no manual config
   - [If migrating from X]: "Unlike [X], this happened automatically"
2. **Service Map** → Show the topology
   - Point out: request flow between services, latency on edges
3. **Live trace** → Click any trace on [entry-service]
   - Show: flamegraph spanning [service-1] → [service-2]
   - Show: correlated logs (click "Logs" tab on the trace)
   - [Talking point about MTTR reduction]

### Do (optional live demo)
```bash
curl -X POST http://localhost:8080/api/<entities> \
  -H "Content-Type: application/json" \
  -d '{"name": "Demo Entity"}'
```
→ Refresh trace view to show the new trace

## Act 2: When Things Go Wrong ([X] min)

### Scenario: [Failure name]
**Talking point:** [What to say — frame the pain this solves]

**Trigger:**
```bash
curl -X POST http://localhost:8080/api/<entities> \
  -H "Content-Type: application/json" \
  -d '{"name": "<entity>-fail-500"}'
```

**Show in Datadog:**
1. **Error Tracking** → new error appears within seconds
2. **APM → Traces** → filter by status:error
   - Show: error span with stack trace
   - Show: which service caused the error
3. **Logs** → correlated error log with trace_id
   - [Talking point: "From alert to root cause in 3 clicks"]

### Scenario: [Next failure...]
...

## Act 3: Deep Dives ([X] min, pick based on audience)

### Database Monitoring (if active)
**Talking point:** [Frame the value for this prospect]
**Show:**
1. DBM → Query Metrics → filter by env:[dd_env]
2. Point out: slow queries, execution plans, wait events
3. Click into a slow query → show explain plan

### Code Security (if active)
...

### Continuous Profiling (if active)
...

## Closing

### Key takeaways
- [3 bullet points tailored to prospect pain points]

### Next steps
- "Want to try this on your own code? We can set up a POC in [timeframe]"
- Link to relevant docs or resources

## Appendix: Quick Commands

| Action | Command |
|--------|---------|
| Start stack | `docker compose up -d` |
| Stop stack | `docker compose down` |
| View logs | `docker compose logs -f <service>` |
| Restart traffic | `docker compose restart traffic` |
| Scale traffic | `LOCUST_USERS=20 docker compose up -d traffic` |
```

### Step 3: Populate the runbook

For each act:

**Act 1 (Happy Path):**
- Use the golden path from DEMO-SCENARIOS.md or infer from service code
- Map each step to a specific Datadog UI page and what to look for
- Include exact navigation: sidebar → page → filter by env
- Add talking points that connect Datadog capabilities to prospect pain points

**Act 2 (Failures):**
- Use failure scenarios from DEMO-SCENARIOS.md or infer from magic values in code
- For each failure: exact curl command, what to show in Datadog, talking point
- Prioritize scenarios that match active features (DBM, Security, Profiling)
- Order by impact — start with the most impressive demo moment

**Act 3 (Deep Dives):**
- One section per active Datadog feature
- Include feature-specific navigation and what to point out
- These are optional during the demo — the SE picks based on audience interest

**Talking points:**
- If prospect pain points were provided, tailor every talking point
- If not, use generic value propositions:
  - "Auto-instrumented — no code changes needed"
  - "From alert to root cause in 3 clicks"
  - "Full-stack visibility — traces, logs, metrics, all correlated"

### Step 4: Write the file

Write `DEMO-RUNBOOK.md` to the project root.

### Step 5: Report

Tell the user:
1. Runbook created at `DEMO-RUNBOOK.md`
2. Structure: [N] acts covering [list of scenarios]
3. Estimated demo time: [X] min for full runthrough, [Y] min for highlights only
4. If prospect context was provided: key personalization points included
5. Suggest: "Review the talking points and adjust for your presentation style"

## Constraints

- **Read actual code** to discover endpoints and entities — don't use generic placeholders
- **Datadog navigation must be accurate** — use real page names (Service Catalog, APM Traces, Error Tracking, etc.)
- **Talking points are suggestions** — the SE will adapt them to their style
- **Keep it actionable** — every section has a "Show" (what to click) and optionally a "Do" (curl command)
- **Feature-gated content** — only include deep dives for features that are active in the project
- **Time-aware** — if the user specified a duration, pace the acts accordingly. Default: 30 min
