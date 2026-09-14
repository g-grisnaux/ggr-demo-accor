# APM retention filter for the demo environment.
#
# Why this is needed. Datadog's default intelligent retention keeps a sample of
# traces in full and only part of the others in the search index. Measured on
# this stack: one `createBooking` trace came back with 41 spans across all four
# services, while its neighbours came back with 3 or 4 from the BFF alone.
#
# For an investigation demo that is a real hazard. Clicking from a RUM session
# into "the" backend trace has to land on the whole chain — BFF, booking-api,
# payment-api, hotel-search-api and their SQL — not on a fragment. A partial
# trace makes the product look like it lost the data.
#
# Keeping 100% of a demo environment is affordable precisely because it is a
# demo: the load generator runs at roughly 3 requests per second. This is not a
# pattern to copy into production, where the whole point of retention filters is
# to keep the interesting traces rather than all of them.

resource "datadog_apm_retention_filter" "demo_keep_all" {
  name      = "ggr-demo-accor — conserver toutes les traces"
  rate      = "1.0"
  enabled   = true
  filter_type = "spans-sampling-processor"

  filter {
    query = "env:${var.env}"
  }
}
