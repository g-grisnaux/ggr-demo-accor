const tracer = require('dd-trace');
const { UpstreamError } = require('../errors');

// Shared REST client for every downstream API. dd-trace propagates the trace
// context on the outgoing fetch automatically, which is what lets a GraphQL
// operation be followed all the way into the REST spans.
//
// Each call gets its own span named after the logical upstream operation so the
// APM service map shows `searchHotels -> hotel-search-api` rather than an
// anonymous HTTP client span.
function makeClient({ name, baseUrl, timeoutMs = 5000 }) {
  async function request(operation, path, { method = 'GET', body, query } = {}) {
    const url = new URL(`${baseUrl}${path}`);
    if (query) {
      for (const [k, v] of Object.entries(query)) {
        if (v !== undefined && v !== null) url.searchParams.set(k, String(v));
      }
    }

    return tracer.trace(
      'bff.upstream.request',
      {
        resource: `${name}.${operation}`,
        tags: {
          'upstream.service': name,
          'upstream.operation': operation,
          'http.method': method,
          'span.kind': 'client',
        },
      },
      async (span) => {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), timeoutMs);
        try {
          const resp = await fetch(url, {
            method,
            signal: controller.signal,
            headers: { 'content-type': 'application/json' },
            body: body ? JSON.stringify(body) : undefined,
          });

          span.setTag('http.status_code', resp.status);

          // 4xx carrying a business code is a normal outcome the resolver will
          // translate; only 5xx and transport failures are upstream incidents.
          const payload = await resp.json().catch(() => ({}));
          if (resp.status >= 500) {
            span.setTag('error', true);
            throw new UpstreamError(name, resp.status, `${name} failed on ${operation}`);
          }
          return { status: resp.status, body: payload };
        } catch (err) {
          if (err instanceof UpstreamError) throw err;
          span.setTag('error', true);
          span.setTag('error.message', err.message);
          const reason = err.name === 'AbortError' ? 'timeout' : 'transport';
          span.setTag('upstream.failure_reason', reason);
          throw new UpstreamError(name, 0, `${name} unreachable on ${operation} (${reason})`);
        } finally {
          clearTimeout(timer);
        }
      }
    );
  }

  return { name, request };
}

module.exports = { makeClient };
