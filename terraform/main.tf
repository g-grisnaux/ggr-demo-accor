# GKE Standard, not Autopilot. The Datadog Agent and the DDOT collector need
# host-level access (kubelet metrics, host ports, privileged process
# collection) that Autopilot restricts, so Autopilot would quietly cost us the
# infrastructure half of the demo.
resource "google_container_cluster" "demo" {
  name     = var.cluster_name
  location = var.zone

  # The default pool cannot be customised after creation, so it is replaced by
  # the managed pool below.
  remove_default_node_pool = true
  initial_node_count       = 1

  # A demo cluster gets torn down often; protection would only get in the way.
  deletion_protection = false

  release_channel {
    channel = "REGULAR"
  }

  # GCP labels, so the cluster is findable in the Cloud console and carries the
  # same env/service identity through Datadog's GCP integration as the workloads
  # carry through unified service tagging. GCP labels must be lowercase and use
  # dashes/underscores only, which is why the env tag is not reused verbatim.
  resource_labels = {
    env     = "ggr-demo-accor-260907"
    service = "ggr-demo-accor"
    demo    = "accor-bff-observability"
    owner   = "gael-grisnaux"
    managed = "terraform"
  }

  # Cheaper and less noisy than the Google-managed stack, which would otherwise
  # ship metrics and logs the demo does not use.
  logging_service    = "none"
  monitoring_service = "none"

  # Workload Identity is not needed to pull images, but leaving it enabled is
  # the current GKE default and avoids the legacy metadata server.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}

resource "google_container_node_pool" "demo" {
  name       = "${var.cluster_name}-pool"
  location   = var.zone
  cluster    = google_container_cluster.demo.name
  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    disk_size_gb = 50
    disk_type    = "pd-balanced"

    # Least privilege that still lets nodes pull images and resolve the
    # project. Pulling from Artifact Registry additionally requires
    # roles/artifactregistry.reader on the node service account.
    oauth_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    # Node labels become kubernetes_node tags in Datadog, so the same identity
    # is visible on the infrastructure side.
    labels = {
      env     = "ggr-demo-accor-260907"
      service = "ggr-demo-accor"
      demo    = "accor-bff-observability"
    }

    resource_labels = {
      env     = "ggr-demo-accor-260907"
      service = "ggr-demo-accor"
      demo    = "accor-bff-observability"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
