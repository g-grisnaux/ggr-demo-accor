---
name: dd-customize-domain
description: >
  Adapt an existing demo to a different business domain
  or prospect context. Use when reusing a demo for a
  new prospect in a different industry.
tools: [terminal, file_read, file_write, ask_user]
---

# Customize Domain

Adapt an existing d-scribe demo project to a different business domain or prospect context. Use this when reusing a demo for a new prospect in a different industry.

## When to Use

- When an SE wants to repurpose an existing demo for a different prospect
- When changing the business domain of a previously scaffolded project

## Workflow

### Step 1: Discover current state

Ask the user:
1. What is the new domain/industry?
2. What pain points should the demo address?

### Step 2: Read project context

Read `AGENTS.md` to understand:
- Current service architecture and backends
- Active Datadog features
- Available instrumentation patterns in `references/patterns/`

### Step 3: Propose domain changes

Present a concrete proposal:
- Renamed services (e.g., `account-service` → `patient-service`)
- Modified entities and endpoints
- Adjusted demo scenarios for the new domain
- Which instrumentation patterns stay relevant

**Stop here.** Use `ask_user` to present the proposal and wait for user confirmation. Do not continue until they reply.

### Step 4: Apply changes service by service

For each service:
1. Rename the directory
2. Modify entities, endpoints, and business logic
3. Adapt instrumentation patterns to the new domain context
4. Verify compilation (`docker compose build <service>`)
5. Fix errors before moving to the next service

### Step 5: Update infrastructure

- Update `docker-compose.yml` (service names, DD_SERVICE, build contexts, env vars)
- Update Locust scenarios in `traffic/locustfile.py`
- Update `AGENTS.md` and `README.md`

## Constraints

- **Keep Datadog instrumentation intact** — DD_SERVICE must match service names
- **Present mapping for confirmation** before making changes
- **Verify compilation** after each service change

## Your Job

1. Read the CURRENT content of both files first
2. Replace each with the EXACT content above (be careful with the YAML frontmatter — use --- delimiters)
3. Do NOT commit — I'll handle it
