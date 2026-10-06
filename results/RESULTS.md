# Results · da-learn-21 e-commerce web analytics (full data)

Source: Google Merchandise Store **GA4 obfuscated sample e-commerce export** (BigQuery `ga4_obfuscated_sample_ecommerce`, 2020-11-01 to 2021-01-31, 92 days), flattened to one row per event. All numbers below come from `python run_pipeline.py --source full` (DuckDB 1.5.6) on the **full** export: **4,295,584 events, 270,154 users, 360,129 sessions, 4,887 transactions**. Session = `user_pseudo_id` + `ga_session_id`; engaged session = any event with `session_engaged = 1`; **bounce rate = 1 - engagement rate** (GA4 definition); conversion = session with at least one purchase with revenue > 0. Times are UTC. Quality checks: **28/28 assertions pass**.

Databricks was skipped for this project (workspace resource quota); the SQL is Spark-style and runs on DuckDB through the shims in `sql/00_duckdb_compat.sql`.

![Dashboard](images/dashboard.png)

## Headline KPIs
| KPI | Value |
|---|---|
| Events / users / sessions | 4,295,584 / 270,154 / 360,129 (1.33 sessions per user) |
| Period | 2020-11-01 to 2021-01-31 (92 days), 108 countries |
| Engagement rate / bounce rate | 88.88% / 11.12% |
| Page views per session / avg engagement time | 3.75 / 70.3 s (median session span 14 s) |
| New-user sessions | 72.54% |
| Converting sessions / session CVR | 4,446 / **1.235%** |
| Purchasers / user CVR | 4,066 / 1.505% |
| Transactions / revenue | 4,887 / **$339,343** |
| AOV / revenue per session / revenue per user | $69.44 / $0.942 / $1.256 |
| Cart abandonment (cart sessions without purchase) | 83.06% of 15,188 cart sessions |
| Checkout abandonment (checkout sessions without purchase) | 59.97% |

