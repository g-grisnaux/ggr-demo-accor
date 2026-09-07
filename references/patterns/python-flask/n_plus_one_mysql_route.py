import mysql.connector
import os
from flask import jsonify

# Pattern: DBM N+1 — one query per parent row (MySQL)
# Adapt: replace table/column names with domain entities
MYSQL_CONFIG = {
    "host": os.environ.get("MYSQL_HOST", "mysql"),
    "user": os.environ.get("MYSQL_USER", "demo"),
    "password": os.environ.get("MYSQL_PASSWORD", "demo"),
    "database": os.environ.get("MYSQL_DATABASE", "demo"),
}


def items_with_details():
    conn = mysql.connector.connect(**MYSQL_CONFIG)
    cur = conn.cursor(dictionary=True)
    cur.execute("SELECT * FROM parents")
    parents = cur.fetchall()
    results = []
    for parent in parents:
        cur.execute("SELECT * FROM children WHERE parent_id = %s", (parent["id"],))
        results.append({"parent": parent, "children": cur.fetchall()})
    cur.close()
    conn.close()
    return jsonify(results)
