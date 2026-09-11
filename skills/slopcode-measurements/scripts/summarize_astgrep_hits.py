#!/usr/bin/env python3
"""Summarize ast-grep JSON-stream hits into mapped verbosity metrics."""
from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any


def load_hits(path: Path) -> list[dict[str, Any]]:
    hits: list[dict[str, Any]] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        hits.append(json.loads(line))
    return hits


def hit_lines(hit: dict[str, Any]) -> list[tuple[str, int]]:
    start = int(hit["range"]["start"]["line"]) + 1
    end = int(hit["range"]["end"]["line"]) + 1
    file = str(hit["file"])
    return [(file, line) for line in range(start, end + 1)]


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit("usage: summarize_astgrep_hits.py HITS_JSONL RAW_JSON LANGUAGE RULES")

    hits_path = Path(sys.argv[1])
    raw_json_text = sys.argv[2]
    language = sys.argv[3]
    rules_path = sys.argv[4]

    hits = load_hits(hits_path)
    unique_span_lines = {line for hit in hits for line in hit_lines(hit)}
    unique_start_lines = {
        (str(hit["file"]), int(hit["range"]["start"]["line"]) + 1)
        for hit in hits
    }
    by_rule = Counter(str(hit.get("ruleId", "<unknown>")) for hit in hits)
    by_file = Counter(str(hit.get("file", "<unknown>")) for hit in hits)

    raw: dict[str, Any] = json.loads(raw_json_text) if raw_json_text and raw_json_text != "{}" else {}
    total_loc = int(raw.get("total_loc") or 0)
    raw_flagged = int(raw.get("verbosity_flagged_loc") or 0)

    mapped: dict[str, Any] = {
        "language": language,
        "rules": rules_path,
        "ast_grep_hits": len(hits),
        "mapped_ast_grep_unique_start_loc": len(unique_start_lines),
        "mapped_ast_grep_unique_span_loc": len(unique_span_lines),
        "mapped_ast_grep_unique_loc": len(unique_span_lines),
        "rules_with_hits": len(by_rule),
        "top_rules": by_rule.most_common(25),
        "top_files": by_file.most_common(25),
    }

    if total_loc > 0:
        mapped["total_loc_from_raw"] = total_loc
        mapped["mapped_ast_grep_start_pct"] = len(unique_start_lines) / total_loc
        mapped["mapped_ast_grep_span_pct"] = len(unique_span_lines) / total_loc
        mapped["mapped_ast_grep_pct"] = len(unique_span_lines) / total_loc
        mapped["raw_plus_mapped_verbosity_upper_bound"] = (raw_flagged + len(unique_span_lines)) / total_loc
        mapped["raw_plus_mapped_start_line_verbosity_upper_bound"] = (raw_flagged + len(unique_start_lines)) / total_loc
        mapped["raw_verbosity_flagged_loc"] = raw_flagged

    print(json.dumps(mapped, sort_keys=True))


if __name__ == "__main__":
    main()
