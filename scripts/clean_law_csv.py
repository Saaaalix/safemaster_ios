#!/usr/bin/env python3
"""
Clean parsed law CSV for retrieval usage.

Input: rows from build_law_csv.py
Output:
  - laws_clean.csv
  - laws_clean_removed.csv (removed rows + reason)

Usage:
  python3 scripts/clean_law_csv.py \
    --input-csv "/Users/mu/Desktop/安全大师/scripts/laws_raw_v2.csv" \
    --output-csv "/Users/mu/Desktop/安全大师/scripts/laws_clean.csv" \
    --removed-csv "/Users/mu/Desktop/安全大师/scripts/laws_clean_removed.csv"
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import re
from pathlib import Path
from typing import Dict, List, Tuple


TEXT_NOISE_PATTERNS = [
    re.compile(r"^目\s*录$"),
    re.compile(r"^前\s*言$"),
    re.compile(r"^附\s*录\s*目录$"),
    re.compile(r"^\.{2,}$"),
    re.compile(r"^\d+(?:\.\d+){0,4}\s*$"),
]

ARTICLE_NO_NOISE_PATTERNS = [
    re.compile(r"^\d+(?:\.\d+){0,4}$"),
    re.compile(r"^第\s*[一二三四五六七八九十百千万零〇0-9]+\s*条$"),
]

CSV_HEADERS = [
    "law_id",
    "law_name",
    "version",
    "chapter",
    "article_no",
    "article_title",
    "article_text",
    "keywords",
    "scene_tags",
    "priority",
    "is_mandatory",
    "status",
    "source_file",
    "notes",
]

REMOVED_HEADERS = CSV_HEADERS + ["remove_reason"]


def norm(s: str) -> str:
    if s is None:
        return ""
    s = s.replace("\u3000", " ").replace("\xa0", " ").replace("．", ".")
    s = re.sub(r"\s+", " ", s).strip()
    return s


def looks_like_noise_text(text: str) -> bool:
    t = norm(text)
    if not t:
        return True
    if len(t) <= 3:
        return True
    for p in TEXT_NOISE_PATTERNS:
        if p.match(t):
            return True
    return False


def looks_like_valid_article_no(article_no: str) -> bool:
    a = norm(article_no)
    if not a:
        return False
    return bool(
        re.match(r"^第\s*[一二三四五六七八九十百千万零〇0-9]+\s*条", a)
        or re.match(r"^\d+(?:\.\d+){1,4}$", a)
    )


def text_signature(row: Dict[str, str]) -> str:
    # Signature for dedup: same source/law/article_no + normalized article_text
    key = "|".join(
        [
            norm(row.get("source_file", "")),
            norm(row.get("law_name", "")),
            norm(row.get("article_no", "")),
            norm(row.get("article_text", "")),
        ]
    )
    return hashlib.md5(key.encode("utf-8")).hexdigest()


def clean_rows(rows: List[Dict[str, str]], min_text_len: int) -> Tuple[List[Dict[str, str]], List[Dict[str, str]]]:
    cleaned: List[Dict[str, str]] = []
    removed: List[Dict[str, str]] = []
    seen_sig = set()

    for row in rows:
        # normalize fields
        for k in CSV_HEADERS:
            if k in row:
                row[k] = norm(row[k])
            else:
                row[k] = ""

        text = row["article_text"]
        article_no = row["article_no"]

        # 1) must have valid-ish article number
        if not looks_like_valid_article_no(article_no):
            bad = dict(row)
            bad["remove_reason"] = "invalid_article_no"
            removed.append(bad)
            continue

        # 2) drop obvious noisy text
        if looks_like_noise_text(text):
            bad = dict(row)
            bad["remove_reason"] = "noise_or_empty_text"
            removed.append(bad)
            continue

        # 3) short text filter
        if len(text) < min_text_len:
            bad = dict(row)
            bad["remove_reason"] = f"too_short_lt_{min_text_len}"
            removed.append(bad)
            continue

        # 4) remove rows whose text is mostly punctuation/leader dots
        punct_ratio = len(re.sub(r"[\u4e00-\u9fffA-Za-z0-9]", "", text)) / max(len(text), 1)
        if punct_ratio > 0.65:
            bad = dict(row)
            bad["remove_reason"] = "punctuation_heavy"
            removed.append(bad)
            continue

        # 5) deduplicate exact same normalized content
        sig = text_signature(row)
        if sig in seen_sig:
            bad = dict(row)
            bad["remove_reason"] = "duplicate_exact"
            removed.append(bad)
            continue
        seen_sig.add(sig)

        cleaned.append(row)

    return cleaned, removed


def read_csv(path: Path) -> List[Dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, rows: List[Dict[str, str]], headers: List[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=headers)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in headers})


def main():
    ap = argparse.ArgumentParser(description="Clean parsed law CSV")
    ap.add_argument("--input-csv", required=True)
    ap.add_argument("--output-csv", required=True)
    ap.add_argument("--removed-csv", default="")
    ap.add_argument("--min-text-len", type=int, default=20)
    args = ap.parse_args()

    input_csv = Path(args.input_csv)
    output_csv = Path(args.output_csv)
    removed_csv = Path(args.removed_csv) if args.removed_csv else None

    rows = read_csv(input_csv)
    cleaned, removed = clean_rows(rows, min_text_len=args.min_text_len)

    write_csv(output_csv, cleaned, CSV_HEADERS)
    if removed_csv:
        write_csv(removed_csv, removed, REMOVED_HEADERS)

    print("Done.")
    print(f"- Input rows: {len(rows)}")
    print(f"- Clean rows: {len(cleaned)}")
    print(f"- Removed rows: {len(removed)}")
    print(f"- Output: {output_csv}")
    if removed_csv:
        print(f"- Removed detail: {removed_csv}")


if __name__ == "__main__":
    main()
