variable "project_id" {
  description = "GCP project hosting the demo."
  type        = string
  default     = "datadog-ese-sandbox"
}

variable "region" {
  description = "Region for the cluster and the image repository."
  type        = string
  default     = "europe-west9"
}

variable "zone" {
  description = "Zone for the cluster. A zonal cluster keeps the demo cheap; a regional one would triple the control plane cost for no demo value."
  type        = string
  default     = "europe-west9-a"
}

variable "impersonate_service_account" {
  description = "Service account Terraform impersonates. Never a key file."
  type        = string
  default     = "gael-service-account-demo@datadog-ese-sandbox.iam.gserviceaccount.com"
}

variable "cluster_name" {
  type    = string
  default = "ggr-demo-accor"
}

variable "node_count" {
  description = "Nodes in the pool. Two e2-standard-4 hold Postgres, the four services, the front, the load generator and the Datadog agents with room for the CPU-bound latency scenario."
  type        = number
  default     = 2
}

variable "machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "create_artifact_registry" {
  description = "Whether Terraform creates the image repository. Requires Artifact Registry permissions on the impersonated service account."
  type        = bool
  default     = true
}

variable "repository_name" {
  type    = string
  default = "ggr-demo-accor"
}
