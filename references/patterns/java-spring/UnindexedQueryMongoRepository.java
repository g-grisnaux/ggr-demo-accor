package com.example.service;

import com.mongodb.client.*;
import com.mongodb.client.model.Sorts;
import org.bson.Document;
import java.util.*;

// Pattern: DBM unindexed query — collection scan (COLLSCAN)
// Adapt: replace collection and field names with domain entities
public class UnindexedQueryMongoRepository {

    private final MongoCollection<Document> events;

    public UnindexedQueryMongoRepository(MongoClient client) {
        this.events = client.getDatabase("demo").getCollection("events");
    }

    public List<Document> findByCategory(String category) {
        return events.find(new Document("category", category))
            .sort(Sorts.descending("created_at"))
            .limit(50)
            .into(new ArrayList<>());
    }
}
