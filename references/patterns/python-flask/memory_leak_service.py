from flask import request, jsonify

# Pattern: Profiling — gradual memory allocation in a cache
# Adapt: use a domain-relevant cache concept
_cache = {}


def add_to_cache():
    key = request.args.get("key", "default")
    _cache[key] = bytearray(1024 * 100)  # 100KB per entry
    return jsonify({"cached": len(_cache), "key": key})
