#!/usr/bin/env python3
"""
Batch parse Chinese law/regulation .docx files into CSV rows (chapter/article level).

Usage:
  python3 scripts/build_law_csv.py \
      --input-dir "/Users/mu/Desktop/仙/建筑工程施工安全技术规范27份（Word版）" \
      --output-csv "/Users/mu/Desktop/安全大师/scripts/laws_raw.csv"

Optional:
  --output-issues "/Users/mu/Desktop/安全大师/scripts/laws_issues.csv"
  --law-id-prefix LAW
  --priority 2
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

try:
    from docx import Document
except ImportError:
    print(
        "Missing dependency: python-docx\n"
        "Install with: python3 -m pip install python-docx",
        file=sys.stderr,
    )
    raise


# 法律类（第X章 / 第X条）
CHAPTER_RE = re.compile(r"^第\s*[一二三四五六七八九十百千万零〇0-9]+\s*章")
ARTICLE_RE = re.compile(r"^第\s*[一二三四五六七八九十百千万零〇0-9]+\s*条")
# 标准规范类（1 总则 / 3.0.1 条）
STANDARD_CHAPTER_RE = re.compile(r"^(\d{1,2})\s*([^\d].+)$")
CLAUSE_RE = re.compile(r"^(\d+(?:[\.．]\d+){1,3})\s*(.*)$")
APPENDIX_RE = re.compile(r"^附录\s*[A-ZＡ-Ｚ一二三四五六七八九十]?\s*.*$")
VERSION_RE = re.compile(r"(20\d{2}年(?:修订|版)?)")


TAG_RULES = {
    "高处作业": ["高处", "临边", "洞口", "坠落", "安全带", "防护栏杆"],
    "临时用电": ["临时用电", "漏电", "配电箱", "接地", "电缆", "电工", "触电"],
    "脚手架": ["脚手架", "扣件", "立杆", "连墙件", "剪刀撑"],
    "起重吊装": ["起重", "吊装", "塔吊", "吊钩", "起重机", "司索", "指挥"],
    "基坑工程": ["基坑", "支护", "降水", "边坡", "土方开挖"],
    "模板支撑": ["模板", "支撑体系", "满堂架", "立杆基础"],
    "消防动火": ["动火", "消防", "易燃", "灭火器", "火灾"],
    "有限空间": ["有限空间", "缺氧", "有毒气体", "受限空间"],
    "机械设备": ["机械设备", "设备", "防护罩", "传动", "维护保养"],
    "教育培训": ["培训", "教育", "持证上岗", "交底", "特种作业"],
    "应急救援": ["应急", "救援", "预案", "演练"],
    "事故报告": ["事故", "报告", "调查", "瞒报", "迟报"],
    "处罚问责": ["罚款", "处罚", "法律责任", "责令", "停产", "追究"],
    "责任体系": ["负责人", "责任制", "管理机构", "职责", "安全生产责任"],
}

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

ISSUE_HEADERS = ["source_file", "issue_type", "line_text", "hint"]


@dataclass
class ArticleRow:
    law_id: str
    law_name: str
    version: str
    chapter: str
    article_no: str
    article_title: str
    article_text: str
    keywords: str
    scene_tags: str
    priority: int
    is_mandatory: str
    status: str
    source_file: str
    notes: str = ""

    def as_dict(self):
        return {
            "law_id": self.law_id,
            "law_name": self.law_name,
            "version": self.version,
            "chapter": self.chapter,
            "article_no": self.article_no,
            "article_title": self.article_title,
            "article_text": self.article_text,
            "keywords": self.keywords,
            "scene_tags": self.scene_tags,
            "priority": self.priority,
            "is_mandatory": self.is_mandatory,
            "status": self.status,
            "source_file": self.source_file,
            "notes": self.notes,
        }


def normalize_space(s: str) -> str:
    s = s.replace("\u3000", " ").replace("\xa0", " ")
    s = re.sub(r"\s+", " ", s).strip()
    return s


def normalize_for_match(s: str) -> str:
    """Normalize punctuation variants for regex matching."""
    return normalize_space(s).replace("．", ".")


def split_article_header(line: str) -> Tuple[str, str]:
    """Return (article_no, article_title)."""
    m = re.match(r"^(第\s*[一二三四五六七八九十百千万零〇0-9]+\s*条)\s*(.*)$", line)
    if not m:
        return line, ""
    article_no = normalize_space(m.group(1))
    rest = normalize_space(m.group(2))
    # Titles are often short; keep as title if it doesn't look like full sentence.
    if rest and len(rest) <= 40 and "。" not in rest and "；" not in rest:
        return article_no, rest
    return article_no, ""


def split_clause_header(line: str) -> Tuple[str, str]:
    """Return (clause_no, clause_title) for standards like 3.0.1."""
    m = CLAUSE_RE.match(normalize_for_match(line))
    if not m:
        return line, ""
    clause_no = normalize_space(m.group(1))
    rest = normalize_space(m.group(2))
    if rest and len(rest) <= 40 and "。" not in rest and "；" not in rest:
        return clause_no, rest
    return clause_no, ""


def parse_law_name_and_version(file_stem: str) -> Tuple[str, str]:
    version = ""
    vm = VERSION_RE.search(file_stem)
    if vm:
        version = vm.group(1)
        law_name = file_stem.replace(version, "").strip("_- ")
    else:
        law_name = file_stem
    return law_name, version


def make_law_id(prefix: str, idx: int, law_name: str) -> str:
    base = re.sub(r"[^A-Za-z0-9\u4e00-\u9fff]", "", law_name)
    # Keep it simple and deterministic.
    short = base[:8] if base else f"LAW{idx:03d}"
    return f"{prefix}_{idx:03d}_{short}"


def infer_tags_and_keywords(text: str) -> Tuple[str, str]:
    hits = []
    keywords = []
    for tag, kws in TAG_RULES.items():
        for kw in kws:
            if kw in text:
                hits.append(tag)
                keywords.append(kw)
    # de-dup preserving order
    unique_tags = list(dict.fromkeys(hits))
    unique_keywords = list(dict.fromkeys(keywords))

    if not unique_tags:
        unique_tags = ["通用"]
    if not unique_keywords:
        # fallback keyword extraction: pick top noun-like chunks by length
        candidates = re.findall(r"[\u4e00-\u9fff]{2,8}", text)
        unique_keywords = list(dict.fromkeys(candidates[:6])) or ["安全生产"]

    return ",".join(unique_tags), ",".join(unique_keywords[:8])


def parse_docx(
    path: Path,
    law_id: str,
    law_name: str,
    version: str,
    priority: int,
    is_mandatory: str,
    status: str,
) -> Tuple[List[ArticleRow], List[dict]]:
    doc = Document(str(path))

    rows: List[ArticleRow] = []
    issues: List[dict] = []

    current_chapter = ""
    current_article_no = ""
    current_article_title = ""
    current_article_parts: List[str] = []
    unattached_count = 0

    def flush_article():
        nonlocal current_article_no, current_article_title, current_article_parts
        if not current_article_no:
            return
        article_text = normalize_space(" ".join(current_article_parts))
        if not article_text:
            issues.append(
                {
                    "source_file": path.name,
                    "issue_type": "empty_article_text",
                    "line_text": current_article_no,
                    "hint": "条号已识别但正文为空，请人工检查。",
                }
            )
            return

        scene_tags, keywords = infer_tags_and_keywords(article_text)
        rows.append(
            ArticleRow(
                law_id=law_id,
                law_name=law_name,
                version=version,
                chapter=current_chapter,
                article_no=current_article_no,
                article_title=current_article_title,
                article_text=article_text,
                keywords=keywords,
                scene_tags=scene_tags,
                priority=priority,
                is_mandatory=is_mandatory,
                status=status,
                source_file=path.name,
            )
        )

    for para in doc.paragraphs:
        raw_line = para.text
        line = normalize_space(raw_line)
        if not line:
            continue

        match_line = normalize_for_match(raw_line)

        if CHAPTER_RE.match(line):
            flush_article()
            current_article_no = ""
            current_article_title = ""
            current_article_parts = []
            current_chapter = line
            continue

        if ARTICLE_RE.match(line):
            flush_article()
            current_article_no, current_article_title = split_article_header(line)
            current_article_parts = [line]
            continue

        if STANDARD_CHAPTER_RE.match(match_line) or APPENDIX_RE.match(line):
            # Avoid misclassifying numeric clauses (e.g. 3.0.1) as chapter.
            if not CLAUSE_RE.match(match_line):
                flush_article()
                current_article_no = ""
                current_article_title = ""
                current_article_parts = []
                current_chapter = line
                continue

        if CLAUSE_RE.match(match_line):
            flush_article()
            current_article_no, current_article_title = split_clause_header(line)
            current_article_parts = [line]
            continue

        if current_article_no:
            current_article_parts.append(line)
        else:
            # Content before first recognized article.
            unattached_count += 1
            if unattached_count <= 80:
                issues.append(
                    {
                        "source_file": path.name,
                        "issue_type": "unattached_text",
                        "line_text": line[:200],
                        "hint": "未挂接到任何条号，可能是前言/目录/格式异常。",
                    }
                )

    flush_article()

    if unattached_count > 80:
        issues.append(
            {
                "source_file": path.name,
                "issue_type": "unattached_text_truncated",
                "line_text": "",
                "hint": f"未挂接文本共 {unattached_count} 行，仅保留前 80 行示例。",
            }
        )

    if not rows:
        issues.append(
            {
                "source_file": path.name,
                "issue_type": "no_articles_parsed",
                "line_text": "",
                "hint": "未识别到任何条款（第X条 或 3.0.1）。请检查文档格式。",
            }
        )

    return rows, issues


def collect_docx_files(input_dir: Path) -> List[Path]:
    files = sorted([p for p in input_dir.rglob("*.docx") if not p.name.startswith("~$")])
    return files


def main():
    parser = argparse.ArgumentParser(description="Parse .docx laws into CSV.")
    parser.add_argument("--input-dir", required=True, help="Directory containing .docx files")
    parser.add_argument("--output-csv", required=True, help="Output CSV file path")
    parser.add_argument("--output-issues", default="", help="Optional issues CSV path")
    parser.add_argument("--law-id-prefix", default="LAW", help="Law ID prefix")
    parser.add_argument("--priority", type=int, default=2, help="Default priority")
    parser.add_argument("--is-mandatory", default="是", help="Default is_mandatory")
    parser.add_argument("--status", default="现行", help="Default status")
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    output_csv = Path(args.output_csv)
    output_issues = Path(args.output_issues) if args.output_issues else None

    if not input_dir.exists() or not input_dir.is_dir():
        print(f"Input directory not found: {input_dir}", file=sys.stderr)
        sys.exit(2)

    files = collect_docx_files(input_dir)
    if not files:
        print(f"No .docx files found under: {input_dir}", file=sys.stderr)
        sys.exit(3)

    all_rows: List[ArticleRow] = []
    all_issues: List[dict] = []

    for idx, fp in enumerate(files, start=1):
        law_name, version = parse_law_name_and_version(fp.stem)
        law_id = make_law_id(args.law_id_prefix, idx, law_name)
        rows, issues = parse_docx(
            path=fp,
            law_id=law_id,
            law_name=law_name,
            version=version,
            priority=args.priority,
            is_mandatory=args.is_mandatory,
            status=args.status,
        )
        all_rows.extend(rows)
        all_issues.extend(issues)
        print(f"[OK] {fp.name}: {len(rows)} 条")

    output_csv.parent.mkdir(parents=True, exist_ok=True)
    with output_csv.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_HEADERS)
        writer.writeheader()
        for row in all_rows:
            writer.writerow(row.as_dict())

    if output_issues:
        output_issues.parent.mkdir(parents=True, exist_ok=True)
        with output_issues.open("w", encoding="utf-8-sig", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=ISSUE_HEADERS)
            writer.writeheader()
            writer.writerows(all_issues)

    print("\nDone.")
    print(f"- Laws parsed: {len(files)}")
    print(f"- Article rows: {len(all_rows)}")
    print(f"- Output CSV: {output_csv}")
    if output_issues:
        print(f"- Issues CSV: {output_issues} ({len(all_issues)} rows)")


if __name__ == "__main__":
    main()
