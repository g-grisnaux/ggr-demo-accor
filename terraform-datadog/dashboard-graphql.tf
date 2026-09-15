# Dashboard A — BFF GraphQL operation health.
#
# This is the dashboard that answers Hive and CloudWatch at the same time:
# latency per named operation, latency and errors per resolver, and the error
# rate broken down by *business* code rather than one global figure.
#
# Widgets are split between two groups on purpose. Everything in the first group
# runs on APM trace metrics, which the trace-agent produces with no extra
# configuration — those work today and have a week of history. The second group
# runs on the custom DogStatsD metrics from src/telemetry.js, which only start
# filling once datadog.dogstatsd.useHostPort is enabled on the Agent.

resource "datadog_dashboard" "graphql_health" {
  title       = "ALL BFF — GraphQL operation health"
  description = "Latency and errors per GraphQL operation, resolver and business error code. Demo: Accor BFF team."
  layout_type = "ordered"
  reflow_type = "auto"

  template_variable {
    name     = "env"
    prefix   = "env"
    defaults = [var.env]
  }

  template_variable {
    name     = "service"
    prefix   = "service"
    defaults = ["*"]
  }

  widget {
    group_definition {
      title            = "Entry point — what the clients experience"
      layout_type      = "ordered"
      background_color = "vivid_blue"

      widget {
        timeseries_definition {
          title       = "GraphQL endpoint latency (p50 / p95 / p99)"
          show_legend = true

          request {
            # trace.express.request is the duration distribution the trace-agent
            # emits; percentile suffixes come from the same metric family.
            q            = "p50:trace.express.request{$env,service:${var.bff_service}}"
            display_type = "line"
            style { palette = "cool" }
          }
          request {
            q            = "p95:trace.express.request{$env,service:${var.bff_service}}"
            display_type = "line"
            style { palette = "warm" }
          }
          request {
            q            = "p99:trace.express.request{$env,service:${var.bff_service}}"
            display_type = "line"
            style { palette = "orange" }
          }
          yaxis { label = "seconds" }
        }
      }

      widget {
        query_value_definition {
          title      = "Requests / s"
          autoscale  = true
          precision  = 1
          request {
            q          = "sum:trace.express.request.hits{$env,service:${var.bff_service}}.as_rate()"
            aggregator = "avg"
          }
        }
      }

      widget {
        query_value_definition {
          title     = "p99 latency (s)"
          autoscale = true
          precision = 3
          request {
            q          = "p99:trace.express.request{$env,service:${var.bff_service}}"
            aggregator = "avg"
          }
        }
      }

      widget {
        query_value_definition {
          # Replaces an Apdex tile, which stayed empty: Datadog only computes
          # apdex for a service that has a latency threshold configured, and
          # graphql-bff has none. This number is more useful to this audience
          # anyway — it is the share of traffic a global error-rate threshold
          # would alert on while nothing is actually broken.
          # Numérateur et dénominateur comptent tous deux des *opérations* : la
          # métrique de span porte un span par opération en erreur, et
          # execute.hits un span par opération. Le compteur DogStatsD
          # bff.graphql.errors ne convient pas ici — il s'incrémente une fois par
          # erreur du tableau `errors`, donc plusieurs fois pour une seule
          # opération dont plusieurs champs échouent.
          title     = "Business rejections, % of operations"
          autoscale = false
          precision = 1
          custom_unit = "%"
          request {
            q          = "100*sum:${datadog_spans_metric.graphql_business_errors.name}{$env,service:${var.bff_service},error_kind:business}.as_count()/sum:trace.graphql.execute.hits{$env,service:${var.bff_service}}.as_count()"
            aggregator = "avg"
          }
        }
      }

      widget {
        query_value_definition {
          # Le chiffre que surveille le monitor à seuil fixe. Il additionne les
          # rejets métier et les vraies pannes, parce que dd-trace marque le span
          # graphql.execute en erreur dès que la réponse contient des erreurs.
          # Mesuré autour de 9,5% alors que rien n'est cassé.
          title       = "Taux d'erreur GraphQL global"
          autoscale   = false
          precision   = 2
          custom_unit = "%"
          request {
            q          = "100*sum:trace.graphql.execute.errors{$env}.as_count()/sum:trace.graphql.execute.hits{$env}.as_count()"
            aggregator = "avg"
            conditional_formats {
              comparator = ">"
              value      = 5
              palette    = "white_on_yellow"
            }
            conditional_formats {
              comparator = "<="
              value      = 5
              palette    = "white_on_green"
            }
          }
        }
      }

      widget {
        query_value_definition {
          # Le même trafic, dont on a retiré les rejets métier. C'est le taux
          # qu'on veut réellement surveiller : proche de zéro en régime normal,
          # il décolle pendant booking-outage.
          #
          # Même contrainte d'unité que la tuile des rejets métier ci-dessus. La
          # première version divisait des erreurs par des opérations et affichait
          # 2750% pendant booking-outage : une seule searchHotels y déclenche
          # jusqu'à 25 résolutions d'availability qui échouent chacune.
          title       = "Taux de vraies pannes (hors rejets métier)"
          autoscale   = false
          precision   = 2
          custom_unit = "%"
          request {
            q          = "100*sum:${datadog_spans_metric.graphql_business_errors.name}{$env,service:${var.bff_service},!error_kind:business}.as_count()/sum:trace.graphql.execute.hits{$env,service:${var.bff_service}}.as_count()"
            aggregator = "avg"
            conditional_formats {
              comparator = ">"
              value      = 1
              palette    = "white_on_red"
            }
            conditional_formats {
              comparator = "<="
              value      = 1
              palette    = "white_on_green"
            }
          }
        }
      }

      widget {
        timeseries_definition {
          # Le graphe qui porte l'argument : deux lignes, l'une plate autour de
          # 9% qui ne veut rien dire, l'autre à zéro qui bouge seulement quand
          # quelque chose casse vraiment.
          title       = "Taux global vs vraies pannes — pourquoi un seuil unique échoue"
          show_legend = true
          request {
            q            = "100*sum:trace.graphql.execute.errors{$env}.as_count()/sum:trace.graphql.execute.hits{$env}.as_count()"
            display_type = "line"
            style { palette = "warm" }
          }
          request {
            q            = "100*sum:${datadog_spans_metric.graphql_business_errors.name}{$env,service:${var.bff_service},!error_kind:business}.as_count()/sum:trace.graphql.execute.hits{$env,service:${var.bff_service}}.as_count()"
            display_type = "line"
            style { palette = "purple" }
          }
          yaxis { label = "%" }

          # Le seuil de 5% du monitor, matérialisé : on voit d'un coup d'oeil que
          # la ligne globale est au-dessus en permanence.
          marker {
            display_type = "error dashed"
            value        = "y = 5"
            label        = "seuil fixe 5%"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "HTTP status mix — 402 is a declined payment, not an outage"
          show_legend = true
          request {
            q            = "sum:trace.express.request.hits.by_http_status{$env}by{http.status_code}.as_count()"
            display_type = "bars"
            style { palette = "dog_classic" }
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title            = "Paiement — détection d'anomalie"
      layout_type      = "ordered"
      background_color = "vivid_green"

      widget {
        note_definition {
          content          = "La bande grise est apprise, pas écrite. Elle est calculée à l'affichage par la même expression `anomalies()` que le monitor — donc **elle se dessine même si le monitor n'a pas encore basculé**, ce qui est ce qu'on veut en démo.\n\nMesuré sur 4h : borne haute entre 8,7% et 11,3% pour une médiane réelle à 2,5%. Le scénario `payment-storm` pousse à 45%, soit 4x au-dessus de la bande."
          background_color = "green"
          font_size        = "12"
          text_align       = "left"
          show_tick        = false
        }
      }

      widget {
        timeseries_definition {
          # C'est la tuile qui rend l'anomalie visible. Une timeseries dont la
          # requête utilise anomalies() fait dessiner la bande par Datadog et
          # peindre en rouge la partie hors bande. Contrairement au statut du
          # monitor, ce rendu ne dépend pas de l'horloge d'évaluation : il est
          # recalculé sur la fenêtre affichée, donc rejouable sur un créneau
          # passé si la tempête du jour arrive trop tard.
          title       = "Part de paiements refusés vs bande apprise"
          show_legend = true
          request {
            q            = "anomalies(sum:trace.express.request.hits.by_http_status{$env,service:payment-api,http.status_code:402}.as_count() / sum:trace.express.request.hits{$env,service:payment-api}.as_count(), 'robust', 2, direction='above', interval=60, alert_window='last_5m', seasonality='daily', count_default_zero='true')"
            display_type = "line"
            style { palette = "dog_classic" }
          }
          yaxis { label = "part des autorisations" }
        }
      }

      # Tuile d'historique du monitor, désactivée au décommissionnement du
      # 15/09/2026 : les monitors ont été supprimés avec l'infrastructure, et un
      # alert_graph pointant sur un monitor inexistant affiche une tuile en
      # erreur. Les définitions restent dans monitors.tf — réactiver ce bloc
      # après avoir réappliqué les monitors. Voir RESTORE.md.
      #
      # widget {
      #   alert_graph_definition {
      #     title    = "Historique du monitor à seuil dynamique"
      #     alert_id = datadog_monitor.dynamic_payment_declines.id
      #     viz_type = "timeseries"
      #   }
      # }

      widget {
        timeseries_definition {
          title       = "Le même trafic sans anomalies() — ce qu'on voyait avant"
          show_legend = true
          request {
            q            = "100*sum:trace.express.request.hits.by_http_status{$env,service:payment-api,http.status_code:402}.as_count()/sum:trace.express.request.hits{$env,service:payment-api}.as_count()"
            display_type = "line"
            style { palette = "warm" }
          }
          yaxis { label = "%" }
        }
      }
    }
  }

  widget {
    group_definition {
      title            = "Per resolver — the field-level view read in Hive today"
      layout_type      = "ordered"
      background_color = "vivid_purple"

      widget {
        timeseries_definition {
          title       = "Resolver latency (p95) by resolver"
          show_legend = true
          request {
            q            = "p95:trace.graphql.resolve{$env}by{resource_name}"
            display_type = "line"
            style { palette = "purple" }
          }
          yaxis { label = "seconds" }
        }
      }

      widget {
        toplist_definition {
          title = "Slowest resolvers (avg)"
          request {
            q = "top(avg:trace.graphql.resolve{$env}by{resource_name}, 10, 'mean', 'desc')"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Errors per resolver"
          show_legend = true
          request {
            q            = "sum:trace.graphql.resolve.errors{$env}by{resource_name}.as_count()"
            display_type = "bars"
            style { palette = "warm" }
          }
        }
      }

      widget {
        note_definition {
          content          = "The resolver error count includes **business rejections** — an invalid date is counted here exactly like a real failure. That is the CloudWatch problem in miniature, and the next group is the answer to it."
          background_color = "yellow"
          font_size        = "14"
          text_align       = "left"
          show_tick        = false
        }
      }
    }
  }

  widget {
    group_definition {
      title            = "Per business error code — the alertable dimension"
      layout_type      = "ordered"
      background_color = "vivid_orange"

      widget {
        note_definition {
          content          = "Two views of the same information, on purpose.\n\nThe **span-based** widget is computed from the traces themselves. The **DogStatsD** widget is the counter the anomaly monitor runs on — cheaper at high cardinality, but a standalone timeseries with no link back to individual requests. Worth explaining as an architecture trade-off: the counter for alerting, the span metric for drilling in.\n\n**Right-click either widget** for the trace and log links, including one per business error code. Those links are wired explicitly: Datadog greys out its own trace pivot on these widgets and the cause could not be established, so every link here was verified by hand instead."
          background_color = "gray"
          font_size        = "12"
          text_align       = "left"
          show_tick        = false
        }
      }

      widget {
        timeseries_definition {
          title       = "Errors by business code (span-based)"
          show_legend = true
          request {
            # Computed from the spans rather than from a StatsD counter, which
            # is the honest architecture for a drill-in view. Note that this did
            # NOT make Datadog enable its native trace pivot on the widget —
            # hence the explicit custom links below.
            q            = "sum:${datadog_spans_metric.graphql_business_errors.name}{$env,service:${var.bff_service}}by{error_code}.as_count()"
            display_type = "bars"
            style { palette = "warm" }
          }

          custom_link {
            override_label = "traces"
            link           = "${local.trace_link_base}%40graphql.error.code%3A*"
          }

          custom_link {
            override_label = "logs"
            link           = "${local.log_link_base}%40error_code%3A*"
          }

          dynamic "custom_link" {
            for_each = local.business_error_codes
            content {
              label = "Traces — ${custom_link.value}"
              link  = "${local.trace_link_base}%40graphql.error.code%3A${custom_link.value}"
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "GraphQL errors by business code (DogStatsD) — what the monitor alerts on"
          show_legend = true
          request {
            q            = "sum:bff.graphql.errors{$env,service:${var.bff_service}}by{error_code}.as_count()"
            display_type = "bars"
            style { palette = "warm" }
          }

          # Same links as the span-based widget above, so whichever of the two
          # is on screen during the demo behaves identically.
          custom_link {
            override_label = "traces"
            link           = "${local.trace_link_base}%40graphql.error.code%3A*"
          }

          custom_link {
            override_label = "logs"
            link           = "${local.log_link_base}%40error_code%3A*"
          }

          dynamic "custom_link" {
            for_each = local.business_error_codes
            content {
              label = "Traces — ${custom_link.value}"
              link  = "${local.trace_link_base}%40graphql.error.code%3A${custom_link.value}"
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Errors by kind — BUSINESS vs UPSTREAM vs SERVER"
          show_legend = true
          request {
            q            = "sum:bff.graphql.errors{$env,service:${var.bff_service}}by{error_kind}.as_count()"
            display_type = "area"
            style { palette = "dog_classic" }
          }
        }
      }

      widget {
        toplist_definition {
          title = "Which upstream caused the error"
          request {
            q = "top(sum:bff.graphql.errors{$env,service:${var.bff_service}}by{upstream_service}.as_count(), 10, 'sum', 'desc')"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Operations by client name and version"
          show_legend = true
          request {
            q            = "sum:bff.graphql.operation{$env,service:${var.bff_service}}by{client_name,client_version}.as_count()"
            display_type = "area"
            style { palette = "cool" }
          }
        }
      }

      widget {
        toplist_definition {
          title = "Deprecated field usage by client version — when can thumbnailUrl go?"
          request {
            q = "top(sum:bff.graphql.field.usage{$env,service:${var.bff_service},deprecated:true}by{field,client_version}.as_count(), 10, 'sum', 'desc')"
          }
        }
      }
    }
  }
}
