output "cluster_name" {
  value = google_container_cluster.demo.name
}

output "cluster_location" {
  value = google_container_cluster.demo.location
}

output "registry_host" {
  description = "Docker registry host to authenticate against."
  value       = "${var.region}-docker.pkg.dev"
}

output "image_prefix" {
  description = "Prefix the built images must be tagged with."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository_name}"
}

output "get_credentials_command" {
  description = "Point kubectl at the new cluster, still under impersonation."
  value = join(" ", [
    "gcloud container clusters get-credentials",
    google_container_cluster.demo.name,
    "--zone", var.zone,
    "--project", var.project_id,
    "--impersonate-service-account", var.impersonate_service_account,
  ])
}
