const { Kafka } = require('kafkajs');

// Pattern: DSM — Kafka producer for pipeline monitoring
// Adapt: replace topic name and payload with domain events
const kafka = new Kafka({
  brokers: [process.env.KAFKA_BOOTSTRAP_SERVERS || 'kafka:9092'],
});
const producer = kafka.producer();
let connected = false;

async function publishEvent(req, res) {
  if (!connected) { await producer.connect(); connected = true; }
  const id = require('crypto').randomUUID();
  await producer.send({
    topic: 'demo-events',
    messages: [{ key: id, value: JSON.stringify({ id, timestamp: Date.now() }) }],
  });
  res.json({ status: 'sent', id });
}

module.exports = { publishEvent };