## Insights
1. **The biggest leak is before the cart.** Only **21.4%** of sessions view a product and only 19.7% of those add to cart, so 4.22% of sessions ever have a cart. Once a cart exists the funnel is much tighter: 73.1% begin checkout, 61.4% of shipping-info sessions reach payment and 65.2% of payment sessions buy. End to end, **1.24%** of sessions convert, with **83.1% cart abandonment** and 60.0% checkout abandonment. Product discovery (home and category pages to product pages) is the lever with the most volume.
2. **Revenue is concentrated in the shopping season.** December 1-23 earned **$6,423 per day** at a 1.70% CVR, and Black Friday to Cyber Monday (27-30 Nov) $7,051 per day at 2.10% with the highest AOV ($82.46). Regular days averaged $2,700 and Christmas to New Year only $1,354. The best day was **Cyber Monday 2020-11-30 ($11,910, 134 transactions)**, and 8 of the top 10 days fall in 7-16 December. By month: Nov $123,507, Dec $158,956, Jan $56,880 (CVR 0.71%, half of December's 1.53%).
3. **Returning visitors are the money.** Returning sessions are 27.5% of traffic but **67.0% of revenue**, convert at **2.83%** vs 0.63% for new users (x4.5) and spend more per order ($72.15 vs $64.53). Buying sessions are long: the 2.5% of sessions with 21+ page views convert at 29.7% and bring **70.4% of revenue**; sessions with 1-3 page views (71.2% of traffic) never convert.
4. **Channels: organic brings the volume, referrals convert.** First-touch Organic Search is the largest channel (34.1% of sessions, 28.8% of revenue, CVR 1.02%), then Direct (23.2% / 22.0%). Paid Search is 4.3% of sessions with the lowest CVR (0.92%) and AOV ($58.53). On the session-scoped source/medium, Referral sessions convert at **3.56%** ($2.65 per session) and the tiny Email channel at 10.2% (197 sessions). 26.3% of sessions carry no session source at all and almost never buy (1 conversion), and self-referrals from the store's own domains are 15.7% of sessions but 32.2% of revenue, a sign of cross-domain checkout returns that a production GA4 setup would exclude.
5. **Device, country and weekday matter less than you might expect.** Desktop has 58.0% of sessions and 58.0% of revenue, mobile 39.8% and 40.2%. Mobile converts no worse (CVR 1.27% vs 1.21%; cart-to-purchase 30.0% vs 28.8%). The US is 43.9% of sessions and 44.3% of revenue, followed by India (9.4%) and Canada (7.5%, highest AOV of the top 3 at $77.41). Weekdays carry the traffic: Tuesday averages 4,669 sessions per day vs 2,894 on Sunday, and Sunday also converts worst (0.87%). These dimensions are fairly flat (engagement is about 89% in every device and top country), partly because Google obfuscated the sample.
6. **Landing pages.** Sessions that land on **Home** (102,934) convert at 2.25% and bring 51.7% of revenue. Product and brand landings such as Google Dino Game Tee (18,450 sessions, CVR 0.02%) and YouTube Shop by Brand (0.22%) attract browsers rather than buyers, and 6,279 sessions landed on "Page Unavailable".

## Funnel (open = fired the step event; strict = also fired every earlier step)
| step | sessions | pct_of_sessions | pct_of_previous_step | drop_off_pct | strict_sessions | strict_pct_of_sessions |
|---|---|---|---|---|---|---|
| 0 session | 360,129 | 100 |  |  | 360,129 | 100 |
| 1 view_item | 77,020 | 21.387 | 21.39 | 78.61 | 77,020 | 21.387 |
| 2 add_to_cart | 15,188 | 4.217 | 19.72 | 80.28 | 15,173 | 4.213 |
| 3 begin_checkout | 11,106 | 3.084 | 73.12 | 26.88 | 5,959 | 1.655 |
| 4 add_shipping_info | 11,105 | 3.084 | 99.99 | 0.01 | 5,959 | 1.655 |
| 5 add_payment_info | 6,815 | 1.892 | 61.37 | 38.63 | 3,858 | 1.071 |
| 6 purchase | 4,446 | 1.235 | 65.24 | 34.76 | 2,573 | 0.714 |

1,873 of 4,446 converting sessions have no `add_to_cart` event, so the strict funnel ends at 2,573 purchases. This is an artefact of the obfuscated sample. The open funnel is the headline view.

![Funnel](images/funnel.png)
![Open vs strict funnel](images/funnel_strict.png)
![Funnel by device](images/funnel_device.png)

## Acquisition channels (first touch)
| channel_group | sessions | pct_sessions | users | engagement_rate_pct | bounce_rate_pct | add_to_cart_rate_pct | cvr_pct | transactions | revenue_usd | pct_revenue | aov_usd | revenue_per_session_usd |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Organic Search | 122,841 | 34.11 | 112,358 | 92.41 | 7.59 | 3.85 | 1.017 | 1,350 | 97,607 | 28.76 | 72.3 | 0.795 |
| Direct | 83,459 | 23.17 | 75,951 | 89.6 | 10.4 | 4.21 | 1.16 | 1,067 | 74,638 | 21.99 | 69.95 | 0.894 |
| Obfuscated (<Other>) | 52,058 | 14.46 | 51,038 | 95.81 | 4.19 | 3.81 | 0.907 | 514 | 32,733 | 9.65 | 63.68 | 0.629 |
| Referral | 34,675 | 9.63 | 32,883 | 88.03 | 11.97 | 4.21 | 1.252 | 484 | 33,957 | 10.01 | 70.16 | 0.979 |
| Self-referral | 28,849 | 8.01 | 26,065 | 78.17 | 21.83 | 5.07 | 1.865 | 604 | 44,613 | 13.15 | 73.86 | 1.546 |
| (data deleted) | 22,629 | 6.28 | 18,204 | 60.89 | 39.11 | 6.5 | 2.837 | 723 | 47,308 | 13.94 | 65.43 | 2.091 |
| Paid Search | 15,618 | 4.34 | 15,528 | 96.45 | 3.55 | 3.62 | 0.916 | 145 | 8,487 | 2.5 | 58.53 | 0.543 |

`Obfuscated (<Other>)` and `(data deleted)` are the placeholders Google used when it obfuscated the sample. They are kept as their own values, not guessed.

![Channel CVR](images/channel_cvr.png)
![Channel mix](images/channel_mix.png)

## Session source / medium (session-scoped event params)
| session_channel | sessions | pct_sessions | engagement_rate_pct | bounce_rate_pct | add_to_cart_rate_pct | converting_sessions | cvr_pct | revenue_usd | pct_revenue | revenue_per_session_usd |
|---|---|---|---|---|---|---|---|---|---|---|
| Organic Search | 103,039 | 28.61 | 94.17 | 5.83 | 5.07 | 1,537 | 1.492 | 108,700 | 32.03 | 1.055 |
| (not set) | 94,554 | 26.26 | 87.54 | 12.46 | 0.61 | 1 | 0.001 | 12 | 0 | 0 |
| Self-referral | 56,492 | 15.69 | 76.31 | 23.69 | 6.78 | 1,287 | 2.278 | 109,329 | 32.22 | 1.935 |
| Direct | 37,786 | 10.49 | 92.93 | 7.07 | 4.22 | 283 | 0.749 | 22,741 | 6.7 | 0.602 |
| Referral | 27,289 | 7.58 | 91.39 | 8.61 | 8.19 | 972 | 3.562 | 72,366 | 21.33 | 2.652 |
| Obfuscated (<Other>) | 25,328 | 7.03 | 97.34 | 2.66 | 3.77 | 117 | 0.462 | 8,490 | 2.5 | 0.335 |
| Paid Search | 7,672 | 2.13 | 97.72 | 2.28 | 3.53 | 45 | 0.587 | 3,114 | 0.92 | 0.406 |
| (data deleted) | 6,443 | 1.79 | 57.75 | 42.25 | 6.52 | 182 | 2.825 | 12,765 | 3.76 | 1.981 |
| Affiliates | 1,329 | 0.37 | 81.79 | 18.21 | 2.48 | 2 | 0.15 | 167 | 0.05 | 0.126 |
| Email | 197 | 0.05 | 91.88 | 8.12 | 23.86 | 20 | 10.152 | 1,659 | 0.49 | 8.421 |

![Session channel](images/session_channel.png)

## Devices
| device_category | sessions | pct_sessions | users | engagement_rate_pct | bounce_rate_pct | pageviews_per_session | avg_engagement_time_s | add_to_cart_rate_pct | cart_to_purchase_pct | cvr_pct | transactions | revenue_usd | pct_revenue | aov_usd |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| desktop | 208,942 | 58.02 | 158,917 | 88.92 | 11.08 | 3.76 | 69.8 | 4.21 | 28.81 | 1.212 | 2,806 | 196,789 | 57.99 | 70.13 |
| mobile | 143,185 | 39.76 | 109,195 | 88.82 | 11.18 | 3.74 | 71.4 | 4.24 | 30 | 1.273 | 1,989 | 136,601 | 40.25 | 68.68 |
| tablet | 8,002 | 2.22 | 6,250 | 88.99 | 11.01 | 3.67 | 65.3 | 4.01 | 28.35 | 1.137 | 92 | 5,953 | 1.75 | 64.71 |

Operating system:

| device_os | sessions | engagement_rate_pct | cvr_pct | revenue_usd | aov_usd |
|---|---|---|---|---|---|
| Web | 209,949 | 88.88 | 1.242 | 196,991 | 68.73 |
| iOS | 41,532 | 89.03 | 1.271 | 38,712 | 68.04 |
| Windows | 41,524 | 88.86 | 1.163 | 36,622 | 69.36 |
| Android | 31,244 | 88.72 | 1.168 | 26,993 | 66.65 |
| Macintosh | 26,789 | 88.8 | 1.254 | 28,384 | 75.09 |
| (other) | 9,091 | 89.26 | 1.397 | 11,641 | 82.56 |

![Device mix](images/device_mix.png)

## Time: months, seasons, days, hours
| year_month | days | sessions | users | engagement_rate_pct | cvr_pct | transactions | revenue_usd | aov_usd |
|---|---|---|---|---|---|---|---|---|
| 2020-11 | 30 | 108,401 | 79,421 | 84.28 | 1.443 | 1,680 | 123,507 | 73.52 |
| 2020-12 | 31 | 133,351 | 104,302 | 88.2 | 1.528 | 2,312 | 158,956 | 68.75 |
| 2021-01 | 31 | 118,377 | 94,788 | 93.87 | 0.714 | 895 | 56,880 | 63.55 |

| season | days | sessions | sessions_per_day | cvr_pct | transactions | revenue_usd | revenue_per_day_usd | aov_usd |
|---|---|---|---|---|---|---|---|---|
| Black Friday-Cyber Monday | 4 | 15,200 | 3,800 | 2.105 | 342 | 28,203 | 7,050.75 | 82.46 |
| December pre-Christmas | 23 | 109,932 | 4,779.7 | 1.702 | 2,136 | 147,731 | 6,423.09 | 69.16 |
| Regular | 56 | 209,270 | 3,737 | 0.992 | 2,220 | 151,223 | 2,700.41 | 68.12 |
| Christmas-New Year | 9 | 25,727 | 2,858.6 | 0.692 | 189 | 12,186 | 1,354 | 64.48 |

Top 10 revenue days:

| rnk | date | day_name | season | sessions | cvr_pct | transactions | revenue_usd |
|---|---|---|---|---|---|---|---|
| 1 | 2020-11-30 | Mon | Black Friday-Cyber Monday | 4,583 | 2.662 | 134 | 11,910 |
| 2 | 2020-12-16 | Wed | December pre-Christmas | 5,528 | 2.08 | 140 | 10,847 |
| 3 | 2020-12-10 | Thu | December pre-Christmas | 5,993 | 2.086 | 138 | 10,835 |
| 4 | 2020-12-09 | Wed | December pre-Christmas | 6,282 | 2.038 | 143 | 10,621 |
| 5 | 2020-12-15 | Tue | December pre-Christmas | 5,741 | 1.968 | 133 | 10,152 |
| 6 | 2020-12-11 | Fri | December pre-Christmas | 5,607 | 2.515 | 151 | 10,129 |
| 7 | 2020-12-07 | Mon | December pre-Christmas | 5,451 | 1.651 | 107 | 8,735 |
| 8 | 2020-12-14 | Mon | December pre-Christmas | 5,098 | 1.589 | 92 | 8,471 |
| 9 | 2020-12-08 | Tue | December pre-Christmas | 7,562 | 1.402 | 116 | 8,197 |
| 10 | 2020-11-25 | Wed | Regular | 4,604 | 1.781 | 95 | 7,647 |

By weekday (average per calendar day):

| day_name | days | sessions_per_day | engagement_rate_pct | cvr_pct | revenue_per_day_usd |
|---|---|---|---|---|---|
| Mon | 13 | 3,986.1 | 88.22 | 1.333 | 4,402.08 |
| Tue | 13 | 4,669 | 88.23 | 1.323 | 4,503.38 |
| Wed | 13 | 4,623.1 | 88.47 | 1.27 | 4,742.31 |
| Thu | 13 | 4,289.4 | 88.67 | 1.137 | 3,666 |
| Fri | 13 | 3,918.2 | 89.16 | 1.441 | 4,105.31 |
| Sat | 13 | 3,099.9 | 90.19 | 1.166 | 2,692.62 |
| Sun | 14 | 2,894 | 89.98 | 0.866 | 1,849.36 |

Sessions peak at 5:00 UTC and are lowest at 12:00 UTC. The last week of January (25-31 Jan) has 26,342 sessions but only 98 transactions, and 31 Jan has none. Traffic stays normal, so this looks like purchase tracking tailing off at the end of the sample, not a real collapse in demand.

![Daily revenue](images/daily_revenue.png)
![Daily sessions](images/daily_sessions.png)
![Season](images/season.png)
![Weekday x hour](images/dow_hour.png)

## Countries (top 15 by sessions)
| rnk | country | sessions | pct_sessions | engagement_rate_pct | converting_sessions | cvr_pct | transactions | revenue_usd | pct_revenue | aov_usd |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | United States | 158,155 | 43.92 | 88.91 | 1,932 | 1.222 | 2,133 | 150,278 | 44.28 | 70.45 |
| 2 | India | 33,769 | 9.38 | 88.84 | 415 | 1.229 | 449 | 32,754 | 9.65 | 72.95 |
| 3 | Canada | 26,824 | 7.45 | 89.23 | 357 | 1.331 | 401 | 31,041 | 9.15 | 77.41 |
| 4 | United Kingdom | 11,327 | 3.15 | 88.94 | 141 | 1.245 | 147 | 10,627 | 3.13 | 72.29 |
| 5 | France | 7,162 | 1.99 | 88.65 | 99 | 1.382 | 103 | 6,161 | 1.82 | 59.82 |
| 6 | Spain | 6,667 | 1.85 | 89.23 | 93 | 1.395 | 112 | 7,036 | 2.07 | 62.82 |
| 7 | Germany | 6,393 | 1.78 | 89.16 | 75 | 1.173 | 77 | 5,097 | 1.5 | 66.19 |
| 8 | China | 6,258 | 1.74 | 89.07 | 72 | 1.151 | 85 | 5,735 | 1.69 | 67.47 |
| 9 | Taiwan | 6,057 | 1.68 | 88.86 | 73 | 1.205 | 75 | 4,137 | 1.22 | 55.16 |
| 10 | Italy | 4,998 | 1.39 | 89.38 | 51 | 1.02 | 55 | 4,943 | 1.46 | 89.87 |
| 11 | Singapore | 4,741 | 1.32 | 89.07 | 49 | 1.034 | 58 | 3,529 | 1.04 | 60.84 |
| 12 | Japan | 4,732 | 1.31 | 88.52 | 69 | 1.458 | 73 | 5,445 | 1.6 | 74.59 |
| 13 | South Korea | 4,523 | 1.26 | 89.1 | 45 | 0.995 | 46 | 3,334 | 0.98 | 72.48 |
| 14 | Netherlands | 4,073 | 1.13 | 88.66 | 54 | 1.326 | 58 | 3,802 | 1.12 | 65.55 |
| 15 | Turkey | 3,646 | 1.01 | 88.67 | 54 | 1.481 | 60 | 4,311 | 1.27 | 71.85 |
| 16 | All other countries | 70,804 | 19.66 | 88.65 | 867 | 1.225 | 955 | 61,113 | 18.01 | 63.99 |

![Countries](images/country.png)

## Landing pages (top 12 by sessions)
| rnk | landing_page | sessions | bounce_rate_pct | add_to_cart_rate_pct | cvr_pct | revenue_usd |
|---|---|---|---|---|---|---|
| 1 | Home | 102,934 | 3.62 | 7.57 | 2.248 | 175,293 |
| 2 | Google Online Store | 64,348 | 5.34 | 2.61 | 0.522 | 24,887 |
| 3 | Apparel / Google Merchandise Store | 39,325 | 2.05 | 1.49 | 0.323 | 10,467 |
| 4 | (no page_view) | 28,806 | 85.9 | 0.15 | 0 | 0 |
| 5 | YouTube / Shop by Brand / Google Merchandise Store | 23,631 | 2.22 | 2.67 | 0.216 | 1,474 |
| 6 | Google Dino Game Tee | 18,450 | 1.25 | 0.07 | 0.022 | 327 |
| 7 | Men's T-Shirts / Apparel / Google Merchandise Store | 6,960 | 2.33 | 6.71 | 0.56 | 1,887 |
| 8 | Page Unavailable | 6,279 | 6.58 | 0.65 | 0 | 0 |
| 9 | Drinkware / Lifestyle / Google Merchandise Store | 5,047 | 13.33 | 1.92 | 0.852 | 3,654 |
| 10 | The Google Merchandise Store - Log In | 4,328 | 10.47 | 4.94 | 2.703 | 9,538 |
| 11 | Men's / Unisex / Apparel / Google Merchandise Store | 3,893 | 9.81 | 9.32 | 3.493 | 14,547 |
| 12 | Shopping Cart | 3,827 | 9.12 | 15.16 | 9.25 | 30,608 |

`(no page_view)` = sessions whose events contain no `page_view` (for example only `session_start` / `first_visit` / `user_engagement`). They are 85.9% bounces.

![Landing pages](images/landing_page.png)

## New vs returning, and engagement depth
| user_type | sessions | pct_sessions | engagement_rate_pct | pageviews_per_session | add_to_cart_rate_pct | cvr_pct | transactions | revenue_usd | pct_revenue | aov_usd |
|---|---|---|---|---|---|---|---|---|---|---|
| new | 261,238 | 72.54 | 99.94 | 3.57 | 3.39 | 0.631 | 1,738 | 112,147 | 33.05 | 64.53 |
| returning | 98,891 | 27.46 | 59.67 | 4.22 | 6.41 | 2.829 | 3,149 | 227,196 | 66.95 | 72.15 |

| page_views_band | sessions | pct_sessions | engagement_rate_pct | cvr_pct | revenue_usd | pct_revenue |
|---|---|---|---|---|---|---|
| 0 | 26,446 | 7.34 | 6.67 | 0 | 0 | 0 |
| 1 | 126,049 | 35 | 87.82 | 0 | 0 | 0 |
| 2-3 | 130,366 | 36.2 | 100 | 0 | 0 | 0 |
| 4-6 | 36,303 | 10.08 | 100 | 0.039 | 815 | 0.24 |
| 7-10 | 18,236 | 5.06 | 100 | 1.557 | 15,677 | 4.62 |
| 11-20 | 13,719 | 3.81 | 100 | 10.7 | 84,032 | 24.76 |
| 21+ | 9,010 | 2.5 | 100 | 29.745 | 238,819 | 70.38 |

New-user sessions show 99.94% engagement against 59.67% for returning ones. That gap reflects how `session_engaged` is populated in this sample. Read bounce by user type with care.

![New vs returning](images/new_returning.png)
![Page depth](images/page_depth.png)

## Order values
| order_value_band | transactions | pct_transactions | revenue_usd | pct_revenue | avg_items |
|---|---|---|---|---|---|
| 1: < $25 | 1,102 | 22.55 | 18,321 | 5.4 | 1.72 |
| 2: $25-49 | 1,434 | 29.34 | 53,285 | 15.7 | 2.6 |
| 3: $50-99 | 1,497 | 30.63 | 107,145 | 31.57 | 3.91 |
| 4: $100-199 | 651 | 13.32 | 90,580 | 26.69 | 7.57 |
| 5: $200-499 | 177 | 3.62 | 50,656 | 14.93 | 18.41 |
| 6: $500+ | 26 | 0.53 | 19,356 | 5.7 | 65.23 |

Mean $69.44, median $48.00, p90 $140.00, max $1,530; 127 orders above Q3 + 3 IQR are flagged (kept) and carry 15.6% of revenue. Collapsing repeated purchase events of the same transaction removed $22,822 of double-counted revenue ($362,165 summed over raw purchase events → $339,343).

![Order values](images/order_value.png)

## Data quality (before → after)
| entity | raw_rows | distinct_keys | clean_rows | grain |
|---|---|---|---|---|
| dim_date |  |  | 92 | day |
| dim_device |  |  | 49 | device category x OS x browser |
| dim_geo |  |  | 122 | continent x sub-continent x country |
| dim_traffic |  |  | 15 | first-touch source x medium x campaign |
| fact_session |  |  | 360,129 | session |
| fact_transaction |  |  | 4,887 | transaction |
| purchase events -> transactions | 5,692 | 5,242 | 4,887 | transaction |
| raw events (stg_events) | 4,295,615 | 4,295,584 | 4,295,584 | event |
| sessions |  | 360,129 | 360,129 | user_pseudo_id + ga_session_id |
| users |  |  | 270,154 | user_pseudo_id |

Issue counts:

| check_name | affected_rows |
|---|---|
| sessions with 2+ different session mediums (first one used) | 53,993 |
| users whose first-touch medium differs between events (obfuscation) | 41,164 |
| ga_session_id values shared by 2+ users (key = user + session id) | 9,906 |
| sessions without a session_start event (kept) | 5,272 |
| converting sessions without add_to_cart event (obfuscation) | 1,873 |
| purchase events with revenue 0 / NULL (not transactions) | 450 |
| transactions with missing / (not set) transaction id (kept) | 421 |
| purchase events collapsed as repeats of the same transaction | 355 |
| transactions flagged revenue outlier (> Q3 + 3 IQR, kept) | 127 |
| raw: repeated header lines inside the export (dropped) | 31 |
| sessions spanning > 4 h (flagged, kept) | 26 |
| transaction ids reused across sessions (obfuscation; kept separate) | 15 |
| events with engagement_time > 1 h (flagged, kept) | 10 |
| RI: sessions lost in dim joins | 0 |
| RI: transactions lost in session join | 0 |
| converting sessions without begin_checkout event | 0 |
| events: exact duplicate events dropped | 0 |

Null / placeholder rates:

| entity | column_name | null_pct | treatment |
|---|---|---|---|
| events | engagement_time_msec | 43.388 | treated as 0 in session sums |
| events | ep_medium (session-scoped medium param) | 66.495 | resolved per session (first non-NULL); sessions with none -> (not set) |
| events | ga_session_id | 0 | row dropped if NULL |
| events | page_title (page_view events) | 0.508 | landing page = (no page_view) |
| events | traffic_medium = (other) / (data deleted) (obfuscated) | 21.217 | kept as own channel values |
| purchase events | ecom_revenue_usd | 0 | NULL / 0 revenue -> not a transaction |
| purchase events | ecom_transaction_id | 15.917 | NULL or (not set) -> keyed by session + revenue |
| sessions | session source / medium | 26.256 | session_channel = (not set); first-touch channel always present |

Assertions (28/28 PASS):

| check_name | failed_rows | status |
|---|---|---|
| channel table covers all sessions and revenue | 0 | PASS |
| clean events = distinct valid event keys in staging | 0 | PASS |
| converted sessions all have a purchase event | 0 | PASS |
| daily x device x channel aggregate reconciles to fact_session | 0 | PASS |
| device_category in {desktop, mobile, tablet} | 0 | PASS |
| dim_date contiguous (rows = days between first and last date) | 0 | PASS |
| event key unique in cln_events | 0 | PASS |
| event_date = UTC date of event_timestamp | 0 | PASS |
| events within 2020-11-01..2021-01-31 | 0 | PASS |
| every session belongs to one user and has >= 1 event | 0 | PASS |
| fact_session rows = distinct sessions in events | 0 | PASS |
| fact_session.date_key -> dim_date | 0 | PASS |
| fact_session.device_key -> dim_device | 0 | PASS |
| fact_session.geo_key -> dim_geo | 0 | PASS |
| fact_session.traffic_key -> dim_traffic | 0 | PASS |
| fact_transaction rows = cleaned transactions | 0 | PASS |
| fact_transaction.session_key -> fact_session | 0 | PASS |
| funnel purchase step = converting sessions | 0 | PASS |
| funnel strict counts never exceed open counts | 0 | PASS |
| is_engaged and is_bounce are complements | 0 | PASS |
| no negative durations / engagement times | 0 | PASS |
| no repeated header rows left | 0 | PASS |
| session attributes constant within session (device / OS / country / first touch) | 0 | PASS |
| session revenue = transaction revenue (total) | 0 | PASS |
| session transactions = transaction rows (total) | 0 | PASS |
| session_id unique in fact_session | 0 | PASS |
| session_key unique in fact_session | 0 | PASS |
| transaction revenue > 0 | 0 | PASS |

![Data quality](images/data_quality.png)

## How the images were made
`scripts/make_charts.py` draws every chart from the CSVs in `results/tables/`, which are the DuckDB query results of `sql/04_analysis.sql` and `sql/05_quality_checks.sql`. Each one is a plain-vector SVG (only rect, line, polyline, circle and text, written by the small custom writer `scripts/svgcharts.py`, no plotting library). `scripts/render_png.py` then rasterises each SVG to PNG at 2x with headless Google Chrome. `images/dashboard.svg` tiles seven KPI cards and six panels into one page. All 18 charts are in `images/` as both `.svg` and `.png`.
