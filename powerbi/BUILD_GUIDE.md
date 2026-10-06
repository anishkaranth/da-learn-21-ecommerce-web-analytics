# Build guide (Power BI Desktop, Windows)

No `.pbix` is committed: this repo is built on Linux and Power BI Desktop runs on Windows only.

1. Use the committed CSVs in `powerbi/data/` (7 files, about 4 MB, UTF-8, written by `python run_pipeline.py --source full`): `agg_daily_device_channel` (full, 1,924 rows), `fact_transaction` (full, 4,887), `fact_session_sample` (1-in-20 sample, 18,006), `dim_date` (92), `dim_device` (49), `dim_geo` (122), `dim_traffic` (15).
2. Power BI Desktop > Get data > Text/CSV: load all seven. In Power Query set **`user_pseudo_id`, `session_id`, `transaction_id` to Text** (auto-detect would turn the pseudo ids into decimals). Set `date` to Date. Set `*_key`, `start_hour_utc`, `session_number`, counts, `has_*`, `is_*` and `dq_*` columns to Whole number, and `revenue_usd`, `tax_usd`, `engagement_time_s` and `duration_s` to Decimal number.
3. Model view: create the relationships listed in `model.md`. All are many-to-one and single direction. `agg_daily_device_channel` joins `dim_date` only.
4. New measures: paste `measures.dax` one measure at a time into the home table given in each block.
5. Sort `dim_date[day_name]` by `dim_date[day_of_week_num]`. Mark `dim_date` as the date table (`date` column).
6. Build the two pages in `dashboard_spec.md` and check them against the "Expected" column. Aggregate-based and transaction-based visuals should match exactly. Sample-based visuals should land near the full values in brackets.
7. Optional: match colours to `results/images/dashboard.png`.
8. Save as `da-learn-21-ecommerce-web-analytics.pbix` locally (the binary is not committed).
