#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: measure.sh [--language LANG] [--mode raw|mapped|both] [--mapped-rules FILE] [--sgconfig FILE] [--exclude GLOB]... PATH

Measure SlopCodeBench-style code sloppiness.

Modes:
  raw     Run scb-check report (clone + bundled Python ast-grep + erosion).
  mapped  Run ast-grep rules for LANG and compute mapped flagged LOC/verbosity.
  both    Run raw and mapped and emit one JSON object.

Supported bundled mapped rules:
  python, javascript, typescript, tsx, rust, go, java, c, cpp, csharp,
  swift, kotlin, ruby, php, zig. Zig uses Tree-sitter custom-language setup.

Dependencies:
  scb-check via uvx, ast-grep, tree-sitter, gcc, git, jq, python3.12+.
  In this repository: run with `devenv shell -- ...` or from an entered devenv shell.

Default excludes:
  .git, .zig-cache, zig-out, node_modules, out, .devenv, .cache
EOF
}

json_extract_last_object() {
  python3 - "$1" <<'PY'
import json
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
decoder = json.JSONDecoder()
last = None
index = 0
while True:
    start = text.find("{", index)
    if start == -1:
        break
    try:
        obj, end = decoder.raw_decode(text[start:])
    except json.JSONDecodeError:
        index = start + 1
        continue
    last = obj
    index = start + end
if last is None:
    raise SystemExit("no JSON object found in command output")
print(json.dumps(last, sort_keys=True))
PY
}

language="auto"
mode="both"
mapped_rules=""
sgconfig=""
path=""
exclude_args=()
default_excludes=(
  ".git"
  ".git/**"
  "**/.git/**"
  ".zig-cache"
  ".zig-cache/**"
  "**/.zig-cache/**"
  "zig-out"
  "zig-out/**"
  "**/zig-out/**"
  "node_modules"
  "node_modules/**"
  "**/node_modules/**"
  "out"
  "out/**"
  "**/out/**"
  ".devenv"
  ".devenv/**"
  "**/.devenv/**"
  ".cache"
  ".cache/**"
  "**/.cache/**"
)

while [ "$#" -gt 0 ]; do
  case "$1" in
    --language|-l) language="${2:?missing language}"; shift 2 ;;
    --mode|-m) mode="${2:?missing mode}"; shift 2 ;;
    --mapped-rules) mapped_rules="${2:?missing rules file}"; shift 2 ;;
    --sgconfig) sgconfig="${2:?missing sgconfig}"; shift 2 ;;
    --exclude) exclude_args+=("${2:?missing exclude glob}"); shift 2 ;;
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

case "$language" in
  py) language="python" ;;
  js) language="javascript" ;;
  ts) language="typescript" ;;
  rs) language="rust" ;;
  c++) language="cpp" ;;
  cs) language="csharp" ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd -- "$script_dir/.." && pwd)"
if [ -d "$path" ]; then
  path_abs="$(cd -- "$path" && pwd)"
elif [ -f "$path" ]; then
  path_dir="$(cd -- "$(dirname -- "$path")" && pwd)"
  path_abs="$path_dir/$(basename -- "$path")"
else
  echo "path does not exist: $path" >&2
  exit 2
fi

all_excludes=("${default_excludes[@]}" "${exclude_args[@]}")
exclude_globs=()
for pattern in "${all_excludes[@]}"; do
  exclude_globs+=("--globs" "!$pattern")
done

raw_json="{}"
if [ "$mode" = raw ] || [ "$mode" = both ]; then
  raw_tmp="$(mktemp)"
  raw_clean_tmp="$(mktemp)"
  raw_config_tmp="$(mktemp --suffix=.toml)"
  {
    echo 'exclude = ['
    for pattern in "${all_excludes[@]}"; do
      printf '  "%s",\n' "$pattern"
    done
    echo ']'
  } >"$raw_config_tmp"

  # scb-check can emit logs/warnings before JSON; capture both streams and extract the final JSON object.
  if uvx --from scb-check==0.1.3 scb-check check --config "$raw_config_tmp" --report --include-all "$path_abs" >"$raw_tmp" 2>&1; then
    raw_status=0
  else
    raw_status=$?
  fi
  if json_extract_last_object "$raw_tmp" >"$raw_clean_tmp" 2>/dev/null; then
    raw_json="$(cat "$raw_clean_tmp")"
  else
    # Keep stdout JSON-valid even when raw scb-check cannot analyze the target
    # (for example, a non-Python repository with generated Python dirs excluded).
    raw_json="$(python3 - "$raw_status" "$raw_tmp" <<'PY'
import json
import sys
from pathlib import Path
status = int(sys.argv[1])
message = Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace").strip()
print(json.dumps({"error": "scb-check failed", "status": status, "message": message}, sort_keys=True))
PY
)"
  fi
  rm -f "$raw_tmp" "$raw_clean_tmp" "$raw_config_tmp"
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
  sg_status=0
  if [ -n "$sgconfig" ]; then
    ast-grep scan -c "$sgconfig" -r "$mapped_rules" "${exclude_globs[@]}" --json=stream "$path_abs" >"$hits_tmp" || sg_status=$?
  else
    ast-grep scan -r "$mapped_rules" "${exclude_globs[@]}" --json=stream "$path_abs" >"$hits_tmp" || sg_status=$?
  fi
  sg_status="${sg_status:-0}"
  # ast-grep may return 1 for no matches; anything above that is a real failure.
  if [ "$sg_status" -gt 1 ]; then
    cat "$hits_tmp" >&2 || true
    rm -f "$hits_tmp"
    exit "$sg_status"
  fi

  mapped_json="$(python3 "$script_dir/summarize_astgrep_hits.py" "$hits_tmp" "$raw_json" "$language" "$mapped_rules" "$path_abs" "${all_excludes[@]}")"
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
