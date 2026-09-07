---
name: dd-lookup-docs
description: >
  Look up current Datadog documentation via the official LLM-optimized index at
  docs.datadoghq.com/llms.txt. Use this skill whenever you need accurate, up-to-date
  Datadog configuration steps, feature details, API references, integration setup,
  or troubleshooting guidance — even if you think you already know the answer.
  Datadog docs change frequently and your training data is likely stale.
  Trigger on any Datadog-related question: agent install, log pipelines, APM setup,
  DBM, monitors, dashboards, SLOs, integrations, RBAC, cloud cost, synthetics,
  LLM observability, etc. Also trigger when another dd- prefixed skill needs
  to reference official documentation.
tools:
  - web_fetch
---

# Datadog Documentation Lookup

Look up current Datadog documentation using the official LLM-optimized index.

## When to Use

- Any time you need Datadog-specific configuration, setup, or feature details.
- When another dd- skill references this one for version-sensitive documentation.
- **Always prefer this over training data** — Datadog docs change frequently.

## Procedure

### Quick path — guess the URL first

Datadog docs follow a predictable URL structure. If you can guess the path, skip the index and fetch directly:

```
https://docs.datadoghq.com/<product>/<subtopic>.md
```

Common patterns:

| Topic | URL pattern |
|-------|-------------|
| Product overview | `/<product>.md` → `logs.md`, `tracing.md`, `database_monitoring.md` |
| Sub-feature | `/<product>/<feature>.md` → `logs/log_configuration/pipelines.md` |
| Setup guide | `/<product>/setup_<engine>/<variant>.md` → `database_monitoring/setup_mysql/rds.md` |
| Integration | `/integrations/<name>.md` → `integrations/amazon_web_services.md` |
| API endpoint | `/api/latest/<resource>.md` → `api/latest/logs-pipelines.md` |

If the guessed URL returns a valid page, you're done. If it 404s or doesn't match, fall through to Step 1.

### Step 1 — Fetch the documentation index

Fetch the plain-text index:

```
https://docs.datadoghq.com/llms.txt
```

This file has two sections:

1. **Introductory overview** — a short description of Datadog and its major product areas, with links.
2. **`# Docs Pages` listing** — one entry per line in the format:

```
- [Page Title](https://docs.datadoghq.com/<path>.md): Short description
```

> **Important:** The URLs in the index **already end in `.md`**. You can fetch them directly — do not append `.md` again.

### Step 2 — Find relevant entries

Search the index for keywords related to your topic. Use multiple keyword variants to cast a wide net. For example, to find Database Monitoring docs, search for: `database_monitoring`, `dbm`, `postgres`, `mysql`, `setup_postgres`.

Each matching line gives you:
- A human-readable **title**
- A **direct `.md` URL** you can fetch
- A brief **description** of the page content

Pick the entries whose title and description best match your question. If multiple entries look relevant (e.g. a product overview page plus a specific setup page), fetch the most specific one first.

### Step 3 — Fetch the documentation page

Fetch the `.md` URL from the index entry. The response is clean Markdown suitable for reading directly.

Example — if the index contains:

```
- [Database Monitoring](https://docs.datadoghq.com/database_monitoring.md): Learn about Database Monitoring and get started
```

Fetch `https://docs.datadoghq.com/database_monitoring.md`.

#### Following links within a doc page

Documentation pages often link to **sub-pages using regular (non-.md) URLs**, and those URLs frequently have a **trailing slash**:

```
https://docs.datadoghq.com/logs/log_configuration/
https://docs.datadoghq.com/database_monitoring/setup_postgres/selfhosted
```

To convert these to Markdown URLs, apply two steps in order:

1. **Strip any trailing slash** — `log_configuration/` → `log_configuration`
2. **Append `.md`** — `log_configuration` → `log_configuration.md`

Correct result:
```
https://docs.datadoghq.com/logs/log_configuration.md
https://docs.datadoghq.com/database_monitoring/setup_postgres/selfhosted.md
```

> **Warning:** Skipping step 1 produces `log_configuration/.md`, which will fail. Always strip the trailing slash first.

#### Detecting a failed fetch

If a guessed or constructed URL is wrong, you'll typically get:
- An HTTP 404 error
- An HTML page instead of Markdown (look for `<!DOCTYPE` or `<html>` at the start)
- A redirect to the Datadog docs search page

If any of these happen, fall back to searching the `llms.txt` index or use web search as described in Step 4.

### Step 4 — Fallback

If `llms.txt` is unreachable or the topic doesn't appear in the index:

1. Try constructing a URL directly: `https://docs.datadoghq.com/<topic>.md`
   (e.g. `https://docs.datadoghq.com/tracing.md`)
2. For API-specific questions, try: `https://docs.datadoghq.com/api/latest.md`

## Tips

- **The index is very large** (~200+ entries). It will often be truncated by your HTTP tool. If your topic keywords aren't found in the visible portion, try fetching with a higher token limit, or use the Quick Path approach to guess the URL directly.
- **Expect 2–3 hops** for specific topics. Overview pages rarely have the details you need — they link to sub-pages that do. Budget for following 1–2 in-page links.
- **Prefer the most specific page.** A setup guide for "MySQL on RDS" is far more useful than the generic "Database Monitoring" overview.
- **In-page links often have trailing slashes** — you must strip the slash *before* appending `.md`. See "Following links within a doc page" for the exact two-step rule. Index URLs already end in `.md` — don't double-append.
- **The `integrations.md` page is a JSON catalog**, not a readable listing. Don't fetch it to browse integrations. Instead, guess the URL directly: `integrations/<name>.md` (e.g. `integrations/postgres.md`, `integrations/amazon_web_services.md`). Integration names use lowercase with underscores or hyphens.
- **The Markdown output uses custom directives** like `{% callout %}`, `{% tab %}`, `{% image %}`, and `{% alert %}`. These are readable enough to extract information from; don't be confused by them.
- **If your HTTP tool restricts URLs** (e.g. only allows previously-seen URLs), use a web search for `site:docs.datadoghq.com <topic>` as a fallback to discover the right page URL, then fetch its `.md` variant.
