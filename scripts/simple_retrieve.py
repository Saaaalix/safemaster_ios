#!/usr/bin/env python3
"""
Simple local retrieval for laws_retrieval.json/jsonl.

Features:
- Keyword scoring on search_text
- scene_tags / keywords boost
- priority weighting

Usage:
  python3 scripts/simple_retrieve.py \
    --data "/Users/mu/Desktop/安全大师/scripts/laws_retrieval.jsonl" \
    --query "临边防护 洞口 高处作业" \
    --topk 10
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Dict, List, Tuple


def norm(s: str) -> str:
    s = s.replace("\u3000", " ").replace("\xa0", " ")
    s = re.sub(r"\s+", " ", s).strip().lower()
    return s


_CJK_STOP = set(
    "的了在是和与及或等应将对于以中有不可需须宜并其该此均所由被于而之也又若则但如即"
)


def tokenize_query(q: str) -> List[str]:
    """
    与 App 内 LawEvidenceRetriever 一致：对连续汉字做 2/3 字滑动窗口，避免贪婪 1~8 字
    切成「基坑底部存在少量积」导致法规库零命中。
    """
    q = norm(q)
    seen: set[str] = set()
    out: list[str] = []
    max_terms = 160

    def add(s: str) -> None:
        if len(out) >= max_terms or not s:
            return
        if len(s) == 1:
            if s in _CJK_STOP or not ("\u4e00" <= s <= "\u9fff"):
                return
        if s not in seen:
            seen.add(s)
            out.append(s)

    for m in re.finditer(r"[a-z0-9][a-z0-9\-\.]*", q):
        add(m.group(0))

    for m in re.finditer(r"[\u4e00-\u9fff]+", q):
        run = m.group(0)
        L = len(run)
        if L <= 10:
            add(run)
        if L >= 2:
            for i in range(L - 1):
                add(run[i : i + 2])
        if L >= 3:
            for i in range(L - 2):
                add(run[i : i + 3])

    return out


def load_records(path: Path) -> List[Dict]:
    if path.suffix.lower() == ".jsonl":
        rows = []
        with path.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                rows.append(json.loads(line))
        return rows

    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def term_count(text: str, term: str) -> int:
    return text.count(term)


def score_record(rec: Dict, terms: List[str]) -> Tuple[float, Dict[str, float]]:
    search_text = norm(rec.get("search_text", ""))
    if not search_text:
        return 0.0, {}

    kw = [norm(x) for x in rec.get("keywords", []) if isinstance(x, str)]
    tags = [norm(x) for x in rec.get("scene_tags", []) if isinstance(x, str)]
    title = norm(rec.get("title", ""))

    score = 0.0
    detail = {
        "hit": 0.0,
        "title": 0.0,
        "kw": 0.0,
        "tag": 0.0,
        "priority": 0.0,
    }

    for t in terms:
        c = term_count(search_text, t)
        if c > 0:
            # diminishing returns
            part = 1.8 * (1.0 + math.log(1 + c))
            score += part
            detail["hit"] += part

        if t in title:
            score += 1.2
            detail["title"] += 1.2

        if any(t in k or k in t for k in kw):
            score += 1.0
            detail["kw"] += 1.0

        if any(t in tg or tg in t for tg in tags):
            score += 1.0
            detail["tag"] += 1.0

    priority = int(rec.get("priority", 2) or 2)
    pr_boost = {1: 0.0, 2: 0.6, 3: 1.0}.get(priority, 0.6)
    score += pr_boost
    detail["priority"] = pr_boost

    return score, detail


def pretty_row(i: int, rec: Dict, score: float, detail: Dict[str, float]) -> str:
    law = rec.get("law_name", "")
    article_no = rec.get("article_no", "")
    chapter = rec.get("chapter", "")
    title = rec.get("article_title", "")
    text = rec.get("text", "")
    snippet = text[:150] + ("..." if len(text) > 150 else "")
    tags = ",".join(rec.get("scene_tags", [])[:4])
    return (
        f"[{i}] score={score:.2f} | {law} | {chapter} | {article_no} {title}\n"
        f"    tags={tags}\n"
        f"    {snippet}\n"
        f"    detail={{hit:{detail.get('hit',0):.2f}, title:{detail.get('title',0):.2f}, "
        f"kw:{detail.get('kw',0):.2f}, tag:{detail.get('tag',0):.2f}, pr:{detail.get('priority',0):.2f}}}"
    )


def main():
    ap = argparse.ArgumentParser(description="Simple local retrieval")
    ap.add_argument("--data", required=True, help="Path to laws_retrieval.json or .jsonl")
    ap.add_argument("--query", required=True, help="Search query")
    ap.add_argument("--topk", type=int, default=10)
    ap.add_argument("--min-score", type=float, default=1.0)
    args = ap.parse_args()

    data_path = Path(args.data)
    records = load_records(data_path)

    terms = tokenize_query(args.query)
    if not terms:
        print("Query empty after tokenization.")
        return

    ranked = []
    for rec in records:
        s, detail = score_record(rec, terms)
        if s >= args.min_score:
            ranked.append((s, rec, detail))

    ranked.sort(key=lambda x: x[0], reverse=True)

    print(f"Query: {args.query}")
    print(f"Terms: {terms}")
    print(f"Candidates >= {args.min_score}: {len(ranked)}")
    print("=" * 88)

    for idx, (s, rec, detail) in enumerate(ranked[: args.topk], start=1):
        print(pretty_row(idx, rec, s, detail))
        print("-" * 88)


if __name__ == "__main__":
    main()
