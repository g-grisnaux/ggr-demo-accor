# Demo flow and the Bits Investigation comparison

Keep this open on a second screen. The point of the exercise is not that Bits
says something plausible — it is that Bits reaches **the same five findings** as
the manual investigation, and in particular that it does *not* blame the service
everyone expects.

Availability of Bits AI Investigate depends on the Datadog account and could not
be verified from outside the UI. Check it before building the live moment around
it; everything below is reproducible by hand regardless.

---

## Part 1 — The demo flow

Not repeated here. The flow lives in **[DEMO-DEROULE.md](DEMO-DEROULE.md)**,
in French, click by click, and it is the single source of truth — an earlier
version of this section had drifted out of date with the monitor names and
carried a framing of act 1 that was not defensible.

What matters for this document: the investigation happens in **acte 3**, driven
by `scripts/scenario.sh booking-outage`, and the monitor that fires is
`[ALL BFF] (seuil dynamique) Code d'erreur métier anormal` on the code
`UPSTREAM_UNAVAILABLE`.

---

## Part 2 — Prompts for Bits Investigation

### Launching from the monitor

The monitor already carries the scope, so keep the prompt short and, critically,
**describe only the symptom**. Naming a service in the prompt hands over the
answer and destroys the demo.

> Bookings are failing for users. Find the root cause of this alert and tell me
> which service is responsible. Explain what evidence you used.

A slightly richer variant that still leaks nothing:

> This alert fired on the `UPSTREAM_UNAVAILABLE` business error code for the
> `createBooking` GraphQL mutation. Identify the service actually responsible,
> confirm which services in the request path are healthy, and show the trace
> evidence.

### Standalone, without a monitor

> In env `ggr-demo-accor-260907`, the `createBooking` GraphQL mutation on
> service `graphql-bff` started failing in the last 15 minutes while
> `searchHotels` is unaffected. Find the root cause, name the responsible
> service, and rule out the services that are not at fault.

### A prompt that deliberately tests the trap

Use this one if you want a memorable moment. It plants the wrong hypothesis and
a good investigation should reject it.

> Bookings are failing. I think the payment provider is down — can you confirm?

**A correct answer refuses the premise**: payment-api is healthy and is never
even reached. If Bits agrees with the premise, say so out loud. Being honest
about a wrong answer in front of a prospect buys more credibility than hiding
it, and the manual path immediately after shows the ground truth.

---

## Part 3 — Ground truth: the five findings to grade against

This is what the manual investigation establishes, with values measured on this
stack. Hold Bits' output against it item by item.

| # | Finding | Evidence | Measured |
|---|---|---|---|
| 1 | The failing operation is the **`createBooking` mutation**, not `searchHotels` | Error rate per resolver; `query.searchhotels` unchanged | `searchHotels` keeps its normal background rate |
| 2 | The error code is **`UPSTREAM_UNAVAILABLE`**, not `PAYMENT_DECLINED` | Business error code breakdown | The per-code monitor names it in the alert |
| 3 | **payment-api is not involved at all** | No `payment-api` span in the failing traces; no authorization logs | **0 authorizations attempted** during the outage |
| 4 | The failure **surfaces in booking-api** | booking-api log, in the trace | `availability lookup failed ... Read timed out. (read timeout=5)` against `hotel-search-api:8081` |
| 5 | The cause is **hotel-search-api's availability endpoint** | Latency per endpoint on that service; its own log line | `get_/hotels/_hotelid_/availability` goes from **2.8 ms to over 6 s**; the log carries `delay_ms=6000` |

### The trap, stated plainly

On a **healthy** `createBooking` trace, `payment-api` is by far the slowest
span: **120 ms of the 180 ms** the whole operation takes. Anyone who has looked
at this trace before reaches for the payment partner first, and every naive
heuristic — "show me the slowest service" — points there.

