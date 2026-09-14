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
