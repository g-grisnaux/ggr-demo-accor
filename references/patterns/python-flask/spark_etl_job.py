from pyspark.sql import SparkSession
from pyspark.sql.functions import count, sum as _sum

# Pattern: DJM — Spark ETL job reading from project database
# Adapt: replace table names and transformations with domain logic
DB_URL = "jdbc:postgresql://postgresql:5432/demo"
DB_PROPS = {"user": "demo", "password": "demo", "driver": "org.postgresql.Driver"}

spark = SparkSession.builder.appName("demo-etl").getOrCreate()

df = spark.read.jdbc(DB_URL, "your_table", properties=DB_PROPS)
summary = df.groupBy("category").agg(
    count("*").alias("total"),
    _sum("amount").alias("revenue"),
)
summary.write.jdbc(DB_URL, "your_table_summary", mode="overwrite", properties=DB_PROPS)

spark.stop()
