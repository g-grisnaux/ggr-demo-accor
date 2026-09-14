# Demo scenarios — Accor BFF observability

Everything below runs against the public GraphQL endpoint, the way a real ALL
client would. Failures are triggered by runtime switches inside the running
pods, not by redeploying, so the before/after lands on the same dashboard.

**Dashboards and monitors** (created by `terraform-datadog/`)

| Asset | Link / id |
|---|---|
| ALL BFF — GraphQL operation health | <https://app.datadoghq.com/dashboard/tgq-6hy-vt9> |
| ALL BFF — BFF to REST chain latency | <https://app.datadoghq.com/dashboard/h7a-fyg-da5> |
| Monitor: anomalous error rate per resolver | `321507072` — `agile`, daily seasonality, ~7 days of history |
| Monitor: anomalous rate per business error code | `321507071` — `basic`, history started today |
| Monitor: global error rate > 5% (counter-example) | `321507068` — already firing on the normal invalid-date background |

---

## The demo flow — which monitor you start from, and why

The order matters, and getting it wrong makes the argument collapse. Two
separate stories, one monitor each.

### Act 1 — the alert they have learned to ignore

Nothing running, system healthy. Open **Monitors → `[ALL BFF] (contrast) Global
GraphQL error rate over 5%`**. It is red, and it has been red for days.

Ask the room what is broken. Nothing is. Follow the dashboard link in the alert
and scroll to the business-error group: `invalid_date` is a flat background of
clients sending reversed date ranges. The tile "Business rejections, % of
operations" puts a number on it — around 6 to 10%, permanently above a 5%
threshold.

**No investigation happens in this act.** That is the whole point: a global
threshold on a GraphQL error rate fires on business as usual, so nobody reads it
any more.

### Act 2 — the alert that means something

Trigger the storm **four to five minutes before you need it**. Measured on this
stack: raised at 08:08:38Z, the monitor went to Alert at 08:12:51Z.

```bash
scripts/scenario.sh payment-storm
```

**Monitors → `[ALL BFF] Anomalous rate on a business error code`** goes from OK
to Alert, and the alert names `PAYMENT_DECLINED`.

The line that carries the argument: the naive monitor is red at this moment too
— but it was *already* red, so it carries no information. Only the business
monitor has a delta, and that delta names the failing business rule. You know
which team to wake before opening a single trace.

Then follow its dashboard link and drill:

1. **"Errors by business code (span-based)"** — the spike on `payment_declined`
   while `invalid_date` does not move.
2. **Right-click the series → View traces**, or one of the
   "Traces — PAYMENT_DECLINED" entries to go straight to a single code. These
   are explicit links on the widget: Datadog greys out its own trace pivot on
   these widgets and the reason could not be established, so the links are
   wired by hand. Every target was verified to return spans.
3. **A failing trace** — `graphql-bff` → `booking-api` → `payment-api`, with
   `decline_reason` on the payment span.
4. **The trace's Logs tab** — five logs, one from each service it touched.
5. **A SQL span → View query in DBM** — the execution plan.


### Why the traces show as OK, not error

Expect this question, and have the answer ready — it is an argument, not a bug.

A GraphQL operation that fails returns **HTTP 200** with the errors in the
response body. That is the GraphQL specification, not a Datadog quirk. So the
root span of the trace, `POST /graphql`, sees a 200 and is marked `ok`, and the
trace list shows the status of the root span.

Inside the trace, the GraphQL spans *are* marked as errors — measured on a
business-error trace: `Query.searchHotels`, `searchHotels:SearchResult!` and the
`graphql.execute` span all carry `status=error`, while `POST /graphql` carries
`status=ok`.

The point to make: **an HTTP-level error rate is structurally blind to GraphQL
failures.** Any monitoring that watches status codes on a GraphQL endpoint sees
a permanently healthy service. That is precisely why the failing business rule
has to be its own dimension, which is what `bff.graphql.errors` by `error_code`
provides.

To find these traces, filter on `@graphql.error.code:*` rather than on
`status:error`.

Note also that the BFF deliberately clears the error flag on the root span for
`kind=BUSINESS`, so a declined card does not inflate the APM error rate of the
service. Genuine upstream failures are a different case — see the caveat at the
end of this document.

### Act 3 — the investigation

```bash
scripts/scenario.sh reset
scripts/scenario.sh booking-outage
```

