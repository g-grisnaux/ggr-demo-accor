# Monitors — the fixed-threshold versus dynamic-threshold comparison.
#
# This is what the BFF team asked to see side by side, so the names carry the
# distinction explicitly: the monitor list itself shows "(seuil fixe)" next to
# "(seuil dynamique)" before anyone clicks anything.
#
# The algorithm chosen for each dynamic monitor follows the history actually
# available behind its signal, which is not the same for all of them:
#
#   - Declined payments ride on HTTP 402 from payment-api, an APM trace metric
#     with ~7 days behind it. That supports `agile` with daily seasonality: it
#     learns the day/night rhythm and tolerates level shifts.
#   - The per-business-code monitor rides on the DogStatsD metrics, which only
#     started flowing when the Agent's dogstatsd hostPort was opened. With a few
#     hours of history a seasonal algorithm has nothing to learn, so it uses
#     `basic` — a rolling band, no seasonality assumed.

# --- The fixed threshold: what they have on CloudWatch today ----------------

resource "datadog_monitor" "fixed_global_error_rate" {
  name    = "[ALL BFF] (seuil fixe) Taux d'erreur GraphQL global > 5%"
  type    = "query alert"
  message = <<-EOT
    Le taux d'erreur GraphQL global dépasse 5%.

    Ce monitor est le point de comparaison, pas un modèle à suivre. Le ratio
    qu'il surveille additionne deux choses de nature différente : des rejets
    métier — chambre complète, tarif expiré, carte refusée — et de vraies pannes
    d'infrastructure. dd-trace marque le span `graphql.execute` en erreur dès
    que la réponse GraphQL contient des erreurs, sans distinguer les deux.

    Conséquence : le seuil est soit trop bas et l'alerte est rouge en
    permanence, soit assez haut pour être silencieuse et il rate les pannes.
    Il n'existe pas de bonne valeur, parce que le problème est la dimension
    manquante, pas le seuil.

    La réponse : [ALL BFF — GraphQL operation health](https://app.${var.datadog_site}/dashboard/${datadog_dashboard.graphql_health.id}),
    groupe "Per business error code".
    Notify: @${var.notification_handle}
  EOT

  query = "sum(last_10m):sum:trace.graphql.execute.errors{env:${var.env}}.as_count() / sum:trace.graphql.execute.hits{env:${var.env}}.as_count() > 0.05"

  monitor_thresholds {
    critical = 0.05
    warning  = 0.03
  }

  notify_no_data      = false
  require_full_window = false
  renotify_interval   = 0

  tags = ["env:${var.env}", "demo:accor-bff", "seuil:fixe", "purpose:counter-example", "managed:terraform"]
}

# --- The dynamic threshold on the same funnel, one layer down ----------------

resource "datadog_monitor" "dynamic_payment_declines" {
  name    = "[ALL BFF] (seuil dynamique) Refus de paiement anormaux"
  type    = "query alert"
  message = <<-EOT
    La part de paiements refusés sort de sa bande habituelle.

    Aucun seuil n'est écrit ici. Le monitor a appris le rythme des refus sur
    plusieurs jours — nuits, heures creuses, pics — et alerte sur l'écart à ce
    rythme. Un taux de refus de 4% est normal pour un tunnel de paiement ; ce
    qui compte est qu'il passe à 45%.

    Le signal est le HTTP 402 renvoyé par `payment-api`. À ce niveau le code de
    statut a un sens : 402 *est* un refus de paiement. C'est au niveau GraphQL
    qu'il n'en a plus, puisqu'une opération en échec répond 200 — d'où la
    taxonomie d'erreurs métier propre au BFF.

    Pour investiguer : [ALL BFF — GraphQL operation health](https://app.${var.datadog_site}/dashboard/${datadog_dashboard.graphql_health.id}),
    puis clic droit sur le graphe des codes métier → "Traces — PAYMENT_DECLINED".
    Notify: @${var.notification_handle}
  EOT

  # Ratio rather than a raw count, so a change in traffic volume cannot look
  # like a change in decline behaviour.
  #
  # `robust`, not `agile`. agile is designed to adapt quickly to level shifts,
  # which is exactly what a decline storm is: rehearsing the scenario three
  # times taught it the storm was normal and it stopped firing. robust holds its
  # band and treats a regime change as the anomaly it is. Measured: with agile
  # the monitor fired after 9 minutes on the first run and not at all on the
  # third, at an 83% decline rate.
  query = "avg(last_15m):anomalies(sum:trace.express.request.hits.by_http_status{env:${var.env},service:payment-api,http.status_code:402}.as_count() / sum:trace.express.request.hits{env:${var.env},service:payment-api}.as_count(), 'robust', 2, direction='above', interval=60, alert_window='last_5m', seasonality='daily', count_default_zero='true') >= 0.5"

  monitor_thresholds {
    critical          = 0.5
    critical_recovery = 0.2
  }

  notify_no_data      = false
  require_full_window = false
  renotify_interval   = 0

  tags = ["env:${var.env}", "demo:accor-bff", "seuil:dynamique", "team:payment", "managed:terraform"]
}

# --- The dynamic threshold per business code, for act three -----------------

resource "datadog_monitor" "dynamic_business_error_code" {
  name    = "[ALL BFF] (seuil dynamique) Code d'erreur métier anormal"
  type    = "query alert"
  message = <<-EOT
    Un code d'erreur métier précis sort de sa bande habituelle.

    C'est ce qu'un taux d'erreur global ne peut pas donner. `INVALID_DATE` est
    un fond de saisies clients ; `PAYMENT_DECLINED` qui bouge est un problème de
    partenaire ; `UPSTREAM_UNAVAILABLE` est une panne de service aval. Trois
    causes, trois propriétaires, trois urgences — et l'alerte nomme laquelle.

    Départ : [ALL BFF — GraphQL operation health](https://app.${var.datadog_site}/dashboard/${datadog_dashboard.graphql_health.id}),
    groupe "Per business error code". Les liens traces y sont par code.
    Notify: @${var.notification_handle}
  EOT

  # basic: the underlying DogStatsD metric has only a few hours of history, so
  # there is no season to learn yet. Worth revisiting to agile/daily once a week
  # of data exists.
  query = "avg(last_30m):anomalies(sum:bff.graphql.errors{env:${var.env}} by {error_code}.as_count(), 'basic', 3, direction='above', interval=60, alert_window='last_15m', count_default_zero='true') >= 0.5"

  monitor_thresholds {
    critical          = 0.5
    critical_recovery = 0.2
  }

  notify_no_data      = false
  require_full_window = false
  renotify_interval   = 0

  tags = ["env:${var.env}", "demo:accor-bff", "seuil:dynamique", "team:bff", "managed:terraform"]
}

# --- Per-resolver, kept out of the demo flow but useful ---------------------

resource "datadog_monitor" "dynamic_resolver_errors" {
  name    = "[ALL BFF] (seuil dynamique) Erreurs anormales sur un resolver"
  type    = "query alert"
  message = <<-EOT
    Le taux d'erreur d'un resolver GraphQL sort de sa bande habituelle.

    Volontairement par resolver et non global : un pic sur
    `mutation.createbooking` et un pic sur `query.searchhotels` n'ont ni la même
    cause ni le même propriétaire.

    [ALL BFF — GraphQL operation health](https://app.${var.datadog_site}/dashboard/${datadog_dashboard.graphql_health.id})
    puis [BFF to REST chain latency](https://app.${var.datadog_site}/dashboard/${datadog_dashboard.bff_rest_chain.id})
    Notify: @${var.notification_handle}
  EOT

  query = "avg(last_1h):anomalies(sum:trace.graphql.resolve.errors{env:${var.env}} by {resource_name}.as_count(), 'agile', 2, direction='above', interval=120, alert_window='last_30m', seasonality='daily', count_default_zero='true') >= 0.5"

  monitor_thresholds {
    critical          = 0.5
    critical_recovery = 0.2
  }

  notify_no_data      = false
  require_full_window = false
  renotify_interval   = 0

  tags = ["env:${var.env}", "demo:accor-bff", "seuil:dynamique", "team:bff", "managed:terraform"]
}
