package com.example.service;

import org.apache.spark.sql.*;
import static org.apache.spark.sql.functions.*;
import java.util.Properties;

// Pattern: DJM — Spark ETL job reading from project database
// Adapt: replace table names and transformations with domain logic
public class SparkEtlJob {

    public static void main(String[] args) {
        SparkSession spark = SparkSession.builder().appName("demo-etl").getOrCreate();
        Properties props = new Properties();
        props.put("user", "demo");
        props.put("password", "demo");
        props.put("driver", "org.postgresql.Driver");

        String url = "jdbc:postgresql://postgresql:5432/demo";
        Dataset<Row> df = spark.read().jdbc(url, "your_table", props);
        Dataset<Row> summary = df.groupBy("category")
            .agg(count("*").alias("total"), sum("amount").alias("revenue"));
        summary.write().mode(SaveMode.Overwrite).jdbc(url, "your_table_summary", props);
        spark.stop();
    }
}
