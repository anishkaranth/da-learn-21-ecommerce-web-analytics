#!/usr/bin/env python3
"""Render SVG charts (pure vector shapes, no raster) from the KPI tables exported by run_pipeline.py."""
import csv, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import svgcharts as S

BLUE, ORANGE, GREEN, SAND, NAVY, BROWN, PURPLE, ROSE = S.PALETTE[:8]
STEP = {"0 session": "All sessions", "1 view_item": "Viewed an item", "2 add_to_cart": "Added to cart", "3 begin_checkout": "Began checkout",
        "4 add_shipping_info": "Added shipping info", "5 add_payment_info": "Added payment info", "6 purchase": "Purchased"}
DQ_SHORT = {"sessions with 2+ different session mediums (first one used)": "sessions with 2+ session mediums",
            "users whose first-touch medium differs between events (obfuscation)": "users with 2+ first-touch mediums",
            "ga_session_id values shared by 2+ users (key = user + session id)": "ga_session_id shared by 2+ users",
            "sessions without a session_start event (kept)": "sessions w/o session_start",
            "converting sessions without add_to_cart event (obfuscation)": "purchase sessions w/o add_to_cart",
            "purchase events with revenue 0 / NULL (not transactions)": "zero-revenue purchase events",
            "transactions with missing / (not set) transaction id (kept)": "transactions w/o transaction id",
            "purchase events collapsed as repeats of the same transaction": "repeat purchase events collapsed",
            "transactions flagged revenue outlier (> Q3 + 3 IQR, kept)": "revenue outliers (> Q3 + 3 IQR)",
            "raw: repeated header lines inside the export (dropped)": "repeated header lines dropped",
            "sessions spanning > 4 h (flagged, kept)": "sessions spanning > 4 h",
            "transaction ids reused across sessions (obfuscation; kept separate)": "transaction ids reused across sessions",
            "events with engagement_time > 1 h (flagged, kept)": "events with engagement > 1 h"}
DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


