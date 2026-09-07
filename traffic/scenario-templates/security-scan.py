# Scenario template: Security scan
# Usage: Simulate common attack patterns

@task(5)
def security_scan(self):
    """Simulate common security probes"""
    payloads = [
        {"q": "' OR 1=1 --"},
        {"q": "<script>alert(1)</script>"},
        {"q": "../../etc/passwd"},
    ]
    for payload in payloads:
        self.client.get("/api/ENDPOINT/search", params=payload)
