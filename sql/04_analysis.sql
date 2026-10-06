-- 04_analysis.sql  KPIs and business questions (Spark SQL dialect). Every a_* table is exported to results/tables/.
-- Definitions (GA4 style)
--   session          = user_pseudo_id + ga_session_id;  engaged session = any event with session_engaged = '1'
--   bounce rate      = 1 - engagement rate (GA4 definition: share of sessions that were not engaged)
--   conversion (CVR) = sessions with >= 1 valid transaction / sessions;  user CVR = purchasing users / users
--   AOV              = revenue / transactions;  revenue = sum of de-duplicated transaction revenue (USD)
--   funnel           = "open" funnel: sessions that fired each step event at least once (any order);
--                      "strict" = sessions that also fired every earlier step
--   channel          = first-touch acquisition channel (dim_traffic) unless stated; session_channel = session-scoped source/medium params

-- Q1 headline KPIs
CREATE OR REPLACE TABLE a_kpi_headline AS
SELECT
  (SELECT COUNT(*) FROM cln_events)                                                     AS events,
  COUNT(DISTINCT f.user_pseudo_id)                                                      AS users,
  COUNT(*)                                                                              AS sessions,
  ROUND(COUNT(*) / COUNT(DISTINCT f.user_pseudo_id), 3)                                 AS sessions_per_user,
  SUM(f.is_engaged)                                                                     AS engaged_sessions,
  ROUND(100.0 * AVG(f.is_engaged), 2)                                                   AS engagement_rate_pct,
  ROUND(100.0 * AVG(f.is_bounce), 2)                                                    AS bounce_rate_pct,
  ROUND(AVG(f.page_views), 3)                                                           AS pageviews_per_session,
  ROUND(AVG(f.engagement_time_s), 1)                                                    AS avg_engagement_time_s,
  ROUND(percentile_approx(f.duration_s, 0.5), 1)                                        AS median_session_span_s,
  SUM(f.is_converted)                                                                   AS converting_sessions,
  ROUND(100.0 * AVG(f.is_converted), 3)                                                 AS session_cvr_pct,
  COUNT(DISTINCT CASE WHEN f.is_converted = 1 THEN f.user_pseudo_id END)                AS purchasers,
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN f.is_converted = 1 THEN f.user_pseudo_id END) / COUNT(DISTINCT f.user_pseudo_id), 3) AS user_cvr_pct,
  SUM(f.transactions)                                                                   AS transactions,
  ROUND(SUM(f.revenue_usd), 2)                                                          AS revenue_usd,
  ROUND(SUM(f.revenue_usd) / SUM(f.transactions), 2)                                    AS aov_usd,
  ROUND(SUM(f.revenue_usd) / COUNT(*), 4)                                               AS revenue_per_session_usd,
  ROUND(SUM(f.revenue_usd) / COUNT(DISTINCT f.user_pseudo_id), 4)                       AS revenue_per_user_usd,
  ROUND(100.0 * AVG(CASE WHEN f.user_type = 'new' THEN 1 ELSE 0 END), 2)                AS new_session_pct,
  SUM(f.has_add_to_cart)                                                                AS cart_sessions,
  ROUND(100.0 * SUM(CASE WHEN f.has_add_to_cart = 1 AND f.is_converted = 0 THEN 1 ELSE 0 END) / SUM(f.has_add_to_cart), 2) AS cart_abandonment_pct,
  ROUND(100.0 * SUM(CASE WHEN f.has_begin_checkout = 1 AND f.is_converted = 0 THEN 1 ELSE 0 END) / SUM(f.has_begin_checkout), 2) AS checkout_abandonment_pct,
  (SELECT MIN(date) FROM dim_date)                                                      AS first_date,
  (SELECT MAX(date) FROM dim_date)                                                      AS last_date,
  (SELECT COUNT(*) FROM dim_date)                                                       AS days,
  (SELECT COUNT(DISTINCT country) FROM dim_geo WHERE country <> '(not set)')            AS countries
FROM fact_session f;

