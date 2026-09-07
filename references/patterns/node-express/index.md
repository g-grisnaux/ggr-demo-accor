# Instrumentation patterns — Node.js Express

| Pattern | Feature | Description |
|---------|---------|-------------|
| slow_query_repository.js | dbm:postgresql | Slow SELECT with artificial delay |
| n_plus_one_route.js | dbm:postgresql | N+1 query on related entities |
| unsafe_search_route.js | security:code | SQL injection via string concat |
| ssrf_example_route.js | security:code | SSRF via unvalidated URL param |
| cpu_intensive_service.js | profiling | Nested loop aggregation |
| memory_leak_service.js | profiling | Gradual allocation in a cache |
| audit_log_middleware.js | siem | Structured audit log for auth events |
| inter_service_client.js | (base) | HTTP call with tracing headers propagated |
| kafka_producer_route.js | dsm:kafka | Kafka producer for pipeline monitoring |
| kafka_consumer_service.js | dsm:kafka | Kafka consumer with optional lag simulation |
| rag_seed_route.js | ai:llmobs | Embed and store documents in pgvector for RAG |
| rag_chat_route.js | ai:llmobs | RAG chat: embed query, search pgvector, generate response |
| slow_query_mysql_repository.js | dbm:mysql | Slow SELECT with artificial delay (MySQL) |
| n_plus_one_mysql_route.js | dbm:mysql | N+1 query on related entities (MySQL) |
| slow_aggregation_mongo_repository.js | dbm:mongodb | Expensive aggregation pipeline (MongoDB) |
| unindexed_query_mongo_repository.js | dbm:mongodb | Collection scan on unindexed field (MongoDB) |
| rag_seed_mongo_route.js | ai:llmobs | Embed and store documents in MongoDB for RAG |
| rag_chat_mongo_route.js | ai:llmobs | RAG chat using MongoDB vector search |
| feature_flag_boolean_gate.js | delivery:feature-flags | OpenFeature boolean gate with user targeting context |
| feature_flag_string_variant.js | delivery:feature-flags | OpenFeature string variant for A/B branching |
