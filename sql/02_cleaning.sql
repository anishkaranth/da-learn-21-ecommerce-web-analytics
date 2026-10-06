-- 02_cleaning.sql  Typed, standardised, de-duplicated events -> sessions -> transactions (Spark SQL dialect)
-- Rules
--   * header rows: the shard header line re-appears inside the raw file (event_name = 'event_name') -> dropped
--   * types: event_date 'yyyyMMdd' -> DATE (GA4 export date = UTC date of event_timestamp); event_timestamp us -> TIMESTAMP (UTC);
--            ids / counters -> BIGINT/INT; revenue, tax -> DOUBLE (USD)
--   * standardisation: trim; event_name / device_category lower-case; empty or NULL dimension -> '(not set)';
--            GA4 obfuscation placeholder '<Other>' -> '(other)'; '(data deleted)' kept as its own value
--   * dedupe: exact event key (user_pseudo_id, event_timestamp, event_name, event_bundle_sequence_id) -> keep 1
--   * session key: ga_session_id is NOT unique across users in this export, so session = user_pseudo_id + ga_session_id
--   * transactions: purchase events with revenue > 0; repeated purchase events of the same transaction in the same session
--            (confirmation-page reloads) collapse to one; '(not set)' / NULL transaction ids are keyed by session + revenue
--   * outlier flags (kept, not deleted): transaction revenue > Q3 + 3 IQR; session span > 4 h; single event engagement > 1 h
--   * integrity flags: zero-revenue purchase events, purchase sessions without add_to_cart / begin_checkout, sessions without session_start

CREATE OR REPLACE TABLE cln_events AS
WITH typed AS (
  SELECT
    to_date(trim(event_date), 'yyyyMMdd')                                   AS event_date,
    lower(trim(event_name))                                                 AS event_name,
    TRY_CAST(trim(event_timestamp) AS BIGINT)                               AS event_ts_us,
    TRY_CAST(trim(event_bundle_sequence_id) AS BIGINT)                      AS bundle_seq,
    trim(user_pseudo_id)                                                    AS user_pseudo_id,
    TRY_CAST(trim(ga_session_id) AS BIGINT)                                 AS ga_session_id,
    TRY_CAST(trim(ga_session_number) AS INT)                                AS ga_session_number,
    CASE WHEN trim(device_category) IN ('desktop', 'mobile', 'tablet') THEN trim(device_category)
         WHEN device_category IS NULL OR trim(device_category) = '' THEN '(not set)' ELSE lower(trim(device_category)) END AS device_category,
    CASE WHEN device_os IS NULL OR trim(device_os) = '' THEN '(not set)' WHEN trim(device_os) = '<Other>' THEN '(other)' ELSE trim(device_os) END AS device_os,
    CASE WHEN browser IS NULL OR trim(browser) = '' THEN '(not set)' WHEN trim(browser) = '<Other>' THEN '(other)' ELSE trim(browser) END AS browser,
    CASE WHEN continent IS NULL OR trim(continent) = '' THEN '(not set)' ELSE trim(continent) END       AS continent,
    CASE WHEN sub_continent IS NULL OR trim(sub_continent) = '' THEN '(not set)' ELSE trim(sub_continent) END AS sub_continent,
    CASE WHEN country IS NULL OR trim(country) = '' THEN '(not set)' ELSE trim(country) END             AS country,
    CASE WHEN traffic_source IS NULL OR trim(traffic_source) = '' THEN '(not set)' WHEN trim(traffic_source) = '<Other>' THEN '(other)' ELSE lower(trim(traffic_source)) END AS traffic_source,
    CASE WHEN traffic_medium IS NULL OR trim(traffic_medium) = '' THEN '(not set)' WHEN trim(traffic_medium) = '<Other>' THEN '(other)' ELSE lower(trim(traffic_medium)) END AS traffic_medium,
    CASE WHEN traffic_campaign IS NULL OR trim(traffic_campaign) = '' THEN '(not set)' WHEN trim(traffic_campaign) = '<Other>' THEN '(other)' ELSE trim(traffic_campaign) END AS traffic_campaign,
    -- event-scoped source / medium params: NULL means "not sent with this event" (kept NULL here, resolved per session below)
    CASE WHEN ep_source IS NULL OR trim(ep_source) = '' THEN NULL WHEN trim(ep_source) = '<Other>' THEN '(other)' ELSE lower(trim(ep_source)) END AS ep_source,
    CASE WHEN ep_medium IS NULL OR trim(ep_medium) = '' THEN NULL WHEN trim(ep_medium) = '<Other>' THEN '(other)' ELSE lower(trim(ep_medium)) END AS ep_medium,
    CASE WHEN page_title IS NULL OR trim(page_title) = '' THEN NULL WHEN trim(page_title) = '<Other>' THEN '(other)' ELSE trim(page_title) END AS page_title,
    CASE WHEN trim(entrances) = '1' THEN 1 ELSE 0 END                       AS is_entrance,
    CASE WHEN trim(session_engaged) = '1' THEN 1 ELSE 0 END                 AS is_engaged_event,
    TRY_CAST(trim(engagement_time_msec) AS BIGINT)                          AS engagement_time_ms,
    TRY_CAST(trim(ecom_revenue_usd) AS DOUBLE)                              AS revenue_usd,
    TRY_CAST(trim(ecom_tax_usd) AS DOUBLE)                                  AS tax_usd,
    TRY_CAST(trim(ecom_total_item_qty) AS INT)                              AS item_qty,
    TRY_CAST(trim(ecom_unique_items) AS INT)                                AS unique_items,
    CASE WHEN ecom_transaction_id IS NULL OR trim(ecom_transaction_id) IN ('', '(not set)') THEN NULL ELSE trim(ecom_transaction_id) END AS transaction_id
  FROM stg_events
  WHERE trim(event_name) <> 'event_name'                                    -- repeated shard header lines
),
ranked AS (
  SELECT t.*, ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, event_ts_us, event_name, bundle_seq ORDER BY page_title) AS rn
  FROM typed t
  WHERE user_pseudo_id IS NOT NULL AND user_pseudo_id <> '' AND ga_session_id IS NOT NULL AND event_ts_us IS NOT NULL AND event_date IS NOT NULL
)
SELECT
  event_date, timestamp_micros(event_ts_us) AS event_ts, event_ts_us, bundle_seq, event_name, user_pseudo_id, ga_session_id,
  concat(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) AS session_id, ga_session_number,
  device_category, device_os, browser, continent, sub_continent, country, traffic_source, traffic_medium, traffic_campaign,
  ep_source, ep_medium, page_title, is_entrance, is_engaged_event, engagement_time_ms, revenue_usd, tax_usd, item_qty, unique_items, transaction_id,
  CASE WHEN event_name = 'purchase' AND transaction_id IS NULL THEN 1 ELSE 0 END                       AS dq_txn_id_missing,
  CASE WHEN event_name = 'purchase' AND COALESCE(revenue_usd, 0) <= 0 THEN 1 ELSE 0 END               AS dq_zero_revenue_purchase,
  CASE WHEN engagement_time_ms > 3600000 THEN 1 ELSE 0 END                                             AS dq_engagement_outlier