-- Q2 funnel (all sessions)
CREATE OR REPLACE TABLE a_funnel AS
WITH f AS (
  SELECT COUNT(*) AS s0, SUM(has_view_item) AS s1, SUM(has_add_to_cart) AS s2, SUM(has_begin_checkout) AS s3,
         SUM(has_add_shipping_info) AS s4, SUM(has_add_payment_info) AS s5, SUM(is_converted) AS s6,
         SUM(has_view_item) AS t1, SUM(has_view_item * has_add_to_cart) AS t2, SUM(has_view_item * has_add_to_cart * has_begin_checkout) AS t3,
         SUM(has_view_item * has_add_to_cart * has_begin_checkout * has_add_shipping_info) AS t4,
         SUM(has_view_item * has_add_to_cart * has_begin_checkout * has_add_shipping_info * has_add_payment_info) AS t5,
         SUM(has_view_item * has_add_to_cart * has_begin_checkout * has_add_shipping_info * has_add_payment_info * is_converted) AS t6
  FROM fact_session
),
steps AS (
  SELECT 0 AS step_no, '0 session' AS step, s0 AS sessions, s0 AS strict_sessions, CAST(NULL AS BIGINT) AS prev, s0 AS total FROM f
  UNION ALL SELECT 1, '1 view_item', s1, t1, s0, s0 FROM f
  UNION ALL SELECT 2, '2 add_to_cart', s2, t2, s1, s0 FROM f
  UNION ALL SELECT 3, '3 begin_checkout', s3, t3, s2, s0 FROM f
  UNION ALL SELECT 4, '4 add_shipping_info', s4, t4, s3, s0 FROM f
  UNION ALL SELECT 5, '5 add_payment_info', s5, t5, s4, s0 FROM f
  UNION ALL SELECT 6, '6 purchase', s6, t6, s5, s0 FROM f
)
SELECT step_no, step, sessions, ROUND(100.0 * sessions / total, 3) AS pct_of_sessions,
       ROUND(100.0 * sessions / prev, 2) AS pct_of_previous_step, ROUND(100.0 - 100.0 * sessions / prev, 2) AS drop_off_pct,
       strict_sessions, ROUND(100.0 * strict_sessions / total, 3) AS strict_pct_of_sessions
FROM steps;

-- Q2b funnel by device
CREATE OR REPLACE TABLE a_funnel_device AS
WITH d AS (
  SELECT dd.device_category, COUNT(*) AS s0, SUM(f.has_view_item) AS s1, SUM(f.has_add_to_cart) AS s2, SUM(f.has_begin_checkout) AS s3,
         SUM(f.has_add_shipping_info) AS s4, SUM(f.has_add_payment_info) AS s5, SUM(f.is_converted) AS s6
  FROM fact_session f JOIN dim_device dd ON f.device_key = dd.device_key GROUP BY dd.device_category
)
SELECT device_category, 0 AS step_no, '0 session' AS step, s0 AS sessions, 100.0 AS pct_of_device_sessions FROM d
UNION ALL SELECT device_category, 1, '1 view_item', s1, ROUND(100.0 * s1 / s0, 3) FROM d
UNION ALL SELECT device_category, 2, '2 add_to_cart', s2, ROUND(100.0 * s2 / s0, 3) FROM d
UNION ALL SELECT device_category, 3, '3 begin_checkout', s3, ROUND(100.0 * s3 / s0, 3) FROM d
UNION ALL SELECT device_category, 4, '4 add_shipping_info', s4, ROUND(100.0 * s4 / s0, 3) FROM d
UNION ALL SELECT device_category, 5, '5 add_payment_info', s5, ROUND(100.0 * s5 / s0, 3) FROM d
UNION ALL SELECT device_category, 6, '6 purchase', s6, ROUND(100.0 * s6 / s0, 3) FROM d;

