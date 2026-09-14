# Credentials come from DD_API_KEY / DD_APP_KEY in the environment. Nothing is
# written to this repository; terraform-datadog/terraform.tfvars is gitignored
# and not used.
provider "datadog" {
  api_url = "https://api.${var.datadog_site}/"
}
