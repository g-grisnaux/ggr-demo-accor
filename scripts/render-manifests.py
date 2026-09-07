#!/usr/bin/env python3
"""Generate the Kubernetes manifests for the demo.

Written as a generator rather than hand-maintained YAML because every service
needs the same twelve lines of unified service tagging, probes and Datadog
environment, and keeping those in sync by hand is how a demo ends up with one
service silently missing its DD_ENV.

Run from the repo root:  python3 scripts/render-manifests.py
"""

import pathlib

NAMESPACE = "ggr-demo-accor"
ENV_TAG = "ggr-demo-accor-260907"
VERSION = "1.0.0"

# Image names stay registry-agnostic here; the kustomization rewrites them to the
# Artifact Registry path at deploy time.
IMAGE_PREFIX = "ggr-demo-accor"

DB_NAME = "accor"
DB_USER = "accor"

SERVICES = [
    {
        "name": "graphql-bff",
        "port": 8080,
        "log_source": "nodejs",
        "public": True,
        "env": {
            "HOTEL_SEARCH_URL": "http://hotel-search-api:8081",
            "BOOKING_URL": "http://booking-api:8082",
            # Lets the Datadog OpenFeature provider serve the dataloader flag.
            "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED": "true",
        },
        "resources": {"cpu": "200m", "memory": "256Mi", "cpu_limit": "1", "memory_limit": "512Mi"},
    },
    {
        "name": "hotel-search-api",
        "port": 8081,
        "log_source": "java",
        "public": False,
        "needs_db": True,
        "env": {
            # Injects the trace context as a SQL comment, which is what links an
            # APM span to its DBM query sample and execution plan. Without it you
            # get postgresql.query spans and DBM samples that cannot be joined.
            "DD_DBM_PROPAGATION_MODE": "full",
            "HOTEL_SEARCH_SLOW_MODE": "false",
            "HOTEL_SEARCH_EXPENSIVE_RANKING": "false",
            "HOTEL_SEARCH_RANKING_PASSES": "60000",
        },
        # The JVM plus the CPU-bound ranking scenario needs real headroom, or the
        # latency demo measures throttling instead of the code.
        "resources": {"cpu": "500m", "memory": "768Mi", "cpu_limit": "2", "memory_limit": "1Gi"},
        "startup_delay": 40,
    },
    {
        "name": "booking-api",
        "port": 8082,
        "log_source": "python",
        "public": False,
        "needs_db": True,
        "env": {
            "DD_DBM_PROPAGATION_MODE": "full",
            "PAYMENT_URL": "http://payment-api:8083",
            "HOTEL_SEARCH_URL": "http://hotel-search-api:8081",
        },
        "resources": {"cpu": "200m", "memory": "256Mi", "cpu_limit": "1", "memory_limit": "512Mi"},
    },
    {
        "name": "payment-api",
        "port": 8083,
        "log_source": "nodejs",
        "public": False,
        "needs_db": True,
        "env": {
            "DD_DBM_PROPAGATION_MODE": "full",
            "PAYMENT_DECLINE_RATE": "0.04",
        },
        "resources": {"cpu": "200m", "memory": "256Mi", "cpu_limit": "1", "memory_limit": "512Mi"},
    },
]

ROOT = pathlib.Path(__file__).resolve().parent.parent
K8S = ROOT / "k8s"


def tags(service):
    return f"""    tags.datadoghq.com/env: "{ENV_TAG}"
    tags.datadoghq.com/service: "{service}"
    tags.datadoghq.com/version: "{VERSION}\""""


def datadog_env(service, port):
    return f"""            - name: DD_SERVICE
              value: "{service}"
            - name: DD_ENV
              valueFrom:
                fieldRef:
                  fieldPath: metadata.labels['tags.datadoghq.com/env']
            - name: DD_VERSION
              value: "{VERSION}"
            - name: DD_AGENT_HOST
              valueFrom:
                fieldRef:
                  fieldPath: status.hostIP
            - name: DD_TRACE_PROPAGATION_STYLE
              value: "datadog,tracecontext"
            - name: PORT
              value: "{port}\""""


