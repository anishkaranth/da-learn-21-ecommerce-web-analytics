-- 05_quality_checks.sql  Data-quality evidence: before/after counts, issue counts, null rates, assertions (Spark SQL dialect)

CREATE OR REPLACE TABLE dq_row_counts AS
SELECT 'raw events (stg_events)' AS entity, (SELECT COUNT(*) FROM stg_events) AS raw_rows,
       (SELECT COUNT(*) FROM (SELECT DISTINCT user_pseudo_id, event_timestamp, event_name, event_bundle_sequence_id FROM stg_events
                              WHERE event_name <> 'event_name') d) AS distinct_keys,
       (SELECT COUNT(*) FROM cln_events) AS clean_rows, 'event' AS grain
UNION ALL SELECT 'sessions', NULL, (SELECT COUNT(DISTINCT session_id) FROM cln_events), (SELECT COUNT(*) FROM cln_sessions), 'user_pseudo_id + ga_session_id'
UNION ALL SELECT 'purchase events -> transactions', (SELECT COUNT(*) FROM cln_events WHERE event_name = 'purchase'),
       (SELECT COUNT(*) FROM cln_events WHERE event_name = 'purchase' AND revenue_usd > 0), (SELECT COUNT(*) FROM cln_transactions), 'transaction'
UNION ALL SELECT 'users', NULL, NULL, (SELECT COUNT(DISTINCT user_pseudo_id) FROM cln_sessions), 'user_pseudo_id'
UNION ALL SELECT 'fact_session', NULL, NULL, (SELECT COUNT(*) FROM fact_session), 'session'
UNION ALL SELECT 'fact_transaction', NULL, NULL, (SELECT COUNT(*) FROM fact_transaction), 'transaction'
UNION ALL SELECT 'dim_date', NULL, NULL, (SELECT COUNT(*) FROM dim_date), 'day'
UNION ALL SELECT 'dim_device', NULL, NULL, (SELECT COUNT(*) FROM dim_device), 'device category x OS x browser'
UNION ALL SELECT 'dim_geo', NULL, NULL, (SELECT COUNT(*) FROM dim_geo), 'continent x sub-continent x country'
UNION ALL SELECT 'dim_traffic', NULL, NULL, (SELECT COUNT(*) FROM dim_traffic), 'first-touch source x medium x campaign';

CREATE OR REPLACE TABLE dq_null_rates AS
SELECT 'events' AS entity, 'ga_session_id' AS column_name,
       ROUND(100.0 * SUM(CASE WHEN ga_session_id IS NULL OR trim(ga_session_id) = '' THEN 1 ELSE 0 END) / COUNT(*), 3) AS null_pct, 'row dropped if NULL' AS treatment
