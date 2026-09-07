# Scenario template: Error burst
# Usage: Send a burst of requests that trigger errors

@task(20)
def error_burst(self):
    """Send multiple failing requests in quick succession"""
    for _ in range(5):
        self.client.post("/api/ENDPOINT", json={"name": "ENTITY-fail-500"})
