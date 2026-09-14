variable "datadog_site" {
  description = "Datadog site the account lives on."
  type        = string
  default     = "datadoghq.com"
}

variable "env" {
  description = "Unified service tagging env this demo reports under."
  type        = string
  default     = "ggr-demo-accor-260907"
}

variable "bff_service" {
  type    = string
  default = "graphql-bff"
}

variable "notification_handle" {
  description = "Where monitors notify. A demo org has no on-call, so this defaults to the owner."
  type        = string
  default     = "gael.grisnaux@datadoghq.com"
}

# Id du dashboard GraphQL, en littéral et non en référence de ressource.
#
# Le monitor de paiement cite ce dashboard dans son message, et le dashboard
# affiche en retour l'historique de ce monitor (widget alert_graph). Référencer
# la ressource des deux côtés produit un cycle Terraform. L'id est un slug
# stable assigné par Datadog, déjà écrit tel quel dans README.md,
# DEMO-DEROULE.md et DEMO-SCENARIOS.md — cette variable s'aligne sur eux au
# lieu d'introduire une source de vérité supplémentaire.
variable "graphql_dashboard_id" {
  description = "Slug du dashboard ALL BFF — GraphQL operation health."
  type        = string
  default     = "tgq-6hy-vt9"
}
