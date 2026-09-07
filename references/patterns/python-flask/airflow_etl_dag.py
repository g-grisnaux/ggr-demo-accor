import psycopg2
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

# Pattern: DJM — Airflow ETL DAG processing project database
# Adapt: replace task logic with domain-specific extraction and transformation
DB_URL = "postgresql://demo:demo@postgresql:5432/demo"


def extract(**ctx):
    conn = psycopg2.connect(DB_URL)
    cur = conn.cursor()
    cur.execute("SELECT * FROM your_table")
    ctx["ti"].xcom_push(key="rows", value=cur.fetchall())
    cur.close()
    conn.close()


def transform(**ctx):
    rows = ctx["ti"].xcom_pull(key="rows", task_ids="extract")
    summary = {}
    for row in rows:
        cat = row[1]
        summary[cat] = summary.get(cat, 0) + 1
    ctx["ti"].xcom_push(key="summary", value=summary)


def load(**ctx):
    summary = ctx["ti"].xcom_pull(key="summary", task_ids="transform")
    conn = psycopg2.connect(DB_URL)
    cur = conn.cursor()
    for cat, total in summary.items():
        cur.execute(
            "INSERT INTO your_table_summary (category, total) VALUES (%s, %s) "
            "ON CONFLICT (category) DO UPDATE SET total = %s",
            (cat, total, total),
        )
    conn.commit()
    cur.close()
    conn.close()


with DAG("etl_pipeline", schedule="@daily", start_date=datetime(2024, 1, 1), catchup=False) as dag:
    extract_task = PythonOperator(task_id="extract", python_callable=extract)
    transform_task = PythonOperator(task_id="transform", python_callable=transform)
    load_task = PythonOperator(task_id="load", python_callable=load)
    extract_task >> transform_task >> load_task