The *same* business monitor fires, on a different code:
`UPSTREAM_UNAVAILABLE`. Same alert, completely different cause, and this time
the trace is the only way to find it. See "The investigation scenario" below.

Three distinct causes, one monitor, three different codes — that is the summary
sentence.

**Prerequisites**

```bash
kubectl port-forward -n ggr-demo-accor svc/frontend 8090:80
```

The UI is then on <http://localhost:8090> and the GraphQL endpoint is proxied at
`http://localhost:8090/graphql`.

Set a stay in the future — the API rejects past check-ins:

```bash
export CI=$(date -v+7d +%Y-%m-%d) CO=$(date -v+10d +%Y-%m-%d)
```

---

## Golden path

The point of this sequence is that a client makes **one** GraphQL call and
Datadog shows the whole fan-out underneath it.

### 1. Search for hotels

```bash
curl -s -X POST http://localhost:8090/graphql \
  -H 'content-type: application/json' \
  -H 'x-client-name: all-ios' -H 'x-client-version: 6.2.0' \
  -d "{\"operationName\":\"SearchHotels\",\"query\":\"query SearchHotels(\$city:String!,\$checkIn:String!,\$checkOut:String!){searchHotels(city:\$city,checkIn:\$checkIn,checkOut:\$checkOut){nights resultCount hotels{id name brand starRating availability{available roomsLeft offers{rateCode totalPrice currency}}}}}\",\"variables\":{\"city\":\"Paris\",\"checkIn\":\"$CI\",\"checkOut\":\"$CO\"}}"
```

Services hit: `all-web` (if driven from the UI) → `graphql-bff` → `hotel-search-api` → `postgresql`

**Show in Datadog**
- **APM → Service Map**: the four services and the database, connected.
- **APM → Traces**, one `searchHotels` trace: the flame graph has a span per
  GraphQL resolver *and* per field, then the batched REST call, then the SQL.
  This is the field-level view the team reads in Hive today.
- Click through from the trace to **Logs** — `dd.trace_id` is injected, so the
  correlation needs no configuration.

### 2. Create a booking

```bash
curl -s -X POST http://localhost:8090/graphql \
  -H 'content-type: application/json' \
  -d "{\"operationName\":\"CreateBooking\",\"query\":\"mutation CreateBooking(\$input:CreateBookingInput!){createBooking(input:\$input){id reference status totalPrice currency payment{status method} hotel{name city}}}\",\"variables\":{\"input\":{\"hotelId\":\"1\",\"guestId\":\"guest-demo\",\"checkIn\":\"$CI\",\"checkOut\":\"$CO\",\"guests\":2,\"rateCode\":\"FLEX\",\"paymentMethod\":\"VISA\"}}}"
```

Services hit: `graphql-bff` → `booking-api` → `payment-api`, plus
`booking-api` → `hotel-search-api` for the price check.

**Show in Datadog**
- A single trace spanning **three hops**. This is the "which API is at fault"
  answer: the span tree names the service, not a log line.
- The booking span carries `booking.reference`, `booking.hotel_id` and
  `booking.status` as tags, so a support ticket reference finds its own trace.

### 3. The booking journey in the browser

Open <http://localhost:8090>, search, and book a room.

**Show in Datadog**
- **RUM → Sessions**: the session, its replay, and the custom actions
  (`hotel_search`, `booking_confirmed`) with their attributes.
- From the RUM resource for `/graphql`, jump straight into the backend trace —
  the browser SDK injects both `datadog` and `tracecontext` headers.

---

## Failure scenarios

All of them are driven by `scripts/scenario.sh`. Run `scripts/scenario.sh list`
for the menu and `scripts/scenario.sh reset` to return to baseline.

