import os
from pymongo import MongoClient

# Pattern: DBM unindexed query — collection scan (COLLSCAN)
# Adapt: replace collection and field names with domain entities
MONGO_URL = os.environ.get("MONGODB_URL", "mongodb://demo:demo@mongodb:27017/demo")
_client = MongoClient(MONGO_URL)
_db = _client.get_default_database()


def find_by_category(category):
    return list(_db.events.find({"category": category}).sort("created_at", -1).limit(50))
