#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd -- "$script_dir/.." && pwd)"
cache_base="${XDG_CACHE_HOME:-$HOME/.cache}"
cache_dir="${SCB_SKILL_CACHE_DIR:-$cache_base/slopcode-measurements}"
parser_dir="$cache_dir/tree-sitter-zig"
lib_path="$cache_dir/zig.so"
config_path="$cache_dir/sgconfig.zig.yml"
repo_url="${TREE_SITTER_ZIG_REPO:-https://github.com/tree-sitter-grammars/tree-sitter-zig.git}"

mkdir -p "$cache_dir"

if [ ! -d "$parser_dir/.git" ]; then
  rm -rf "$parser_dir"
  git clone --depth 1 "$repo_url" "$parser_dir" >/dev/null
fi

if [ ! -f "$lib_path" ]; then
  (cd "$parser_dir" && tree-sitter build --output "$lib_path") >/dev/null
fi

cat > "$config_path" <<YAML
customLanguages:
  zig:
    libraryPath: $lib_path
    extensions: [zig]
    expandoChar: _
YAML

printf '%s\n' "$config_path"
