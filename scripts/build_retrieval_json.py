#!/usr/bin/env python3
"""
Convert cleaned law CSV into retrieval-friendly JSON/JSONL.

Input:
  laws_clean.csv (from clean_law_csv.py)

Outputs:
  - laws_retrieval.json   (array)
  - laws_retrieval.jsonl  (one json object per line)

Usage:
  python3 scripts/build_retrieval_json.py \
    --input-csv "/Users/mu/Desktop/安全大师/scripts/laws_clean.csv" \
    --output-json "/Users/mu/Desktop/安全大师/scripts/laws_retrieval.json" \
    --output-jsonl "/Users/mu/Desktop/安全大师/scripts/laws_retrieval.jsonl"
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Dict, List


def norm(s: str) -> str:
    if s is None:
        return ""
    s = s.replace("\u3000", " ").replace("\xa0", " ").replace("．", ".")
    s = re.sub(r"\s+", " ", s).strip()
    return s


def split_csv_list(s: str) -> List[str]:
    if not s:
        return []
    raw = re.split(r"[,，;；]", s)
    out = []
    for x in raw:
        x = norm(x)
        if x:
            out.append(x)
    # de-dup keep order
    return list(dict.fromkeys(out))


def parse_int(s: str, default: int = 2) -> int:
    try:
        return int(str(s).strip())
    except Exception:
        return default


def make_chunk_id(row: Dict[str, str], idx: int) -> str:
    law_id = norm(row.get("law_id", "LAW")) or "LAW"
    article_no = norm(row.get("article_no", ""))
    if article_no:
        safe = re.sub(r"[^0-9A-Za-z\u4e00-\u9fff\.]+", "_", article_no)
        return f"{law_id}_{safe}_{idx:05d}"
    return f"{law_id}_{idx:05d}"


def to_record(row: Dict[str, str], idx: int) -> Dict:
    text = norm(row.get("article_text", ""))
    law_name = norm(row.get("law_name", ""))
    article_no = norm(row.get("article_no", ""))
    chapter = norm(row.get("chapter", ""))
    article_title = norm(row.get("article_title", ""))

    title_parts = [law_name]
    if chapter:
        title_parts.append(chapter)
    if article_no:
        title_parts.append(article_no)
    if article_title:
        title_parts.append(article_title)

    return {
        "id": make_chunk_id(row, idx),
        "law_id": norm(row.get("law_id", "")),
        "law_name": law_name,
        "version": norm(row.get("version", "")),
        "chapter": chapter,
        "article_no": article_no,
        "article_title": article_title,
        "title": " / ".join([x for x in title_parts if x]),
        "text": text,
        "keywords": split_csv_list(row.get("keywords", "")),
        "scene_tags": split_csv_list(row.get("scene_tags", "")),
        "priority": parse_int(row.get("priority", "2"), 2),
        "is_mandatory": norm(row.get("is_mandatory", "")),
        "status": norm(row.get("status", "")),
        "source_file": norm(row.get("source_file", "")),
        # 便于后续简单关键词检索的拼接字段
        "search_text": " ".join(
            [
                law_name,
                chapter,
                article_no,
                article_title,
                " ".join(split_csv_list(row.get("keywords", ""))),
                text,
            ]
        ).strip(),
    }


def main():
    ap = argparse.ArgumentParser(description="Build retrieval JSON from cleaned CSV")
    ap.add_argument("--input-csv", required=True)
    ap.add_argument("--output-json", required=True)
    ap.add_argument("--output-jsonl", default="")
    args = ap.parse_args()

    input_csv = Path(args.input_csv)
    output_json = Path(args.output_json)
    output_jsonl = Path(args.output_jsonl) if args.output_jsonl else None

    rows: List[Dict[str, str]] = []
    with input_csv.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader, start=1):
            rec = to_record(row, i)
            if rec["text"]:
                rows.append(rec)

    output_json.parent.mkdir(parents=True, exist_ok=True)
    with output_json.open("w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)

    if output_jsonl:
        output_jsonl.parent.mkdir(parents=True, exist_ok=True)
        with output_jsonl.open("w", encoding="utf-8") as f:
            for rec in rows:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    print("Done.")
    print(f"- Input CSV: {input_csv}")
    print(f"- Records: {len(rows)}")
    print(f"- JSON: {output_json}")
    if output_jsonl:
        print(f"- JSONL: {output_jsonl}")


if __name__ == "__main__":
    main()
