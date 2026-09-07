// Pattern: Feature Flags — boolean gate with user targeting context
// Deps: dd-trace@>=5.80.0, @openfeature/server-sdk@~1.20.0
// Note: DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED=true is set by the manifest agent_env
// Adapt: replace 'checkout-new-flow' with your flag key; add domain attributes to context
const tracer = require('dd-trace');
const { OpenFeature } = require('@openfeature/server-sdk');

OpenFeature.setProvider(tracer.openfeature);
const client = OpenFeature.getClient();

async function isCheckoutEnabled(userId, plan) {
  return client.getBooleanValue('checkout-new-flow', false, { targetingKey: userId, plan });
}

module.exports = { client, isCheckoutEnabled };
