terraform {
  required_version = ">= 1.6"

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.60"
    }
  }
}

# Deliberately a separate root module from terraform/, with its own state.
#
# The GKE module needs Google credentials to refresh; the dashboards and
# monitors need none. Keeping them together would mean an expired gcloud token
# blocks a dashboard change — which is exactly what happened once already.