| Scenario | Command | What happens | Datadog view |
|---|---|---|---|
| **Latency regression** | `scripts/scenario.sh latency-on` | `searchHotels` goes from ~5 ms to ~160 ms. The SQL predicate becomes non-sargable (`LOWER(city)`) and the ranking turns CPU-bound. | **APM**: p95 on `searchHotels` jumps. **DBM**: the plan flips from Bitmap Index Scan to Seq Scan — 0.8 ms → 14.8 ms on the query alone. **Profiler**: `RankingService.relevanceScore` dominates the flame graph. |
| **Payment storm** | `scripts/scenario.sh payment-storm` | Declines go from 4% to 45%, split across `insufficient_funds`, `card_expired`, `do_not_honor`. | **Dashboards**: `bff.graphql.errors` broken down by `error_code`. **Monitors**: anomaly detection fires on `PAYMENT_DECLINED` while `INVALID_DATE` stays flat — the two never share an alert. |
| **N+1 resolver** | `scripts/scenario.sh n-plus-one-on` | The availability dataloader is disabled; each of the 25 results fetches its own availability. | **APM trace**: 25 sibling `hotel-search-api` spans instead of 1. Latency only moves ~10 ms → ~18 ms because the fan-out is concurrent — the story here is span count and upstream load, not a latency spike. |
| **Booking outage (investigation)** | `scripts/scenario.sh booking-outage` | A 6s delay on hotel-search-api's availability endpoints exceeds booking-api's 5s timeout. `createBooking` fails with `UPSTREAM_UNAVAILABLE` before payment is ever contacted. | The scenario to *investigate* rather than narrate — see the section below. Verified: 0 payment authorizations during the outage, `booking-api` logging `Read timed out (read timeout=5)` against `hotel-search-api:8081`. |
| **Front-end crash** | Click **Break the funnel** in the UI navbar | A React render reads a property of an undefined rate object and the error boundary catches it. | **RUM → Error Tracking**: the error with its component stack, the session replay of the click that caused it, and the console/network context. |
| **Business rejection baseline** | Always on — the load generator sends ~9% malformed date ranges | `INVALID_DATE` errors flow continuously. | Shows why a single "GraphQL error rate" monitor is useless: business rejections are a stable background, and burying them with real failures is what makes CloudWatch alerting noisy. |


---

## The investigation scenario — following one trace across four services

This is the scenario to run as an *investigation* rather than a guided tour. It
is built so the cause sits two hops from the symptom, with a plausible innocent
suspect in between.

```bash
scripts/scenario.sh booking-outage
```

**The symptom.** `createBooking` starts failing. On the GraphQL health
dashboard, `error_code:upstream_unavailable` climbs while `invalid_date` and
`payment_declined` stay where they were.

**The trap.** On a healthy `createBooking` trace, `payment-api` is by far the
slowest span — about 122ms out of 183ms. Anyone who has looked at this trace
before will reach for the payment partner first. Payment is completely healthy
throughout: measured 0 authorizations attempted during the outage, because it is
never called.

**The path.**

1. **Dashboard** — error rate on the mutation up, and the breakdown says
   `UPSTREAM_UNAVAILABLE`, not `PAYMENT_DECLINED`. The business error taxonomy
   has already ruled out the obvious suspect, before opening a single trace.
2. **APM trace** — the span tree stops at `booking-api`. There is no
   `payment-api` span at all, which is the tell: the booking never got that far.
3. **Logs from the trace** — `booking-api` says it plainly:
   `availability lookup failed ... Read timed out. (read timeout=5)` against
   `hotel-search-api:8081`.
4. **hotel-search-api** — `GET /hotels/{hotelId}/availability` has gone from
   ~2ms to over 5s, and its own log line carries `delay_ms=6000`.
5. **Conclusion** — a dependency of a dependency. The public GraphQL operation
   that failed is three layers above the service that broke.

**Why it is a good fit for an AI-assisted investigation.** The signal that
matters (`UPSTREAM_UNAVAILABLE` rather than `PAYMENT_DECLINED`) is a tag on a
custom metric, the evidence is split across a trace and the logs of two
different services, and the span tree proves a negative — that payment was
never reached. That is a lot of correlation to do by hand under time pressure.

Availability of Bits AI Investigate depends on the Datadog account; confirm it
in the UI before building the live demo around it. Everything above is
reproducible manually regardless.

```bash
scripts/scenario.sh booking-outage-off   # or: scenario.sh reset
```

---

## Reading the GraphQL-specific telemetry

These are the custom metrics the BFF emits, and they are what the Hive
comparison rests on:

| Metric | Tags | Answers |
|---|---|---|
| `bff.graphql.operation` | `operation`, `operation_type`, `client_name`, `client_version` | Which operations are used, by which app version |
| `bff.graphql.operation.duration` | `operation`, `client_name` | Latency per named operation |
| `bff.graphql.errors` | `operation`, `error_code`, `error_kind`, `upstream_service` | Error rate per **business** code, and which upstream caused it |
| `bff.graphql.field.duration` | `parent_type`, `field` | Latency per field |
| `bff.graphql.field.usage` | `parent_type`, `field`, `deprecated` | Field usage, and whether a deprecated field is still being requested |
| `payment.authorization` | `status`, `decline_reason`, `method` | Payment funnel health |
| `booking.rejected` | `error_code`, `decline_reason` | Where bookings are lost |

