package com.example.service;

import com.mongodb.client.*;
import com.mongodb.client.model.*;
import org.bson.Document;
import java.util.*;

// Pattern: DBM slow aggregation — expensive pipeline on large collection
// Adapt: replace collection and field names with domain entities
public class SlowAggregationMongoRepository {

    private final MongoCollection<Document> events;

    public SlowAggregationMongoRepository(MongoClient client) {
        this.events = client.getDatabase("demo").getCollection("events");
    }

    public List<Document> aggregateEvents() {
        return events.aggregate(List.of(
            Aggregates.group("$category", Accumulators.sum("total", "$amount"), Accumulators.sum("count", 1)),
            Aggregates.sort(Sorts.descending("total")),
            Aggregates.limit(10)
        )).into(new ArrayList<>());
    }
}
