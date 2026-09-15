# Remonter la démo après décommissionnement

L'infrastructure a été détruite après la démo du 15 septembre 2026 pour ne plus
générer de coût. Ce document est la procédure de reconstruction, et il est
explicite sur ce qui revient à l'identique et ce qui ne revient pas.

**Ce qui a été supprimé :** le cluster GKE, son node pool et le dépôt Artifact
Registry côté GCP ; les 4 monitors et les 5 tests Synthetics côté Datadog.

**Ce qui a été conservé :** les 2 dashboards, la span metric et le filtre de
rétention — ils ne coûtent rien, et comme Datadog garde les métriques 15 mois,
les dashboards continuent d'afficher la démo réelle sur une fenêtre passée.

**Ce qui subsiste sans être géré par Terraform :** la private location Synthetics
existe toujours côté Datadog, sans worker pour l'exécuter. Elle ne coûte rien
mais elle est orpheline — à supprimer dans l'interface si tu ne comptes pas
reconstruire, sachant qu'une nouvelle private location impliquera de toute façon
de nouveaux identifiants.

## Ce qui est entièrement dans le code

| Composant | Reproductible par |
|---|---|
| Cluster GKE, node pool, Artifact Registry | `terraform/` |
| Images des 4 services + front | `scripts/deploy-gke.sh` (Cloud Build) |
| Manifestes Kubernetes | `scripts/render-manifests.py` |
| Agent Datadog + collecteur DDOT | `helm/datadog-values.yaml`, chart épinglé 3.242.0 |
| Worker de private location | `helm/synthetics-pl-values.yaml`, chart épinglé 0.17.32 |
| Dashboards, monitors, tests Synthetics, span metric, filtre de rétention | `terraform-datadog/` |
| Schéma et jeu de données PostgreSQL | `deps/postgresql/` |
| Scénarios de démo | `scripts/scenario.sh` |

## Ce qui n'est pas dans le code, et pourquoi

### 1. `.env` — volontairement absent

Gitignoré. `.env.example` documente les variables. À recréer avec :

- `DD_API_KEY`, `DD_APP_KEY` — depuis l'organisation Datadog
- `DD_RUM_APPLICATION_ID`, `DD_RUM_CLIENT_TOKEN` — voir point 3
- `DD_SITE`, `DD_ENV`, `PROJECT_ID`, `SERVICE_ACCOUNT`

### 2. La private location Synthetics — deux étapes manuelles

Datadog ne renvoie les identifiants d'une private location **qu'une seule fois**,
à sa création. Ils ne doivent donc jamais transiter par un état Terraform, d'où
cette exception assumée à l'infrastructure-as-code.

1. Dans Datadog : **Synthetics → Settings → Private Locations → New**. Nommer la
   location, télécharger le fichier `synthetics-check-runner.json` proposé, et
   **noter l'identifiant `pl:...`**.
2. Créer le Secret puis installer le worker :

```bash
kubectl create secret generic synthetics-private-location \
  --from-file=synthetics-check-runner.json=./synthetics-check-runner.json \
  -n ggr-demo-accor
```

```bash
helm upgrade --install synthetics-pl datadog/synthetics-private-location \
  --version 0.17.32 -n ggr-demo-accor -f helm/synthetics-pl-values.yaml
```

Le nouvel identifiant `pl:...` est ensuite passé à Terraform :

```bash
terraform -chdir=terraform-datadog apply -var="private_location_id=pl:..."
```

### 3. L'application RUM

Créée à la main dans Datadog (**Digital Experience → Add an Application →
Browser**, service `all-web`). Reporter l'application ID et le client token dans
`.env`. Une nouvelle application signifie **aucun historique de sessions**.

### 4. Source Code Integration

L'application GitHub a été installée manuellement sur `g-grisnaux/ggr-demo-accor`.
Si elle est encore en place, rien à refaire. Les spans portent `git.commit.sha`
via les variables `DD_GIT_REPOSITORY_URL` et `DD_GIT_COMMIT_SHA` — les
placeholders sont dans `scripts/render-manifests.py` et **ne sont pas substitués
par `deploy-gke.sh`** : il faut les renseigner avant d'appliquer les manifestes.

