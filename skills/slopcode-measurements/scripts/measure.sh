#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: measure.sh [--language LANG] [--mode raw|mapped|both] [--mapped-rules FILE] [--sgconfig FILE] PATH

Measure SlopCodeBench-style code sloppiness.

Modes:
  raw     Run scb-check report (clone + bundled Python ast-grep + erosion).
  mapped  Run ast-grep rules for LANG and compute mapped flagged LOC/verbosity.
  both    Run raw and mapped and emit one JSON object.

Supported bundled mapped rules:
  zig     Uses Tree-sitter custom-language ast-grep config and mechanical Zig ports.

Dependencies:
  scb-check via uvx, ast-grep, tree-sitter, gcc, git, jq, python3.
  In this repository: run inside `devenv shell`.
EOF
}

language="auto"
mode="both"
mapped_rules=""
sgconfig=""
path=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --language|-l) language="${2:?missing language}"; shift 2 ;;
    --mode|-m) mode="${2:?missing mode}"; shift 2 ;;
    --mapped-rules) mapped_rules="${2:?missing rules file}"; shift 2 ;;
    --sgconfig) sgconfig="${2:?missing sgconfig}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) path="$1"; shift ;;
  esac
done

if [ -z "$path" ]; then
  usage >&2
  exit 2
fi
case "$mode" in raw|mapped|both) ;; *) echo "invalid --mode: $mode" >&2; exit 2 ;; esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd -- "$script_dir/.." && pwd)"
path_abs="$(cd -- "$path" && pwd)"

raw_json="{}"
if [ "$mode" = raw ] || [ "$mode" = both ]; then
  raw_tmp="$(mktemp)"
  # scb-check exits 1 when it finds slop; keep the report.
  if uvx --from git+https://github.com/gabeorlanski/scb-check scb-check check --report --include-all "$path_abs" >"$raw_tmp"; then
    :
  else
    status=$?
    if [ "$status" -ne 1 ]; then
      cat "$raw_tmp" >&2 || true
      exit "$status"
    fi
  fi
  raw_json="$(cat "$raw_tmp")"
  rm -f "$raw_tmp"
fi

mapped_json="{}"
if [ "$mode" = mapped ] || [ "$mode" = both ]; then
  if [ "$language" = auto ]; then
    echo "--language is required for mapped mode" >&2
    exit 2
  fi

  if [ -z "$mapped_rules" ]; then
    mapped_rules="$skill_dir/rules/$language/mechanical.yml"
  fi
  if [ ! -f "$mapped_rules" ]; then
    echo "mapped rule file not found: $mapped_rules" >&2
    exit 2
  fi

  if [ -z "$sgconfig" ]; then
    case "$language" in
      zig) sgconfig="$($script_dir/prepare-zig-ast-grep.sh)" ;;
      *) sgconfig="" ;;
    esac
  fi

  hits_tmp="$(mktemp)"
  if [ -n "$sgconfig" ]; then
    ast-grep scan -c "$sgconfig" -r "$mapped_rules" --json=stream "$path_abs" >"$hits_tmp"
  else
    ast-grep scan -r "$mapped_rules" --json=stream "$path_abs" >"$hits_tmp"
  fi

  mapped_json="$(python3 "$script_dir/summarize_astgrep_hits.py" "$hits_tmp" "$raw_json" "$language" "$mapped_rules")"
  rm -f "$hits_tmp"
fi

python3 - "$mode" "$raw_json" "$mapped_json" <<'PY'
import json, sys
mode=sys.argv[1]
raw=json.loads(sys.argv[2])
mapped=json.loads(sys.argv[3])
if mode == 'raw':
    print(json.dumps(raw, sort_keys=True))
elif mode == 'mapped':
    print(json.dumps(mapped, sort_keys=True))
else:
    print(json.dumps({'raw': raw, 'mapped': mapped}, sort_keys=True))
PY
