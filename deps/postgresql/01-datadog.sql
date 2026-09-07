-- Datadog Database Monitoring setup for PostgreSQL.
-- Runs automatically on first container start via docker-entrypoint-initdb.d.
--
-- pg_stat_statements also needs `shared_preload_libraries=pg_stat_statements`,
-- which is passed as a command argument on the postgresql Deployment — an
-- extension alone is not enough.

CREATE USER datadog WITH PASSWORD 'datadog';
GRANT pg_monitor TO datadog;
ALTER ROLE datadog INHERIT;

CREATE SCHEMA IF NOT EXISTS datadog;
GRANT USAGE ON SCHEMA datadog TO datadog;
GRANT USAGE ON SCHEMA public TO datadog;

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Lets DBM collect execution plans for the queries it samples. SECURITY DEFINER
-- plus SET TRANSACTION READ ONLY keeps it to EXPLAIN and nothing else.
CREATE OR REPLACE FUNCTION datadog.explain_statement(
   l_query TEXT,
   OUT explain JSON
)
RETURNS SETOF JSON AS
$$
DECLARE
  curs REFCURSOR;
  plan JSON;
BEGIN
  SET TRANSACTION READ ONLY;
  OPEN curs FOR EXECUTE pg_catalog.concat('EXPLAIN (FORMAT JSON) ', l_query);
  FETCH curs INTO plan;
  CLOSE curs;
  RETURN QUERY SELECT plan;
END;
$$
LANGUAGE 'plpgsql'
RETURNS NULL ON NULL INPUT
SECURITY DEFINER;
