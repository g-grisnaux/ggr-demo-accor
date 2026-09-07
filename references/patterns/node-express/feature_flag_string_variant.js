// Pattern: Feature Flags — string variant for A/B branching
// Adapt: replace 'ui-theme' with your flag key; variant values must match Datadog flag config
const { client } = require('./feature_flag_boolean_gate'); // provider already initialized

const VARIANTS = { 'treatment-a': 'new_design_a', 'treatment-b': 'new_design_b' };

async function getUiVariant(userId) {
  const variant = await client.getStringValue('ui-theme', 'control', { targetingKey: userId });
  return VARIANTS[variant] ?? 'control_design';
}

module.exports = { getUiVariant };