-- Q3 acquisition channel (first touch)
CREATE OR REPLACE TABLE a_channel AS
SELECT t.channel_group, COUNT(*) AS sessions, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_sessions,
       COUNT(DISTINCT f.user_pseudo_id) AS users,
       ROUND(100.0 * AVG(f.is_engaged), 2) AS engagement_rate_pct, ROUND(100.0 * AVG(f.is_bounce), 2) AS bounce_rate_pct,
       ROUND(AVG(f.page_views), 2) AS pageviews_per_session,
       ROUND(100.0 * AVG(f.has_add_to_cart), 2) AS add_to_cart_rate_pct,
       SUM(f.is_converted) AS converting_sessions, ROUND(100.0 * AVG(f.is_converted), 3) AS cvr_pct,
       SUM(f.transactions) AS transactions, ROUND(SUM(f.revenue_usd), 2) AS revenue_usd,
       ROUND(100.0 * SUM(f.revenue_usd) / SUM(SUM(f.revenue_usd)) OVER (), 2) AS pct_revenue,
       ROUND(SUM(f.revenue_usd) / NULLIF(SUM(f.transactions), 0), 2) AS aov_usd,
       ROUND(SUM(f.revenue_usd) / COUNT(*), 3) AS revenue_per_session_usd
FROM fact_session f JOIN dim_traffic t ON f.traffic_key = t.traffic_key
GROUP BY t.channel_group;

-- Q3b session-scoped source / medium (event params; NULL on 26% of sessions -> '(not set)')
CREATE OR REPLACE TABLE a_session_channel AS
SELECT session_channel, COUNT(*) AS sessions, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_sessions,
       ROUND(100.0 * AVG(is_engaged), 2) AS engagement_rate_pct, ROUND(100.0 * AVG(is_bounce), 2) AS bounce_rate_pct,
       ROUND(100.0 * AVG(has_add_to_cart), 2) AS add_to_cart_rate_pct,
       SUM(is_converted) AS converting_sessions, ROUND(100.0 * AVG(is_converted), 3) AS cvr_pct,
       ROUND(SUM(revenue_usd), 2) AS revenue_usd, ROUND(100.0 * SUM(revenue_usd) / SUM(SUM(revenue_usd)) OVER (), 2) AS pct_revenue,
       ROUND(SUM(revenue_usd) / COUNT(*), 3) AS revenue_per_session_usd
FROM fact_session GROUP BY session_channel;

-- Q4 device
CREATE OR REPLACE TABLE a_device AS
SELECT d.device_category, COUNT(*) AS sessions, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_sessions,
       COUNT(DISTINCT f.user_pseudo_id) AS users,
       ROUND(100.0 * AVG(f.is_engaged), 2) AS engagement_rate_pct, ROUND(100.0 * AVG(f.is_bounce), 2) AS bounce_rate_pct,
       ROUND(AVG(f.page_views), 2) AS pageviews_per_session, ROUND(AVG(f.engagement_time_s), 1) AS avg_engagement_time_s,
       ROUND(100.0 * AVG(f.has_add_to_cart), 2) AS add_to_cart_rate_pct,
       ROUND(100.0 * SUM(f.is_converted) / NULLIF(SUM(f.has_add_to_cart), 0), 2) AS cart_to_purchase_pct,
       SUM(f.is_converted) AS converting_sessions, ROUND(100.0 * AVG(f.is_converted), 3) AS cvr_pct,
       SUM(f.transactions) AS transactions, ROUND(SUM(f.revenue_usd), 2) AS revenue_usd,
       ROUND(100.0 * SUM(f.revenue_usd) / SUM(SUM(f.revenue_usd)) OVER (), 2) AS pct_revenue,
       ROUND(SUM(f.revenue_usd) / NULLIF(SUM(f.transactions), 0), 2) AS aov_usd
FROM fact_session f JOIN dim_device d ON f.device_key = d.device_key
GROUP BY d.device_category;

-- Q4b operating system x device (top OS by sessions)
CREATE OR REPLACE TABLE a_os AS
SELECT d.device_os, COUNT(*) AS sessions, ROUND(100.0 * AVG(f.is_engaged), 2) AS engagement_rate_pct,
       ROUND(100.0 * AVG(f.is_converted), 3) AS cvr_pct, ROUND(SUM(f.revenue_usd), 2) AS revenue_usd,
       ROUND(SUM(f.revenue_usd) / NULLIF(SUM(f.transactions), 0), 2) AS aov_usd
