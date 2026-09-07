#!/usr/bin/env bash
#
# Deploy the Accor BFF demo to GKE.
#
# Every GCP call for infrastructure goes through service account impersonation —
# Terraform via the provider's impersonate_service_account, gcloud via
# --impersonate-service-account. No JSON key is ever created.
#
# Image pushes run under impersonation too, which requires Artifact Registry
# permissions on the service account — the four roles it starts with
# (container.admin, compute.admin, iam.serviceAccountUser, storage.admin) grant
# none of them. Add roles/artifactregistry.admin before the first run.
#
#   REGISTRY_IDENTITY=service-account push under impersonation (default)
#   REGISTRY_IDENTITY=user            fall back to your own gcloud account
#
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-datadog-ese-sandbox}"
REGION="${REGION:-europe-west9}"
ZONE="${ZONE:-europe-west9-a}"
CLUSTER_NAME="${CLUSTER_NAME:-ggr-demo-accor}"
REPOSITORY="${REPOSITORY:-ggr-demo-accor}"
NAMESPACE="${NAMESPACE:-ggr-demo-accor}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-gael-service-account-demo@datadog-ese-sandbox.iam.gserviceaccount.com}"
REGISTRY_IDENTITY="${REGISTRY_IDENTITY:-service-account}"

# GKE node pools are amd64. Building on an Apple Silicon Mac without pinning the
# platform produces arm64 images that pass the push and then crashloop on the
# node with "exec format error" — set explicitly rather than inherited from the
# build host.
BUILD_PLATFORM="${BUILD_PLATFORM:-linux/amd64}"

REGISTRY_HOST="${REGION}-docker.pkg.dev"
IMAGE_PREFIX="${REGISTRY_HOST}/${PROJECT_ID}/${REPOSITORY}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SERVICES=(graphql-bff hotel-search-api booking-api payment-api frontend traffic)

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Preconditions -----------------------------------------------------------

log "Checking prerequisites"
for tool in gcloud kubectl helm docker terraform; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is not installed"
done

[[ -f .env ]] || fail ".env not found — copy .env.example and fill in DD_API_KEY"
# shellcheck disable=SC1091
set -a; source .env; set +a

[[ -n "${DD_API_KEY:-}" && "$DD_API_KEY" != "your_"* ]] || fail "DD_API_KEY is not set in .env"
if [[ -z "${DD_RUM_APPLICATION_ID:-}" || "$DD_RUM_APPLICATION_ID" == "your_"* ]]; then
  printf '\033[1;33mWARNING:\033[0m DD_RUM_APPLICATION_ID is unset — the browser RUM part of the demo will be inert.\n'
fi

# gke-gcloud-auth-plugin is what kubectl uses to authenticate against GKE; without
# it get-credentials succeeds and every later kubectl call fails.
command -v gke-gcloud-auth-plugin >/dev/null 2>&1 \
  || fail "gke-gcloud-auth-plugin is missing — install with: gcloud components install gke-gcloud-auth-plugin"

log "Verifying impersonation of ${SERVICE_ACCOUNT}"
gcloud auth print-access-token --impersonate-service-account="$SERVICE_ACCOUNT" >/dev/null \
  || fail "cannot impersonate $SERVICE_ACCOUNT — you need roles/iam.serviceAccountTokenCreator on it"

# --- Infrastructure ----------------------------------------------------------

log "Provisioning GKE with Terraform (impersonated)"
terraform -chdir=terraform init -input=false
terraform -chdir=terraform apply -input=false -auto-approve \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}" \
  -var="zone=${ZONE}" \
  -var="cluster_name=${CLUSTER_NAME}" \
  -var="impersonate_service_account=${SERVICE_ACCOUNT}"

log "Verifying the Artifact Registry repository (created by Terraform)"
if ! gcloud artifacts repositories describe "$REPOSITORY" \
      --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud artifacts repositories create "$REPOSITORY" \
    --repository-format=docker \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --description="Container images for the Accor BFF observability demo"
fi

# --- Images ------------------------------------------------------------------

