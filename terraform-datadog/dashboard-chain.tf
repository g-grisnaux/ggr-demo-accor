# Dashboard B — where the time goes across the BFF → REST chain.
#
# This is the "which API is slowing my GraphQL query" dashboard. Every widget
# here runs on APM trace metrics and the PostgreSQL integration, so it works
# without the DogStatsD fix and already has a week of history.

resource "datadog_dashboard" "bff_rest_chain" {
  title       = "ALL BFF — BFF to REST chain latency"
  description = "Latency per downstream REST service and endpoint, SQL cost, and container resources. Demo: Accor BFF team."
  layout_type = "ordered"
  reflow_type = "auto"

  template_variable {
    name     = "env"
    prefix   = "env"
    defaults = [var.env]
  }

  widget {
    group_definition {
      title            = "Latency per service in the chain"
      layout_type      = "ordered"
      background_color = "vivid_blue"

      widget {
        timeseries_definition {
          title       = "p95 per service — each integration reports its own metric"
          show_legend = true

          # One request per framework: Node/Express for the BFF and payment,
          # Flask for booking, Servlet for the Java search service. Putting them
          # on one graph is what makes the chain readable at a glance.
          request {
            q            = "p95:trace.express.request{$env}by{service}"
            display_type = "line"
            style { palette = "cool" }
          }
          request {
            q            = "p95:trace.flask.request{$env}by{service}"
            display_type = "line"
            style { palette = "purple" }
          }
          request {
            q            = "p95:trace.servlet.request{$env}by{service}"
            display_type = "line"
            style { palette = "orange" }
          }
          yaxis { label = "seconds" }
        }
      }

      widget {
        toplist_definition {
          title = "Slowest REST endpoints across every downstream service"
          request {
            q = "top(avg:trace.flask.request{$env}by{resource_name}, 5, 'mean', 'desc')"
          }
        }
      }

      widget {
        toplist_definition {
          title = "Slowest endpoints — hotel-search-api"
          request {
            q = "top(avg:trace.servlet.request{$env}by{resource_name}, 5, 'mean', 'desc')"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Throughput per service"
          show_legend = true
          request {
            q            = "sum:trace.express.request.hits{$env}by{service}.as_rate()"
            display_type = "area"
            style { palette = "cool" }
          }
          request {
            q            = "sum:trace.flask.request.hits{$env}by{service}.as_rate()"
            display_type = "area"
            style { palette = "purple" }
          }
          request {
            q            = "sum:trace.servlet.request.hits{$env}by{service}.as_rate()"
            display_type = "area"
            style { palette = "orange" }
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title            = "Database — Database Monitoring"
      layout_type      = "ordered"
      background_color = "vivid_green"

      widget {
        timeseries_definition {
          title       = "Query throughput"
          show_legend = true
          request {
            q            = "sum:postgresql.queries.count{$env}.as_rate()"
            display_type = "bars"
            style { palette = "green" }
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Time spent in queries"
          show_legend = true
          request {
            q            = "avg:postgresql.queries.time{$env}"
            display_type = "line"
            style { palette = "green" }
          }
        }
      }

      widget {
        note_definition {
          content          = "With `DD_DBM_PROPAGATION_MODE=full`, every statement reaching Postgres carries a `traceparent` comment. That is what lets a slow span jump straight to its own query sample and execution plan — the plan flip from Index Scan to Seq Scan in the latency scenario is visible there."
          background_color = "green"
          font_size        = "12"
          text_align       = "left"
          show_tick        = false
        }
      }
    }
  }

  widget {
    group_definition {
      title            = "Runtime — is it the code or the container"
      layout_type      = "ordered"
      background_color = "vivid_yellow"

      widget {
        timeseries_definition {
          title       = "CPU per deployment"
          show_legend = true
          request {
            q            = "avg:kubernetes.cpu.usage.total{$env}by{kube_deployment}"
            display_type = "line"
            style { palette = "dog_classic" }
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Memory per deployment"
          show_legend = true
          request {
            q            = "avg:kubernetes.memory.usage{$env}by{kube_deployment}"
            display_type = "line"
            style { palette = "cool" }
          }
        }
      }

      widget {
        note_definition {
          content          = "Continuous Profiling is active on all four services. When the latency scenario is on, `RankingService.relevanceScore` dominates the hotel-search-api flame graph — a CPU cost an endpoint latency metric can see but cannot explain."
          background_color = "yellow"
          font_size        = "12"
          text_align       = "left"
          show_tick        = false
        }
      }
    }
  }
}
