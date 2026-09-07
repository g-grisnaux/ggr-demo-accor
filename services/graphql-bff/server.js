// dd-trace must be initialised before anything else is required, otherwise the
// http/express/graphql integrations have nothing left to patch.
const tracer = require('dd-trace').init({
  logInjection: true,
});

// depth: -1 keeps a span for every field resolution, not just the top level.
// That per-field granularity is what replaces the field-level view the team
// reads in Hive today.
tracer.use('graphql', {
  depth: -1,
  signature: true,
  source: true,
});

const express = require('express');
const pino = require('pino');
const { ApolloServer } = require('@apollo/server');
const { expressMiddleware } = require('@as-integrations/express5');

const { typeDefs } = require('./src/schema');
const { resolvers } = require('./src/resolvers');
const { datadogGraphQLPlugin, errorCodeOf } = require('./src/telemetry');

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
const port = Number(process.env.PORT || 8080);

async function main() {
  const server = new ApolloServer({
    typeDefs,
    resolvers,
    // Introspection stays on: the demo shows schema exploration, and the
    // downstream APIs are not reachable from outside the cluster anyway.
    introspection: true,
    plugins: [datadogGraphQLPlugin(logger)],
    formatError: (formatted, raw) => {
      const code = errorCodeOf(formatted);
      // Business rejections travel with their code and stay client-readable.
      // Anything unexpected is logged in full and reduced to a generic message,
      // so an upstream stack trace never reaches a public client.
      if (formatted.extensions?.kind === 'BUSINESS' || formatted.extensions?.kind === 'UPSTREAM') {
        // Apollo attaches a stacktrace outside production; strip it
        // unconditionally so internal paths never reach a public client.
        const { stacktrace, ...extensions } = formatted.extensions;
        return { ...formatted, extensions };
      }
      logger.error({ err: raw, error_code: code }, 'unexpected graphql error');
      return {
        message: 'Internal error',
        extensions: { code: 'INTERNAL_ERROR', kind: 'SERVER' },
      };
    },
  });

  await server.start();

  const app = express();
  app.use(express.json({ limit: '256kb' }));

  app.get('/health', (_req, res) => res.json({ status: 'ok', service: process.env.DD_SERVICE || 'graphql-bff' }));

  app.use(
    '/graphql',
    expressMiddleware(server, {
      context: async ({ req }) => ({
        // Identity comes from the edge in production; here the headers stand in
        // for it and feed both the flag targeting and the RUM/APM correlation.
        guestId: req.headers['x-guest-id'] || 'anonymous',
        tier: req.headers['x-loyalty-tier'] || 'CLASSIC',
        clientName: req.headers['x-client-name'] || 'unknown',
        clientVersion: req.headers['x-client-version'] || 'unknown',
      }),
    })
  );

  app.listen(port, () => {
    logger.info({ port, endpoint: '/graphql' }, 'graphql-bff started');
  });
}

main().catch((err) => {
  logger.error({ err }, 'graphql-bff failed to start');
  process.exit(1);
});
