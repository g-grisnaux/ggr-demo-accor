# Demo scenarios — Accor BFF observability

Everything below runs against the public GraphQL endpoint, the way a real ALL
client would. Failures are triggered by runtime switches inside the running
pods, not by redeploying, so the before/after lands on the same dashboard.

**Prerequisites**

```bash
kubectl port-forward -n demo-accor svc/frontend 8090:80
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
| **Front-end crash** | Click **Break the funnel** in the UI navbar | A React render reads a property of an undefined rate object and the error boundary catches it. | **RUM → Error Tracking**: the error with its component stack, the session replay of the click that caused it, and the console/network context. |
| **Business rejection baseline** | Always on — the load generator sends ~9% malformed date ranges | `INVALID_DATE` errors flow continuously. | Shows why a single "GraphQL error rate" monitor is useless: business rejections are a stable background, and burying them with real failures is what makes CloudWatch alerting noisy. |

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

The load generator sends a deliberate mix of `all-web 3.4.0`, `all-ios 6.2.0`,
`all-ios 6.1.0` and `all-android 5.9.0`, and the `6.1.0` cohort still requests
the deprecated `Hotel.thumbnailUrl`. Filtering `bff.graphql.field.usage` on
`deprecated:true` by `client_version` is the deprecation-tracking answer.

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
