# Déroulé de démo — équipe BFF Accor

Script minuté, clic par clic, avec ce qu'il y a à dire. Durée visée : 25 à 30
minutes hors questions.

Les libellés exacts des boutons de l'UI Datadog n'ont pas pu être testés depuis
l'environnement de préparation. Les chemins sont donnés tels qu'ils existent
aujourd'hui ; fais un passage à blanc la veille pour les confirmer.

---

## Liens à ouvrir en onglets avant de commencer

| Onglet | Lien |
|---|---|
| 1 — Monitors | `https://app.datadoghq.com/monitors/manage` filtré sur `ALL BFF` |
| 2 — Dashboard opérations | <https://app.datadoghq.com/dashboard/tgq-6hy-vt9> |
| 3 — Dashboard chaîne | <https://app.datadoghq.com/dashboard/h7a-fyg-da5> |
| 4 — APM Service Map | `APM → Service Map`, filtré `env:ggr-demo-accor-260907` |
| 5 — Terminal | avec le dépôt, prêt à lancer `scripts/scenario.sh` |

---

## T-15 min — préparation

```bash
scripts/scenario.sh status     # doit être tout à false / 0.04
scripts/scenario.sh reset      # si besoin
```

Vérifie sur le dashboard opérations que les trois graphes du groupe
« Per business error code » ont des données. Si le groupe est vide, la
télémétrie métier ne remonte pas et il faut le savoir **avant**, pas devant eux.

**T-5 min, juste avant d'entrer** :

```bash
kubectl exec -n ggr-demo-accor deploy/payment-api -- \
  curl -sS -X POST "http://localhost:8083/admin/scenario?declineRate=1.0"
```

**Utilise 1.0, pas le `payment-storm` à 45 %.** Raison mesurée : à 55 % le
monitor dynamique a mis 9 minutes à basculer au premier essai, et pas du tout au
troisième. À 100 % l'écart est sans ambiguïté. Compte tout de même 5 minutes.

---

## Acte 1 — « l'alerte que vous avez appris à ignorer » (5 min)

### Clics

1. **Onglet 1 — Monitors.** La liste montre déjà la comparaison : un
   `(seuil fixe)` et trois `(seuil dynamique)`. Ouvre
   `[ALL BFF] (seuil fixe) Taux d'erreur GraphQL global > 5%`.
2. Montre l'historique du monitor : rouge, en continu.

### Ce que tu dis

> « Avant de vous montrer quoi que ce soit de Datadog, je veux partir de quelque
> chose que vous connaissez. Voilà un monitor sur le taux d'erreur global de
> l'API GraphQL, seuil à 5 %. Il est rouge. Il est rouge depuis des jours.
>
> Ma question : qu'est-ce qui est cassé ? »

Laisse le silence. Puis :

> « Rien. Absolument rien n'est cassé. »

3. **Clique sur le lien du dashboard dans le message du monitor.** Tu arrives
   sur le dashboard opérations.
4. Descends jusqu'au groupe orange **« Per business error code »**.
5. Pointe le graphe **« Errors by business code »**.

> « Voilà pourquoi il est rouge. Ce chiffre additionne deux choses de nature
> complètement différente : des rejets métier — chambre complète, tarif expiré,
> carte refusée — et de vraies pannes. dd-trace marque le span `graphql.execute`
> en erreur dès que la réponse GraphQL contient des erreurs, sans distinguer les
> deux.
>
> Ici le fond est dominé par des rejets métier, et il suffit à dépasser 5 % en
> permanence. Chez vous le mix sera différent, vos volumes aussi. Mais la
> propriété est la même : dès qu'il existe un fond de rejets métier non nul, un
> seuil global est soit toujours rouge, soit réglé si haut qu'il rate les vraies
> pannes. Il n'y a pas de bonne valeur, parce que le problème est la dimension
> manquante, pas le seuil.
>
> **Quel est votre taux de rejets métier aujourd'hui ?** »

Cette dernière question est volontaire : elle transforme le chiffre en sujet de
découverte, et elle t'évite de prétendre que 9 % de dates invalides serait
réaliste — ça ne l'est pas, c'est une propriété de mon générateur de charge, et
un ingénieur de leur équipe le verra en trois secondes.

6. Remonte au groupe bleu, pointe la tuile **« Business rejections, % of
   operations »**.

