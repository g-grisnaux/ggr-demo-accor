const tracer = require('dd-trace');
const { OpenFeature } = require('@openfeature/server-sdk');

// Datadog acts as the OpenFeature provider, so a flag evaluation is attached to
// the trace automatically — that is what makes "the N+1 came back after this
// flag flipped" visible instead of guesswork.
OpenFeature.setProvider(tracer.openfeature);
const client = OpenFeature.getClient();

// Batching availability through a dataloader is the correct behaviour. The flag
// exists so the demo can turn it off on stage and watch the flamegraph explode.
// Escape hatch for the stage. Flag delivery is a network round-trip that can be
// slow or unavailable in a conference room, so the N+1 scenario must also be
// triggerable from the deployment itself.
const FORCE_OFF = process.env.BFF_FORCE_DATALOADER_OFF === 'true';

async function isDataloaderEnabled(guestId, tier) {
  if (FORCE_OFF) return false;
  try {
    return await client.getBooleanValue('bff-availability-dataloader', true, {
      targetingKey: guestId || 'anonymous',
      tier: tier || 'CLASSIC',
    });
  } catch {
    // A flagging outage must never take the BFF down — batching stays on.
    return true;
  }
}

module.exports = { client, isDataloaderEnabled };
