#!/usr/bin/env python3
"""Summarize ast-grep JSON-stream hits into mapped verbosity metrics."""
from __future__ import annotations

import fnmatch
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any

EXTENSIONS: dict[str, tuple[str, ...]] = {
    "python": (".py", ".pyw"),
    "py": (".py", ".pyw"),
    "zig": (".zig",),
    "rust": (".rs",),
    "rs": (".rs",),
    "javascript": (".js", ".mjs", ".cjs"),
    "js": (".js", ".mjs", ".cjs"),
    "typescript": (".ts", ".tsx"),
    "ts": (".ts", ".tsx"),
    "tsx": (".tsx",),
    "cpp": (".cpp", ".cc", ".cxx", ".c++", ".hpp", ".hh", ".hxx", ".h"),
    "c++": (".cpp", ".cc", ".cxx", ".c++", ".hpp", ".hh", ".hxx", ".h"),
    "haskell": (".hs",),
    "hs": (".hs",),
    "go": (".go",),
    "java": (".java",),
    "c": (".c", ".h"),
    "csharp": (".cs",),
    "cs": (".cs",),
    "swift": (".swift",),
    "kotlin": (".kt", ".kts"),
    "ruby": (".rb",),
    "php": (".php",),
}


LINE_COMMENT: dict[str, tuple[str, ...]] = {
    "python": ("#",),
    "py": ("#",),
    "zig": ("//",),
    "rust": ("//",),
    "rs": ("//",),
    "javascript": ("//",),
    "js": ("//",),
    "typescript": ("//",),
    "ts": ("//",),
    "tsx": ("//",),
    "cpp": ("//",),
    "c++": ("//",),
    "haskell": ("--",),
    "hs": ("--",),
    "go": ("//",),
    "java": ("//",),
    "c": ("//",),
    "csharp": ("//",),
    "cs": ("//",),
    "swift": ("//",),
    "kotlin": ("//",),
    "ruby": ("#",),
    "php": ("//", "#"),
}



def load_hits(path: Path) -> list[dict[str, Any]]:
    hits: list[dict[str, Any]] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if line:
            hits.append(json.loads(line))
    return hits


def hit_lines(hit: dict[str, Any]) -> list[tuple[str, int]]:
    start = int(hit["range"]["start"]["line"]) + 1
    end = int(hit["range"]["end"]["line"]) + 1
    file = str(hit["file"])
    return [(file, line) for line in range(start, end + 1)]


def excluded(path: Path, root: Path, patterns: list[str]) -> bool:
    try:
        rel = path.relative_to(root).as_posix()
    except ValueError:
        rel = path.as_posix()
    parts = set(path.parts)
    for pattern in patterns:
        normalized = pattern.rstrip("/")
        if normalized in parts:
            return True
        if fnmatch.fnmatch(rel, pattern) or fnmatch.fnmatch(rel, normalized):
            return True
    return False


def source_files(root: Path, language: str, excludes: list[str]) -> list[Path]:
    suffixes = EXTENSIONS.get(language, tuple())
    if not suffixes:
        return []
    if root.is_file():
        return [root] if root.suffix in suffixes and not excluded(root, root.parent, excludes) else []
    return sorted(
        path
        for path in root.rglob("*")
        if path.is_file()
        and path.suffix in suffixes
        and not excluded(path, root, excludes)
    )


def sloc(path: Path, language: str) -> int:
    comments = LINE_COMMENT.get(language, ("//", "#"))
    count = 0
    for raw_line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if any(line.startswith(prefix) for prefix in comments):
            continue
        count += 1
    return count


def main() -> None:
    if len(sys.argv) < 6:
        raise SystemExit(
            "usage: summarize_astgrep_hits.py HITS_JSONL RAW_JSON LANGUAGE RULES TARGET [EXCLUDE...]"
        )

    hits_path = Path(sys.argv[1])
    raw_json_text = sys.argv[2]
    language = sys.argv[3]
    rules_path = sys.argv[4]
    target = Path(sys.argv[5]).resolve()
    excludes = sys.argv[6:]

    hits = load_hits(hits_path)
    unique_span_lines = {line for hit in hits for line in hit_lines(hit)}
    unique_start_lines = {
        (str(hit["file"]), int(hit["range"]["start"]["line"]) + 1)
        for hit in hits
    }
    unique_rule_line_pairs = {
        (str(hit["file"]), int(hit["range"]["start"]["line"]) + 1, str(hit.get("ruleId", "<unknown>")))
        for hit in hits
    }
    by_rule = Counter(str(hit.get("ruleId", "<unknown>")) for hit in hits)
    by_file = Counter(str(hit.get("file", "<unknown>")) for hit in hits)

    raw: dict[str, Any] = json.loads(raw_json_text) if raw_json_text and raw_json_text != "{}" else {}
    raw_flagged = int(raw.get("verbosity_flagged_loc") or 0)

    files = source_files(target, language, excludes)
    mapped_total_loc = sum(sloc(path, language) for path in files)

    mapped: dict[str, Any] = {
        "language": language,
        "rules": rules_path,
        "mapped_files_scanned": len(files),
        "mapped_total_loc": mapped_total_loc,
        "ast_grep_hits": len(hits),
        "unique_rule_line_pairs": len(unique_rule_line_pairs),
        "mapped_ast_grep_unique_start_loc": len(unique_start_lines),
        "mapped_ast_grep_unique_span_loc": len(unique_span_lines),
        "mapped_ast_grep_unique_loc": len(unique_span_lines),
        "rules_with_hits": len(by_rule),
        "top_rules": by_rule.most_common(25),
        "top_files": by_file.most_common(25),
    }

    if mapped_total_loc > 0:
        mapped["mapped_ast_grep_start_pct"] = len(unique_start_lines) / mapped_total_loc
        mapped["mapped_ast_grep_span_pct"] = len(unique_span_lines) / mapped_total_loc
        mapped["mapped_ast_grep_pct"] = len(unique_span_lines) / mapped_total_loc

    if raw.get("total_loc"):
        mapped["raw_total_loc"] = int(raw["total_loc"])
        mapped["raw_verbosity_flagged_loc"] = raw_flagged
        mapped["raw_plus_mapped_verbosity_upper_bound"] = None
        mapped["raw_plus_mapped_note"] = (
            "Not computed: raw scb-check and mapped ast-grep may use different language surfaces; "
            "true union requires line-level raw findings."
        )

    print(json.dumps(mapped, sort_keys=True))


if __name__ == "__main__":
    main()
