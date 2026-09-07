import mysql.connector
import os

# Pattern: DBM slow query — artificial delay via MySQL SLEEP
# Adapt: replace 'your_table' with a domain entity table
MYSQL_CONFIG = {
    "host": os.environ.get("MYSQL_HOST", "mysql"),
    "user": os.environ.get("MYSQL_USER", "demo"),
    "password": os.environ.get("MYSQL_PASSWORD", "demo"),
    "database": os.environ.get("MYSQL_DATABASE", "demo"),
}


def find_all_slow():
    conn = mysql.connector.connect(**MYSQL_CONFIG)
    cur = conn.cursor(dictionary=True)
    cur.execute("SELECT *, SLEEP(0.3) FROM your_table ORDER BY created_at DESC LIMIT 50")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return rows
