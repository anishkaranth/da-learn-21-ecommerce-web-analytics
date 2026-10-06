"""Project-specific settings used by run_pipeline.py (raw files, exports, JSON.shot content)."""
NAME = "da-learn-21-ecommerce-web-analytics"
DATASET = ("Google Merchandise Store GA4 obfuscated sample e-commerce event export (bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*, "
           "Google Analytics / BigQuery public datasets program), 2020-11-01..2021-01-31, flattened 1:1 to one CSV row per event "
           "(4,295,584 events, 60 columns; items[] removed) by D. Gizdevans and mirrored on Hugging Face gizdevans/ga4-bq-flattened-data "
           "(MIT on the mirror; upstream is Google's public BigQuery sample). Kaggle copies: pdaasha/ga4-obfuscated-sample-ecommerce-jan2021 "
           "(Jan 2021 subset), mexwell/google-merchandise-sales-data (curated subset). Full file 1,844,623,697 B")
RAW_FILES = ["full_flatten_data.csv"]
DIMS = ["dim_date", "dim_device", "dim_geo", "dim_traffic"]
METRIC_TABLES = ["a_kpi_headline", "a_funnel", "a_funnel_device", "a_channel", "a_session_channel", "a_device", "a_os", "a_daily",
                 "a_season", "a_monthly", "a_dow_hour", "a_weekday", "a_country", "a_landing_page", "a_new_returning", "a_page_depth",
                 "a_order_value", "a_order_stats", "a_top_days"]
SESSION_SAMPLE_EVERY = 20   # powerbi/ and data/clean/ hold every 20th session (session_key % 20 = 0); aggregates are full


def export_full(con, export, root):
    """Full run: dims, fact_transaction and the daily x device x channel aggregate are small -> exported in full;
    fact_session (360k rows) is exported as a deterministic 1-in-20 sample (session_key % 20 = 0)."""
    con.execute(f"CREATE OR REPLACE TEMP VIEW fact_session_sample AS SELECT * FROM fact_session WHERE session_key % {SESSION_SAMPLE_EVERY} = 0")
    for t, name in [(d, d) for d in DIMS] + [("fact_transaction", "fact_transaction"), ("agg_daily_device_channel", "agg_daily_device_channel"),
                                             ("fact_session_sample", "fact_session_sample")]:
        export(con, t, root / "data/clean/star" / f"{name}.csv")
        export(con, t, root / "powerbi/data" / f"{name}.csv")


def build_shot(q, kpi):
    """Headline snapshot written to results/JSON.shot."""
    return {
        "config": {"sql_dialect": "Spark SQL style (+ DuckDB shims in sql/00), run on DuckDB; Databricks skipped (workspace quota)",
                   "grain": "fact_session = one GA4 session (user_pseudo_id + ga_session_id); fact_transaction = one de-duplicated purchase",
                   "engaged_bounce": "engaged session = any event with session_engaged = 1; bounce rate = 1 - engagement rate (GA4)",
                   "conversion": "session CVR = sessions with >= 1 purchase with revenue > 0 / all sessions",
                   "funnel": "open funnel: sessions that fired each step event (view_item, add_to_cart, begin_checkout, add_shipping_info, "
                             "add_payment_info, purchase); strict = also fired every earlier step",
                   "channel": "first-touch traffic_source.source/medium grouped GA-style; session_channel from session-scoped source/medium params",
                   "time": "event_date and hours are UTC (export date = UTC date of event_timestamp)",
                   "dedupe": "exact event key; repeat purchase events of the same transaction in a session collapse to one",
                   "sample_rule": "data/raw: all events of every 1000th user (sorted user_pseudo_id) + every 80th purchasing user, plus the repeated "
                                  "header lines (scripts/make_sample.py)"},
        "headline": kpi,
        "funnel": q("SELECT step, sessions, pct_of_sessions, pct_of_previous_step, strict_sessions FROM a_funnel ORDER BY step_no"),
        "channels": q("SELECT channel_group, sessions, pct_sessions, engagement_rate_pct, cvr_pct, revenue_usd, pct_revenue, aov_usd "
                      "FROM a_channel ORDER BY sessions DESC"),
        "devices": q("SELECT device_category, sessions, pct_sessions, engagement_rate_pct, cvr_pct, revenue_usd, pct_revenue, aov_usd "
                     "FROM a_device ORDER BY sessions DESC"),
        "months": q("SELECT year_month, sessions, cvr_pct, transactions, revenue_usd, aov_usd FROM a_monthly ORDER BY year_month"),
        "seasons": q("SELECT season, days, sessions_per_day, cvr_pct, revenue_per_day_usd, aov_usd FROM a_season ORDER BY revenue_per_day_usd DESC"),
        "new_vs_returning": q("SELECT user_type, sessions, pct_sessions, cvr_pct, pct_revenue, aov_usd FROM a_new_returning ORDER BY user_type"),
        "top_days": q("SELECT rnk, date, day_name, sessions, transactions, revenue_usd FROM a_top_days ORDER BY rnk LIMIT 5"),
    }
