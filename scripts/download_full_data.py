#!/usr/bin/env python3
"""Download the full GA4 Google Merchandise Store event export into data/raw_full/ and verify SHA-256.

Dataset: Google Analytics 4 obfuscated sample e-commerce data of the Google Merchandise Store
  BigQuery: bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*  (92 daily tables, 2020-11-01..2021-01-31, 4,295,584 events)
  Docs:     https://developers.google.com/analytics/bigquery/web-ecommerce-demo-dataset
Mirror (used here, no Google Cloud account needed): Hugging Face gizdevans/ga4-bq-flattened-data, pinned to commit
  29f8ceef9152ff23b9c5446f40c1fb7c059f34d5. One CSV row per event, 60 columns (event_params / device / geo / traffic_source /
  ecommerce flattened; the items[] arrays removed), flattening SQL in https://github.com/dgizdevans/ga4-bq-flatten (MIT).
  full_flatten_data.csv  1,844,623,697 B (1.84 GB), SHA-256 f09b13d6d59f8fd72ef07095eb95085388fa873129961eb116fc0d20dc1e9012
Kaggle copies of the same BigQuery source (subsets): kaggle.com/datasets/pdaasha/ga4-obfuscated-sample-ecommerce-jan2021 (January 2021)
  and kaggle.com/datasets/mexwell/google-merchandise-sales-data (curated events/items/users subset).
"""
import hashlib, pathlib, shutil, sys, urllib.request

REV = "29f8ceef9152ff23b9c5446f40c1fb7c059f34d5"
FILES = {
    "full_flatten_data.csv": (f"https://huggingface.co/datasets/gizdevans/ga4-bq-flattened-data/resolve/{REV}/full_flatten_data.csv",
                              "f09b13d6d59f8fd72ef07095eb95085388fa873129961eb116fc0d20dc1e9012", 1844623697),
}
out = pathlib.Path(__file__).resolve().parents[1] / "data" / "raw_full"
out.mkdir(parents=True, exist_ok=True)
bad = 0
for name, (url, sha, size) in FILES.items():
    p = out / name
    if not p.exists() or p.stat().st_size != size:
        print("downloading", url, f"({size / 1e9:.2f} GB)")
        tmp = p.with_suffix(".part")
        with urllib.request.urlopen(url, timeout=120) as r, open(tmp, "wb") as fo:
            shutil.copyfileobj(r, fo, length=1 << 22)
        tmp.replace(p)
    h = hashlib.sha256()
    with open(p, "rb") as fi:
        for chunk in iter(lambda: fi.read(1 << 24), b""):
            h.update(chunk)
    got = h.hexdigest()
    print(f"{name:26s} {p.stat().st_size:>15,} bytes  {'OK' if got == sha else 'CHECKSUM MISMATCH ' + got}")
    bad += got != sha
sys.exit(1 if bad else 0)
