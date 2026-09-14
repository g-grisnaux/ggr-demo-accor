# Démo observabilité — BFF GraphQL Accor

Un BFF GraphQL public devant trois API REST, instrumenté avec Datadog, déployé
sur GKE par Terraform sous impersonation de compte de service.

Construit pour répondre à ce que l'équipe BFF d'Accor a réellement demandé :
suivre une opération GraphQL jusqu'à l'API REST fautive, ventiler les taux
d'erreur par code **métier** et non globalement, mesurer la latence par resolver
et par champ, et ne plus maintenir des dashboards à la main en Terraform.

| Document | Contenu |
|---|---|
| **[DEMO-DEROULE.md](DEMO-DEROULE.md)** | Le déroulé minuté, clic par clic, avec ce qu'il y a à dire. À garder ouvert pendant la démo. |
| **[DEMO-SCENARIOS.md](DEMO-SCENARIOS.md)** | Les scénarios de panne, les métriques custom, les pivots vérifiés. |
| **[BITS-INVESTIGATION.md](BITS-INVESTIGATION.md)** | Prompts pour Bits Investigation et la fiche de notation pour juger sa réponse. |
| **[mobile/README.md](mobile/README.md)** | L'app mobile : écrite, **non compilée**. |

---

## Architecture

```
                    ┌──────────────┐        ┌──────────────────────┐
                    │ rum-traffic  │        │  synthetics private  │
                    │  Playwright  │        │      location        │
                    └──────┬───────┘        └──────────┬───────────┘
                           │ navigue                   │ sonde
                           ▼                           ▼
  ┌──────────┐      ┌──────────────┐          ┌──────────────────┐
  │ traffic  │────▶ │   all-web    │────────▶ │   graphql-bff    │
  │  Locust  │      │ React + RUM  │  nginx   │  Apollo Server 5 │
  └──────────┘      └──────────────┘          └────────┬─────────┘
                                                       │
                              ┌────────────────────────┼──────────────┐
                              ▼                        ▼              │
                    ┌──────────────────┐   ┌──────────────────┐       │
                    │ hotel-search-api │   │   booking-api    │       │
                    │  Java 21 Spring  │   │  Python 3.12     │       │
                    └────────┬─────────┘   └────┬────────┬────┘       │
                             │                  │        ▼            │
                             │                  │  ┌──────────────┐   │
                             │                  │  │ payment-api  │   │
                             │                  │  │  Node.js 22  │   │
                             │                  │  └──────┬───────┘   │
                             ▼                  ▼         ▼           │
                        ┌───────────────────────────────────────┐      │
                        │      PostgreSQL 16 (DBM)              │◀─────┘
                        └───────────────────────────────────────┘
```

Trois langages différents, volontairement : c'est ce qui rend le tracing
distribué crédible plutôt que théorique.

### Les composants applicatifs

| Service | Stack | Port | Rôle |
|---|---|---|---|
| `graphql-bff` | Node 22 / Apollo Server 5 | 8080 | Point d'entrée public unique. Découpé comme le BFF Accor : resolvers → repositories avec dataloaders → API clients → mappers DTO. Porte la taxonomie d'erreurs métier. |
| `hotel-search-api` | Java 21 / Spring Boot 3.4 | 8081 | Recherche et disponibilités sur PostgreSQL. Héberge les scénarios de latence et DBM. |
| `booking-api` | Python 3.12 / Flask + gunicorn | 8082 | Cycle de vie des réservations. Appelle `payment-api`, ce qui donne à la trace son troisième niveau. |
| `payment-api` | Node 22 / Express | 8083 | Autorisation de paiement, HTTP 402 sur refus. Source du scénario de tempête de refus. |
| `all-web` | React 18 / Vite + nginx | 80 | Parcours de réservation, Browser RUM, session replay, Browser Logs. |
| `postgresql` | PostgreSQL 16 | 5432 | Sous Database Monitoring, `pg_stat_statements` préchargé. |

### Les générateurs et sondes

| Workload | Rôle |
|---|---|
| `traffic` | Locust, 8 utilisateurs, ~3 req/s en continu sur l'API GraphQL. Quatre identités de client, dont une cohorte qui interroge encore un champ déprécié. |
| `rum-traffic` | Playwright pilotant le vrai front en Chromium sur quatre profils d'écran. Sans lui le RUM reste vide : Locust parle à l'API, pas au navigateur. 12% des sessions finissent sur un crash volontaire. |
| `synthetics-pl` | Worker de private location Datadog. Les Synthetics tournent **depuis l'intérieur du cluster** — comme une sonde interne Accor, et rien n'est exposé sur Internet. |

