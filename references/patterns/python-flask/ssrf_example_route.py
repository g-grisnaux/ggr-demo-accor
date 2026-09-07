import requests as http_client
from flask import request, jsonify

# Pattern: Code Security — SSRF via unvalidated URL parameter
# WARNING: intentionally vulnerable for IAST demo
# Adapt: use a domain-appropriate endpoint name


def fetch_url():
    url = request.args.get("url", "")
    try:
        resp = http_client.get(url, timeout=5)
        return resp.text
    except Exception as e:
        return jsonify({"error": str(e)}), 500
