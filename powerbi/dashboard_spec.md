# Dashboard spec (2 pages)

Expected values come from the full data (`results/metrics.json`, `results/tables/`). Visuals on `agg_daily_device_channel` and `fact_transaction` should match them **exactly**. Visuals on `fact_session_sample` show 1-in-20 sample values; the full-data value is given in brackets.

## Page 1 - Traffic, funnel and conversion (agg_daily_device_channel, full)
| Visual | Fields | Expected (full data) |
|---|---|---|
| Cards | Sessions, Engagement Rate %, Bounce Rate %, Session CVR %, Transactions, Revenue (US$), AOV (US$) | 360,129 · 88.88% · 11.12% · 1.235% · 4,887 · $339,343 · $69.44 |
| Funnel | Sessions, View Item Sessions, Add to Cart Sessions, Begin Checkout Sessions, Add Shipping Sessions, Add Payment Sessions, Converting Sessions | 360,129 → 77,020 → 15,188 → 11,106 → 11,105 → 6,815 → 4,446 |
| Bar chart | agg[channel_group] × Session CVR %, tooltip Sessions, Revenue Share % | (data deleted) 2.84% · Self-referral 1.87% · Referral 1.25% · Direct 1.16% · Organic Search 1.02% · Paid Search 0.92% · Obfuscated 0.91% |
| Clustered column | agg[channel_group] × Session Share %, Revenue Share % | Organic Search 34.11% / 28.76% · Direct 23.17% / 21.99% · Paid Search 4.34% / 2.50% |
| Line chart | dim_date[date] × Revenue (US$) | peak 2020-11-30 $11,910; Nov $123,507 · Dec $158,956 · Jan $56,880 |
| Clustered column | agg[device_category] × Session CVR %, Add to Cart Rate % | desktop 1.212% / 4.21% · mobile 1.273% / 4.24% · tablet 1.137% / 4.01% |
| Slicers | dim_date[season], dim_date[year_month], agg[device_category] | Black Friday-Cyber Monday CVR 2.105%, December pre-Christmas 1.702% |

## Page 2 - Orders and session drill-downs
| Visual | Fields | Expected |
|---|---|---|
| Cards (fact_transaction) | Orders, Order Revenue (US$), Median Order (US$), Avg Items per Order | 4,887 · $339,343 · $48 · 4.37 |
| Column chart (fact_transaction) | revenue band (new column: `SWITCH(TRUE(), [revenue_usd] < 25, "< $25", [revenue_usd] < 50, "$25-49", [revenue_usd] < 100, "$50-99", [revenue_usd] < 200, "$100-199", [revenue_usd] < 500, "$200-499", "$500+")`) × Orders | 1,102 · 1,434 · 1,497 · 651 · 177 · 26 |
| Map / bar (fact_transaction) | dim_geo[country] × Order Revenue (US$), top 10 | United States $150,278 · India $32,754 · Canada $31,041 |
| Clustered column (sample) | fact_session_sample[user_type] × Sample CVR % | new 0.594% (full 0.631%) · returning 3.137% (full 2.829%) |
| Table (sample) | fact_session_sample[landing_page] × Sample Sessions, Sample Bounce Rate %, Sample CVR %, top 10 | Home 5,166 sessions, CVR 2.36% (full 102,934, 2.25%) |
| Bar (sample) | fact_session_sample[session_channel] × Sample CVR % | Referral highest among large channels (full 3.56%); (not set) ≈ 0% |
| Slicers | dim_device[device_category], dim_traffic[channel_group], dim_date[season] | |

The 1-in-20 sample holds 18,006 sessions, 235 converting sessions and $22,233 revenue (full: 360,129 / 4,446 / $339,343). Its CVR is 1.305% vs 1.235% in the full data.
