#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
workspace="$(cd -- "$script_dir/../../.." && pwd)"

if ! command -v devenv >/dev/null 2>&1; then
  echo "devenv is not installed. Install dependencies yourself or run scripts/measure.sh in an environment with uvx, ast-grep, tree-sitter, gcc, git, jq, python3." >&2
  exit 127
fi

cd "$workspace"
exec devenv shell "$script_dir/measure.sh" "$@"