def db_env():
    """Credentials come from a Secret, never from the manifest."""
    return """            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: postgres-credentials
                  key: url
            - name: DATABASE_USER
              valueFrom:
                secretKeyRef:
                  name: postgres-credentials
                  key: username
            - name: DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-credentials
                  key: password"""


def jdbc_env():
    """The Spring service needs a JDBC URL, which has a different scheme."""
    return """            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: postgres-credentials
                  key: jdbc-url
            - name: DATABASE_USER
              valueFrom:
                secretKeyRef:
                  name: postgres-credentials
                  key: username
            - name: DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-credentials
                  key: password"""


def render_deployment(svc):
    name = svc["name"]
    port = svc["port"]
    res = svc["resources"]

    extra_env = "".join(
        f'\n            - name: {k}\n              value: "{v}"' for k, v in svc.get("env", {}).items()
    )

    db_block = ""
    if svc.get("needs_db"):
        db_block = "\n" + (jdbc_env() if name == "hotel-search-api" else db_env())

    # The JVM starts slowly; a startupProbe keeps the liveness probe from killing
    # it mid-boot without having to inflate the liveness thresholds forever.
    startup = ""
    if svc.get("startup_delay"):
        startup = f"""
          startupProbe:
            httpGet:
              path: /health
              port: {port}
            periodSeconds: 5
            failureThreshold: {svc['startup_delay'] // 5}"""

    return f"""apiVersion: apps/v1
kind: Deployment
metadata:
  name: {name}
  namespace: {NAMESPACE}
  labels:
    app: {name}
{tags(name)}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {name}
  template:
    metadata:
      labels:
        app: {name}
{tags(name).replace('    ', '        ')}
      annotations:
        ad.datadoghq.com/{name}.logs: '[{{"source":"{svc["log_source"]}","service":"{name}"}}]'
    spec:
      containers:
        - name: {name}
          image: {IMAGE_PREFIX}/{name}:latest
          # Always, not IfNotPresent: the images are published under a mutable
          # :latest tag, so IfNotPresent makes a node serve whatever it cached
          # first and silently ignore a rebuild. That is how a fixed image kept
          # crashlooping with the old binary still in the node cache.
          imagePullPolicy: Always
          ports:
            - containerPort: {port}
          env:
{datadog_env(name, port)}{extra_env}{db_block}
          resources:
            requests:
              cpu: "{res['cpu']}"
              memory: "{res['memory']}"
            limits:
              cpu: "{res['cpu_limit']}"
              memory: "{res['memory_limit']}"{startup}
          readinessProbe:
            httpGet:
              path: /health
              port: {port}
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: {port}
            initialDelaySeconds: 15
            periodSeconds: 20
"""


def render_service(svc):
    return f"""apiVersion: v1
kind: Service
metadata:
  name: {svc['name']}
  namespace: {NAMESPACE}
  labels:
    app: {svc['name']}
spec:
  selector:
    app: {svc['name']}
  ports:
    - port: {svc['port']}
      targetPort: {svc['port']}
      protocol: TCP
"""


def main():
    (K8S / "services").mkdir(parents=True, exist_ok=True)

    # Clear the scaffold's service-N manifests so no stale copy gets applied.
    for stale in (K8S / "services").glob("service-*.yaml"):
        stale.unlink()

    for svc in SERVICES:
        (K8S / "services" / f"{svc['name']}-deployment.yaml").write_text(render_deployment(svc))
        (K8S / "services" / f"{svc['name']}-service.yaml").write_text(render_service(svc))

    (K8S / "namespace.yaml").write_text(f"""apiVersion: v1
kind: Namespace
metadata:
  name: {NAMESPACE}
  labels:
    app.kubernetes.io/part-of: {NAMESPACE}
    tags.datadoghq.com/env: "{ENV_TAG}"
""")

    print(f"rendered {len(SERVICES)} services into {K8S}")


if __name__ == "__main__":
    main()
