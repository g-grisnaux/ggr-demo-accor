# Diagnostic Hints

Common telemetry failures and their fixes. Referenced by the verify-telemetry skill when reporting FAIL results.

## Service Not Found in Catalog

**Likely cause:** `DD_SERVICE` env var not set, or Datadog Agent not running.

**Fix:**
1. Check `docker-compose.yml` — verify the service has `DD_SERVICE=<name>` in its environment
2. Check Agent is running: `docker compose ps datadog-agent`
3. Check Agent logs: `docker compose logs datadog-agent | tail -50`

## Logs Missing dd.trace_id

**Likely cause:** Trace-log correlation not configured in the application's logging library.

**Fix:**
- **Java**: Verify `logstash-logback-encoder` is in pom.xml and `logback-spring.xml` includes MDC key names `dd.trace_id` and `dd.span_id`
- **Python**: Verify `python-json-logger` is in requirements.txt and the JSON formatter is configured with dd trace fields

## Fragmented Traces (Single-Service Only)

**Likely cause:** Trace context not propagated between services. The HTTP client used for inter-service calls is not instrumented.

**Fix:**
- **Java**: Ensure `RestTemplate` is used (auto-instrumented by dd-java-agent). Do not use raw `HttpURLConnection`.
- **Python**: Ensure `requests` library is used (auto-instrumented by ddtrace). Do not use `urllib` directly.

## RUM Events Missing

**Likely cause:** RUM SDK not initialized — missing application ID or client token.

**Fix:**
1. Check `.env` has `DD_RUM_APPLICATION_ID` and `DD_RUM_CLIENT_TOKEN` set (not placeholder values)
2. Check `frontend/src/main.tsx` — verify `datadogRum.init()` is called
3. Check frontend container is running and accessible at http://localhost:3000

## DBM Not Flowing

**Likely cause:** The `datadog` monitoring user or `pg_stat_statements` extension is missing.

**Fix:**
1. Check `deps/postgresql/init.sql` was mounted: `docker compose exec postgresql psql -U demo -c "SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'"`
2. Check `datadog` user exists: `docker compose exec postgresql psql -U demo -c "SELECT 1 FROM pg_roles WHERE rolname = 'datadog'"`
3. If either is missing, recreate the container: `docker compose down postgresql && docker compose up -d postgresql`

## Tags Mismatch (env/service/version)

**Likely cause:** `DD_ENV` is set differently across services, or a service overrides the shared `.env` value.

**Fix:**
1. Check `docker-compose.yml` — all services should reference `${DD_ENV}` from the shared `.env` file
2. Check no service has a hardcoded `DD_ENV` value overriding the variable
3. Verify with: `docker compose config | grep DD_ENV`
