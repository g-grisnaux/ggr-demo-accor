package com.example.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;

// Pattern: DSM — Kafka consumer with optional lag simulation
// Adapt: replace processing logic with domain-specific handling
@Service
public class KafkaConsumerService {

    private static final Logger log = LoggerFactory.getLogger(KafkaConsumerService.class);
    private static final long DELAY = Long.parseLong(
            System.getenv().getOrDefault("KAFKA_CONSUMER_DELAY_MS", "0"));

    @KafkaListener(topics = "demo-events", groupId = "demo-consumer-group")
    public void consume(String message) throws InterruptedException {
        log.info("consumed event: {}", message);
        if (DELAY > 0) Thread.sleep(DELAY);
    }
}
