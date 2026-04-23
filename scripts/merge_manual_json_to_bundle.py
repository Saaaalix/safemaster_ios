#!/usr/bin/env python3
"""
Merge manually curated JSON files under json库/ into two App bundle files:

- laws_playbook.jsonl   — 《建筑安全操作准则》展开后的检查要点（整改措施优先匹配）
- laws_basis.jsonl      — 安全生产法、JGJ59、细部国标等（整改依据优先匹配）

Input JSON files may contain multiple concatenated top-level arrays; we parse with
JSONDecoder.raw_decode in a loop.

Usage:
  python3 scripts/merge_manual_json_to_bundle.py \
    --input "/Users/mu/Desktop/json库" \
    --playbook-dir "/Users/mu/Desktop/建筑安全操作准则" \
    --out-playbook "../安全大师/laws_playbook.jsonl" \
    --out-basis "../安全大师/laws_basis.jsonl"

《建筑安全操作准则》可二选一：
  • 单文件：json库 下任意处名为「建筑安全操作准则.json」
  • 拆分目录：--playbook-dir 指向仅含准则分册 *.json 的文件夹（与整改依据其它 json 分离）
  • 或把拆分文件放在 json库/建筑安全操作准则/ 下（无需 --playbook-dir）
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple


PLAYBOOK_BASENAME = "建筑安全操作准则.json"
PLAYBOOK_LAW_NAME = "建筑安全操作准则"


def iter_top_json_arrays(text: str) -> Iterable[Any]:
    dec = json.JSONDecoder()
    idx = 0
    n = len(text)
    while idx < n:
        while idx < n and text[idx] in " \t\n\r":
            idx += 1
        if idx >= n:
            break
        try:
            obj, end = dec.raw_decode(text, idx)
        except json.JSONDecodeError as e:
            raise json.JSONDecodeError(
                f"{e.msg} (at file offset {idx})",
                e.doc,
                e.pos,
            ) from e
        yield obj
        idx = end


def load_file_objects(path: Path) -> List[Any]:
    text = path.read_text(encoding="utf-8")
    out: List[Any] = []
    for chunk in iter_top_json_arrays(text):
        if isinstance(chunk, list):
            out.extend(chunk)
        else:
            out.append(chunk)
    return out


def norm_search_parts(*parts: str) -> str:
    t = " ".join(p for p in parts if p)
    t = t.replace("\u3000", " ").replace("\xa0", " ")
    t = re.sub(r"\s+", " ", t).strip()
    return t


def emit_record(
    rid: str,
    law_name: str,
    chapter: str,
    article_no: str,
    article_title: str,
    title: str,
    text: str,
    keywords: List[str],
    scene_tags: List[str],
    priority: int,
    law_id: Optional[str] = None,
) -> Dict[str, Any]:
    search_text = norm_search_parts(
        law_name,
        chapter,
        article_no,
        article_title,
        title,
        text,
        " ".join(keywords),
        " ".join(scene_tags),
    )
    rec: Dict[str, Any] = {
        "id": rid,
        "law_name": law_name,
        "chapter": chapter,
        "article_no": article_no,
        "article_title": article_title,
        "title": title,
        "text": text,
        "search_text": search_text,
        "keywords": keywords,
        "scene_tags": scene_tags,
        "priority": priority,
    }
    if law_id:
        rec["law_id"] = law_id
    return rec


def flatten_playbook(items: List[Any]) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    for obj in items:
        if not isinstance(obj, dict):
            continue
        cl = obj.get("check_list")
        if not isinstance(cl, list):
            continue
        pid = str(obj.get("id") or "PB")
        module = str(obj.get("module") or "")
        subject = str(obj.get("subject") or "")
        std_act = str(obj.get("standard_action") or "")
        danger = str(obj.get("danger_level") or "")
        mapping = obj.get("mapping") if isinstance(obj.get("mapping"), dict) else {}
        mk = mapping.get("keywords") if isinstance(mapping.get("keywords"), list) else []
        map_kws = [str(x) for x in mk if x]
        l3 = str(mapping.get("level_3_code") or "")

        for i, chk in enumerate(cl):
            if not isinstance(chk, dict):
                continue
            point = str(chk.get("point") or "")
            req = str(chk.get("requirement") or "")
            logic = str(chk.get("logic") or "")
            rid = f"{pid}-c{i + 1}"
            text = norm_search_parts(
                f"检查要点：{point}",
                f"操作要求：{req}",
                f"管理逻辑：{logic}",
            )
            chapter = norm_search_parts(module, subject)
            article_title = std_act
            kws = list(dict.fromkeys(map_kws + [point, std_act, subject, module]))
            tags = list(dict.fromkeys([danger, l3] + map_kws))
            title = norm_search_parts(PLAYBOOK_LAW_NAME, module, subject, std_act, point)
            rows.append(
                emit_record(
                    rid=rid,
                    law_id="PLAYBOOK",
                    law_name=PLAYBOOK_LAW_NAME,
                    chapter=chapter,
                    article_no=point[:80] if point else danger,
                    article_title=article_title,
                    title=title,
                    text=text,
                    keywords=kws,
                    scene_tags=tags,
                    priority=3,
                )
            )
    return rows


def is_playbook_shaped(obj: Dict[str, Any]) -> bool:
    return (
        "check_list" in obj
        and "module" in obj
        and "standard_action" in obj
        and isinstance(obj.get("check_list"), list)
    )


def basis_from_simple_law(obj: Dict[str, Any], *, priority: int) -> Optional[Dict[str, Any]]:
    """安全生产法 / JGJ59 等同型：title, section_number, content."""
    if "title" not in obj or "content" not in obj:
        return None
    if "section_number" not in obj:
        return None
    rid = str(obj.get("id") or "")
    if not rid:
        return None
    title = str(obj["title"])
    chapter = str(obj.get("chapter") or "")
    sec = str(obj.get("section_number") or "")
    content = str(obj["content"])
    ver = str(obj.get("version") or "")
    tags = [str(x) for x in obj.get("tags") or [] if x]
    kws = [str(x) for x in obj.get("keywords") or [] if x]
    law_line = norm_search_parts(title, ver)
    composite_title = norm_search_parts(title, ver, chapter, sec)
    return emit_record(
        rid=rid,
        law_id=None,
        law_name=law_line,
        chapter=chapter,
        article_no=sec,
        article_title="",
        title=composite_title,
        text=content,
        keywords=kws,
        scene_tags=tags,
        priority=priority,
    )


def basis_from_standard_code(obj: Dict[str, Any], *, priority: int) -> Optional[Dict[str, Any]]:
    """GB50194 / JGJ80 等：standard_code, standard_name, item_number, content."""
    if "standard_name" not in obj or "content" not in obj:
        return None
    rid = str(obj.get("id") or "")
    if not rid:
        return None
    code = str(obj.get("standard_code") or "")
    name = str(obj["standard_name"])
    chapter = str(obj.get("chapter") or "")
    section = str(obj.get("section") or "")
    item_no = str(obj.get("item_number") or "")
    content = str(obj["content"])
    tags = [str(x) for x in obj.get("tags") or [] if x]
    law_name = norm_search_parts(name, code) if code else name
    ch = norm_search_parts(chapter, section)
    title = norm_search_parts(law_name, ch, item_no)
    return emit_record(
        rid=rid,
        law_id=None,
        law_name=law_name,
        chapter=ch,
        article_no=item_no,
        article_title="",
        title=title,
        text=content,
        keywords=tags,
        scene_tags=tags,
        priority=priority,
    )


def object_to_basis_row(obj: Any, *, file_stem: str) -> Optional[Dict[str, Any]]:
    if not isinstance(obj, dict):
        return None
    if is_playbook_shaped(obj):
        return None

    title = str(obj.get("title") or "")
    pri = 3 if "安全生产法" in title else 2

    r = basis_from_simple_law(obj, priority=pri)
    if r:
        return r
    r = basis_from_standard_code(obj, priority=pri)
    if r:
        return r

    # Unknown shape: skip quietly (avoid crashing on stray objects)
    return None


def dedupe_ids(rows: List[Dict[str, Any]], *, prefix: str) -> List[Dict[str, Any]]:
    seen: Dict[str, int] = {}
    out: List[Dict[str, Any]] = []
    for rec in rows:
        rid = str(rec["id"])
        if rid in seen:
            seen[rid] += 1
            rec = dict(rec)
            rec["id"] = f"{prefix}-{seen[rid]}-{rid}"
        else:
            seen[rid] = 0
        out.append(rec)
    return out


def write_jsonl(path: Path, rows: List[Dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


def load_playbook_from_directory(dir_path: Path) -> List[Dict[str, Any]]:
    """目录内全部 *.json 合并为 playbook 行（每项须含 module / standard_action / check_list）。"""
    if not dir_path.is_dir():
        raise SystemExit(f"--playbook-dir 不是目录: {dir_path}")
    rows: List[Dict[str, Any]] = []
    json_files = sorted(dir_path.glob("*.json"))
    if not json_files:
        raise SystemExit(f"目录内无 *.json: {dir_path}")
    for path in json_files:
        try:
            objs = load_file_objects(path)
        except json.JSONDecodeError as e:
            raise SystemExit(f"playbook 文件 JSON 错误 {path}: {e}") from e
        rows.extend(flatten_playbook(objs))
    return dedupe_ids(rows, prefix="PB")


def resolve_playbook_rows(
    root: Path,
    playbook_dir_arg: Optional[Path],
) -> Tuple[List[Dict[str, Any]], set[Path]]:
    """
    返回 (playbook_rows, paths_to_skip_for_basis)。
    paths_to_skip_for_basis：在 json库 内合并准则分册时，避免 basis 扫描重复读这些文件。
    """
    skip_basis: set[Path] = set()

    if playbook_dir_arg is not None:
        pdir = playbook_dir_arg.expanduser().resolve()
        return load_playbook_from_directory(pdir), skip_basis

    playbook_path = next(root.rglob(PLAYBOOK_BASENAME), None)
    if playbook_path is not None:
        pb_items = load_file_objects(playbook_path)
        return dedupe_ids(flatten_playbook(pb_items), prefix="PB"), skip_basis

    sub = root / "建筑安全操作准则"
    if sub.is_dir():
        for path in sorted(sub.glob("*.json")):
            skip_basis.add(path.resolve())
        return load_playbook_from_directory(sub), skip_basis

    raise SystemExit(
        "未找到《建筑安全操作准则》数据源。请任选其一：\n"
        f"  1) 在 json库 下放置 {PLAYBOOK_BASENAME}\n"
        f"  2) 在 json库 下创建子目录 建筑安全操作准则/ 并放入拆分 *.json\n"
        "  3) 使用 --playbook-dir 指向拆分目录（可在 json库 外，如桌面）"
    )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", type=Path, required=True, help="json库 根目录")
    ap.add_argument(
        "--playbook-dir",
        type=Path,
        default=None,
        help="拆分后的准则目录（仅 *.json 分册）；指定后不再在 --input 内查找单文件",
    )
    ap.add_argument(
        "--out-playbook",
        type=Path,
        default=Path("安全大师/laws_playbook.jsonl"),
        help="输出 playbook jsonl",
    )
    ap.add_argument(
        "--out-basis",
        type=Path,
        default=Path("安全大师/laws_basis.jsonl"),
        help="输出 basis jsonl",
    )
    args = ap.parse_args()
    root: Path = args.input.expanduser().resolve()

    playbook_rows, skip_basis_paths = resolve_playbook_rows(root, args.playbook_dir)

    basis_rows: List[Dict[str, Any]] = []
    skipped: List[str] = []
    for path in sorted(root.rglob("*.json")):
        if path.resolve() in skip_basis_paths:
            continue
        if path.name == PLAYBOOK_BASENAME:
            continue
        stem = path.stem
        try:
            objs = load_file_objects(path)
        except json.JSONDecodeError as e:
            msg = f"SKIP (JSON error): {path}: {e}"
            print(msg)
            skipped.append(msg)
            continue
        for obj in objs:
            row = object_to_basis_row(obj, file_stem=stem)
            if row:
                basis_rows.append(row)

    basis_rows = dedupe_ids(basis_rows, prefix="B")

    write_jsonl(args.out_playbook, playbook_rows)
    write_jsonl(args.out_basis, basis_rows)

    print(f"playbook: {len(playbook_rows)} -> {args.out_playbook}")
    print(f"basis:    {len(basis_rows)} -> {args.out_basis}")
    if skipped:
        print("\n以下文件未并入 basis（修复 JSON 后请重新运行本脚本）：")
        for s in skipped:
            print(" ", s)


if __name__ == "__main__":
    main()
