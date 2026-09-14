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

Three acts, one monitor each. The order matters: getting it wrong makes the
argument collapse, because during Act 2 *both* monitors are red.

### Act 1 — the alert they have learned to ignore

Nothing running. System healthy.

**Monitors → `[ALL BFF] (contrast) Global GraphQL error rate over 5%`** — red,
and red for days.

Ask what is broken. Nothing is. Follow the dashboard link, scroll to the
business-error group. `invalid_date` is a flat background of clients sending
reversed date ranges, and the tile puts a number on it: **9.6% of operations**
are business rejections, permanently above a 5% threshold.

No investigation in this act. That is the point — a global threshold on a
GraphQL error rate fires on business as usual, so nobody reads it any more.

### Act 2 — the alert that means something

Trigger **4 to 5 minutes before** you need it. Measured: raised at 08:08:38Z,
the monitor went to Alert at 08:12:51Z.

```bash
scripts/scenario.sh payment-storm
```

**`[ALL BFF] Anomalous rate on a business error code`** goes OK → Alert, and
names `PAYMENT_DECLINED`.

The line that carries the argument: the naive monitor is red at this moment too
— but it was *already* red, so it carries no information. Only the business
monitor has a delta, and that delta names the failing business rule. You know
which team to wake before opening a trace.

Then drill: right-click the business-code widget → **Traces — PAYMENT_DECLINED**
→ a failing trace → its **Logs** tab (five logs, one per service) → a SQL span →
**View query in DBM**.

### Act 3 — the investigation, and where Bits comes in

```bash
scripts/scenario.sh reset
scripts/scenario.sh booking-outage
```

The *same* business monitor fires on a different code:
`UPSTREAM_UNAVAILABLE`. Same alert, completely different cause. This is the one
to hand to Bits.

Reset when done:

```bash
scripts/scenario.sh booking-outage-off
```

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
| 1 | The failing operation is the **`createBooking` mutation**, not `searchHotels` | Error rate per resolver; `query.searchhotels` unchanged | `searchHotels` keeps its normal ~9% invalid-date background |
| 2 | The error code is **`UPSTREAM_UNAVAILABLE`**, not `PAYMENT_DECLINED` | Business error code breakdown | The business monitor names the code in its title |
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
- **The business monitor takes about 4 minutes** to fire after a scenario is
  triggered. Trigger early.
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

## Part 5 — Source code integration: what Bits is missing

Bits reports `Unknown repository` for `graphql-bff` and cannot finish. That is
correct behaviour, not a bug: Datadog's Source Code Integration is not set up on
this project. Three things are missing, not one.

1. **There is no git remote.** The repository is local only — it was created
   during this work and never pushed. `datadog-ci git-metadata upload` reports a
   repository URL and a commit SHA, so with no remote there is nothing to
   report.
2. **The services carry no git tags.** Datadog links a span to a line of code
   through `git.commit.sha` and `git.repository_url` on the telemetry, which
   come from `DD_GIT_REPOSITORY_URL` and `DD_GIT_COMMIT_SHA` at build or run
   time. Neither is set anywhere, so even with metadata uploaded the traces
   would not point at it.
3. **`datadog-ci` is not installed.**

### What it would take

| Étape | Coût | Remarque |
|---|---|---|
| Créer un dépôt distant et pousser | 10 min | **Décision à prendre** : cela publie le code. L'historique a été audité, `.env` n'y a jamais été commité et aucun secret n'y apparaît. |
| `npm i -g @datadog/datadog-ci` puis `datadog-ci git-metadata upload` | 5 min | |
| Ajouter `DD_GIT_*` aux manifests, rebuild des 4 images, redéploiement | 30-40 min | Cloud Build plus rollout |

Compter une heure, et le dernier point touche au déploiement.

### Ce que ça change, et ce que ça ne change pas

Sans intégration du code source, Bits travaille **sur la télémétrie seule** :
métriques, traces, logs, profils. Le chemin d'enquête conçu pour cette démo —
code d'erreur métier, puis trace, puis logs des services traversés — ne dépend
pas du code source. Les cinq constats de la fiche ci-dessus sont tous
atteignables sans.

Ce qu'on perd : les fonctions liées au code — remonter à la ligne fautive,
proposer un correctif, relier un déploiement à un commit. C'est appréciable,
mais ce n'est pas ce qui répond à « quelle API REST est fautive ».

### Recommandation pour demain

Ne pas le monter dans l'urgence. Deux raisons : une heure de travail la veille,
dont un rebuild complet, pour une fonctionnalité annexe au récit ; et pousser le
code sur un dépôt distant est une décision qui mérite mieux qu'une décision
prise à la hâte.

À la place, l'annoncer franchement s'ils posent la question :

> « L'intégration du code source n'est pas branchée sur cet environnement, donc
> Bits raisonne ici sur la télémétrie seule — métriques, traces, logs. Branchée,
> elle ajoute le lien vers la ligne de code et le commit. C'est une commande
> `datadog-ci` dans votre CI, pas un chantier. »

C'est vrai, c'est vérifiable, et ça vaut mieux qu'une démo à moitié câblée qui
échoue devant eux.
