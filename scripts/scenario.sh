#!/usr/bin/env bash
#
# Drive the demo scenarios from a single place.
#
# Each scenario flips a runtime switch inside a running pod. Nothing is
# redeployed, so the change lands in a couple of seconds and Datadog shows the
# before/after on the same dashboard — which is the point.
#
set -euo pipefail

NAMESPACE="${NAMESPACE:-ggr-demo-accor}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }

# The /admin endpoints are not exposed through the ingress on purpose, so they
# are reached with an in-cluster curl rather than from the laptop.
in_pod() {
  local app="$1"; shift
  kubectl exec -n "$NAMESPACE" "deploy/${app}" -- "$@"
}

hotel_scenario() {
  in_pod hotel-search-api curl -sS -X POST "http://localhost:8081/admin/scenario?$1"
  echo
}

payment_scenario() {
  in_pod payment-api curl -sS -X POST "http://localhost:8083/admin/scenario?$1"
  echo
}

dataloader() {
  # The dataloader is driven by a feature flag, so the honest way to flip it is
  # in Datadog Feature Flags. The env override exists because flag delivery is a
  # network round-trip that should not be trusted in a conference room.
  kubectl set env -n "$NAMESPACE" deployment/graphql-bff "BFF_FORCE_DATALOADER_OFF=$1"
  kubectl rollout status -n "$NAMESPACE" deployment/graphql-bff --timeout=3m
}

case "${1:-list}" in
  list)
    cat <<'EOF'
Scenarios

  reset               Everything back to healthy baseline
  status              Current state of every switch

  latency-on          hotel-search-api: unindexed search + CPU-bound ranking
  latency-off         hotel-search-api: back to the indexed fast path
                      -> APM p95 on searchHotels, DBM plan flip, profiler flame graph

  payment-storm       payment-api: 45% of authorizations declined
  payment-normal      payment-api: back to the 4% baseline
                      -> error rate by error_code, anomaly detection on PAYMENT_DECLINED

  n-plus-one-on       graphql-bff: availability dataloader disabled
  n-plus-one-off      graphql-bff: dataloader re-enabled
                      -> 25 sibling REST spans per query instead of 1

  booking-outage      hotel-search-api: 6s delay on the availability endpoints
  booking-outage-off  back to no delay
                      -> createBooking starts failing with UPSTREAM_UNAVAILABLE.
                         The cause is two hops from the symptom, and payment-api
                         is the obvious suspect while being entirely healthy.
EOF
    ;;

  status)
    log "hotel-search-api"; in_pod hotel-search-api curl -sS http://localhost:8081/admin/scenario; echo
    log "payment-api";      in_pod payment-api      curl -sS http://localhost:8083/admin/scenario; echo
    log "graphql-bff dataloader override"
    kubectl get deploy/graphql-bff -n "$NAMESPACE" \
      -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="BFF_FORCE_DATALOADER_OFF")].value}'
    echo
    ;;

  latency-on)
    log "Degrading hotel search (sequential scan + expensive ranking)"
    hotel_scenario "slowSearch=true&expensiveRanking=true"
    warn "Give it ~2 minutes for the APM p95 and the profiler to move."
    ;;
  latency-off)
    log "Restoring the fast search path"
    hotel_scenario "slowSearch=false&expensiveRanking=false"
    ;;

  payment-storm)
    log "Raising the payment decline rate to 45%"
    payment_scenario "declineRate=0.45"
    warn "Anomaly detection needs a few minutes of history before it flags this."
    ;;
  payment-normal)
    log "Restoring the 4% baseline decline rate"
    payment_scenario "declineRate=0.04"
    ;;

  n-plus-one-on)
    log "Disabling the availability dataloader"
    dataloader true
    ;;
  n-plus-one-off)
    log "Re-enabling the availability dataloader"
    dataloader false
    ;;

  booking-outage)
    # 6s exceeds booking-api's 5s timeout on the availability call, so the
    # booking fails before payment is ever contacted.
    log "Delaying hotel-search-api availability by 6s"
    hotel_scenario "availabilityDelayMs=6000"
    warn "createBooking will start failing with UPSTREAM_UNAVAILABLE within seconds."
    warn "Note that payment-api stays healthy — that is the point of the scenario."
    ;;
  booking-outage-off)
    log "Removing the availability delay"
    hotel_scenario "availabilityDelayMs=0"
    ;;

  reset)
    log "Resetting every scenario to baseline"
    hotel_scenario "slowSearch=false&expensiveRanking=false&availabilityDelayMs=0"
    payment_scenario "declineRate=0.04"
    dataloader false
    ;;

  *)
    echo "Unknown scenario: $1" >&2
    echo "Run '$0 list' to see what is available." >&2
    exit 1
    ;;
esac
