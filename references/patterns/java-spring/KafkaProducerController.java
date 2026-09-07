package com.example.service;

import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.web.bind.annotation.*;
import java.util.*;

// Pattern: DSM — Kafka producer for pipeline monitoring
// Adapt: replace topic name and payload with domain events
@RestController
public class KafkaProducerController {

    private final KafkaTemplate<String, String> kafka;

    public KafkaProducerController(KafkaTemplate<String, String> kafka) {
        this.kafka = kafka;
    }

    @PostMapping("/api/events/publish")
    public Map<String, Object> publish() {
        String id = UUID.randomUUID().toString();
        String payload = "{\"id\":\"" + id + "\",\"timestamp\":\"" + java.time.Instant.now() + "\"}";
        kafka.send("demo-events", id, payload);
        return Map.of("status", "sent", "id", id);
    }
}