During the outage payment-api is not merely fast, it is **absent**. The booking
never gets that far, because booking-api checks availability *before* it
authorizes. A correct investigation proves a negative: the expected culprit was
never called.

### What to say depending on what Bits returns

- **It names hotel-search-api and clears payment** → the strongest possible
  outcome. Walk the five findings and point out that the pivot chain is what
  made it possible: business error code → trace → cross-service logs.
- **It names booking-api** → half right, and worth saying so. booking-api is
  where the failure *surfaces*, not where it originates. Then show finding 5.
- **It names payment-api** → it fell into the trap. Say it, then do the manual
  path. The lesson lands harder: the evidence that clears payment is the
  *absence* of a span, which is precisely the kind of thing that needs a
  complete trace rather than a dashboard.

---

## Part 4 — Honest caveats

- **Bits AI Investigate availability is unverified** on this account. No public
  API exposes it, so it has to be checked in the UI.
- **Firing delay, measured.** The per-code monitor took about 4 minutes on one
  run. The payment monitor took 9 minutes on its first run and did not fire at
  all on its third at an 83% decline rate — rehearsing had taught the `agile`
  algorithm that the storm was normal. It now runs `robust`, which holds its
  band, and the scenario should be driven at `declineRate=1.0` rather than 0.45.
  Trigger 5 minutes early either way.
- **The trace list shows these traces as `ok`.** A failing GraphQL operation
  returns HTTP 200 by specification, so the root span is healthy while the
  inner GraphQL spans carry `status=error`. Filter on
  `@graphql.error.code:*`, not on `status:error`. This is worth saying out
  loud: an HTTP-level error rate is structurally blind to GraphQL failures.
- **Root spans stay `ok` even for genuine upstream failures.** During
  `booking-outage` the trace list looks healthy. Fixing it properly means
  marking the root span as an error for `kind=UPSTREAM` and `kind=SERVER` while
  leaving `BUSINESS` clean — a one-line change in `src/telemetry.js` plus a BFF
  rollout, not applied.
- **The trace and log links on the business-code widgets are hand-wired.**
  Datadog greys out its own trace pivot on those widgets and the cause could
  not be established; every link was verified by hand instead.

---

## Part 5 — Source code integration: wired and verified

Done on 2026-09-14. Bits no longer reports `Unknown repository`.

| Étape | État |
|---|---|
| Dépôt hébergé | `github.com/g-grisnaux/ggr-demo-accor`, **public** |
| Datadog GitHub App | installée, dépôt `CONFIGURED`, dernière synchro 09:55:22Z |
| Métadonnées git | 208 chemins de fichiers, commit `610d876` |
| Tags sur les services | `DD_GIT_REPOSITORY_URL` et `DD_GIT_COMMIT_SHA` sur les 4 |
| Spans | portent `git.commit.sha` et `git.repository.id` — vérifié |

Aucun rebuild d'image n'a été nécessaire : les tracers lisent ces variables dans
l'environnement au démarrage, et elles viennent du Deployment. La documentation
Node de Datadog est explicite sur ce point. Un rollout de trois minutes a suffi
là où un premier brouillon prévoyait quatre Cloud Builds.

### Deux choses à savoir

**Le dépôt est public.** Il contient la documentation de démo, réserves
honnêtes incluses — « Feature Flags ne s'initialise pas », « les spans racine
restent ok », « les liens de pivot sont câblés à la main ». C'est bon pour
l'honnêteté d'ingénierie, mais c'est lisible par n'importe qui.

**L'App Datadog a des permissions en écriture** sur le dépôt : `contents`,
`administration`, `workflows`, `actions`, `pull_requests` et quatre autres.
C'est le jeu de permissions recommandé par défaut, nécessaire aux PR Comments et
aux liens de contexte. Sur un dépôt de démo jetable c'est sans conséquence ; si
l'installation couvre « All repositories », elle porte les mêmes droits sur les
autres dépôts personnels, ce qui mérite un coup d'oeil dans les réglages GitHub.

