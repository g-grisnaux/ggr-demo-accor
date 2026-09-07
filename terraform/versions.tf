terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # State stays local by default so the demo needs no bootstrap bucket. The
  # service account holds roles/storage.admin, so switching to a GCS backend is
  # a matter of uncommenting this and running `terraform init -migrate-state`.
  #
  # backend "gcs" {
  #   bucket                      = "datadog-ese-sandbox-tfstate-ggr-demo-accor"
  #   prefix                      = "ggr-demo-accor"
  #   impersonate_service_account = "gael-service-account-demo@datadog-ese-sandbox.iam.gserviceaccount.com"
  # }
}
