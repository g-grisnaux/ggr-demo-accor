import os
import requests as http_client

# Pattern: Cross-service HTTP call — tracing headers propagated
# automatically by ddtrace. Adapt: inject the target service
# URL via environment variable.
TARGET_URL = os.environ.get("TARGET_SERVICE_URL", "http://localhost:8080")


def call(path):
    resp = http_client.get(f"{TARGET_URL}{path}", timeout=5)
    return resp.json()
