const tracer = require('dd-trace');
const StatsD = require('hot-shots');

// DogStatsD carries the business-error breakdown. APM already knows a request
// errored; only the BFF knows *which* business rule rejected it, so that
// dimension has to be emitted explicitly to be alertable.
const statsd = new StatsD({
  host: process.env.DD_AGENT_HOST || 'localhost',
  port: 8125,
  globalTags: {
    env: process.env.DD_ENV || 'dev',
    service: process.env.DD_SERVICE || 'graphql-bff',
    version: process.env.DD_VERSION || '1.0.0',
  },
  errorHandler: () => {},
});

function errorCodeOf(err) {
  return (err.extensions && err.extensions.code) || 'UNKNOWN';
}

// Apollo plugin: tags the APM span with GraphQL-level context and emits the
// per-operation / per-error-code metrics. This is the Hive-equivalent layer —
// operation name, client platform and version, deprecated field usage.
function datadogGraphQLPlugin(logger) {
  return {
    async requestDidStart(requestContext) {
      const started = process.hrtime.bigint();
      const clientName = requestContext.request.http?.headers.get('x-client-name') || 'unknown';
      const clientVersion = requestContext.request.http?.headers.get('x-client-version') || 'unknown';

      return {
        async didResolveOperation(ctx) {
          const operationName = ctx.operationName || 'anonymous';
          const operationType = ctx.operation?.operation || 'unknown';
          const span = tracer.scope().active();
          if (span) {
            span.setTag('graphql.operation.name', operationName);
            span.setTag('graphql.operation.type', operationType);
            span.setTag('client.name', clientName);
            span.setTag('client.version', clientVersion);
          }
          statsd.increment('bff.graphql.operation', 1, {
            operation: operationName,
            operation_type: operationType,
            client_name: clientName,
            client_version: clientVersion,
          });
        },

        async didEncounterErrors(ctx) {
          const operationName = ctx.operationName || 'anonymous';
          const span = tracer.scope().active();
          for (const err of ctx.errors) {
            const code = errorCodeOf(err);
            const kind = (err.extensions && err.extensions.kind) || 'SERVER';
            if (span) {
              span.setTag('graphql.error.code', code);
              span.setTag('graphql.error.kind', kind);
              // Business rejections are valid outcomes, not service failures.
              // Marking them as errors would drown the real incidents.
              if (kind === 'BUSINESS') span.setTag('error', false);
            }
            statsd.increment('bff.graphql.errors', 1, {
              operation: operationName,
              error_code: code,
              error_kind: kind,
              upstream_service: (err.extensions && err.extensions.upstreamService) || 'none',
              client_name: clientName,
            });
            logger.warn(
              { operation: operationName, error_code: code, error_kind: kind, msg_detail: err.message },
              'graphql operation returned an error'
            );
          }
        },

        async willSendResponse(ctx) {
          const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;
          statsd.histogram('bff.graphql.operation.duration', elapsedMs, {
            operation: ctx.operationName || 'anonymous',
            client_name: clientName,
          });
        },
      };
    },
  };
}

// Field-resolution timings, per field, so field-level usage and latency can be
// read the way Accor reads them in Hive today.
function fieldTiming(parentType, fieldName, deprecated = false) {
  return (elapsedMs) => {
    statsd.histogram('bff.graphql.field.duration', elapsedMs, {
      parent_type: parentType,
      field: fieldName,
    });
    statsd.increment('bff.graphql.field.usage', 1, {
      parent_type: parentType,
      field: fieldName,
      deprecated: String(deprecated),
    });
  };
}

module.exports = { statsd, datadogGraphQLPlugin, fieldTiming, errorCodeOf };
