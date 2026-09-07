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

    labels = {
      environment = "demo"
      demo        = "accor-bff"
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