log "Authenticating Docker against ${REGISTRY_HOST} (identity: ${REGISTRY_IDENTITY})"
if [[ "$REGISTRY_IDENTITY" == "service-account" ]]; then
  gcloud auth print-access-token --impersonate-service-account="$SERVICE_ACCOUNT" \
    | docker login -u oauth2accesstoken --password-stdin "https://${REGISTRY_HOST}"
else
  gcloud auth configure-docker "$REGISTRY_HOST" --quiet
fi

# The front-end bundle is compiled here rather than inside the image. It is
# HTML/CSS/JS — identical on every architecture — so building it natively is
# both faster and immune to the cross-platform build problems below. The RUM
# credentials are inlined by Vite at this point, which is why they are passed
# as environment variables to the build and not to the container.
log "Building the front-end bundle"
( cd frontend && npm ci --silent 2>/dev/null || npm install --silent
  VITE_DD_RUM_APPLICATION_ID="${DD_RUM_APPLICATION_ID:-}" \
  VITE_DD_RUM_CLIENT_TOKEN="${DD_RUM_CLIENT_TOKEN:-}" \
  VITE_DD_SITE="${DD_SITE:-datadoghq.com}" \
  VITE_DD_ENV="${DD_ENV}" \
  VITE_DD_SERVICE="all-web" \
  npm run build )

log "Building images for ${BUILD_PLATFORM}"
docker build --platform "$BUILD_PLATFORM" -t "${IMAGE_PREFIX}/frontend:${IMAGE_TAG}" ./frontend

for svc in graphql-bff hotel-search-api booking-api payment-api; do
  docker build --platform "$BUILD_PLATFORM" -t "${IMAGE_PREFIX}/${svc}:${IMAGE_TAG}" "./services/${svc}"
done
docker build --platform "$BUILD_PLATFORM" -t "${IMAGE_PREFIX}/traffic:${IMAGE_TAG}" ./traffic

log "Pushing images"
for svc in "${SERVICES[@]}"; do
  docker push "${IMAGE_PREFIX}/${svc}:${IMAGE_TAG}"
done

# --- Cluster access ----------------------------------------------------------

log "Pointing kubectl at the cluster"
gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --zone "$ZONE" --project "$PROJECT_ID" \
  --impersonate-service-account="$SERVICE_ACCOUNT"

# --- Secrets -----------------------------------------------------------------

log "Creating namespace and secrets"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic datadog-secret \
  --from-literal=api-key="$DD_API_KEY" \
  -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Generated rather than hardcoded, so no database password lives in the repo.
DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -hex 16)}"
kubectl create secret generic postgres-credentials \
  --from-literal=username="accor" \
  --from-literal=password="$DB_PASSWORD" \
  --from-literal=url="postgresql://accor:${DB_PASSWORD}@postgresql:5432/accor" \
  --from-literal=jdbc-url="jdbc:postgresql://postgresql:5432/accor" \
  -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# --- Datadog -----------------------------------------------------------------

log "Installing the Datadog Agent with the DDOT collector"
helm repo add datadog https://helm.datadoghq.com >/dev/null 2>&1 || true
helm repo update datadog >/dev/null
# Pinned: an unpinned install makes helm pick "the closest available version",
# which is not something a demo should discover on the day.
helm upgrade --install datadog datadog/datadog \
  --version "${DATADOG_CHART_VERSION:-3.242.0}" \
  -f helm/datadog-values.yaml \
  -n "$NAMESPACE" \
  --set datadog.site="${DD_SITE:-datadoghq.com}" \
  --wait --timeout 10m

# --- Application -------------------------------------------------------------

log "Applying the application manifests"
kubectl apply -k .

log "Waiting for the stack to become ready"
# Postgres seeds a million availability rows on first boot, so it gets the
# longest window.
kubectl rollout status deployment/postgresql -n "$NAMESPACE" --timeout=10m
for svc in graphql-bff hotel-search-api booking-api payment-api frontend; do
  kubectl rollout status "deployment/${svc}" -n "$NAMESPACE" --timeout=5m
done

log "Done"
kubectl get pods -n "$NAMESPACE"
cat <<EOF

Reach the demo:
  kubectl port-forward -n ${NAMESPACE} svc/frontend 8090:80
  open http://localhost:8090

Drive the scenarios:
  scripts/scenario.sh list
EOF