FROM stg_events WHERE event_name <> 'event_name'
UNION ALL SELECT 'events', 'ep_medium (session-scoped medium param)', ROUND(100.0 * SUM(CASE WHEN ep_medium IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3),
       'resolved per session (first non-NULL); sessions with none -> (not set)' FROM cln_events
UNION ALL SELECT 'events', 'page_title (page_view events)', ROUND(100.0 * SUM(CASE WHEN page_title IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3),
       'landing page = (no page_view)' FROM cln_events WHERE event_name = 'page_view'
UNION ALL SELECT 'events', 'engagement_time_msec', ROUND(100.0 * SUM(CASE WHEN engagement_time_ms IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3),
       'treated as 0 in session sums' FROM cln_events
UNION ALL SELECT 'purchase events', 'ecom_revenue_usd', ROUND(100.0 * SUM(CASE WHEN revenue_usd IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3),
       'NULL / 0 revenue -> not a transaction' FROM cln_events WHERE event_name = 'purchase'
UNION ALL SELECT 'purchase events', 'ecom_transaction_id', ROUND(100.0 * SUM(dq_txn_id_missing) / COUNT(*), 3),
       'NULL or (not set) -> keyed by session + revenue' FROM cln_events WHERE event_name = 'purchase'
UNION ALL SELECT 'sessions', 'session source / medium', ROUND(100.0 * SUM(CASE WHEN sess_medium IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3),
       'session_channel = (not set); first-touch channel always present' FROM cln_sessions
UNION ALL SELECT 'events', 'traffic_medium = (other) / (data deleted) (obfuscated)', ROUND(100.0 * SUM(CASE WHEN traffic_medium IN ('(other)', '(data deleted)') THEN 1 ELSE 0 END) / COUNT(*), 3),
       'kept as own channel values' FROM cln_events;

CREATE OR REPLACE TABLE dq_issues AS
SELECT 'raw: repeated header lines inside the export (dropped)' AS check_name,
       (SELECT COUNT(*) FROM stg_events WHERE trim(event_name) = 'event_name') AS affected_rows
UNION ALL SELECT 'events: exact duplicate events dropped', (SELECT COUNT(*) FROM stg_events WHERE trim(event_name) <> 'event_name') - (SELECT COUNT(*) FROM cln_events)
UNION ALL SELECT 'ga_session_id values shared by 2+ users (key = user + session id)',
       (SELECT COUNT(*) FROM (SELECT ga_session_id FROM cln_sessions GROUP BY ga_session_id HAVING COUNT(*) > 1) x)
UNION ALL SELECT 'purchase events with revenue 0 / NULL (not transactions)', (SELECT SUM(dq_zero_revenue_purchase) FROM cln_events)
UNION ALL SELECT 'purchase events collapsed as repeats of the same transaction',
       (SELECT COUNT(*) FROM cln_events WHERE event_name = 'purchase' AND revenue_usd > 0) - (SELECT COUNT(*) FROM cln_transactions)
UNION ALL SELECT 'transactions with missing / (not set) transaction id (kept)', (SELECT SUM(dq_txn_id_missing) FROM cln_transactions)
UNION ALL SELECT 'transaction ids reused across sessions (obfuscation; kept separate)',
       (SELECT COUNT(*) FROM (SELECT transaction_id FROM cln_transactions WHERE transaction_id IS NOT NULL GROUP BY transaction_id HAVING COUNT(*) > 1) x)
UNION ALL SELECT 'transactions flagged revenue outlier (> Q3 + 3 IQR, kept)', (SELECT SUM(dq_revenue_outlier) FROM cln_transactions)
UNION ALL SELECT 'sessions without a session_start event (kept)', (SELECT SUM(dq_no_session_start) FROM cln_sessions)
UNION ALL SELECT 'sessions spanning > 4 h (flagged, kept)', (SELECT SUM(dq_long_session) FROM cln_sessions)
UNION ALL SELECT 'events with engagement_time > 1 h (flagged, kept)', (SELECT SUM(dq_engagement_outlier) FROM cln_events)
UNION ALL SELECT 'converting sessions without add_to_cart event (obfuscation)', (SELECT SUM(dq_purchase_without_cart) FROM cln_sessions)
UNION ALL SELECT 'converting sessions without begin_checkout event', (SELECT SUM(dq_purchase_without_checkout) FROM cln_sessions)
UNION ALL SELECT 'sessions with 2+ different session mediums (first one used)', (SELECT SUM(dq_multi_session_medium) FROM cln_sessions)
UNION ALL SELECT 'users whose first-touch medium differs between events (obfuscation)',
       (SELECT COUNT(*) FROM (SELECT user_pseudo_id FROM cln_sessions GROUP BY user_pseudo_id HAVING COUNT(DISTINCT ft_medium) > 1) x)
UNION ALL SELECT 'RI: sessions lost in dim joins', (SELECT COUNT(*) FROM cln_sessions) - (SELECT COUNT(*) FROM fact_session)
UNION ALL SELECT 'RI: transactions lost in session join', (SELECT COUNT(*) FROM cln_transactions) - (SELECT COUNT(*) FROM fact_transaction);

CREATE OR REPLACE TABLE dq_assertions AS
WITH c AS (
  SELECT 'clean events = distinct valid event keys in staging' AS check_name,
         (SELECT ABS((SELECT COUNT(*) FROM cln_events) - (SELECT COUNT(*) FROM (SELECT DISTINCT trim(user_pseudo_id), TRY_CAST(trim(event_timestamp) AS BIGINT),
            lower(trim(event_name)), TRY_CAST(trim(event_bundle_sequence_id) AS BIGINT) FROM stg_events
            WHERE trim(event_name) <> 'event_name' AND TRY_CAST(trim(ga_session_id) AS BIGINT) IS NOT NULL AND TRY_CAST(trim(event_timestamp) AS BIGINT) IS NOT NULL) k))) AS failed_rows
  UNION ALL SELECT 'no repeated header rows left', (SELECT COUNT(*) FROM cln_events WHERE event_name = 'event_name')
  UNION ALL SELECT 'event key unique in cln_events',
         (SELECT COUNT(*) FROM (SELECT user_pseudo_id, event_ts_us, event_name, bundle_seq FROM cln_events GROUP BY user_pseudo_id, event_ts_us, event_name, bundle_seq HAVING COUNT(*) > 1) x)
  UNION ALL SELECT 'event_date = UTC date of event_timestamp', (SELECT COUNT(*) FROM cln_events WHERE CAST(event_ts AS DATE) <> event_date)
  UNION ALL SELECT 'events within 2020-11-01..2021-01-31', (SELECT COUNT(*) FROM cln_events WHERE event_date < DATE '2020-11-01' OR event_date > DATE '2021-01-31')
  UNION ALL SELECT 'device_category in {desktop, mobile, tablet}', (SELECT COUNT(*) FROM cln_events WHERE device_category NOT IN ('desktop', 'mobile', 'tablet'))
  UNION ALL SELECT 'session_key unique in fact_session', (SELECT COUNT(*) - COUNT(DISTINCT session_key) FROM fact_session)
  UNION ALL SELECT 'session_id unique in fact_session', (SELECT COUNT(*) - COUNT(DISTINCT session_id) FROM fact_session)
  UNION ALL SELECT 'fact_session rows = distinct sessions in events', (SELECT ABS((SELECT COUNT(*) FROM fact_session) - (SELECT COUNT(DISTINCT session_id) FROM cln_events)))
  UNION ALL SELECT 'session attributes constant within session (device / OS / country / first touch)', (SELECT SUM(dq_attr_conflict) FROM cln_sessions)
  UNION ALL SELECT 'fact_session.date_key -> dim_date', (SELECT COUNT(*) FROM fact_session WHERE date_key NOT IN (SELECT date_key FROM dim_date))
  UNION ALL SELECT 'fact_session.device_key -> dim_device', (SELECT COUNT(*) FROM fact_session WHERE device_key NOT IN (SELECT device_key FROM dim_device))
  UNION ALL SELECT 'fact_session.geo_key -> dim_geo', (SELECT COUNT(*) FROM fact_session WHERE geo_key NOT IN (SELECT geo_key FROM dim_geo))
  UNION ALL SELECT 'fact_session.traffic_key -> dim_traffic', (SELECT COUNT(*) FROM fact_session WHERE traffic_key NOT IN (SELECT traffic_key FROM dim_traffic))
  UNION ALL SELECT 'fact_transaction.session_key -> fact_session', (SELECT COUNT(*) FROM fact_transaction WHERE session_key NOT IN (SELECT session_key FROM fact_session))
  UNION ALL SELECT 'fact_transaction rows = cleaned transactions', (SELECT ABS((SELECT COUNT(*) FROM fact_transaction) - (SELECT COUNT(*) FROM cln_transactions)))
  UNION ALL SELECT 'dim_date contiguous (rows = days between first and last date)',
         (SELECT ABS(COUNT(*) - (datediff(MAX(date), MIN(date)) + 1)) FROM dim_date)
  UNION ALL SELECT 'transaction revenue > 0', (SELECT COUNT(*) FROM fact_transaction WHERE revenue_usd IS NULL OR revenue_usd <= 0)
  UNION ALL SELECT 'session revenue = transaction revenue (total)',
         (SELECT CASE WHEN ABS((SELECT SUM(revenue_usd) FROM fact_session) - (SELECT SUM(revenue_usd) FROM fact_transaction)) < 0.01 THEN 0 ELSE 1 END)
  UNION ALL SELECT 'session transactions = transaction rows (total)', (SELECT ABS((SELECT SUM(transactions) FROM fact_session) - (SELECT COUNT(*) FROM fact_transaction)))
  UNION ALL SELECT 'converted sessions all have a purchase event', (SELECT COUNT(*) FROM fact_session WHERE is_converted = 1 AND has_purchase_event = 0)
  UNION ALL SELECT 'is_engaged and is_bounce are complements', (SELECT COUNT(*) FROM fact_session WHERE is_engaged + is_bounce <> 1)
  UNION ALL SELECT 'funnel strict counts never exceed open counts', (SELECT COUNT(*) FROM a_funnel WHERE strict_sessions > sessions)
  UNION ALL SELECT 'funnel purchase step = converting sessions', (SELECT ABS((SELECT sessions FROM a_funnel WHERE step_no = 6) - (SELECT SUM(is_converted) FROM fact_session)))
  UNION ALL SELECT 'channel table covers all sessions and revenue',
         (SELECT CASE WHEN (SELECT SUM(sessions) FROM a_channel) = (SELECT COUNT(*) FROM fact_session)
                       AND ABS((SELECT SUM(revenue_usd) FROM a_channel) - (SELECT SUM(revenue_usd) FROM fact_session)) < 0.01 THEN 0 ELSE 1 END)
  UNION ALL SELECT 'daily x device x channel aggregate reconciles to fact_session',
         (SELECT CASE WHEN (SELECT SUM(sessions) FROM agg_daily_device_channel) = (SELECT COUNT(*) FROM fact_session)
                       AND (SELECT SUM(converting_sessions) FROM agg_daily_device_channel) = (SELECT SUM(is_converted) FROM fact_session)
                       AND ABS((SELECT SUM(revenue_usd) FROM agg_daily_device_channel) - (SELECT SUM(revenue_usd) FROM fact_session)) < 0.01 THEN 0 ELSE 1 END)
  UNION ALL SELECT 'no negative durations / engagement times', (SELECT COUNT(*) FROM fact_session WHERE duration_s < 0 OR engagement_time_s < 0)
  UNION ALL SELECT 'every session belongs to one user and has >= 1 event', (SELECT COUNT(*) FROM fact_session WHERE user_pseudo_id IS NULL OR events < 1)
)
SELECT check_name, failed_rows, CASE WHEN failed_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS status FROM c;