FROM ranked
WHERE rn = 1;

-- One row per de-duplicated transaction (valid purchase = purchase event with revenue > 0)
CREATE OR REPLACE TABLE cln_transactions AS
WITH p AS (
  SELECT e.*, COALESCE(transaction_id, concat('no-id/', CAST(CAST(revenue_usd AS BIGINT) AS STRING))) AS txn_part
  FROM cln_events e
  WHERE event_name = 'purchase' AND revenue_usd > 0
),
r AS (
  SELECT p.*, ROW_NUMBER() OVER (PARTITION BY session_id, txn_part ORDER BY event_ts_us) AS rn,
         COUNT(*) OVER (PARTITION BY session_id, txn_part) AS purchase_events
  FROM p
),
t AS (SELECT * FROM r WHERE rn = 1),
iqr AS (SELECT percentile_approx(revenue_usd, 0.25) AS q1, percentile_approx(revenue_usd, 0.75) AS q3 FROM t)
SELECT concat(t.session_id, '|', t.txn_part) AS transaction_id_key, t.transaction_id, t.session_id, t.user_pseudo_id, t.event_date AS order_date,
       t.event_ts AS order_ts, t.revenue_usd, t.tax_usd, t.item_qty, t.unique_items, t.purchase_events,
       t.dq_txn_id_missing,
       CASE WHEN t.purchase_events > 1 THEN 1 ELSE 0 END                                        AS dq_duplicate_purchase_events,
       CASE WHEN t.revenue_usd > iqr.q3 + 3 * (iqr.q3 - iqr.q1) THEN 1 ELSE 0 END               AS dq_revenue_outlier
FROM t CROSS JOIN iqr;

