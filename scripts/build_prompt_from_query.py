#!/usr/bin/env python3
"""
Build LLM prompt with retrieved law evidence.

Pipeline:
1) Load laws_retrieval.json/jsonl
2) Retrieve top-k by simple lexical scoring
3) Compose structured prompt for DeepSeek (or any chat model)

Usage:
  python3 scripts/build_prompt_from_query.py \
    --data "/Users/mu/Desktop/安全大师/scripts/laws_retrieval.jsonl" \
    --query "临边防护缺失，洞口未盖板" \
    --location "3号楼12层" \
    --extra "现场有多人交叉作业" \
    --topk 8 \
    --out "/Users/mu/Desktop/安全大师/scripts/prompt_example.txt"
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


def tokenize_query(q: str) -> List[str]:
    q = norm(q)
    parts = re.findall(r"[\u4e00-\u9fff]{1,8}|[a-z0-9\-\.]+", q)
    out = []
    seen = set()
    for p in parts:
        if p not in seen:
            seen.add(p)
            out.append(p)
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


def score_record(rec: Dict, terms: List[str]) -> float:
    search_text = norm(rec.get("search_text", ""))
    if not search_text:
        return 0.0

    kw = [norm(x) for x in rec.get("keywords", []) if isinstance(x, str)]
    tags = [norm(x) for x in rec.get("scene_tags", []) if isinstance(x, str)]
    title = norm(rec.get("title", ""))

    score = 0.0
    for t in terms:
        c = term_count(search_text, t)
        if c > 0:
            score += 1.8 * (1.0 + math.log(1 + c))
        if t in title:
            score += 1.2
        if any(t in k or k in t for k in kw):
            score += 1.0
        if any(t in tg or tg in t for tg in tags):
            score += 1.0

    priority = int(rec.get("priority", 2) or 2)
    score += {1: 0.0, 2: 0.6, 3: 1.0}.get(priority, 0.6)
    return score


def retrieve(records: List[Dict], query: str, topk: int, min_score: float = 1.0) -> List[Dict]:
    terms = tokenize_query(query)
    ranked: List[Tuple[float, Dict]] = []
    for rec in records:
        s = score_record(rec, terms)
        if s >= min_score:
            ranked.append((s, rec))
    ranked.sort(key=lambda x: x[0], reverse=True)
    out = []
    for s, rec in ranked[:topk]:
        item = dict(rec)
        item["_score"] = round(s, 4)
        out.append(item)
    return out


def build_evidence_block(evidence: List[Dict]) -> str:
    lines: List[str] = []
    for i, e in enumerate(evidence, start=1):
        law_name = e.get("law_name", "")
        version = e.get("version", "")
        article_no = e.get("article_no", "")
        chapter = e.get("chapter", "")
        text = (e.get("text", "") or "").strip()
        if len(text) > 500:
            text = text[:500] + "..."
        score = e.get("_score", 0)
        lines.append(
            f"[{i}] score={score}\\n"
            f"法规：{law_name} {version}\\n"
            f"章节：{chapter}\\n"
            f"条款：{article_no}\\n"
            f"原文摘录：{text}"
        )
    return "\\n\\n".join(lines)


def build_prompt(query: str, location: str, extra: str, evidence: List[Dict]) -> str:
    evidence_block = build_evidence_block(evidence)

    system_prompt = """
你是资深建筑施工安全专家。你必须基于“证据条款”作答，禁止编造条款号或虚构原文。
输出必须是 JSON（不要 markdown 代码块），字段如下：
- hazard_description: 隐患描述（简洁、现场化）
- risk_level: 仅可为 低风险/一般风险/较大风险/重大风险
- rectification_measures: 可执行整改措施，分点，使用\\n换行
- legal_basis: 列出所引用法规（法规名 + 条款号 + 原文关键句）
- citation_ids: 引用证据编号数组，如 [1,3,4]
约束：
1) 必须引用至少2条证据；
2) 证据不足时必须写明“需补充现场信息”；
3) 不得输出证据块中不存在的条号。
""".strip()

    user_prompt = f"""
【现场输入】
- 问题描述：{query}
- 地点：{location or '未提供'}
- 补充信息：{extra or '无'}

【证据条款（检索结果）】
{evidence_block}

请按要求只输出 JSON。
""".strip()

    return f"[SYSTEM]\n{system_prompt}\n\n[USER]\n{user_prompt}\n"


def main():
    ap = argparse.ArgumentParser(description="Build LLM prompt from retrieval")
    ap.add_argument("--data", required=True, help="laws_retrieval.json/.jsonl")
    ap.add_argument("--query", required=True, help="hazard query text")
    ap.add_argument("--location", default="", help="location")
    ap.add_argument("--extra", default="", help="extra context")
    ap.add_argument("--topk", type=int, default=8)
    ap.add_argument("--min-score", type=float, default=1.0)
    ap.add_argument("--out", default="", help="optional output prompt file path")
    ap.add_argument("--evidence-out", default="", help="optional evidence json output")
    args = ap.parse_args()

    data_path = Path(args.data)
    records = load_records(data_path)
    evidence = retrieve(records, args.query, topk=args.topk, min_score=args.min_score)

    prompt = build_prompt(args.query, args.location, args.extra, evidence)

    print(f"Query: {args.query}")
    print(f"Evidence picked: {len(evidence)}")
    print("=" * 80)
    print(prompt[:3000])
    if len(prompt) > 3000:
        print("\n... (truncated preview) ...")

    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(prompt, encoding="utf-8")
        print(f"\nPrompt saved: {out_path}")

    if args.evidence_out:
        ev_path = Path(args.evidence_out)
        ev_path.parent.mkdir(parents=True, exist_ok=True)
        ev_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Evidence saved: {ev_path}")


if __name__ == "__main__":
    main()
