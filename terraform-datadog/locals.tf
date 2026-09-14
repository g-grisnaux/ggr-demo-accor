# Context-menu links for the business-error widgets.
#
# Datadog greys out the native View traces / View logs entries on these widgets
# and I could not determine why from the API alone — the query is scoped to a
# concrete service, the metric reports, and the span-based metric is derived
# from the very spans the pivot should reach. The menu's enabling logic lives in
# the UI, so rather than keep guessing the night before the demo, these links
# are wired explicitly.
#
# Every target below was verified to return data before being wired in. The env
# is interpolated as a literal rather than through `$env.value`, so a broken
# template variable cannot silently produce a dead link.
locals {
  trace_link_base = "/apm/traces?query=env%3A${var.env}%20service%3A${var.bff_service}%20"
  log_link_base   = "/logs?query=env%3A${var.env}%20service%3A${var.bff_service}%20"

  # One entry per business error code the BFF can emit, so the demo can jump
  # straight to a single code instead of filtering by hand on stage.
  business_error_codes = [
    "PAYMENT_DECLINED",
    "INVALID_DATE",
    "UPSTREAM_UNAVAILABLE",
    "HOTEL_UNAVAILABLE",
    "RATE_EXPIRED",
  ]
}
