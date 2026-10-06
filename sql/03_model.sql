-- 03_model.sql  Star schema (Spark SQL dialect)
--   fact_session      1 row per session (user_pseudo_id + ga_session_id): funnel step flags, engagement, transactions, revenue
--   fact_transaction  1 row per de-duplicated transaction (revenue > 0)
--   dim_date / dim_device / dim_traffic (first-touch acquisition) / dim_geo
-- Channel grouping (GA-style, applied to first-touch source/medium and to the session-scoped source/medium event params)
--   organic -> Organic Search, cpc -> Paid Search, (none)/(direct) -> Direct, referral from the store's own domains -> Self-referral,
--   other referral -> Referral, affiliate -> Affiliates, email -> Email, '(other)' -> Obfuscated (<Other>), '(data deleted)', '(not set)'

-- dim_date: full calendar between the first and last session date (no gaps even if a day had no sessions)
CREATE OR REPLACE TABLE dim_date AS
SELECT date_format_yyyymmdd(d) AS date_key, d AS date, year(d) AS year, month(d) AS month,
       concat(CAST(year(d) AS STRING), '-', lpad(CAST(month(d) AS STRING), 2, '0')) AS year_month,
       day(d) AS day, dayofweek(d) AS day_of_week_num,
       CASE dayofweek(d) WHEN 1 THEN 'Sun' WHEN 2 THEN 'Mon' WHEN 3 THEN 'Tue' WHEN 4 THEN 'Wed' WHEN 5 THEN 'Thu' WHEN 6 THEN 'Fri' ELSE 'Sat' END AS day_name,
       CASE WHEN dayofweek(d) IN (1, 7) THEN 1 ELSE 0 END AS is_weekend,
       CASE WHEN d BETWEEN DATE '2020-11-27' AND DATE '2020-11-30' THEN 'Black Friday-Cyber Monday'
            WHEN d BETWEEN DATE '2020-12-01' AND DATE '2020-12-23' THEN 'December pre-Christmas'
            WHEN d BETWEEN DATE '2020-12-24' AND DATE '2021-01-01' THEN 'Christmas-New Year'
            ELSE 'Regular' END AS season
FROM (SELECT CAST(d0 AS DATE) AS d
      FROM (SELECT explode(sequence(lo, hi, INTERVAL 1 DAY)) AS d0
            FROM (SELECT MIN(session_date) AS lo, MAX(session_date) AS hi FROM cln_sessions) b) s) x;

CREATE OR REPLACE TABLE dim_device AS
SELECT ROW_NUMBER() OVER (ORDER BY device_category, device_os, browser) AS device_key, device_category, device_os, browser
FROM (SELECT DISTINCT device_category, device_os, browser FROM cln_sessions) x;

CREATE OR REPLACE TABLE dim_geo AS
SELECT ROW_NUMBER() OVER (ORDER BY continent, sub_continent, country) AS geo_key, continent, sub_continent, country
FROM (SELECT DISTINCT continent, sub_continent, country FROM cln_sessions) x;

CREATE OR REPLACE TABLE dim_traffic AS
SELECT ROW_NUMBER() OVER (ORDER BY ft_source, ft_medium, ft_campaign) AS traffic_key,
       ft_source AS source, ft_medium AS medium, ft_campaign AS campaign,
       CASE WHEN ft_medium = 'organic' THEN 'Organic Search'
            WHEN ft_medium = 'cpc' THEN 'Paid Search'
            WHEN ft_medium = '(none)' OR ft_source = '(direct)' THEN 'Direct'
            WHEN ft_medium = 'referral' AND ft_source IN ('shop.googlemerchandisestore.com', 'googlemerchandisestore.com') THEN 'Self-referral'
            WHEN ft_medium = 'referral' THEN 'Referral'
            WHEN ft_medium = 'affiliate' THEN 'Affiliates'
            WHEN ft_medium = 'email' THEN 'Email'
            WHEN ft_medium = '(other)' THEN 'Obfuscated (<Other>)'
            WHEN ft_medium = '(data deleted)' THEN '(data deleted)'
            ELSE '(not set)' END AS channel_group
FROM (SELECT DISTINCT ft_source, ft_medium, ft_campaign FROM cln_sessions) x;

CREATE OR REPLACE TABLE fact_session AS
SELECT
  ROW_NUMBER() OVER (ORDER BY s.session_start_ts, s.session_id) AS session_key,
  s.session_id, s.user_pseudo_id, s.ga_session_id, date_format_yyyymmdd(s.session_date) AS date_key, s.start_hour_utc,
  d.device_key, g.geo_key, t.traffic_key,
  COALESCE(s.sess_source, '(not set)') AS session_source, COALESCE(s.sess_medium, '(not set)') AS session_medium,
  CASE WHEN s.sess_medium IS NULL THEN '(not set)'
       WHEN s.sess_medium = 'organic' THEN 'Organic Search'
       WHEN s.sess_medium = 'cpc' THEN 'Paid Search'
       WHEN s.sess_medium = '(none)' OR s.sess_source = '(direct)' THEN 'Direct'
       WHEN s.sess_medium = 'referral' AND s.sess_source IN ('shop.googlemerchandisestore.com', 'googlemerchandisestore.com') THEN 'Self-referral'
       WHEN s.sess_medium = 'referral' THEN 'Referral'
       WHEN s.sess_medium = 'affiliate' THEN 'Affiliates'
       WHEN s.sess_medium = 'email' THEN 'Email'
       WHEN s.sess_medium = '(other)' THEN 'Obfuscated (<Other>)'
       WHEN s.sess_medium = '(data deleted)' THEN '(data deleted)'
       ELSE 'Other' END AS session_channel,
  COALESCE(s.landing_page, '(no page_view)') AS landing_page,
  s.session_number, s.user_type, s.is_engaged, 1 - s.is_engaged AS is_bounce,
  s.events, s.page_views, s.view_item_events, s.add_to_cart_events,
  s.has_view_item, s.has_add_to_cart, s.has_begin_checkout, s.has_add_shipping_info, s.has_add_payment_info, s.has_purchase_event,
  s.has_search, s.is_converted, s.transactions, s.revenue_usd,
  ROUND(s.engagement_time_s, 3) AS engagement_time_s, ROUND(s.duration_s, 3) AS duration_s,
  s.dq_no_session_start, s.dq_long_session, s.dq_engagement_outlier, s.dq_purchase_without_cart, s.dq_purchase_without_checkout,
  s.dq_multi_session_medium, s.dq_attr_conflict
FROM cln_sessions s
JOIN dim_device d ON s.device_category = d.device_category AND s.device_os = d.device_os AND s.browser = d.browser
JOIN dim_geo g ON s.continent = g.continent AND s.sub_continent = g.sub_continent AND s.country = g.country
JOIN dim_traffic t ON s.ft_source = t.source AND s.ft_medium = t.medium AND s.ft_campaign = t.campaign;

CREATE OR REPLACE TABLE fact_transaction AS
SELECT ROW_NUMBER() OVER (ORDER BY t.order_ts, t.transaction_id_key) AS transaction_key, f.session_key,
       date_format_yyyymmdd(t.order_date) AS date_key, COALESCE(t.transaction_id, '(not set)') AS transaction_id,
       f.device_key, f.geo_key, f.traffic_key, t.revenue_usd, t.tax_usd, t.item_qty, t.unique_items, t.purchase_events,
       t.dq_txn_id_missing, t.dq_duplicate_purchase_events, t.dq_revenue_outlier
FROM cln_transactions t JOIN fact_session f ON t.session_id = f.session_id;