def rd(t, name):
    with open(pathlib.Path(t) / f"{name}.csv", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def f(x):
    return float(x) if x not in ("", None) else 0.0


def usd(v):
    return f"${f(v):,.0f}"


def panels(t):
    k = rd(t, "a_kpi_headline")[0]
    fun = sorted(rd(t, "a_funnel"), key=lambda r: int(r["step_no"]))
    fdev = rd(t, "a_funnel_device")
    ch = sorted(rd(t, "a_channel"), key=lambda r: -f(r["sessions"]))
    sch = sorted(rd(t, "a_session_channel"), key=lambda r: -f(r["revenue_per_session_usd"]))
    dev = sorted(rd(t, "a_device"), key=lambda r: -f(r["sessions"]))
    day = sorted(rd(t, "a_daily"), key=lambda r: r["date"])
    seas = {r["season"]: r for r in rd(t, "a_season")}
    dh = rd(t, "a_dow_hour")
    ctry = sorted(rd(t, "a_country"), key=lambda r: int(r["rnk"]))
    lp = sorted(rd(t, "a_landing_page"), key=lambda r: int(r["rnk"]))
    nr = sorted(rd(t, "a_new_returning"), key=lambda r: r["user_type"])
    pdp = sorted(rd(t, "a_page_depth"), key=lambda r: int(r["band_min"]))
    ov = sorted(rd(t, "a_order_value"), key=lambda r: r["order_value_band"])
    ost = rd(t, "a_order_stats")[0]
    dq = sorted([r for r in rd(t, "dq_issues") if f(r["affected_rows"]) > 0], key=lambda r: -f(r["affected_rows"]))
    top = sorted(rd(t, "a_top_days"), key=lambda r: int(r["rnk"]))

    devices = [r["device_category"] for r in dev]
    steps = [s for s in STEP if s != "0 session"]
    fd = {(r["device_category"], r["step"]): f(r["pct_of_device_sessions"]) for r in fdev}
    hours = [str(h) for h in range(24)]
    dhm = {(r["day_name"], int(r["start_hour_utc"])): r for r in dh}
    heat = [[f(dhm[(d, h)]["sessions"]) if (d, h) in dhm else None for h in range(24)] for d in DAYS]
    season_order = [s for s in ["Regular", "Black Friday-Cyber Monday", "December pre-Christmas", "Christmas-New Year"] if s in seas]
    ps = [
        ("funnel", S.hbar("Checkout funnel: sessions reaching each step (open funnel)", [STEP[r["step"]] for r in fun],
                          [f(r["sessions"]) for r in fun], "{:,.0f}",
                          f"{int(f(k['sessions'])):,} sessions, Nov 2020 - Jan 2021; label = % of all sessions / % of previous step",
                          notes=[f"({f(r['pct_of_sessions']):.2f}%" + (f" / {f(r['pct_of_previous_step']):.1f}%)" if r["pct_of_previous_step"] else ")")
                                 for r in fun], color=[BLUE, BLUE, GREEN, GREEN, GREEN, GREEN, ORANGE], w=760,
                          vmax=f(fun[0]["sessions"]) * 1.25)),
        ("funnel_strict", S.grouped_vbar("Open vs strict funnel (% of all sessions)", [STEP[s].replace("Added ", "").replace("Began ", "")
                                         for s in steps], [("open: fired the step", [f(r["pct_of_sessions"]) for r in fun[1:]]),
                                                            ("strict: fired every earlier step too", [f(r["strict_pct_of_sessions"]) for r in fun[1:]])],
                                         "{:.2f}", f"{int(f(fun[6]['sessions'])) - int(f(fun[6]['strict_sessions'])):,} of {int(f(fun[6]['sessions'])):,} "
                                         "purchasing sessions skip an earlier step event (GA4 sample obfuscation)", w=760, ylabel="% of sessions")),
        ("funnel_device", S.grouped_vbar("Funnel by device: % of the device's sessions reaching each step",
                                         [STEP[s].replace("Added ", "").replace("Began ", "").replace("Viewed an ", "view ") for s in steps],
                                         [(d, [fd.get((d, s), 0) for s in steps]) for d in devices], "{:.1f}",
                                         " / ".join(f"{r['device_category']} CVR {f(r['cvr_pct']):.2f}%" for r in dev), w=760, ylabel="% of sessions")),
        ("channel_cvr", S.hbar("Session conversion rate by first-touch channel", [r["channel_group"] for r in sorted(ch, key=lambda r: -f(r["cvr_pct"]))],
                               [f(r["cvr_pct"]) for r in sorted(ch, key=lambda r: -f(r["cvr_pct"]))], "{:.2f}%",
                               f"site average {f(k['session_cvr_pct']):.2f}%; label = sessions, revenue",
                               notes=[f"({int(f(r['sessions'])):,} sess, {usd(r['revenue_usd'])})" for r in sorted(ch, key=lambda r: -f(r["cvr_pct"]))],
                               color=BLUE, w=760, vmax=max(f(r["cvr_pct"]) for r in ch) * 1.5)),
        ("channel_mix", S.grouped_vbar("Share of sessions vs share of revenue by first-touch channel",
                                       [r["channel_group"].replace("Obfuscated (<Other>)", "<Other>").replace("(data deleted)", "data deleted")
                                        for r in ch], [("% of sessions", [f(r["pct_sessions"]) for r in ch]),
                                                       ("% of revenue", [f(r["pct_revenue"]) for r in ch])], "{:.1f}",
                                       "first-touch = traffic_source of the user's first visit (GA4 export)", w=760, ylabel="%")),
        ("session_channel", S.hbar("Revenue per session by session source / medium", [r["session_channel"] for r in sch],
                                   [f(r["revenue_per_session_usd"]) for r in sch], "${:.2f}",
                                   "session-scoped source/medium event params; label = sessions, CVR",
                                   notes=[f"({int(f(r['sessions'])):,} sess, CVR {f(r['cvr_pct']):.2f}%)" for r in sch],
                                   color=PURPLE, w=760, vmax=max(f(r["revenue_per_session_usd"]) for r in sch) * 1.45)),
        ("device_mix", S.grouped_vbar("Device: share of sessions vs share of revenue", devices,
                                      [("% of sessions", [f(r["pct_sessions"]) for r in dev]), ("% of revenue", [f(r["pct_revenue"]) for r in dev]),
                                       ("engagement rate %", [f(r["engagement_rate_pct"]) for r in dev])], "{:.1f}",
                                      " / ".join(f"{r['device_category']}: CVR {f(r['cvr_pct']):.2f}%, AOV {usd(r['aov_usd'])}" for r in dev),
                                      w=760, ylabel="%")),
        ("daily_revenue", S.line("Daily revenue (US$), 1 Nov 2020 - 31 Jan 2021", [r["date"][5:] for r in day],
                                 [("revenue", [f(r["revenue_usd"]) for r in day])], "${:,.0f}",
                                 f"peak {top[0]['date']} ({top[0]['day_name']}{', Cyber Monday' if top[0]['date'] == '2020-11-30' else ''}) {usd(top[0]['revenue_usd'])}; "
                                 f"Dec 1-23 avg {usd(seas['December pre-Christmas']['revenue_per_day_usd'])}/day vs "
                                 f"{usd(seas['Christmas-New Year']['revenue_per_day_usd'])}/day Dec 24-Jan 1", w=760, every=7, ylabel="US$ per day")),
        ("daily_sessions", S.line("Daily sessions and converting sessions x 50", [r["date"][5:] for r in day],
                                  [("sessions", [f(r["sessions"]) for r in day]), ("converting sessions x 50", [f(r["converting_sessions"]) * 50 for r in day])],
                                  "{:,.0f}", "converting sessions scaled x50 to share the axis", w=760, every=7)),
        ("season", S.vbar("Revenue per day by shopping season", season_order, [f(seas[s]["revenue_per_day_usd"]) for s in season_order], "${:,.0f}",
                          "label above bar: days, session CVR", notes=[f"{seas[s]['days']} days, CVR {f(seas[s]['cvr_pct']):.2f}%" for s in season_order],
                          color=[BLUE, ORANGE, GREEN, SAND], w=760, ylabel="US$ per day")),
        ("dow_hour", S.heatmap("Sessions by weekday and start hour (UTC)", DAYS, hours, heat, "{:.0f}",
                               "92 days; darker = more sessions; US daytime = 14-02 UTC", w=860, cell_text=False, xlabel="hour of day, UTC")),
        ("country", S.hbar("Top 15 countries by sessions", [r["country"] for r in ctry if r["country"] != "All other countries"],
                           [f(r["sessions"]) for r in ctry if r["country"] != "All other countries"], "{:,.0f}",
                           f"{int(f(k['countries']))} countries; label = CVR, revenue",
                           notes=[f"(CVR {f(r['cvr_pct']):.2f}%, {usd(r['revenue_usd'])})" for r in ctry if r["country"] != "All other countries"],
                           color=NAVY, w=760, vmax=max(f(r["sessions"]) for r in ctry) * 1.35)),
        ("new_returning", S.grouped_vbar("New vs returning sessions", [r["user_type"] for r in nr],
                                         [("% of sessions", [f(r["pct_sessions"]) for r in nr]), ("% of revenue", [f(r["pct_revenue"]) for r in nr]),
                                          ("add-to-cart rate %", [f(r["add_to_cart_rate_pct"]) for r in nr]), ("CVR % x10", [f(r["cvr_pct"]) * 10 for r in nr])],
                                         "{:.1f}", " / ".join(f"{r['user_type']}: CVR {f(r['cvr_pct']):.2f}%, AOV {usd(r['aov_usd'])}" for r in nr),
                                         w=760, ylabel="%")),
        ("page_depth", S.vbar("Conversion rate by page views in the session", [r["page_views_band"] for r in pdp], [f(r["cvr_pct"]) for r in pdp],
                              "{:.2f}%", "label above bar: % of sessions / % of revenue",
                              notes=[f"{f(r['pct_sessions']):.1f}% / {f(r['pct_revenue']):.1f}%" for r in pdp], color=GREEN, w=760,
                              ylabel="session CVR %", vmax=max(f(r["cvr_pct"]) for r in pdp) * 1.25)),
        ("order_value", S.grouped_vbar("Order value bands: share of transactions vs share of revenue", [r["order_value_band"][3:] for r in ov],
                                       [("% of transactions", [f(r["pct_transactions"]) for r in ov]), ("% of revenue", [f(r["pct_revenue"]) for r in ov])],
                                       "{:.1f}", f"{int(f(ost['transactions'])):,} transactions; mean {usd(ost['mean_usd'])}, median {usd(ost['median_usd'])}, "
                                       f"p90 {usd(ost['p90_usd'])}, max {usd(ost['max_usd'])}", w=760, ylabel="%")),
        ("landing_page", S.hbar("Top 12 landing pages: session conversion rate", [r["landing_page"].replace(" | Google Merchandise Store", "")[:40] for r in lp],
                                [f(r["cvr_pct"]) for r in lp], "{:.2f}%", "landing page = title of the session's first page_view; label = sessions, bounce rate",
                                notes=[f"({int(f(r['sessions'])):,} sess, bounce {f(r['bounce_rate_pct']):.1f}%)" for r in lp], color=ROSE, w=760,
                                vmax=max(f(r["cvr_pct"]) for r in lp) * 1.6)),
        ("data_quality", S.hbar("Data-quality findings (rows / sessions / ids affected, all kept or fixed)", [DQ_SHORT.get(r["check_name"], r["check_name"][:38]) for r in dq],
                                [f(r["affected_rows"]) for r in dq], "{:,.0f}",
                                f"{int(f(k['events'])):,} clean events, {int(f(k['sessions'])):,} sessions, {int(f(k['transactions'])):,} transactions",
                                color=SAND, w=860, vmax=max(f(r["affected_rows"]) for r in dq) * 1.2)),
    ]
    return ps, k


def make_all(tables, out):
    out = pathlib.Path(out); out.mkdir(parents=True, exist_ok=True)
    ps, k = panels(tables)
    for name, p in ps:
        S.save(p, out / f"{name}.svg")
    cards = [("Sessions / users", f"{int(f(k['sessions'])):,} / {int(f(k['users'])):,}"),
             ("Engagement / bounce", f"{f(k['engagement_rate_pct']):.1f}% / {f(k['bounce_rate_pct']):.1f}%"),
             ("Session conversion", f"{f(k['session_cvr_pct']):.2f}%"),
             ("Transactions", f"{int(f(k['transactions'])):,}"),
             ("Revenue", usd(k["revenue_usd"])),
             ("Avg order value", f"${f(k['aov_usd']):.2f}"),
             ("Cart abandonment", f"{f(k['cart_abandonment_pct']):.1f}%")]
    order = ["funnel", "channel_cvr", "daily_revenue", "funnel_device", "new_returning", "page_depth"]
    tag = " - SAMPLE" if "sample" in out.parts else ""
    S.dashboard(out / "dashboard.svg", f"Google Merchandise Store web analytics, GA4 sample ({k['first_date']} to {k['last_date']}){tag}",
                f"Rendered from {'results/sample/tables (committed raw sample' if tag else 'results/tables (SQL on DuckDB, full data'}: "
                f"{int(f(k['events'])):,} events, {int(f(k['sessions'])):,} sessions). Session = user_pseudo_id + ga_session_id; "
                "bounce = not engaged (GA4); conversion = session with a purchase (revenue > 0).",
                cards, [dict(ps)[n] for n in order], cols=2)
    print("charts ->", out, sorted(p.name for p in out.glob("*.svg")))


if __name__ == "__main__":
    root = pathlib.Path(__file__).resolve().parents[1]
    make_all(root / "results/tables", root / "results/images")