### 5. Le rôle IAM `roles/artifactregistry.admin`

Ajouté à la main sur le service account impersonné. À vérifier avant le premier
déploiement, sinon le push des images échoue.

### 6. L'état Terraform

Les deux racines utilisent un **état local, gitignoré**. Un backend GCS est
préparé en commentaire dans `terraform/versions.tf` — l'activer (`terraform init
-migrate-state`) est recommandé pour toute reconstruction destinée à durer,
puisque le service account a déjà `roles/storage.admin`.

## Ce qui ne reviendra pas à l'identique

Ces points ne sont pas des oublis : ils sont structurellement non reproductibles.

### Les lignes de base des monitors à seuil dynamique

**C'est la contrainte la plus importante.** Les trois monitors d'anomalie
apprennent le rythme du trafic. Ils sont créés par Terraform, mais **sans
historique** : un monitor `robust` avec `seasonality='daily'` a besoin de
plusieurs jours de données avant d'être fiable. Mesuré sur cette démo, la bande
haute s'est stabilisée entre 8,9 % et 11,3 %, mais seulement après plusieurs
jours de trafic.

**Conséquence : remonter la stack la veille d'une démo ne suffit pas.** Prévoir
au minimum 3 à 4 jours de trafic continu avant de compter sur le déclenchement
natif du monitor de paiement. Le générateur de charge tourne dans le cluster, il
suffit donc de le laisser vivre.

À défaut, la tuile « Part de paiements refusés vs bande apprise » reste
utilisable : elle recalcule `anomalies()` à l'affichage et dessine la bande même
si le monitor n'a pas encore d'historique suffisant pour basculer.

### Les identifiants des dashboards

Les slugs changent à la recréation. L'actuel, `tgq-6hy-vt9`, est écrit en dur
dans `README.md`, `DEMO-DEROULE.md`, `DEMO-SCENARIOS.md` et dans la valeur par
défaut de la variable `graphql_dashboard_id` de `terraform-datadog/variables.tf`.
Après reconstruction, récupérer les nouveaux slugs via
`terraform -chdir=terraform-datadog output` et mettre à jour ces quatre endroits.

Ce littéral existe pour casser un cycle Terraform : le monitor de paiement cite
le dashboard dans son message, et le dashboard affiche l'historique du monitor.

### L'historique de télémétrie

Traces, logs, sessions RUM et résultats Synthetics de septembre 2026 ne sont pas
reconstructibles. Les métriques, elles, restent visibles 15 mois côté Datadog
même après destruction de l'infrastructure — les dashboards sur une fenêtre
passée continuent donc d'afficher la démo réelle.

## Deux blocs à réactiver dans le code

Supprimés le 15/09/2026 avec les monitors, et commentés plutôt que retirés pour
que la reconstruction reste possible. À décommenter **après** avoir réappliqué
`monitors.tf`, sinon Terraform échoue sur une référence à une ressource absente :

| Fichier | Bloc |
|---|---|
| `terraform-datadog/dashboard-graphql.tf` | la tuile `alert_graph_definition` « Historique du monitor à seuil dynamique », dans le groupe vert |
| `terraform-datadog/outputs.tf` | l'output `monitor_ids` |

Un `alert_graph` pointant vers un monitor inexistant affiche une tuile en
erreur — d'où la désactivation plutôt que le maintien en l'état.

## La séquence de reconstruction

```bash
cp .env.example .env    # puis renseigner les valeurs
./scripts/deploy-gke.sh
```

Puis, une fois la private location créée (point 2) :

```bash
terraform -chdir=terraform-datadog init
terraform -chdir=terraform-datadog apply -var="private_location_id=pl:..."
```

Enfin, reporter les nouveaux slugs de dashboards dans les quatre emplacements
listés plus haut, et laisser tourner le trafic plusieurs jours avant de compter
sur les monitors dynamiques.

## Le reste des écarts connus

Inchangés depuis la démo, documentés dans `README.md` et `DEMO-SCENARIOS.md` :
application mobile React Native écrite mais jamais compilée, front en React et
non en UJS, pas d'équivalent au registre de schémas Hive, provider OpenFeature
qui expire au démarrage du BFF, `payment-api` en Node et non en Java.
