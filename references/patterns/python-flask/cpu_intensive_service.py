from flask import jsonify

# Pattern: Profiling — CPU-intensive nested loop
# Adapt: replace with domain-relevant aggregation logic


def aggregate():
    counts = {}
    for _ in range(100):
        counts.clear()
        for j in range(10000):
            key = f"bucket-{j % 50}"
            counts[key] = counts.get(key, 0) + 1
    return jsonify({"buckets": len(counts), "iterations": 100 * 10000})
