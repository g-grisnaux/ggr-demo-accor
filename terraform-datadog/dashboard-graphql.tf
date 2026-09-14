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
          title     = "Apdex"
          autoscale = true
          precision = 2
          request {
            q          = "avg:trace.express.request.apdex{$env,service:${var.bff_service}}"
            aggregator = "avg"
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
          content          = "Fed by DogStatsD from `src/telemetry.js`. Each query is scoped to `service:graphql-bff` on purpose: Datadog only enables the **View traces / View logs / View profiles** pivots when a widget query resolves to a concrete service. Scoping on `env` alone leaves those menu entries greyed out."
          background_color = "gray"
          font_size        = "12"
          text_align       = "left"
          show_tick        = false
        }
      }

      widget {
        timeseries_definition {
          title       = "GraphQL errors by business code"
          show_legend = true
          request {
            q            = "sum:bff.graphql.errors{$env,service:${var.bff_service}}by{error_code}.as_count()"
            display_type = "bars"
            style { palette = "warm" }
          }

          custom_link {
            override_label = "traces"
            link           = "/apm/traces?query=env%3A$env.value%20service%3A${var.bff_service}%20%40graphql.error.code%3A*&agg_m=count"
          }

          custom_link {
            override_label = "logs"
            link           = "/logs?query=env%3A$env.value%20service%3A${var.bff_service}%20%40error_code%3A*"
          }

          custom_link {
            label = "Traces — PAYMENT_DECLINED only"
            link  = "/apm/traces?query=env%3A$env.value%20service%3A${var.bff_service}%20%40graphql.error.code%3APAYMENT_DECLINED&agg_m=count"
          }

          custom_link {
            label = "Traces — INVALID_DATE only"
            link  = "/apm/traces?query=env%3A$env.value%20service%3A${var.bff_service}%20%40graphql.error.code%3AINVALID_DATE&agg_m=count"
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