-- One row per session (user_pseudo_id + ga_session_id); session-constant attributes are taken from the session's events
CREATE OR REPLACE TABLE cln_sessions AS
WITH s AS (
  SELECT
    session_id, MIN(user_pseudo_id) AS user_pseudo_id, MIN(ga_session_id) AS ga_session_id,
    MIN(event_date) AS session_date, MIN(event_ts) AS session_start_ts, MAX(event_ts) AS session_end_ts,
    hour(MIN(event_ts)) AS start_hour_utc, MIN(ga_session_number) AS session_number,
    MIN(device_category) AS device_category, MIN(device_os) AS device_os, MIN(browser) AS browser,
    MIN(continent) AS continent, MIN(sub_continent) AS sub_continent, MIN(country) AS country,
    MIN(traffic_source) AS ft_source, MIN(traffic_medium) AS ft_medium, MIN(traffic_campaign) AS ft_campaign,
    MIN_BY(ep_source, CASE WHEN ep_medium IS NOT NULL THEN event_ts_us END)  AS sess_source,
    MIN_BY(ep_medium, CASE WHEN ep_medium IS NOT NULL THEN event_ts_us END)  AS sess_medium,
    MIN_BY(page_title, CASE WHEN event_name = 'page_view' AND page_title IS NOT NULL THEN event_ts_us END) AS landing_page,
    COUNT(*) AS events,
    SUM(CASE WHEN event_name = 'page_view' THEN 1 ELSE 0 END)          AS page_views,
    SUM(CASE WHEN event_name = 'view_item' THEN 1 ELSE 0 END)          AS view_item_events,
    SUM(CASE WHEN event_name = 'add_to_cart' THEN 1 ELSE 0 END)        AS add_to_cart_events,
    MAX(CASE WHEN event_name = 'session_start' THEN 1 ELSE 0 END)      AS has_session_start,
    MAX(CASE WHEN event_name = 'first_visit' THEN 1 ELSE 0 END)        AS has_first_visit,
    MAX(CASE WHEN event_name = 'view_item' THEN 1 ELSE 0 END)          AS has_view_item,
    MAX(CASE WHEN event_name = 'add_to_cart' THEN 1 ELSE 0 END)        AS has_add_to_cart,
    MAX(CASE WHEN event_name = 'begin_checkout' THEN 1 ELSE 0 END)     AS has_begin_checkout,
    MAX(CASE WHEN event_name = 'add_shipping_info' THEN 1 ELSE 0 END)  AS has_add_shipping_info,
    MAX(CASE WHEN event_name = 'add_payment_info' THEN 1 ELSE 0 END)   AS has_add_payment_info,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END)           AS has_purchase_event,
    MAX(CASE WHEN event_name = 'view_search_results' THEN 1 ELSE 0 END) AS has_search,
    MAX(is_engaged_event) AS is_engaged,
    COALESCE(SUM(engagement_time_ms), 0) / 1000.0 AS engagement_time_s,
    (MAX(event_ts_us) - MIN(event_ts_us)) / 1000000.0 AS duration_s,
    SUM(dq_zero_revenue_purchase) AS zero_revenue_purchase_events,
    MAX(dq_engagement_outlier) AS dq_engagement_outlier,
    CASE WHEN COUNT(DISTINCT device_category) > 1 OR COUNT(DISTINCT country) > 1 OR COUNT(DISTINCT traffic_medium) > 1
           OR COUNT(DISTINCT traffic_source) > 1 OR COUNT(DISTINCT device_os) > 1 THEN 1 ELSE 0 END AS dq_attr_conflict,
    COUNT(DISTINCT ep_medium) AS sess_medium_values
  FROM cln_events
  GROUP BY session_id
),
tx AS (SELECT session_id, COUNT(*) AS transactions, SUM(revenue_usd) AS revenue_usd FROM cln_transactions GROUP BY session_id)
SELECT s.*,
  COALESCE(tx.transactions, 0) AS transactions, COALESCE(tx.revenue_usd, 0) AS revenue_usd,
  CASE WHEN tx.transactions > 0 THEN 1 ELSE 0 END                                         AS is_converted,
  CASE WHEN s.session_number = 1 THEN 'new' ELSE 'returning' END                         AS user_type,
  CASE WHEN tx.transactions > 0 AND s.has_add_to_cart = 0 THEN 1 ELSE 0 END               AS dq_purchase_without_cart,
  CASE WHEN tx.transactions > 0 AND s.has_begin_checkout = 0 THEN 1 ELSE 0 END            AS dq_purchase_without_checkout,
  CASE WHEN s.has_session_start = 0 THEN 1 ELSE 0 END                                     AS dq_no_session_start,
  CASE WHEN s.duration_s > 14400 THEN 1 ELSE 0 END                                        AS dq_long_session,
  CASE WHEN s.sess_medium_values > 1 THEN 1 ELSE 0 END                                    AS dq_multi_session_medium
FROM s LEFT JOIN tx ON s.session_id = tx.session_id;
