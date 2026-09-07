import psycopg2
import os
from flask import jsonify

# Pattern: DBM N+1 — one query per parent row
# Adapt: replace table/column names with domain entities
DB_URL = os.environ.get("DATABASE_URL", "postgresql://demo:demo@postgresql:5432/demo")


def items_with_details():
    conn = psycopg2.connect(DB_URL)
    cur = conn.cursor()
    cur.execute("SELECT * FROM parents")
    parents = cur.fetchall()
    results = []
    for parent in parents:
        cur.execute("SELECT * FROM children WHERE parent_id = %s", (parent[0],))
        results.append({"parent": parent, "children": cur.fetchall()})
    cur.close()
    conn.close()
    return jsonify(results)
