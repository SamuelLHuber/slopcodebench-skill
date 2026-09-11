---
name: slopcode-measurements
description: Measure SlopCodeBench-style code sloppiness for a repository: raw scb-check metrics (verbosity, erosion, clone LOC, Python rules) plus mapped ast-grep rule metrics for a requested language such as Zig. Use when asked to run code slop/sloppiness/verbosity/erosion measurements, port Python slop rules to another language, or compare raw versus language-mapped slop scores.
compatibility: Requires either this skill workspace's devenv shell or installed dependencies: uv/uvx, scb-check runtime, ast-grep, tree-sitter, gcc, git, jq, python3. Bundled mapped rules currently include Zig.
---

# SlopCodeBench Measurements

Use this skill to measure code sloppiness using the metrics described in the Earendil/SlopCodeBench post:

- **Raw**: run `scb-check` directly. This reports verbosity, erosion, cognitive erosion, clone LOC, Python AST-grep rule LOC, and syntax/function summaries.
- **Mapped**: run ast-grep rules mapped to a requested language. This is for non-Python source where Python rules must be translated "in spirit" or where a language-specific rule pack exists.
- **Both**: run raw and mapped, then report a combined JSON object.

Always clearly state that mapped rules are language/rule-pack dependent and are not identical to the original Python rules unless the rule pack says so.

## Paths

Resolve paths relative to this skill directory:

- Main runner: `scripts/measure.sh`
- Devenv wrapper: `scripts/run-with-devenv.sh`
- Zig parser setup: `scripts/prepare-zig-ast-grep.sh`
- Zig mapped rules: `rules/zig/mechanical.yml`
- Devenv workspace root: three directories above this `SKILL.md` (`../../..`)

## Dependency setup

Preferred, reproducible path:

```bash
cd ~/git/playground/slopcodebench
devenv shell
```

Then run the scripts normally.

One-shot without entering a shell:

```bash
~/git/playground/slopcodebench/skills/slopcode-measurements/scripts/run-with-devenv.sh --language zig --mode both /path/to/repo
```

If the user already has dependencies installed, skip devenv and run:

```bash
/path/to/skill/scripts/measure.sh --language zig --mode both /path/to/repo
```

Required commands for direct use:

```text
uvx, ast-grep, tree-sitter, gcc, git, jq, python3
```

## Commands

Raw only:

```bash
scripts/measure.sh --mode raw /path/to/repo
```

Mapped only:

```bash
scripts/measure.sh --language zig --mode mapped /path/to/repo
```

Both raw and mapped:

```bash
scripts/measure.sh --language zig --mode both /path/to/repo
```

Custom language/rules:

```bash
scripts/measure.sh \
  --language mylang \
  --mode mapped \
  --sgconfig /path/to/sgconfig.yml \
  --mapped-rules /path/to/mylang-rules.yml \
  /path/to/repo
```

## Output interpretation

`raw` output is the JSON report from `scb-check`:

- `verbosity`: `(clone LOC ∪ AST-grep flagged LOC ∪ structural rule LOC) / total LOC`
- `erosion`: high-cyclomatic-complexity function mass / total function mass
- `cog_erosion`: high-cognitive-complexity function mass / total cognitive mass
- `clone_loc`, `ast_grep_flagged_loc`, `verbosity_flagged_loc`, `total_loc`

`mapped` output includes:

- `ast_grep_hits`: total mapped rule matches
- `mapped_ast_grep_unique_loc`: unique source lines touched by mapped ast-grep hits
- `mapped_ast_grep_pct`: mapped unique LOC divided by raw `total_loc`, when raw was also run
- `raw_plus_mapped_verbosity_upper_bound`: `(raw verbosity_flagged_loc + mapped unique LOC) / total_loc`; this is an upper bound because it does not currently deduplicate against raw flagged LOC line-by-line
- `top_rules`, `top_files`

## Zig support

The Zig workflow uses ast-grep custom language support:

1. `scripts/prepare-zig-ast-grep.sh` clones `tree-sitter-grammars/tree-sitter-zig` into the skill cache.
2. It builds a dynamic parser library with `tree-sitter build --output zig.so`.
3. It writes a custom `sgconfig.yml` registering Zig with `expandoChar: _`.
4. `measure.sh` scans using `rules/zig/mechanical.yml`.

The Zig mechanical rule pack is a one-to-one port of the Python slop rule IDs where possible:

- Python-specific rules with no direct Zig analogue are inert placeholders and carry `metadata.no_direct_zig_equivalent: true`.
- Active rules translate concepts such as boolean-literal comparisons, null/optional guard ladders, `.len` comparisons, `for (0..x.len)`, repeated validation calls, append loops, redundant trailing `continue`, nested `if`, wrapper functions, string concatenation, and redundant cast chains.
- The pack is intentionally mechanical, not a curated Zig style guide.

## Agent workflow

1. Identify the repository path and requested language(s). If unspecified and the repo is mostly Zig, use `--language zig`.
2. Prefer `scripts/run-with-devenv.sh` unless already inside `devenv shell` or dependencies are known installed.
3. Capture JSON output to a temp file for inspection:

   ```bash
   scripts/run-with-devenv.sh --language zig --mode both /path/to/repo > /tmp/slopcode-report.json
   jq . /tmp/slopcode-report.json
   ```

4. Report:
   - raw verbosity, erosion, cognitive erosion
   - LOC, files scanned, clone LOC, AST-grep LOC
   - mapped hits, mapped unique LOC, top mapped rules
   - caveats: parser failures, rule-pack noise, raw-plus-mapped upper-bound behavior

5. Do not edit the target repository unless the user explicitly asks for fixes.
