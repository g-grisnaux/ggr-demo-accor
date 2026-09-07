# Instrumentation patterns — Java Spring

| Pattern | Feature | Description |
|---------|---------|-------------|
| SlowQueryRepository.java | dbm:postgresql | Slow SELECT with artificial delay |
| NplusOneController.java | dbm:postgresql | N+1 query on related entities |
| UnsafeSearchController.java | security:code | SQL injection via string concat |
| SsrfExampleService.java | security:code | SSRF via unvalidated URL param |
| CpuIntensiveService.java | profiling | Nested loop aggregation |
| MemoryLeakService.java | profiling | Gradual allocation in a cache |
| AuditLogFilter.java | siem | Structured audit log for auth events |
| InterServiceClient.java | (base) | HTTP call with tracing headers propagated |
| KafkaProducerController.java | dsm:kafka | Kafka producer for pipeline monitoring |
| KafkaConsumerService.java | dsm:kafka | Kafka consumer with optional lag simulation |
| RagSeedController.java | ai:llmobs | Embed and store documents in pgvector for RAG |
| RagChatController.java | ai:llmobs | RAG chat: embed query, search pgvector, generate response |
| SlowQueryMysqlRepository.java | dbm:mysql | Slow SELECT with artificial delay (MySQL) |
| NplusOneMysqlController.java | dbm:mysql | N+1 query on related entities (MySQL) |
| SlowAggregationMongoRepository.java | dbm:mongodb | Expensive aggregation pipeline (MongoDB) |
| UnindexedQueryMongoRepository.java | dbm:mongodb | Collection scan on unindexed field (MongoDB) |
| RagSeedMongoController.java | ai:llmobs | Embed and store documents in MongoDB for RAG |
| RagChatMongoController.java | ai:llmobs | RAG chat using MongoDB vector search |
| SparkEtlJob.java | djm:spark | Spark ETL job reading from project database |
| FeatureFlagBooleanGate.java | delivery:feature-flags | OpenFeature boolean gate with user targeting context |
| FeatureFlagStringVariant.java | delivery:feature-flags | OpenFeature string variant for A/B branching |
