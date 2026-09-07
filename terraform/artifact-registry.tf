# Requires Artifact Registry permissions on the impersonated service account.
# The four roles the account started with (container.admin, compute.admin,
# iam.serviceAccountUser, storage.admin) grant none of them, so
# roles/artifactregistry.admin has to be added before this applies — see README.
# Set create_artifact_registry = false to manage the repository outside Terraform.
resource "google_artifact_registry_repository" "images" {
  count = var.create_artifact_registry ? 1 : 0

  location      = var.region
  repository_id = var.repository_name
  description   = "Container images for the Accor BFF observability demo"
  format        = "DOCKER"

  docker_config {
    immutable_tags = false
  }
}
