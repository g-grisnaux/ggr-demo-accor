const { Kafka } = require('kafkajs');
const pino = require('pino');

// Pattern: DSM — Kafka consumer with optional lag simulation
// Adapt: replace processing logic with domain-specific handling
const log = pino({ name: 'kafka-consumer' });
const DELAY_MS = parseInt(process.env.KAFKA_CONSUMER_DELAY_MS || '0', 10);
const kafka = new Kafka({
  brokers: [process.env.KAFKA_BOOTSTRAP_SERVERS || 'kafka:9092'],
});

async function startConsumer() {
  const consumer = kafka.consumer({ groupId: 'demo-consumer-group' });
  await consumer.connect();
  await consumer.subscribe({ topic: 'demo-events', fromBeginning: false });
  await consumer.run({
    eachMessage: async ({ message }) => {
      log.info({ event: message.value.toString() }, 'consumed event');
      if (DELAY_MS > 0) await new Promise(r => setTimeout(r, DELAY_MS));
    },
  });
}

module.exports = { startConsumer };