FROM fact_session f JOIN dim_device d ON f.device_key = d.device_key
GROUP BY d.device_os;

-- Q5 daily trend
CREATE OR REPLACE TABLE a_daily AS
SELECT d.date, d.day_name, d.season, COUNT(*) AS sessions, COUNT(DISTINCT f.user_pseudo_id) AS users,
       ROUND(100.0 * AVG(f.is_engaged), 2) AS engagement_rate_pct, SUM(f.is_converted) AS converting_sessions,
       ROUND(100.0 * AVG(f.is_converted), 3) AS cvr_pct, SUM(f.transactions) AS transactions, ROUND(SUM(f.revenue_usd), 2) AS revenue_usd
FROM fact_session f JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.date, d.day_name, d.season;

-- Q5b season windows and months
CREATE OR REPLACE TABLE a_season AS
SELECT d.season, COUNT(DISTINCT d.date) AS days, COUNT(*) AS sessions, ROUND(COUNT(*) / COUNT(DISTINCT d.date), 1) AS sessions_per_day,
       ROUND(100.0 * AVG(f.is_converted), 3) AS cvr_pct, SUM(f.transactions) AS transactions, ROUND(SUM(f.revenue_usd), 2) AS revenue_usd,
       ROUND(SUM(f.revenue_usd) / COUNT(DISTINCT d.date), 2) AS revenue_per_day_usd,
       ROUND(SUM(f.revenue_usd) / NULLIF(SUM(f.transactions), 0), 2) AS aov_usd
FROM fact_session f JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.season;

CREATE OR REPLACE TABLE a_monthly AS
SELECT d.year_month, COUNT(DISTINCT d.date) AS days, COUNT(*) AS sessions, COUNT(DISTINCT f.user_pseudo_id) AS users,
       ROUND(100.0 * AVG(f.is_engaged), 2) AS engagement_rate_pct, ROUND(100.0 * AVG(f.is_converted), 3) AS cvr_pct,
       SUM(f.transactions) AS transactions, ROUND(SUM(f.revenue_usd), 2) AS revenue_usd,
       ROUND(SUM(f.revenue_usd) / NULLIF(SUM(f.transactions), 0), 2) AS aov_usd
FROM fact_session f JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.year_month;

-- Q5c weekday x hour (UTC) of session start
CREATE OR REPLACE TABLE a_dow_hour AS
SELECT d.day_of_week_num, d.day_name, f.start_hour_utc, COUNT(*) AS sessions, SUM(f.is_converted) AS converting_sessions,
       ROUND(100.0 * AVG(f.is_converted), 3) AS cvr_pct
FROM fact_session f JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.day_of_week_num, d.day_name, f.start_hour_utc;

CREATE OR REPLACE TABLE a_weekday AS
SELECT d.day_of_week_num, d.day_name, COUNT(DISTINCT d.date) AS days, ROUND(COUNT(*) / COUNT(DISTINCT d.date), 1) AS sessions_per_day,
       ROUND(100.0 * AVG(f.is_engaged), 2) AS engagement_rate_pct, ROUND(100.0 * AVG(f.is_converted), 3) AS cvr_pct,
       ROUND(SUM(f.revenue_usd) / COUNT(DISTINCT d.date), 2) AS revenue_per_day_usd
FROM fact_session f JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.day_of_week_num, d.day_name;

-- Q6 countries (top 15 by sessions + the rest)
CREATE OR REPLACE TABLE a_country AS
WITH c AS (
  SELECT g.country, COUNT(*) AS sessions, COUNT(DISTINCT f.user_pseudo_id) AS users, SUM(f.is_engaged) AS engaged,
         SUM(f.is_converted) AS conv, SUM(f.transactions) AS transactions, SUM(f.revenue_usd) AS revenue_usd
  FROM fact_session f JOIN dim_geo g ON f.geo_key = g.geo_key GROUP BY g.country
),
r AS (SELECT c.*, ROW_NUMBER() OVER (ORDER BY sessions DESC, country) AS rnk FROM c),
b AS (SELECT CASE WHEN rnk <= 15 THEN rnk ELSE 16 END AS rnk, CASE WHEN rnk <= 15 THEN country ELSE 'All other countries' END AS country,
             sessions, users, engaged, conv, transactions, revenue_usd FROM r)
