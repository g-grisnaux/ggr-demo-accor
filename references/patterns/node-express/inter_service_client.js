// Pattern: Cross-service HTTP call — tracing headers propagated
// automatically by dd-trace. Adapt: inject the target service
// URL via environment variable.
const TARGET_URL = process.env.TARGET_SERVICE_URL || 'http://localhost:8080';

async function call(path) {
  const resp = await fetch(`${TARGET_URL}${path}`);
  return resp.json();
}

module.exports = { call };