**Datadog lowercases metric tag values**, so a business code emitted as
`INVALID_DATE` is filtered as `error_code:invalid_date` on a metric, while the
same code stays uppercase in log attributes and span tags. Worth knowing before
you type a filter on stage.

The load generator sends a deliberate mix of `all-web 3.4.0`, `all-ios 6.2.0`,
`all-ios 6.1.0` and `all-android 5.9.0`, and the `6.1.0` cohort still requests
the deprecated `Hotel.thumbnailUrl`. Filtering `bff.graphql.field.usage` on
`deprecated:true` by `client_version` is the deprecation-tracking answer.

---

## Pivoting between metrics, logs and traces

Every signal carries the same `env` / `service` / `version` (unified service
tagging), which is what makes the scope of one widget transfer to another view.
On top of that:

| Pivot | Mechanism | Verified |
|---|---|---|
| trace -> logs | `dd.trace_id` / `dd.span_id` injected into the JSON logs by each tracer. Every service logs once per request, so a trace always has a log from each service it touched. | Yes — 5 logs from all 4 services on every sampled createBooking trace |
| logs -> trace | Same ids, consumed by the log intake into the reserved `trace_id` | Yes |
| trace -> DBM query sample & plan | `DD_DBM_PROPAGATION_MODE=full` makes each tracer prepend a SQL comment carrying `traceparent` | Yes — verified on all three tracers (Java, Python, Node) |
| RUM session -> backend trace | `allowedTracingUrls` injects `datadog` + `tracecontext` headers on `/graphql` | Configured, not yet verified in a browser |
| metric -> trace | DogStatsD counters carry env/service/version so a widget scopes into APM, but a counter has no per-request identity. The per-request pivot is a span-based metric on `graphql.error.code`. | Metrics flowing; span-based metric not created |
| RUM session -> browser logs | Browser Logs SDK stamps `session_id` and `view.id` when RUM is present | Configured, not yet verified in a browser |
| profiles -> trace | Endpoint profiling, automatic with `DD_PROFILING_ENABLED` | Configured, not yet verified |
| infrastructure -> APM | `tags.datadoghq.com/*` pod labels, plus `kube_namespace:ggr-demo-accor` and `kube_cluster_name:ggr-demo-accor` | Configured |

**On metric -> trace, be precise with them.** The custom business metrics are
DogStatsD counters. They carry `env`/`service`/`version`, so a dashboard widget
scopes cleanly into APM — but a counter has no per-request identity, so there is
no click-through from one data point to one trace. That is a property of
DogStatsD, not a gap in the setup.

The per-request pivot on the same dimension exists, through span tags: the BFF
also puts `graphql.error.code`, `graphql.error.kind` and `graphql.operation.name`
on the request span. Building a **span-based metric** on `graphql.error.code` in
the Datadog UI gives the same breakdown as `bff.graphql.errors` *and* keeps the
click-through to the underlying traces. Worth showing both and explaining the
trade-off — it lands better than pretending a StatsD counter can do it.

---

## Honest limits of this demo

State these rather than let them be discovered on stage:

- **No mobile app.** Mobile RUM against Firebase is an argument here, not a
  live demo — nothing in this stack emits mobile RUM.
- **The front is React, the real ALL site is UJS/vanilla.** The Browser RUM
  story (errors, sessions, replay, backend correlation) transfers unchanged;
  the framework does not.
- **GraphQL observability is operation- and resolver-level via APM spans and
  custom metrics.** It is not a feature-for-feature Hive replacement — schema
  registry and schema-change tracking are not covered.
- **Feature Flags is not demonstrable.** The Datadog OpenFeature provider times
  out at BFF startup, so the dataloader flag is not actually served; the N+1
  scenario runs off its environment override instead.
- **Root spans are `ok` even for genuine upstream failures**, for the same
  HTTP-200 reason described above. During `booking-outage` the trace list shows
  healthy-looking traces. Marking the root span as an error for
  `kind=UPSTREAM` and `kind=SERVER`, while leaving `BUSINESS` clean, would fix
  that properly — it is a one-line change in `src/telemetry.js` plus a BFF
  rollout, and has not been applied.