### Volumes réels en base

| | |
|---|---|
| Hôtels | 22 410 |
| Tarifs | 61 630 |
| Lignes de disponibilité | 1 008 450 |
| Réservations accumulées | ~102 000 |

Le million de lignes d'inventaire n'est pas décoratif : c'est ce qui permet
qu'une régression de plan d'exécution SQL soit réellement mesurable, plutôt que
simulée par un `sleep`.

---

## Ce qui est monté dans Datadog

### Dashboards

- [ALL BFF — GraphQL operation health](https://app.datadoghq.com/dashboard/tgq-6hy-vt9) — latence par opération et par resolver, erreurs par resolver, ventilation par code métier, usage des champs dépréciés par version de client
- [ALL BFF — BFF to REST chain latency](https://app.datadoghq.com/dashboard/h7a-fyg-da5) — p95 par service aval et par endpoint, répartition des statuts HTTP, coût SQL, CPU et mémoire par déploiement

### Monitors — la comparaison seuil fixe / seuil dynamique

| Monitor | Type |
|---|---|
| Taux d'erreur GraphQL global > 5% | **seuil fixe**, gardé comme contre-exemple : il est rouge en permanence |
| Refus de paiement anormaux | **seuil dynamique** `robust`, saisonnalité journalière, sur le ratio de HTTP 402 |
| Code d'erreur métier anormal | **seuil dynamique** `basic`, par `error_code` |
| Erreurs anormales sur un resolver | **seuil dynamique** `agile`, par resolver |

### Synthetics, depuis la private location

| Test | Ce qu'il vérifie |
|---|---|
| Parcours de réservation (navigateur) | Chargement, recherche, tarifs affichés, dans un vrai Chromium |
| API GraphQL searchHotels | Le **corps** de la réponse, pas le statut — une opération GraphQL en échec répond 200 |
| Santé × 3 | Un test par service aval |

### Produits exercés

APM avec tracing distribué · Logs corrélés par `dd.trace_id` · Infrastructure ·
Browser RUM et Session Replay · Browser Logs · Database Monitoring ·
Continuous Profiling avec timeline · App & API Protection · Synthetics ·
Source Code Integration

---

## Prérequis

### Credentials Datadog

Dans `.env`, gitignoré. Tous renseignés et vérifiés :

```
DD_API_KEY       validée contre /api/v1/validate
DD_APP_KEY       validée
DD_RUM_APPLICATION_ID    correspond à l'app RUM accorDemoApp
DD_RUM_CLIENT_TOKEN
PROJECT_ID       cible GCP, hors du dépôt car celui-ci est public
SERVICE_ACCOUNT  compte impersoné, hors du dépôt pour la même raison
```

### IAM

Le déploiement passe entièrement par l'impersonation d'un compte de service qui
porte `container.admin`, `compute.admin`, `iam.serviceAccountUser`,
`storage.admin` et `artifactregistry.admin` — ce dernier a dû être ajouté, les
quatre premiers ne donnant aucun accès à Artifact Registry.

### Outillage

```bash
brew install hashicorp/tap/terraform
gcloud components install gke-gcloud-auth-plugin
npm install -g @datadog/datadog-ci
```

Note : le plugin `docker compose` n'est pas installé sur la machine de
préparation, seul le binaire `docker-compose`. Et le builder Docker local ne
produit pas d'images amd64 exploitables depuis un Mac Apple Silicon — les
images passent par Cloud Build, voir `scripts/build-cloud.sh`.

---

## Déployer

```bash
./scripts/deploy-gke.sh
```

Le script refuse de démarrer plutôt que de déployer à moitié : il contrôle
chaque outil, rejette les credentials placeholder, vérifie l'impersonation, puis
seulement applique Terraform. Il construit et pousse les images, pointe
`kubectl` sur le cluster, crée les secrets — dont un mot de passe de base
généré qui ne touche jamais le dépôt — installe l'Agent Datadog avec le
collector DDOT, et applique les manifests.

Puis :

```bash
kubectl port-forward -n ggr-demo-accor svc/frontend 8090:80
open http://localhost:8090
```

### Ce que Terraform crée

Un cluster GKE **Standard** zonal en `europe-west9-a`, deux nœuds
`e2-standard-4`, plus le dépôt Artifact Registry.

Standard et non Autopilot volontairement : l'Agent Datadog et le collector DDOT
ont besoin d'accès au niveau hôte — métriques kubelet, host ports, collecte de
processus — qu'Autopilot restreint. Autopilot coûterait silencieusement la
moitié infrastructure de la démo.

Les dashboards, monitors, Synthetics et la métrique de span vivent dans un
module séparé, `terraform-datadog/`, avec son propre état : le module GKE a
besoin de credentials Google pour se rafraîchir, un dashboard non. Les coupler
signifiait qu'un token gcloud expiré bloquait une modification de dashboard —
ce qui est arrivé une fois.

### Démolir

```bash
terraform -chdir=terraform destroy
```

---

## Jouer la démo

Voir **[DEMO-DEROULE.md](DEMO-DEROULE.md)**. Les scénarios sont des
interrupteurs à chaud, pas des redéploiements :

```bash
scripts/scenario.sh list
scripts/scenario.sh latency-on        # bascule de plan SQL + flamegraph profiler
scripts/scenario.sh payment-storm     # anomalie sur un code d'erreur métier
scripts/scenario.sh n-plus-one-on     # 25 spans REST au lieu d'un
scripts/scenario.sh booking-outage    # le scénario d'enquête
scripts/scenario.sh reset
```

---

## Régénérer les manifests

Les manifests de services sont générés, parce que douze lignes de tagging
unifié, de sondes et d'environnement Datadog répétées sur quatre services, c'est
la façon dont une démo finit avec un service qui a silencieusement perdu son
`DD_ENV` :

```bash
python3 scripts/render-manifests.py
```

Éditer la liste `SERVICES` du script, pas le YAML.

---

## Ce que cette démo ne couvre pas

À dire avant la réunion plutôt que de le laisser découvrir :

- **Mobile RUM n'est pas monté.** L'app existe dans `mobile/` mais n'a jamais
  été compilée : ni Xcode ni le SDK Android n'étaient installés. Aucun faux
  événement mobile n'a été fabriqué pour combler le trou.
- **Ce front est en React**, le site ALL est en UJS. L'histoire RUM se
  transpose, le framework non.
- **Ce n'est pas un remplacement de Hive à l'identique.** Latence par
  opération, par resolver et par champ, codes d'erreur, versions de clients et
  usage des champs dépréciés sont couverts. Registre de schéma et suivi des
  changements de schéma ne le sont pas.
- **Feature Flags n'est pas démontrable** : le provider OpenFeature de Datadog
  n'arrive pas à s'initialiser dans le BFF. Le scénario N+1 fonctionne par sa
  variable d'environnement de contournement.
- **`payment-api` est en Node et non en Java.** Le CLI de scaffolding répartit
  les frameworks en round-robin sans contrôle par service ; trois langages et
  une chaîne à trois niveaux survivent intacts.
- **Les liens traces et logs des widgets de code métier sont câblés à la
  main.** Datadog grise son propre pivot sur ces widgets et la cause n'a pas pu
  être établie ; chaque lien a été vérifié individuellement à la place.

---

## Défauts du scaffold corrigés

Le générateur produisait plusieurs choses qui ne pouvaient pas fonctionner,
consignées ici au cas où le CLI resserve :

- Namespace et noms d'images en `demoAccor` — invalides pour Kubernetes
  (RFC 1123) comme pour Docker.
- PostgreSQL avec `imagePullPolicy: Never` sur une image publique, sans mot de
  passe, sans `shared_preload_libraries`, et sans jamais monter son SQL d'init :
  ni schéma, ni métriques DBM.
- Le seed appelait `CREATE EXTENSION vector`, absent de `postgres:16`.
- `datadog.dbm.enabled` dans les values Helm n'existe pas dans le chart et
  était ignoré silencieusement. DBM passe par l'annotation d'autodiscovery.
- DogStatsD n'avait pas de hostPort sur le DaemonSet, donc toutes les métriques
  métier partaient en UDP dans le vide, sans aucune erreur.
- Le générateur de trafic ciblait une API CRUD générique inexistante ici.
- Apollo Server 4 déclenchait trois advisories sans version corrigée ; le BFF
  est en Apollo Server 5 avec l'intégration Express 5.
