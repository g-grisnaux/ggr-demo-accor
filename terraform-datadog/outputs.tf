output "dashboard_graphql_url" {
  value = "https://app.${var.datadog_site}/dashboard/${datadog_dashboard.graphql_health.id}"
}

output "dashboard_chain_url" {
  value = "https://app.${var.datadog_site}/dashboard/${datadog_dashboard.bff_rest_chain.id}"
}

# Identifiants des monitors, désactivés au décommissionnement du 15/09/2026 :
# les monitors ont été supprimés avec l'infrastructure. Les définitions restent
# dans monitors.tf — réactiver ce bloc après les avoir réappliqués.
#
# output "monitor_ids" {
#   value = {
#     fixed_global_error_rate     = datadog_monitor.fixed_global_error_rate.id
#     dynamic_payment_declines    = datadog_monitor.dynamic_payment_declines.id
#     dynamic_business_error_code = datadog_monitor.dynamic_business_error_code.id
#     dynamic_resolver_errors     = datadog_monitor.dynamic_resolver_errors.id
#   }
# }
