import os
import time
import logging
from confluent_kafka import Consumer

# Pattern: DSM — Kafka consumer with optional lag simulation
# Adapt: replace processing logic with domain-specific handling
log = logging.getLogger("kafka-consumer")
DELAY_S = int(os.environ.get("KAFKA_CONSUMER_DELAY_MS", "0")) / 1000.0


def run_consumer():
    consumer = Consumer({
        "bootstrap.servers": os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092"),
        "group.id": "demo-consumer-group",
        "auto.offset.reset": "latest",
    })
    consumer.subscribe(["demo-events"])
    while True:
        msg = consumer.poll(1.0)
        if msg is None or msg.error():
            continue
        log.info("consumed event: %s", msg.value().decode())
        if DELAY_S > 0:
            time.sleep(DELAY_S)
