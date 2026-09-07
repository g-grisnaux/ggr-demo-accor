import psycopg2
import os

# Pattern: DBM slow query — artificial delay via pg_sleep
# Adapt: replace 'your_table' with a domain entity table
DB_URL = os.environ.get("DATABASE_URL", "postgresql://demo:demo@postgresql:5432/demo")


def find_all_slow():
    conn = psycopg2.connect(DB_URL)
    cur = conn.cursor()
    cur.execute("SELECT *, pg_sleep(0.3) FROM your_table ORDER BY created_at DESC LIMIT 50")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return rows