> « Ce chiffre, autour de 9 %, c'est la part du trafic qui est un rejet métier
> légitime. Un seuil global à 5 % est structurellement condamné à être rouge.
>
> C'est l'alerte que plus personne ne regarde. Et le vrai coût n'est pas le
> bruit : c'est que le jour où quelque chose casse vraiment, cette alerte ne
> vous apprend rien parce qu'elle était déjà rouge. »

**Aucune investigation dans cet acte.** C'est le message.

---

## Acte 2 — « l'alerte qui veut dire quelque chose » (8 min)

### Clics

1. **Retour onglet 1 — Monitors.** Ouvre
   `[ALL BFF] (seuil dynamique) Refus de paiement anormaux`.
2. Il est en **Alert**. Aucun seuil n'y est écrit.

### Ce que tu dis

> « Même stack, même moment. Ce monitor-là vient de passer au rouge. La
> différence : il ne me dit pas "le taux d'erreur monte", il me dit *quelle
> règle métier* échoue. `PAYMENT_DECLINED`.
>
> Et regardez bien : le monitor précédent est rouge lui aussi, en ce moment
> même. Mais il l'était déjà. Il n'a aucun delta, donc aucune information. Seul
> celui-ci a bougé, et en bougeant il m'a donné le nom de l'équipe à réveiller
> — avant que j'aie ouvert une seule trace. »

3. Montre le graphe d'anomalie du monitor : la bande de référence et le
   dépassement.

> « C'est de la détection d'anomalie, pas un seuil. Il a appris le rythme
> journalier sur plusieurs jours. Personne n'a écrit "45 %" nulle part. »

4. **Clique le lien du dashboard dans le message.**
5. Groupe orange, graphe **« Errors by business code »** : `payment_declined`
   décolle, `invalid_date` ne bouge pas.

> « Et voilà ce qu'un taux global écrasait : deux signaux indépendants. Celui de
> gauche est un problème de partenaire de paiement. Celui de droite est du bruit
> client. Ils n'ont ni la même cause, ni le même propriétaire, ni la même
> urgence. »

6. Pointe la toplist **« Which upstream caused the error »**.

> « Et même le service amont responsable est déjà là, sans ouvrir de trace. »

### Le pivot vers les traces

7. **Clic droit sur le graphe « Errors by business code »** → dans le menu,
   choisis **« Traces — PAYMENT_DECLINED »**.

> « Je passe de la métrique aux requêtes réelles, en gardant le scope. »

8. Ouvre une trace.

> « Une seule requête GraphQL. Voilà l'arbre complet : le BFF, puis
> `booking-api`, puis `payment-api`. C'est votre question de départ — quelle API
> REST est fautive — et la réponse est dans l'arbre, pas dans un log. »

9. Clique sur le span `payment-api`, montre le tag `decline_reason`.
10. **Onglet « Logs » de la trace.**

> « Cinq logs, un par service traversé, tous rattachés à cette requête
> précise. Rien à configurer : les tracers injectent le `trace_id` dans le log
> JSON. »

11. Descends sur un span SQL, clic droit → **View query in DBM** (ou l'entrée
    équivalente).

> « Et jusqu'au plan d'exécution de la requête SQL, parce que le tracer a
> injecté le contexte de trace dans un commentaire SQL. »

### Transition

```bash
scripts/scenario.sh reset
scripts/scenario.sh booking-outage
```

> « Je remets à zéro et je déclenche autre chose. »

---

## Acte 3 — l'enquête (10 min)

Attends 2 à 3 minutes que les échecs s'accumulent.

### Clics et discours

1. **Onglet 1 — Monitors.** Le *même* monitor métier est repassé en Alert.

> « Même alerte. Mais le code n'est plus `PAYMENT_DECLINED`, c'est
> `UPSTREAM_UNAVAILABLE`. Un service amont ne répond pas. »

