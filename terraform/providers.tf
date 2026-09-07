# Every API call is made as the demo service account, using short-lived tokens
# minted through the IAM Credentials API. No JSON key is created, downloaded or
# stored anywhere — the caller's own gcloud ADC is what authorises the
# impersonation, and it needs roles/iam.serviceAccountTokenCreator on the target
# service account.
provider "google" {
  project                     = var.project_id
  region                      = var.region
  zone                        = var.zone
  impersonate_service_account = var.impersonate_service_account
}