SELECT rnk, country, SUM(sessions) AS sessions, ROUND(100.0 * SUM(sessions) / SUM(SUM(sessions)) OVER (), 2) AS pct_sessions,
       ROUND(100.0 * SUM(engaged) / SUM(sessions), 2) AS engagement_rate_pct, SUM(conv) AS converting_sessions,
       ROUND(100.0 * SUM(conv) / SUM(sessions), 3) AS cvr_pct, SUM(transactions) AS transactions, ROUND(SUM(revenue_usd), 2) AS revenue_usd,
       ROUND(100.0 * SUM(revenue_usd) / SUM(SUM(revenue_usd)) OVER (), 2) AS pct_revenue,
       ROUND(SUM(revenue_usd) / NULLIF(SUM(transactions), 0), 2) AS aov_usd
FROM b GROUP BY rnk, country;

-- Q6b landing pages (first page_view title of the session, top 12 by sessions)
CREATE OR REPLACE TABLE a_landing_page AS
WITH l AS (
  SELECT landing_page, COUNT(*) AS sessions, ROUND(100.0 * AVG(is_bounce), 2) AS bounce_rate_pct,
         ROUND(100.0 * AVG(has_add_to_cart), 2) AS add_to_cart_rate_pct, ROUND(100.0 * AVG(is_converted), 3) AS cvr_pct,
         ROUND(SUM(revenue_usd), 2) AS revenue_usd
  FROM fact_session GROUP BY landing_page
)
SELECT * FROM (SELECT ROW_NUMBER() OVER (ORDER BY sessions DESC, landing_page) AS rnk, l.* FROM l) x WHERE rnk <= 12;

-- Q7 new vs returning
CREATE OR REPLACE TABLE a_new_returning AS
SELECT user_type, COUNT(*) AS sessions, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_sessions,
       ROUND(100.0 * AVG(is_engaged), 2) AS engagement_rate_pct, ROUND(AVG(page_views), 2) AS pageviews_per_session,
       ROUND(100.0 * AVG(has_add_to_cart), 2) AS add_to_cart_rate_pct, ROUND(100.0 * AVG(is_converted), 3) AS cvr_pct,
       SUM(transactions) AS transactions, ROUND(SUM(revenue_usd), 2) AS revenue_usd,
       ROUND(100.0 * SUM(revenue_usd) / SUM(SUM(revenue_usd)) OVER (), 2) AS pct_revenue,
       ROUND(SUM(revenue_usd) / NULLIF(SUM(transactions), 0), 2) AS aov_usd
FROM fact_session GROUP BY user_type;

-- Q7b engagement depth: page views per session vs conversion
CREATE OR REPLACE TABLE a_page_depth AS
SELECT CASE WHEN page_views = 0 THEN '0' WHEN page_views = 1 THEN '1' WHEN page_views <= 3 THEN '2-3' WHEN page_views <= 6 THEN '4-6'
            WHEN page_views <= 10 THEN '7-10' WHEN page_views <= 20 THEN '11-20' ELSE '21+' END AS page_views_band,
       MIN(page_views) AS band_min, COUNT(*) AS sessions, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_sessions,
       ROUND(100.0 * AVG(is_engaged), 2) AS engagement_rate_pct, ROUND(100.0 * AVG(is_converted), 3) AS cvr_pct,
       ROUND(SUM(revenue_usd), 2) AS revenue_usd, ROUND(100.0 * SUM(revenue_usd) / SUM(SUM(revenue_usd)) OVER (), 2) AS pct_revenue
FROM fact_session
GROUP BY CASE WHEN page_views = 0 THEN '0' WHEN page_views = 1 THEN '1' WHEN page_views <= 3 THEN '2-3' WHEN page_views <= 6 THEN '4-6'
              WHEN page_views <= 10 THEN '7-10' WHEN page_views <= 20 THEN '11-20' ELSE '21+' END;

