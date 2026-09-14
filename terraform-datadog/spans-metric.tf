# Span-based metric on the business error code.
#
# Why this exists alongside the DogStatsD metric of the same information.
#
# A DogStatsD counter is a standalone timeseries: it has no link back to the
# requests that produced it, so Datadog's "View traces" pivot has to guess, and
# it guesses by carrying the metric's group-by tag verbatim into a trace query.
# That sends a bare `error_code:payment_declined`, which only resolves if the
# span tag has been promoted to a facet — a UI action this Terraform provider
# cannot perform.
#
# A span-based metric is derived *from* the spans, so the pivot is native by
# construction: the metric knows the filter it was computed from and hands it to
# the trace search. Nothing to override, no facet to create.
#
# The DogStatsD metric stays: it is cheaper at high cardinality, it is what the
# anomaly monitor runs on, and having both is a useful thing to explain — the
# counter for alerting, the span metric for drilling in.

resource "datadog_spans_metric" "graphql_business_errors" {
  name = "bff.graphql.errors.spans"

  filter {
    # Only spans that actually carry a business error code. The `@` prefix is
    # how span attributes are addressed; that is exactly the mismatch the
    # DogStatsD pivot could not bridge.
    query = "service:${var.bff_service} @graphql.error.code:*"
  }

  compute {
    aggregation_type = "count"
  }

  group_by {
    path     = "@graphql.error.code"
    tag_name = "error_code"
  }

  group_by {
    path     = "@graphql.error.kind"
    tag_name = "error_kind"
  }

  group_by {
    path     = "@graphql.operation.name"
    tag_name = "operation"
  }
}
