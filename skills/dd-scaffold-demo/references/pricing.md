# AI Cost Reference

Used by Step 14 of `dd-scaffold-demo` to estimate session cost.
Pricing as of 2026-04-30 — update this date and rates when providers reprice.

## Token Unit Estimates

| Component | Estimated tokens |
|-----------|-----------------|
| Base overhead (CLI run, AGENTS.md read, patterns index) | 20K |
| Per backend service (template read + code gen + build) | 60K |
| Frontend (RUM setup + code gen) | 30K |
| Per additional feature pattern (read + apply) | 10K |
| Preflight check | 20K |
| Telemetry check | 15K |

## Model Pricing Table

Match top-to-bottom — first matching pattern wins.

Ordering rules:
- `gpt-*-pro*` and `gpt-*-nano*` before version patterns
- `gpt-5.4-mini*` before `gpt-5.4*`
- `gpt-4o-mini*` before `gpt-4o*`
- `o4-mini*`, `o3-mini*`, and `o1-mini*` before `o4*`, `o3*`, and `o1*`
- `gemini-2*-flash-lite*` before `gemini-2*-flash*`

| Provider  | Pattern               | Tier                 | Input ($/1M) | Output ($/1M) |
|-----------|-----------------------|----------------------|-------------|--------------|
| Anthropic | `claude-opus-*`       | Opus                 | $15.00      | $75.00       |
| Anthropic | `claude-sonnet-*`     | Sonnet               | $3.00       | $15.00       |
| Anthropic | `claude-haiku-*`      | Haiku                | $1.00       | $5.00        |
| OpenAI    | `gpt-*-pro*`          | GPT pro tier         | $30.00      | $180.00      |
| OpenAI    | `gpt-*-nano*`         | GPT nano tier        | $0.20       | $1.25        |
| OpenAI    | `gpt-5.5*`            | GPT-5.5              | $5.00       | $30.00       |
| OpenAI    | `gpt-5.4-mini*`       | GPT-5.4-mini         | $0.75       | $4.50        |
| OpenAI    | `gpt-5.4*`            | GPT-5.4              | $2.50       | $15.00       |
| OpenAI    | `gpt-5.3*`            | GPT-5.3              | $1.75       | $14.00       |
| OpenAI    | `gpt-4o-mini*`        | GPT-4o-mini          | $0.15       | $0.60        |
| OpenAI    | `gpt-4o*`             | GPT-4o               | $2.50       | $10.00       |
| OpenAI    | `o4-mini*`            | o4-mini              | $4.00       | $16.00       |
| OpenAI    | `o3-mini*`            | o3-mini              | $1.10       | $4.40        |
| OpenAI    | `o3*`                 | o3                   | $2.00       | $8.00        |
| OpenAI    | `o1*`                 | o1                   | $15.00      | $60.00       |
| Google    | `gemini-3*-pro*`      | Gemini 3 Pro         | $2.00       | $12.00       |
| Google    | `gemini-3*-flash*`    | Gemini 3 Flash       | $0.50       | $3.00        |
| Google    | `gemini-2*-pro*`      | Gemini 2.5 Pro       | $1.25       | $10.00       |
| Google    | `gemini-2*-flash-lite*` | Gemini 2.5 Flash-Lite | $0.10    | $0.40        |
| Google    | `gemini-2*-flash*`    | Gemini 2.5 Flash     | $0.30       | $2.50        |
| Mistral   | `mistral-large-*`     | Mistral Large        | $2.00       | $6.00        |
| Mistral   | `mistral-medium-*`    | Mistral Medium       | $0.40       | $2.00        |
| Mistral   | `mistral-small-*`     | Mistral Small        | $0.05       | $0.08        |
| Mistral   | `codestral-*`         | Codestral            | $0.30       | $0.90        |