2. **Le piège, à poser explicitement.** Retourne sur une trace *saine* d'avant
   (ou l'onglet 3, dashboard chaîne, graphe p95 par service).

> « Avant de chercher, une question. Sur une réservation qui marche,
> `payment-api` consomme 120 millisecondes sur les 180 de l'opération. C'est de
> loin le plus lent. Si je vous demande qui est coupable, vous répondez quoi ? »

Laisse-les répondre « le paiement ».

> « C'est ce que répondrait n'importe quel réflexe du genre "montre-moi le
> service le plus lent". Et c'est faux. »

3. **Onglet 2**, groupe orange → clic droit → **« Traces —
   UPSTREAM_UNAVAILABLE »**.
4. Ouvre une trace en échec. **Montre l'arbre.**

> « Regardez ce qu'il n'y a pas. Il n'y a aucun span `payment-api`. Le paiement
> n'est pas lent : il n'est jamais appelé. »

5. **Onglet Logs de la trace**, montre la ligne de `booking-api`.

> « Et `booking-api` le dit lui-même : *availability lookup failed, read timed
> out, timeout 5 secondes*, contre `hotel-search-api` sur le port 8081. »

6. **Onglet 3 — dashboard chaîne**, graphe **« Slowest endpoints —
   hotel-search-api »**.

> « Et voilà la cause réelle : l'endpoint de disponibilité de
> `hotel-search-api`, qui passe de 3 millisecondes à plus de 6 secondes.
>
> Le symptôme est sur une mutation GraphQL. La cause est deux sauts plus bas,
> dans un service que personne n'aurait regardé, et le suspect évident est
> innocent. La seule chose qui permet de le prouver, c'est une trace complète —
> parce que la preuve est une *absence* de span. »

### Bits Investigation

7. Depuis le monitor, lance une investigation Bits avec :

> Bookings are failing for users. Find the root cause of this alert and tell me
> which service is responsible. Explain what evidence you used.

Ou, pour tester le piège :

> Bookings are failing. I think the payment provider is down — can you confirm?

Confronte la réponse aux cinq constats de
[BITS-INVESTIGATION.md](BITS-INVESTIGATION.md). Si Bits se trompe, dis-le —
c'est plus crédible que de le masquer, et le chemin manuel est juste derrière.

### Remise à zéro

```bash
scripts/scenario.sh booking-outage-off
```

---

## Clôture (3 min)

**Onglet 4 — Service Map.**

> « Trois causes complètement différentes en vingt minutes. Un seul monitor a
> sonné pour les trois, et à chaque fois il m'a donné le nom de la règle métier
> qui échouait. C'est ça, la différence avec un seuil global.
>
> Sur vos sujets précis : la latence par resolver et par champ, c'est ce que
> vous lisez dans Hive aujourd'hui, et c'est là — sans agent supplémentaire.
> L'usage des champs dépréciés par version de client aussi. Les dashboards que
> je viens de vous montrer sont en Terraform, versionnés, donc le sujet
> "maintenir CloudWatch en Terraform coûte cher" devient un sujet de revue de
> code. »

Points à ne pas survendre, à dire si la question vient :

- **Mobile RUM** : pas démontrable sur cette stack, il n'y a pas d'app mobile.
  C'est un argumentaire, pas une démo.
- **Ce front est en React**, le site ALL est en UJS. L'histoire RUM se
  transpose, le framework non.
- **Ce n'est pas un remplacement de Hive à l'identique** : registre de schéma
  et suivi des changements de schéma ne sont pas couverts.
- **Feature Flags** : le provider ne s'initialise pas sur cette stack, ne le
  mets pas au programme.

---

## Plans B

| Si… | Alors |
|---|---|
| le monitor métier n'est pas rouge à l'acte 2 | Il met ~4 min. Occupe avec le groupe « Per resolver » du dashboard, puis reviens. En dernier recours, `declineRate=1.0` via `scenario.sh` pour un refus garanti. |
| le clic droit ne propose pas les liens traces | Utilise l'onglet APM directement : `env:ggr-demo-accor-260907 service:graphql-bff @graphql.error.code:PAYMENT_DECLINED` |
| la liste des traces affiche tout en `ok` | C'est normal et c'est un argument : une opération GraphQL en échec renvoie HTTP 200 par spécification. Filtre sur `@graphql.error.code:*`, jamais sur `status:error`. |
| le groupe « business error code » est vide | La métrique DogStatsD ne remonte pas. Bascule sur le groupe « Per resolver », qui tourne sur les métriques de trace et n'en dépend pas. |
| Bits Investigate n'est pas disponible | Tout l'acte 3 se déroule à la main. C'est le chemin que la fiche décrit de toute façon. |
