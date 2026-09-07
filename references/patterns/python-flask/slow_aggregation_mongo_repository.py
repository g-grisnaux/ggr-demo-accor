import os
from pymongo import MongoClient

# Pattern: DBM slow aggregation — expensive pipeline on large collection
# Adapt: replace collection and field names with domain entities
MONGO_URL = os.environ.get("MONGODB_URL", "mongodb://demo:demo@mongodb:27017/demo")
_client = MongoClient(MONGO_URL)
_db = _client.get_default_database()


def aggregate_events():
    pipeline = [
        {"$group": {"_id": "$category", "total": {"$sum": "$amount"}, "count": {"$sum": 1}}},
        {"$sort": {"total": -1}},
        {"$limit": 10},
    ]
    return list(_db.events.aggregate(pipeline))
