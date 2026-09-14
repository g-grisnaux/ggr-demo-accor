# Anomaly detection monitors.
#
# Two of them, on purpose, because they have very different amounts of history
# behind them and that changes which algorithm is honest to use.
#
#   - The resolver-error monitor runs on APM trace metrics, which have been
#     flowing for ~7 days. That supports `agile` with daily seasonality: it
#     learns the day/night rhythm and tolerates level shifts.
#   - The business-code monitor runs on the DogStatsD metrics, which only start
#     filling when datadog.dogstatsd.useHostPort is enabled. With a day or less
#     of history, a seasonal algorithm has nothing to learn from, so it uses
#     `basic` — no seasonality, just a rolling band. It will still catch the
#     4% -> 45% decline spike, which is what the demo needs.

resource "datadog_monitor" "resolver_error_anomaly" {
  name    = "[ALL BFF] Anomalous error rate on a GraphQL resolver"
  type    = "query alert"
  message = <<-EOT
    The error rate on a GraphQL resolver has left its usual band.

    This monitor is deliberately scoped per resolver rather than to a global
    GraphQL error rate: a spike on `mutation.createbooking` and a spike on
    `query.searchhotels` have different causes and different owners.

    Start here: [ALL BFF — GraphQL operation health](https://app.${var.datadog_site}/dashboard/${datadog_dashboard.graphql_health.id})
    Then, for where the time goes across the chain: [BFF to REST chain latency](https://app.${var.datadog_site}/dashboard/${datadog_dashboard.bff_rest_chain.id})

    Open a failing trace from the per-resolver widget and follow it into the
    downstream REST service. Notify: @${var.notification_handle}
  EOT

  # anomalies() with agile: seasonal, tolerant of level shifts. 7 days of
  # history is enough for the daily season; weekly would need several weeks.
  query = "avg(last_1h):anomalies(sum:trace.graphql.resolve.errors{env:${var.env}} by {resource_name}.as_count(), 'agile', 2, direction='above', interval=120, alert_window='last_30m', seasonality='daily', count_default_zero='true') >= 0.5"

  monitor_thresholds {
    critical          = 0.5
    critical_recovery = 0.2
  }

  notify_no_data    = false
  require_full_window = false
  renotify_interval = 0

  tags = ["env:${var.env}", "demo:accor-bff", "team:bff", "managed:terraform"]
}

resource "datadog_monitor" "business_error_code_anomaly" {
  name    = "[ALL BFF] Anomalous rate on a business error code"
  type    = "query alert"
  message = <<-EOT
    A specific business error code has left its usual band.

    This is the monitor that a global GraphQL error rate cannot give you.
    `INVALID_DATE` is a steady background of client mistakes; `PAYMENT_DECLINED`
    moving is a partner problem. They must never share an alert.

    Start here: [ALL BFF — GraphQL operation health](https://app.${var.datadog_site}/dashboard/${datadog_dashboard.graphql_health.id}) — the
    "Per business error code" group at the bottom.

    From that widget, the context menu offers **View traces** and **View logs**,
    which carry the env and service scope straight into APM and Logs.
    Notify: @${var.notification_handle}
  EOT

  # basic: no seasonality assumed. Correct while the metric has little history,
  # and worth revisiting to 'agile'/'daily' once a week of data exists.
  query = "avg(last_30m):anomalies(sum:bff.graphql.errors{env:${var.env}} by {error_code}.as_count(), 'basic', 3, direction='above', interval=60, alert_window='last_15m', count_default_zero='true') >= 0.5"

  monitor_thresholds {
    critical          = 0.5
    critical_recovery = 0.2
  }

  # This metric is empty until the DogStatsD hostPort fix lands, and an alert on
  # missing data would just be noise in the meantime.
  notify_no_data      = false
  require_full_window = false
  renotify_interval   = 0

  tags = ["env:${var.env}", "demo:accor-bff", "team:bff", "managed:terraform"]
}

# A plain threshold monitor alongside the anomaly ones. It is the contrast the
# demo needs: this is what they have on CloudWatch today, and it either screams
# during the normal invalid-date background or misses a real partner outage.
resource "datadog_monitor" "naive_global_error_rate" {
  name    = "[ALL BFF] (contrast) Global GraphQL error rate over 5%"
  type    = "query alert"
  message = <<-EOT
    The global GraphQL error rate is above 5%.

    Kept deliberately as a counter-example. It cannot distinguish a client
    sending a reversed date range from a payment partner failing, which is why
    a single global threshold produces either noise or silence.

    The answer to it: [ALL BFF — GraphQL operation health](https://app.${var.datadog_site}/dashboard/${datadog_dashboard.graphql_health.id}),
    the "Per business error code" group.
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

  tags = ["env:${var.env}", "demo:accor-bff", "purpose:counter-example", "managed:terraform"]
}
