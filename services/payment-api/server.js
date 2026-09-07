const tracer = require('dd-trace').init({ logInjection: true });

// Low-level integrations that add no application meaning to a booking flame
// graph: dns.lookup on the agent hostname, socket-level net spans, and fs
// reads. They were the "datadog-agent" spans sitting in the middle of every
// trace. The http blocklist below covers the agent's own HTTP traffic.
tracer.use('dns', false);
tracer.use('net', false);
tracer.use('fs', false);

// Keeps dd-trace's own agent traffic (profiling, remote config) out of the
// application flame graphs.
tracer.use('http', {
  client: {
    blocklist: [process.env.DD_AGENT_HOST || 'localhost'],
  },
});

const express = require('express');
const pino = require('pino');
const StatsD = require('hot-shots');
const { Pool } = require('pg');

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
const port = Number(process.env.PORT || 8083);

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://accor:accor@postgresql:5432/accor',
  max: 10,
});

const statsd = new StatsD({
  host: process.env.DD_AGENT_HOST || 'localhost',
  port: 8125,
  globalTags: {
    env: process.env.DD_ENV || 'dev',
    service: process.env.DD_SERVICE || 'payment-api',
    version: process.env.DD_VERSION || '1.0.0',
  },
  errorHandler: () => {},
});

// Baseline refusal rate of a real payment funnel. The scenario raises it to
// produce the error-rate spike anomaly detection is meant to catch.
let declineRate = Number(process.env.PAYMENT_DECLINE_RATE || '0.04');

const DECLINE_REASONS = [
  { code: 'insufficient_funds', message: 'Insufficient funds', weight: 0.5 },
  { code: 'card_expired', message: 'Card expired', weight: 0.2 },
  { code: 'do_not_honor', message: 'Issuer declined the transaction', weight: 0.3 },
];

function pickDeclineReason(seed) {
  // Seeded from the booking so a replay of the same booking behaves the same
  // way — makes a scenario reproducible on stage.
  let roll = ((seed * 2654435761) % 1000) / 1000;
  for (const reason of DECLINE_REASONS) {
    if (roll < reason.weight) return reason;
    roll -= reason.weight;
  }
  return DECLINE_REASONS[DECLINE_REASONS.length - 1];
}

const app = express();
app.use(express.json({ limit: '64kb' }));

app.get('/health', (_req, res) => res.json({ status: 'ok', service: process.env.DD_SERVICE || 'payment-api' }));

app.post('/payments', async (req, res) => {
  const { booking_id: bookingId, amount_cents: amountCents, currency = 'EUR', method = 'VISA' } = req.body || {};

  if (!Number.isFinite(Number(amountCents)) || Number(amountCents) <= 0) {
    return res.status(400).json({ error_code: 'invalid_amount', message: 'amount_cents must be a positive number' });
  }

  const declined = Math.random() < declineRate;
  const reason = declined ? pickDeclineReason(Number(bookingId) || 1) : null;
  const status = declined ? 'DECLINED' : 'AUTHORIZED';

  // Authorization latency is where a payment partner actually hurts, so it is
  // modelled rather than instant. Declines come back faster than approvals,
  // which is what real issuers do.
  await new Promise((resolve) => setTimeout(resolve, declined ? 20 + Math.random() * 30 : 60 + Math.random() * 90));

  let paymentId = null;
  try {
    const { rows } = await pool.query(
      `INSERT INTO payments (booking_id, status, amount_cents, currency, method, decline_reason)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING payment_id`,
      [bookingId || null, status, Math.round(Number(amountCents)), currency, method, reason ? reason.code : null]
    );
    paymentId = rows[0].payment_id;
  } catch (err) {
    logger.error({ err, booking_id: bookingId }, 'failed to persist payment');
    statsd.increment('payment.authorization', 1, { status: 'ERROR', decline_reason: 'persistence_failure' });
    return res.status(503).json({ error_code: 'payment_unavailable', message: 'Payment could not be recorded' });
  }

  statsd.increment('payment.authorization', 1, {
    status,
    decline_reason: reason ? reason.code : 'none',
    method,
  });

  const payload = {
    payment_id: paymentId,
    booking_id: bookingId,
    status,
    amount_cents: Math.round(Number(amountCents)),
    currency,
    method,
    decline_reason: reason ? reason.code : null,
  };

  if (declined) {
    logger.warn({ payment_id: paymentId, booking_id: bookingId, decline_reason: reason.code }, 'payment declined');
    // 402 with a machine-readable code — booking-api maps it onto the public
    // PAYMENT_DECLINED GraphQL error.
    return res.status(402).json({ ...payload, error_code: reason.code, message: reason.message });
  }

  logger.info({ payment_id: paymentId, booking_id: bookingId, amount_cents: payload.amount_cents }, 'payment authorized');
  return res.status(201).json(payload);
});

app.get('/payments/:paymentId', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT payment_id, booking_id, status, amount_cents, currency, method, decline_reason
     FROM payments WHERE payment_id = $1`,
    [req.params.paymentId]
  );
  if (rows.length === 0) {
    return res.status(404).json({ error_code: 'payment_not_found', message: 'No such payment' });
  }
  return res.json(rows[0]);
});

// Scenario control — cluster-internal only, never exposed through the ingress.
app.get('/admin/scenario', (_req, res) => res.json({ decline_rate: declineRate }));

app.post('/admin/scenario', (req, res) => {
  const next = Number(req.query.declineRate);
  if (!Number.isFinite(next) || next < 0 || next > 1) {
    return res.status(400).json({ error_code: 'invalid_request', message: 'declineRate must be between 0 and 1' });
  }
  declineRate = next;
  logger.warn({ decline_rate: declineRate }, 'demo scenario changed payment decline rate');
  return res.json({ decline_rate: declineRate });
});

app.listen(port, () => logger.info({ port }, 'payment-api started'));
