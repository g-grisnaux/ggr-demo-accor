#!/usr/bin/env bash
#
# Build and push every image with Google Cloud Build.
#
# Use this instead of the local docker build when the workstation cannot produce
# amd64 images — which is the case on an Apple Silicon Mac without buildx.
# The legacy docker builder there accepts `--platform linux/amd64`, reports the
# image as amd64, and still produces arm64 binaries; the pod then crashloops
# with "exec format error". Cloud Build runs on native amd64, so the question
# does not arise.
#
# Note on identity: Cloud Build runs as its own service account, not as the
# impersonated demo service account, so this step is the one place the strict
# impersonation model does not apply. Infrastructure (Terraform, GKE
# credentials) stays impersonated.
#
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-datadog-ese-sandbox}"
REGION="${REGION:-europe-west9}"
REPOSITORY="${REPOSITORY:-ggr-demo-accor}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

IMAGE_PREFIX="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

[[ -f .env ]] || { echo "ERROR: .env not found" >&2; exit 1; }
# shellcheck disable=SC1091
set -a; source .env; set +a

# The bundle is architecture-independent, so it is compiled locally and the
# image only layers it onto nginx.
log "Building the front-end bundle"
(
  cd frontend
  npm ci --silent 2>/dev/null || npm install --silent
  VITE_DD_RUM_APPLICATION_ID="${DD_RUM_APPLICATION_ID:-}" \
  VITE_DD_RUM_CLIENT_TOKEN="${DD_RUM_CLIENT_TOKEN:-}" \
  VITE_DD_SITE="${DD_SITE:-datadoghq.com}" \
  VITE_DD_ENV="${DD_ENV}" \
  VITE_DD_SERVICE="all-web" \
  npm run build
)

# Submitted asynchronously so the four service builds run in parallel; Cloud
# Build finishes them in well under a minute each.
log "Submitting builds"
for svc in graphql-bff hotel-search-api booking-api payment-api; do
  # Braces are load-bearing: in zsh, "$svc:latest" is parsed as the ${svc:l}
  # lowercase modifier followed by "atest", which silently pushes to a
  # completely different repository.
  printf '  %-20s -> %s\n' "$svc" "${IMAGE_PREFIX}/${svc}:${IMAGE_TAG}"
  gcloud builds submit "./services/${svc}" \
    --tag "${IMAGE_PREFIX}/${svc}:${IMAGE_TAG}" \
    --project "$PROJECT_ID" --region=global --async --format="value(id)" >/dev/null
done

for dir in frontend traffic; do
  printf '  %-20s -> %s\n' "$dir" "${IMAGE_PREFIX}/${dir}:${IMAGE_TAG}"
  gcloud builds submit "./${dir}" \
    --tag "${IMAGE_PREFIX}/${dir}:${IMAGE_TAG}" \
    --project "$PROJECT_ID" --region=global --async --format="value(id)" >/dev/null
done

log "Waiting for the builds to finish"
until [[ "$(gcloud builds list --project "$PROJECT_ID" --limit=6 \
            --format='value(status)' | grep -c 'WORKING\|QUEUED')" -eq 0 ]]; do
  sleep 15
done

gcloud builds list --project "$PROJECT_ID" --limit=6 --format="value(status,images)"

if gcloud builds list --project "$PROJECT_ID" --limit=6 --format='value(status)' | grep -qv SUCCESS; then
  echo "ERROR: at least one build did not succeed — see the list above" >&2
  exit 1
fi

log "Done. Roll the deployments out:"
cat <<EOF
  kubectl rollout restart deployment/graphql-bff deployment/hotel-search-api \\
    deployment/booking-api deployment/payment-api deployment/frontend \\
    deployment/traffic -n ggr-demo-accor
EOF
