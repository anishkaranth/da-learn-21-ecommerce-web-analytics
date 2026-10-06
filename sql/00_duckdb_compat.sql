-- 00_duckdb_compat.sql  (DuckDB ONLY - do NOT run on Databricks)
-- Spark / Databricks SQL function shims so that 02-05 can be written in Spark SQL dialect
-- and still execute unchanged on DuckDB. On Databricks these functions are built in.
-- to_date(s, 'yyyyMMdd'): this project only ever parses GA4 event_date strings, so the shim fixes the format to %Y%m%d.
CREATE OR REPLACE MACRO to_date(s, fmt) AS CAST(strptime(s, '%Y%m%d') AS DATE);
-- timestamp_micros(us): microseconds since epoch -> TIMESTAMP (UTC wall clock, no time zone)
CREATE OR REPLACE MACRO timestamp_micros(us) AS make_timestamp(CAST(us AS BIGINT));
CREATE OR REPLACE MACRO datediff(end_d, start_d) AS date_diff('day', CAST(start_d AS DATE), CAST(end_d AS DATE));
CREATE OR REPLACE MACRO unix_timestamp(ts) AS CAST(epoch(CAST(ts AS TIMESTAMP)) AS BIGINT);
CREATE OR REPLACE MACRO percentile_approx(x, p) AS quantile_cont(x, p);
CREATE OR REPLACE MACRO dayofweek(d) AS (isodow(CAST(d AS DATE)) % 7) + 1;
CREATE OR REPLACE MACRO date_format_yyyymmdd(d) AS CAST(strftime(CAST(d AS DATE), '%Y%m%d') AS INT);
-- sequence(start, stop, step) + explode(array): Spark calendar generation -> DuckDB generate_series + unnest
CREATE OR REPLACE MACRO sequence(a, b, step) AS generate_series(CAST(a AS TIMESTAMP), CAST(b AS TIMESTAMP), step);
CREATE OR REPLACE MACRO explode(l) AS unnest(l);
