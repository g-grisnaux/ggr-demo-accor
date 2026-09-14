#!/usr/bin/env bash
#
# Wire Datadog's Source Code Integration for this demo.
#
# Bits Investigation reports "Unknown repository" because three separate things
# are missing, and all three are needed:
#
#   1. a hosted git repository — the code has to live somewhere Datadog can read
#   2. the git metadata uploaded, so Datadog knows the commit and file paths
#   3. DD_GIT_REPOSITORY_URL and DD_GIT_COMMIT_SHA on the running services, so a
#      span can be tied back to a revision. These are plain environment
#      variables on the Deployment, so this is a rollout and not a rebuild.
#
# A fourth step is NOT automatable and has to be done by hand in the browser:
# installing the Datadog GitHub App on the repository. Uploading metadata tells
# Datadog *which* files exist; only the integration lets it *read* them, which
# is what "see the code in Bits" actually requires.
#
# Usage:
#   REPO_NAME=ggr-demo-accor VISIBILITY=private scripts/setup-source-code.sh
#
set -euo pipefail

REPO_OWNER="${REPO_OWNER:-g-grisnaux}"
REPO_NAME="${REPO_NAME:-ggr-demo-accor}"
VISIBILITY="${VISIBILITY:-private}"
NAMESPACE="${NAMESPACE:-ggr-demo-accor}"
PROJECT_ID="${PROJECT_ID:?set PROJECT_ID, e.g. in .env}"
REGION="${REGION:-europe-west9}"
REPOSITORY="${REPOSITORY:-ggr-demo-accor}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:?set SERVICE_ACCOUNT, e.g. in .env}"

IMAGE_PREFIX="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

for tool in gh git datadog-ci gcloud kubectl; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is not installed"
done

[[ -f .env ]] || fail ".env not found"
# shellcheck disable=SC1091
set -a; source .env; set +a
[[ -n "${DD_API_KEY:-}" ]] || fail "DD_API_KEY is not set"

# --- 0. Refuse to push if the history is not clean ---------------------------

log "Auditing the history for secrets before anything is pushed"
if git log --all --oneline -- .env | grep -q .; then
  fail ".env appears in the git history — do not push. Rewrite the history first."
fi
for secret in "${DD_API_KEY}" "${DD_APP_KEY:-}" "${DD_RUM_CLIENT_TOKEN:-}"; do
  [[ -z "$secret" ]] && continue
  if git log --all -p | grep -qF "$secret"; then
    fail "a credential from .env appears in the git history — do not push"
  fi
done
echo "  history is clean"

# --- 1. The hosted repository ------------------------------------------------

log "Creating ${REPO_OWNER}/${REPO_NAME} (${VISIBILITY}) and pushing"
if gh repo view "${REPO_OWNER}/${REPO_NAME}" >/dev/null 2>&1; then
  echo "  repository already exists, reusing it"
  git remote get-url origin >/dev/null 2>&1 \
    || git remote add origin "https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
else
  gh repo create "${REPO_OWNER}/${REPO_NAME}" \
    --"${VISIBILITY}" \
    --description "Accor BFF observability demo — GraphQL BFF over REST APIs, Datadog on GKE" \
    --source=. --remote=origin
fi
git push -u origin HEAD

GIT_REPOSITORY_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
GIT_COMMIT_SHA="$(git rev-parse HEAD)"
echo "  repository: ${GIT_REPOSITORY_URL}"
echo "  commit:     ${GIT_COMMIT_SHA}"

# --- 2. The git metadata -----------------------------------------------------

log "Uploading git metadata to Datadog"
DATADOG_API_KEY="$DD_API_KEY" DATADOG_SITE="${DD_SITE:-datadoghq.com}" \
  datadog-ci git-metadata upload

# --- 3. The services ---------------------------------------------------------

log "Rendering manifests with the repository URL and commit"
python3 scripts/render-manifests.py
# The manifests carry placeholders so the committed YAML never hardcodes a SHA
# that would be stale the moment anything is committed on top of it.
for f in k8s/services/*-deployment.yaml; do
  sed -i '' \
    -e "s|__GIT_REPOSITORY_URL__|${GIT_REPOSITORY_URL}|g" \
    -e "s|__GIT_COMMIT_SHA__|${GIT_COMMIT_SHA}|g" "$f"
done
grep -h "DD_GIT_COMMIT_SHA" -A1 k8s/services/graphql-bff-deployment.yaml | tail -1

# No image rebuild. DD_GIT_REPOSITORY_URL and DD_GIT_COMMIT_SHA are read from
# the environment by each tracer at process start, and they come from the
# Deployment spec — nothing is baked into the image. A rollout is enough, which
# takes minutes rather than the half hour four Cloud Builds would cost.

log "Applying and rolling out"
gcloud container clusters get-credentials ggr-demo-accor \
  --zone europe-west9-a --project "$PROJECT_ID" \
  --impersonate-service-account="$SERVICE_ACCOUNT"
kubectl apply -k .
kubectl rollout restart deployment/graphql-bff deployment/hotel-search-api \
  deployment/booking-api deployment/payment-api -n "$NAMESPACE"
for svc in graphql-bff hotel-search-api booking-api payment-api; do
  kubectl rollout status "deployment/${svc}" -n "$NAMESPACE" --timeout=6m
done

log "Confirming the tracers picked the git tags up"
kubectl exec -n "$NAMESPACE" deploy/graphql-bff -- \
  sh -c 'env | grep DD_GIT' || echo "  WARNING: DD_GIT_* not visible in the pod"

# Leave the working tree as it was committed, so the substituted SHA does not
# end up in a later commit.
git checkout -- k8s/services/ 2>/dev/null || true

log "Done — but one manual step remains"
cat <<EOF

Datadog now knows the repository and every service reports its commit. To let
Bits actually *read* the source, install the Datadog GitHub App on
${REPO_OWNER}/${REPO_NAME}:

  https://app.${DD_SITE:-datadoghq.com}/integrations/github

That step is a GitHub App authorisation and cannot be scripted — it needs your
click. Uploading metadata tells Datadog which files exist; the integration is
what lets it fetch their contents.

Verify afterwards:
  https://app.${DD_SITE:-datadoghq.com}/source-code/repositories
EOF