-- Q8 order value distribution
CREATE OR REPLACE TABLE a_order_value AS
SELECT CASE WHEN revenue_usd < 25 THEN '1: < $25' WHEN revenue_usd < 50 THEN '2: $25-49' WHEN revenue_usd < 100 THEN '3: $50-99'
            WHEN revenue_usd < 200 THEN '4: $100-199' WHEN revenue_usd < 500 THEN '5: $200-499' ELSE '6: $500+' END AS order_value_band,
       COUNT(*) AS transactions, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_transactions,
       ROUND(SUM(revenue_usd), 2) AS revenue_usd, ROUND(100.0 * SUM(revenue_usd) / SUM(SUM(revenue_usd)) OVER (), 2) AS pct_revenue,
       ROUND(AVG(item_qty), 2) AS avg_items
FROM fact_transaction
GROUP BY CASE WHEN revenue_usd < 25 THEN '1: < $25' WHEN revenue_usd < 50 THEN '2: $25-49' WHEN revenue_usd < 100 THEN '3: $50-99'
              WHEN revenue_usd < 200 THEN '4: $100-199' WHEN revenue_usd < 500 THEN '5: $200-499' ELSE '6: $500+' END;

CREATE OR REPLACE TABLE a_order_stats AS
SELECT COUNT(*) AS transactions, ROUND(AVG(revenue_usd), 2) AS mean_usd, ROUND(percentile_approx(revenue_usd, 0.5), 2) AS median_usd,
       ROUND(percentile_approx(revenue_usd, 0.9), 2) AS p90_usd, MAX(revenue_usd) AS max_usd, ROUND(AVG(item_qty), 2) AS avg_items,
       SUM(dq_revenue_outlier) AS outlier_orders, ROUND(SUM(CASE WHEN dq_revenue_outlier = 1 THEN revenue_usd ELSE 0 END), 2) AS outlier_revenue_usd,
       ROUND(100.0 * SUM(CASE WHEN dq_revenue_outlier = 1 THEN revenue_usd ELSE 0 END) / SUM(revenue_usd), 2) AS outlier_pct_revenue,
       (SELECT ROUND(SUM(revenue_usd), 2) FROM cln_events WHERE event_name = 'purchase' AND revenue_usd > 0) AS purchase_event_revenue_usd,
       (SELECT ROUND(SUM(revenue_usd), 2) FROM cln_events WHERE event_name = 'purchase' AND revenue_usd > 0) - ROUND(SUM(revenue_usd), 2) AS duplicate_revenue_removed_usd
FROM fact_transaction;

-- Q5d top revenue days
CREATE OR REPLACE TABLE a_top_days AS
SELECT * FROM (SELECT ROW_NUMBER() OVER (ORDER BY revenue_usd DESC, date) AS rnk, date, day_name, season, sessions, cvr_pct, transactions, revenue_usd
               FROM a_daily) x WHERE rnk <= 10;

-- Daily x device x first-touch channel aggregate (full, exact totals for Power BI)
CREATE OR REPLACE TABLE agg_daily_device_channel AS
SELECT f.date_key, d.device_category, t.channel_group, COUNT(*) AS sessions, COUNT(DISTINCT f.user_pseudo_id) AS users,
       SUM(f.is_engaged) AS engaged_sessions, SUM(f.page_views) AS page_views, SUM(f.has_view_item) AS view_item_sessions,
       SUM(f.has_add_to_cart) AS add_to_cart_sessions, SUM(f.has_begin_checkout) AS begin_checkout_sessions,
       SUM(f.has_add_shipping_info) AS add_shipping_info_sessions, SUM(f.has_add_payment_info) AS add_payment_info_sessions,
       SUM(f.is_converted) AS converting_sessions, SUM(f.transactions) AS transactions, ROUND(SUM(f.revenue_usd), 2) AS revenue_usd,
       ROUND(SUM(f.engagement_time_s), 3) AS engagement_time_s
FROM fact_session f JOIN dim_device d ON f.device_key = d.device_key JOIN dim_traffic t ON f.traffic_key = t.traffic_key
GROUP BY f.date_key, d.device_category, t.channel_group;
