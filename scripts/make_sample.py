#!/usr/bin/env python3
"""Build the git-sized raw sample data/raw/full_flatten_data.csv from data/raw_full/ (deterministic, no randomness).

Rule: all events of (a) every 1000th user_pseudo_id in sorted order (1st, 1001st, ...) and (b) every 80th user, in sorted order,
among users with at least one purchase event with revenue > 0 (so the sample contains real transactions), plus every repeated
header line found inside the export (so the cleaning step that drops them is exercised). Rows are parsed and re-written with
Python's csv module in their original order (same 60 columns, same header)."""
import csv, pathlib, sys
import duckdb

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC, OUT = ROOT / "data/raw_full/full_flatten_data.csv", ROOT / "data/raw/full_flatten_data.csv"
OUT.parent.mkdir(parents=True, exist_ok=True)
csv.field_size_limit(sys.maxsize)

con = duckdb.connect()
con.execute(f"CREATE TABLE u AS SELECT user_pseudo_id, MAX(CASE WHEN event_name = 'purchase' AND TRY_CAST(ecom_revenue_usd AS DOUBLE) > 0 "
            f"THEN 1 ELSE 0 END) AS buyer FROM read_csv('{SRC.as_posix()}', header = true, all_varchar = true, quote = '\"', escape = '\"') "
            f"WHERE event_name <> 'event_name' GROUP BY 1")
every = [r[0] for r in con.execute("SELECT user_pseudo_id FROM (SELECT user_pseudo_id, ROW_NUMBER() OVER (ORDER BY user_pseudo_id) - 1 AS i "
                                   "FROM u) WHERE i % 1000 = 0").fetchall()]
buyers = [r[0] for r in con.execute("SELECT user_pseudo_id FROM (SELECT user_pseudo_id, ROW_NUMBER() OVER (ORDER BY user_pseudo_id) - 1 AS i "
                                    "FROM u WHERE buyer = 1) WHERE i % 80 = 0").fetchall()]
keep = set(every) | set(buyers)
n_in = n_out = n_hdr = 0
with open(SRC, newline="", encoding="utf-8") as fi, open(OUT, "w", newline="", encoding="utf-8") as fo:
    r, w = csv.reader(fi), csv.writer(fo, lineterminator="\n")
    header = next(r)
    w.writerow(header)
    ui, ei = header.index("user_pseudo_id"), header.index("event_name")
    for row in r:
        n_in += 1
        if row[ei] == "event_name":
            w.writerow(row); n_hdr += 1; n_out += 1
        elif row[ui] in keep:
            w.writerow(row); n_out += 1
print(f"users kept: {len(keep)} ({len(every)} every-1000th + {len(buyers)} every-80th buyers, overlap {len(set(every) & set(buyers))}); "
      f"rows {n_out:,} of {n_in:,} (incl. {n_hdr} repeated header lines); {OUT.stat().st_size:,} B")
