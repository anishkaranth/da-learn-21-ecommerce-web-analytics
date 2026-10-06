#!/usr/bin/env python3
"""Write results/RESULTS.md from results/metrics.json + results/tables/*.csv (every number comes from the full-data run)."""
import csv, json, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
RES = ROOT / "results"
T = RES / "tables"


def rd(name):
    with open(T / f"{name}.csv", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def f(x):
    return float(x) if x not in ("", None) else 0.0


def num(v):
    if v in ("", None):
        return ""
    try:
        x = float(v)
    except ValueError:
        return str(v).replace("|", "/")
    return f"{int(x):,}" if x.is_integer() and abs(x) >= 1000 else (str(int(x)) if x.is_integer() else f"{x:,.3f}".rstrip("0").rstrip("."))


def table(rows, cols, heads=None):
    out = ["| " + " | ".join(heads or cols) + " |", "|" + "---|" * len(cols)]
    for r in rows:
        out.append("| " + " | ".join(num(r[c]) for c in cols) + " |")
    return "\n".join(out)


def usd(v):
    return f"${f(v):,.0f}"


m = json.loads((RES / "metrics.json").read_text())
k = m["kpis"]
fun = sorted(rd("a_funnel"), key=lambda r: int(r["step_no"]))
fs = {r["step"]: r for r in fun}
ch = sorted(rd("a_channel"), key=lambda r: -f(r["sessions"]))
cg = {r["channel_group"]: r for r in ch}
sch = sorted(rd("a_session_channel"), key=lambda r: -f(r["sessions"]))
sc = {r["session_channel"]: r for r in sch}
dev = sorted(rd("a_device"), key=lambda r: -f(r["sessions"]))
dv = {r["device_category"]: r for r in dev}
osr = sorted(rd("a_os"), key=lambda r: -f(r["sessions"]))
day = sorted(rd("a_daily"), key=lambda r: r["date"])
seas = sorted(rd("a_season"), key=lambda r: -f(r["revenue_per_day_usd"]))
se = {r["season"]: r for r in seas}
mon = sorted(rd("a_monthly"), key=lambda r: r["year_month"])
mo = {r["year_month"]: r for r in mon}
wk = sorted(rd("a_weekday"), key=lambda r: (int(r["day_of_week_num"]) + 5) % 7)
wd = {r["day_name"]: r for r in wk}
ctry = sorted(rd("a_country"), key=lambda r: int(r["rnk"]))
ct = {r["country"]: r for r in ctry}
lp = sorted(rd("a_landing_page"), key=lambda r: int(r["rnk"]))
lpg = {r["landing_page"]: r for r in lp}
nr = {r["user_type"]: r for r in rd("a_new_returning")}
pdp = sorted(rd("a_page_depth"), key=lambda r: int(r["band_min"]))
pd = {r["page_views_band"]: r for r in pdp}
ov = sorted(rd("a_order_value"), key=lambda r: r["order_value_band"])
ost = rd("a_order_stats")[0]
top = sorted(rd("a_top_days"), key=lambda r: int(r["rnk"]))
rc = rd("dq_row_counts")
iss = sorted(rd("dq_issues"), key=lambda r: -f(r["affected_rows"]))
isd = {r["check_name"]: r["affected_rows"] for r in iss}
asr = rd("dq_assertions")
npass = sum(r["status"] == "PASS" for r in asr)
late = [r for r in day if r["date"] >= "2021-01-25"]
late_tx, late_sess = sum(int(r["transactions"]) for r in late), sum(int(r["sessions"]) for r in late)
dh = rd("a_dow_hour")
peak_h = max(range(24), key=lambda h: sum(int(r["sessions"]) for r in dh if int(r["start_hour_utc"]) == h))
low_h = min(range(24), key=lambda h: sum(int(r["sessions"]) for r in dh if int(r["start_hour_utc"]) == h))
rev = f(k["revenue_usd"])
dec_top = sorted(r['date'] for r in top if r['date'].startswith('2020-12'))
d21 = pd["21+"]; d1120 = pd["11-20"]

md = f"""# Results · da-learn-21 e-commerce web analytics (full data)

Source: Google Merchandise Store **GA4 obfuscated sample e-commerce export** (BigQuery `ga4_obfuscated_sample_ecommerce`, {k['first_date']} to {k['last_date']}, {k['days']} days), flattened to one row per event. All numbers below come from `python run_pipeline.py --source full` (DuckDB {m['engine']['duckdb']}) on the **full** export: **{int(f(k['events'])):,} events, {int(f(k['users'])):,} users, {int(f(k['sessions'])):,} sessions, {int(f(k['transactions'])):,} transactions**. Session = `user_pseudo_id` + `ga_session_id`; engaged session = any event with `session_engaged = 1`; **bounce rate = 1 - engagement rate** (GA4 definition); conversion = session with at least one purchase with revenue > 0. Times are UTC. Quality checks: **{npass}/{len(asr)} assertions pass**.

Databricks was skipped for this project (workspace resource quota); the SQL is Spark-style and runs on DuckDB through the shims in `sql/00_duckdb_compat.sql`.

![Dashboard](images/dashboard.png)

## Headline KPIs
| KPI | Value |
|---|---|
| Events / users / sessions | {int(f(k['events'])):,} / {int(f(k['users'])):,} / {int(f(k['sessions'])):,} ({f(k['sessions_per_user']):.2f} sessions per user) |
| Period | {k['first_date']} to {k['last_date']} ({k['days']} days), {k['countries']} countries |
| Engagement rate / bounce rate | {f(k['engagement_rate_pct']):.2f}% / {f(k['bounce_rate_pct']):.2f}% |
| Page views per session / avg engagement time | {f(k['pageviews_per_session']):.2f} / {f(k['avg_engagement_time_s']):.1f} s (median session span {f(k['median_session_span_s']):.0f} s) |
| New-user sessions | {f(k['new_session_pct']):.2f}% |
| Converting sessions / session CVR | {int(f(k['converting_sessions'])):,} / **{f(k['session_cvr_pct']):.3f}%** |
| Purchasers / user CVR | {int(f(k['purchasers'])):,} / {f(k['user_cvr_pct']):.3f}% |
| Transactions / revenue | {int(f(k['transactions'])):,} / **{usd(k['revenue_usd'])}** |
| AOV / revenue per session / revenue per user | ${f(k['aov_usd']):.2f} / ${f(k['revenue_per_session_usd']):.3f} / ${f(k['revenue_per_user_usd']):.3f} |
| Cart abandonment (cart sessions without purchase) | {f(k['cart_abandonment_pct']):.2f}% of {int(f(k['cart_sessions'])):,} cart sessions |
| Checkout abandonment (checkout sessions without purchase) | {f(k['checkout_abandonment_pct']):.2f}% |

## Insights
1. **The biggest leak is before the cart.** Only **{f(fs['1 view_item']['pct_of_sessions']):.1f}%** of sessions view a product and only {f(fs['2 add_to_cart']['pct_of_previous_step']):.1f}% of those add to cart, so {f(fs['2 add_to_cart']['pct_of_sessions']):.2f}% of sessions ever have a cart. Once a cart exists the funnel is much tighter: {f(fs['3 begin_checkout']['pct_of_previous_step']):.1f}% begin checkout, {f(fs['5 add_payment_info']['pct_of_previous_step']):.1f}% of shipping-info sessions reach payment and {f(fs['6 purchase']['pct_of_previous_step']):.1f}% of payment sessions buy. End to end, **{f(k['session_cvr_pct']):.2f}%** of sessions convert, with **{f(k['cart_abandonment_pct']):.1f}% cart abandonment** and {f(k['checkout_abandonment_pct']):.1f}% checkout abandonment. Product discovery (home and category pages to product pages) is the lever with the most volume.
2. **Revenue is concentrated in the shopping season.** December 1-23 earned **{usd(se['December pre-Christmas']['revenue_per_day_usd'])} per day** at a {f(se['December pre-Christmas']['cvr_pct']):.2f}% CVR, and Black Friday to Cyber Monday (27-30 Nov) {usd(se['Black Friday-Cyber Monday']['revenue_per_day_usd'])} per day at {f(se['Black Friday-Cyber Monday']['cvr_pct']):.2f}% with the highest AOV (${f(se['Black Friday-Cyber Monday']['aov_usd']):.2f}). Regular days averaged {usd(se['Regular']['revenue_per_day_usd'])} and Christmas to New Year only {usd(se['Christmas-New Year']['revenue_per_day_usd'])}. The best day was **Cyber Monday {top[0]['date']} ({usd(top[0]['revenue_usd'])}, {top[0]['transactions']} transactions)**, and {len(dec_top)} of the top 10 days fall in {int(dec_top[0][8:])}-{int(dec_top[-1][8:])} December. By month: Nov {usd(mo['2020-11']['revenue_usd'])}, Dec {usd(mo['2020-12']['revenue_usd'])}, Jan {usd(mo['2021-01']['revenue_usd'])} (CVR {f(mo['2021-01']['cvr_pct']):.2f}%, half of December's {f(mo['2020-12']['cvr_pct']):.2f}%).
3. **Returning visitors are the money.** Returning sessions are {f(nr['returning']['pct_sessions']):.1f}% of traffic but **{f(nr['returning']['pct_revenue']):.1f}% of revenue**, convert at **{f(nr['returning']['cvr_pct']):.2f}%** vs {f(nr['new']['cvr_pct']):.2f}% for new users (x{f(nr['returning']['cvr_pct']) / f(nr['new']['cvr_pct']):.1f}) and spend more per order (${f(nr['returning']['aov_usd']):.2f} vs ${f(nr['new']['aov_usd']):.2f}). Buying sessions are long: the {f(d21['pct_sessions']):.1f}% of sessions with 21+ page views convert at {f(d21['cvr_pct']):.1f}% and bring **{f(d21['pct_revenue']):.1f}% of revenue**; sessions with 1-3 page views ({f(pd['1']['pct_sessions']) + f(pd['2-3']['pct_sessions']):.1f}% of traffic) never convert.
4. **Channels: organic brings the volume, referrals convert.** First-touch Organic Search is the largest channel ({f(cg['Organic Search']['pct_sessions']):.1f}% of sessions, {f(cg['Organic Search']['pct_revenue']):.1f}% of revenue, CVR {f(cg['Organic Search']['cvr_pct']):.2f}%), then Direct ({f(cg['Direct']['pct_sessions']):.1f}% / {f(cg['Direct']['pct_revenue']):.1f}%). Paid Search is {f(cg['Paid Search']['pct_sessions']):.1f}% of sessions with the lowest CVR ({f(cg['Paid Search']['cvr_pct']):.2f}%) and AOV (${f(cg['Paid Search']['aov_usd']):.2f}). On the session-scoped source/medium, Referral sessions convert at **{f(sc['Referral']['cvr_pct']):.2f}%** (${f(sc['Referral']['revenue_per_session_usd']):.2f} per session) and the tiny Email channel at {f(sc['Email']['cvr_pct']):.1f}% ({int(f(sc['Email']['sessions']))} sessions). {f(sc['(not set)']['pct_sessions']):.1f}% of sessions carry no session source at all and almost never buy ({int(f(sc['(not set)']['converting_sessions']))} conversion), and self-referrals from the store's own domains are {f(sc['Self-referral']['pct_sessions']):.1f}% of sessions but {f(sc['Self-referral']['pct_revenue']):.1f}% of revenue, a sign of cross-domain checkout returns that a production GA4 setup would exclude.
5. **Device, country and weekday matter less than you might expect.** Desktop has {f(dv['desktop']['pct_sessions']):.1f}% of sessions and {f(dv['desktop']['pct_revenue']):.1f}% of revenue, mobile {f(dv['mobile']['pct_sessions']):.1f}% and {f(dv['mobile']['pct_revenue']):.1f}%. Mobile converts no worse (CVR {f(dv['mobile']['cvr_pct']):.2f}% vs {f(dv['desktop']['cvr_pct']):.2f}%; cart-to-purchase {f(dv['mobile']['cart_to_purchase_pct']):.1f}% vs {f(dv['desktop']['cart_to_purchase_pct']):.1f}%). The US is {f(ct['United States']['pct_sessions']):.1f}% of sessions and {f(ct['United States']['pct_revenue']):.1f}% of revenue, followed by India ({f(ct['India']['pct_sessions']):.1f}%) and Canada ({f(ct['Canada']['pct_sessions']):.1f}%, highest AOV of the top 3 at ${f(ct['Canada']['aov_usd']):.2f}). Weekdays carry the traffic: Tuesday averages {f(wd['Tue']['sessions_per_day']):,.0f} sessions per day vs {f(wd['Sun']['sessions_per_day']):,.0f} on Sunday, and Sunday also converts worst ({f(wd['Sun']['cvr_pct']):.2f}%). These dimensions are fairly flat (engagement is about 89% in every device and top country), partly because Google obfuscated the sample.
6. **Landing pages.** Sessions that land on **Home** ({int(f(lpg['Home']['sessions'])):,}) convert at {f(lpg['Home']['cvr_pct']):.2f}% and bring {100 * f(lpg['Home']['revenue_usd']) / rev:.1f}% of revenue. Product and brand landings such as Google Dino Game Tee ({int(f(lpg['Google Dino Game Tee']['sessions'])):,} sessions, CVR {f(lpg['Google Dino Game Tee']['cvr_pct']):.2f}%) and YouTube Shop by Brand ({f(lpg['YouTube | Shop by Brand | Google Merchandise Store']['cvr_pct']):.2f}%) attract browsers rather than buyers, and {int(f(lpg['Page Unavailable']['sessions'])):,} sessions landed on "Page Unavailable".

## Funnel (open = fired the step event; strict = also fired every earlier step)
{table(fun, ['step', 'sessions', 'pct_of_sessions', 'pct_of_previous_step', 'drop_off_pct', 'strict_sessions', 'strict_pct_of_sessions'])}

{int(f(isd['converting sessions without add_to_cart event (obfuscation)'])):,} of {int(f(k['converting_sessions'])):,} converting sessions have no `add_to_cart` event, so the strict funnel ends at {int(f(fs['6 purchase']['strict_sessions'])):,} purchases. This is an artefact of the obfuscated sample. The open funnel is the headline view.

![Funnel](images/funnel.png)
![Open vs strict funnel](images/funnel_strict.png)
![Funnel by device](images/funnel_device.png)

## Acquisition channels (first touch)
{table(ch, ['channel_group', 'sessions', 'pct_sessions', 'users', 'engagement_rate_pct', 'bounce_rate_pct', 'add_to_cart_rate_pct', 'cvr_pct', 'transactions', 'revenue_usd', 'pct_revenue', 'aov_usd', 'revenue_per_session_usd'])}

`Obfuscated (<Other>)` and `(data deleted)` are the placeholders Google used when it obfuscated the sample. They are kept as their own values, not guessed.

![Channel CVR](images/channel_cvr.png)
![Channel mix](images/channel_mix.png)

## Session source / medium (session-scoped event params)
{table(sch, ['session_channel', 'sessions', 'pct_sessions', 'engagement_rate_pct', 'bounce_rate_pct', 'add_to_cart_rate_pct', 'converting_sessions', 'cvr_pct', 'revenue_usd', 'pct_revenue', 'revenue_per_session_usd'])}

![Session channel](images/session_channel.png)

## Devices
{table(dev, ['device_category', 'sessions', 'pct_sessions', 'users', 'engagement_rate_pct', 'bounce_rate_pct', 'pageviews_per_session', 'avg_engagement_time_s', 'add_to_cart_rate_pct', 'cart_to_purchase_pct', 'cvr_pct', 'transactions', 'revenue_usd', 'pct_revenue', 'aov_usd'])}

Operating system:

{table(osr, ['device_os', 'sessions', 'engagement_rate_pct', 'cvr_pct', 'revenue_usd', 'aov_usd'])}

![Device mix](images/device_mix.png)

## Time: months, seasons, days, hours
{table(mon, ['year_month', 'days', 'sessions', 'users', 'engagement_rate_pct', 'cvr_pct', 'transactions', 'revenue_usd', 'aov_usd'])}

{table(seas, ['season', 'days', 'sessions', 'sessions_per_day', 'cvr_pct', 'transactions', 'revenue_usd', 'revenue_per_day_usd', 'aov_usd'])}

Top 10 revenue days:

{table(top, ['rnk', 'date', 'day_name', 'season', 'sessions', 'cvr_pct', 'transactions', 'revenue_usd'])}

By weekday (average per calendar day):

{table(wk, ['day_name', 'days', 'sessions_per_day', 'engagement_rate_pct', 'cvr_pct', 'revenue_per_day_usd'])}

Sessions peak at {peak_h}:00 UTC and are lowest at {low_h}:00 UTC. The last week of January (25-31 Jan) has {late_sess:,} sessions but only {late_tx} transactions, and 31 Jan has none. Traffic stays normal, so this looks like purchase tracking tailing off at the end of the sample, not a real collapse in demand.

![Daily revenue](images/daily_revenue.png)
![Daily sessions](images/daily_sessions.png)
![Season](images/season.png)
![Weekday x hour](images/dow_hour.png)

## Countries (top 15 by sessions)
{table(ctry, ['rnk', 'country', 'sessions', 'pct_sessions', 'engagement_rate_pct', 'converting_sessions', 'cvr_pct', 'transactions', 'revenue_usd', 'pct_revenue', 'aov_usd'])}

![Countries](images/country.png)

## Landing pages (top 12 by sessions)
{table(lp, ['rnk', 'landing_page', 'sessions', 'bounce_rate_pct', 'add_to_cart_rate_pct', 'cvr_pct', 'revenue_usd'])}

`(no page_view)` = sessions whose events contain no `page_view` (for example only `session_start` / `first_visit` / `user_engagement`). They are {f(lpg['(no page_view)']['bounce_rate_pct']):.1f}% bounces.

![Landing pages](images/landing_page.png)

## New vs returning, and engagement depth
{table(sorted(nr.values(), key=lambda r: r['user_type']), ['user_type', 'sessions', 'pct_sessions', 'engagement_rate_pct', 'pageviews_per_session', 'add_to_cart_rate_pct', 'cvr_pct', 'transactions', 'revenue_usd', 'pct_revenue', 'aov_usd'])}

{table(pdp, ['page_views_band', 'sessions', 'pct_sessions', 'engagement_rate_pct', 'cvr_pct', 'revenue_usd', 'pct_revenue'])}

New-user sessions show {f(nr['new']['engagement_rate_pct']):.2f}% engagement against {f(nr['returning']['engagement_rate_pct']):.2f}% for returning ones. That gap reflects how `session_engaged` is populated in this sample. Read bounce by user type with care.

![New vs returning](images/new_returning.png)
![Page depth](images/page_depth.png)

## Order values
{table(ov, ['order_value_band', 'transactions', 'pct_transactions', 'revenue_usd', 'pct_revenue', 'avg_items'])}

Mean ${f(ost['mean_usd']):.2f}, median ${f(ost['median_usd']):.2f}, p90 ${f(ost['p90_usd']):.2f}, max ${f(ost['max_usd']):,.0f}; {int(f(ost['outlier_orders']))} orders above Q3 + 3 IQR are flagged (kept) and carry {f(ost['outlier_pct_revenue']):.1f}% of revenue. Collapsing repeated purchase events of the same transaction removed {usd(ost['duplicate_revenue_removed_usd'])} of double-counted revenue ({usd(ost['purchase_event_revenue_usd'])} summed over raw purchase events → {usd(k['revenue_usd'])}).

![Order values](images/order_value.png)

## Data quality (before → after)
{table(rc, ['entity', 'raw_rows', 'distinct_keys', 'clean_rows', 'grain'])}

Issue counts:

{table(iss, ['check_name', 'affected_rows'])}

Null / placeholder rates:

{table(rd('dq_null_rates'), ['entity', 'column_name', 'null_pct', 'treatment'])}

Assertions ({npass}/{len(asr)} PASS):

{table(asr, ['check_name', 'failed_rows', 'status'])}

![Data quality](images/data_quality.png)

## How the images were made
`scripts/make_charts.py` draws every chart from the CSVs in `results/tables/`, which are the DuckDB query results of `sql/04_analysis.sql` and `sql/05_quality_checks.sql`. Each one is a plain-vector SVG (only rect, line, polyline, circle and text, written by the small custom writer `scripts/svgcharts.py`, no plotting library). `scripts/render_png.py` then rasterises each SVG to PNG at 2x with headless Google Chrome. `images/dashboard.svg` tiles seven KPI cards and six panels into one page. All {len(list((RES / 'images').glob('*.svg')))} charts are in `images/` as both `.svg` and `.png`.
"""
(RES / "RESULTS.md").write_text(md)
print("wrote", (RES / "RESULTS.md").relative_to(ROOT), len(md), "chars")
