# Scenario template: Slow endpoint
# Usage: Customize the endpoint and expected latency for your domain

@task(10)
def slow_endpoint(self):
    """Hit an endpoint known to be slow"""
    with self.client.get("/api/ENDPOINT", catch_response=True) as resp:
        if resp.elapsed.total_seconds() > 1:
            resp.failure(f"Slow response: {resp.elapsed.total_seconds():.2f}s")
