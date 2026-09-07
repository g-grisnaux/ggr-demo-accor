# Instrumentation patterns — Python Flask

| Pattern | Feature | Description |
|---------|---------|-------------|
| slow_query_repository.py | dbm:postgresql | Slow SELECT with artificial delay |
| n_plus_one_route.py | dbm:postgresql | N+1 query on related entities |
| unsafe_search_route.py | security:code | SQL injection via string format |
| ssrf_example_route.py | security:code | SSRF via unvalidated URL param |
| cpu_intensive_service.py | profiling | Nested loop aggregation |
| memory_leak_service.py | profiling | Gradual allocation in a cache |
| audit_log_middleware.py | siem | Structured audit log for auth events |
| inter_service_client.py | (base) | HTTP call with tracing headers propagated |
| kafka_producer_route.py | dsm:kafka | Kafka producer for pipeline monitoring |
| kafka_consumer_service.py | dsm:kafka | Kafka consumer with optional lag simulation |
| rag_seed_route.py | ai:llmobs | Embed and store documents in pgvector for RAG |
| rag_chat_route.py | ai:llmobs | RAG chat: embed query, search pgvector, generate response |
| slow_query_mysql_repository.py | dbm:mysql | Slow SELECT with artificial delay (MySQL) |
| n_plus_one_mysql_route.py | dbm:mysql | N+1 query on related entities (MySQL) |
| slow_aggregation_mongo_repository.py | dbm:mongodb | Expensive aggregation pipeline (MongoDB) |
| unindexed_query_mongo_repository.py | dbm:mongodb | Collection scan on unindexed field (MongoDB) |
| rag_seed_mongo_route.py | ai:llmobs | Embed and store documents in MongoDB for RAG |
| rag_chat_mongo_route.py | ai:llmobs | RAG chat using MongoDB vector search |
| spark_etl_job.py | djm:spark | Spark ETL job reading from project database |
| airflow_etl_dag.py | djm:airflow | Airflow ETL DAG processing project database |
| feature_flag_boolean_gate.py | delivery:feature-flags | OpenFeature boolean gate with user targeting context |
| feature_flag_string_variant.py | delivery:feature-flags | OpenFeature string variant for A/B branching |
