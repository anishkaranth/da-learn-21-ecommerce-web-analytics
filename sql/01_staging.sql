-- 01_staging.sql
-- Land the raw GA4 flattened event export as one all-STRING staging table (no type inference; casting happens in 02).
-- {{RAW_DIR}} is substituted by run_pipeline.py.
-- Source file: full_flatten_data.csv = bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_* (2020-11-01..2021-01-31)
-- flattened 1:1 (one row per event, 60 columns; items[] arrays removed) and mirrored on Hugging Face.
-- The export was written in shards, so the header line re-appears inside the file; those rows are removed in 02.
-- DuckDB : read_csv(path, header = true, all_varchar = true, names = [...])
-- Spark/Databricks equivalent (not run here: Databricks skipped, workspace quota):
--   SELECT * FROM read_files('<path>/full_flatten_data.csv', format => 'csv', header => true,
--          multiLine => true, escape => '"', inferColumnTypes => false, schema => '<col> STRING, ...')
CREATE OR REPLACE TABLE stg_events AS
SELECT * FROM read_csv('{{RAW_DIR}}/full_flatten_data.csv', header = true, all_varchar = true, quote = '"', escape = '"',
  names = ['event_date', 'event_name', 'event_timestamp', 'event_bundle_sequence_id', 'event_value_in_usd', 'user_pseudo_id',
           'user_first_touch_timestamp', 'stream_id', 'platform', 'uses_transient_token', 'device_category', 'device_mobile_brand',
           'device_mobile_model', 'device_mobile_marketing', 'device_os', 'device_os_version', 'device_language',
           'device_limited_ad_tracking', 'browser', 'browser_version', 'continent', 'country', 'region', 'city', 'sub_continent', 'metro',
           'traffic_source', 'traffic_medium', 'traffic_campaign', 'ecom_total_item_qty', 'ecom_revenue_usd', 'ecom_revenue',
           'ecom_tax_usd', 'ecom_tax', 'ecom_unique_items', 'ecom_transaction_id', 'page_location', 'page_title', 'page_referrer',
           'ep_source', 'ep_medium', 'ep_campaign', 'ep_term', 'ga_session_id', 'ga_session_number', 'engagement_time_msec',
           'entrances', 'debug_mode', 'engaged_session_event', 'session_engaged', 'clean_event', 'link_domain', 'link_url', 'outbound',
           'percent_scrolled', 'search_term', 'unique_search_term', 'ep_promotion_name', 'ep_coupon', 'ep_currency']);
