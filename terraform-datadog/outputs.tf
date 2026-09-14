output "dashboard_graphql_url" {
  value = "https://app.${var.datadog_site}/dashboard/${datadog_dashboard.graphql_health.id}"
}

output "dashboard_chain_url" {
  value = "https://app.${var.datadog_site}/dashboard/${datadog_dashboard.bff_rest_chain.id}"
}

output "monitor_ids" {
  value = {
    resolver_error_anomaly      = datadog_monitor.resolver_error_anomaly.id
    business_error_code_anomaly = datadog_monitor.business_error_code_anomaly.id
    naive_global_error_rate     = datadog_monitor.naive_global_error_rate.id
  }
}
