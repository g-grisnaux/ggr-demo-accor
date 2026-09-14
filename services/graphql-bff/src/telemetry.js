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
              // Second copy of the same information, named and cased exactly
              // like the DogStatsD tag. Datadog's built-in "View traces" pivot
              // on a metric widget carries the metric's group-by tag verbatim —
              // tag name `error_code`, value lowercased by the metrics intake —
              // so a span tagged only `graphql.error.code:PAYMENT_DECLINED`
              // never matches and the pivot lands on an empty search.
              span.setTag('error_code', code.toLowerCase());
              span.setTag('error_kind', kind.toLowerCase());
              // Business rejections are valid outcomes, not service failures, so
              // they must not inflate the APM error rate. A genuine upstream or
              // server failure is the opposite and has to be visible as an
              // error — otherwise `status:error` on this service returns
              // nothing during an actual outage, which is what happened before
              // this distinction existed.
              span.setTag('error', kind !== 'BUSINESS');
            }
            statsd.increment('bff.graphql.errors', 1, {
              operation: operationName,
              error_code: code,
              error_kind: kind,
              upstream_service: (err.extensions && err.extensions.upstreamService) || 'none',
              client_name: clientName,
            });
            // Same split for the log level. A declined card is a warning; a
            // downstream service that stopped answering is an error. Keeping
            // both at warn meant the entry-point service looked healthy in the
            // logs while the service behind it was logging errors.
            const logAtErrorLevel = kind !== 'BUSINESS';
            const logPayload = {
              operation: operationName,
              error_code: code,
              error_kind: kind,
              upstream_service: (err.extensions && err.extensions.upstreamService) || undefined,
              msg_detail: err.message,
            };
            if (logAtErrorLevel) {
              logger.error(logPayload, 'graphql operation failed');
            } else {
              logger.warn(logPayload, 'graphql operation rejected');
            }
          }
        },

        async willSendResponse(ctx) {
          const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;
          const operationName = ctx.operationName || 'anonymous';

          statsd.histogram('bff.graphql.operation.duration', elapsedMs, {
            operation: operationName,
            client_name: clientName,
          });

          // One log line per operation, success or not. Without it the BFF is
          // silent on the happy path, so opening "Logs" from a successful trace
          // shows nothing from the entry point — the service that owns the
          // public contract is exactly the one you want to read first.
          const errors = ctx.errors || [];
          logger.info(
            {
              operation: operationName,
              operation_type: ctx.operation?.operation || 'unknown',
              duration_ms: Math.round(elapsedMs * 100) / 100,
              client_name: clientName,
              client_version: clientVersion,
              error_count: errors.length,
              error_code: errors.length ? errorCodeOf(errors[0]) : null,
            },
            'graphql operation completed'
          );
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
