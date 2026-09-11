---
name: slopcode-measurements
description: Measure SlopCodeBench-style code sloppiness for a repository: raw scb-check metrics (verbosity, erosion, clone LOC, Python rules) plus mapped ast-grep rule metrics for a requested language such as Zig. Use when asked to run code slop/sloppiness/verbosity/erosion measurements, port Python slop rules to another language, or compare raw versus language-mapped slop scores.
compatibility: Requires either this skill workspace's devenv shell or installed dependencies: uv/uvx, ast-grep, tree-sitter, gcc, git, jq, and python3.12+ for raw scb-check mode. Bundled mapped rules include common languages plus Zig via custom Tree-sitter.
---

# SlopCodeBench Measurements

Use this skill to measure code sloppiness using the metrics described in the Earendil/SlopCodeBench post:

- **Raw**: run pinned `scb-check==0.1.3` directly. This reports verbosity, erosion, cognitive erosion, clone LOC, bundled Python AST-grep rule LOC, and syntax/function summaries for languages supported by that release.
- **Mapped**: run ast-grep rules mapped to a requested language. This is for non-Python source where Python rules must be translated "in spirit" or where a language-specific rule pack exists.
- **Both**: run raw and mapped, then report a combined JSON object.

Always clearly state that mapped rules are language/rule-pack dependent and are not identical to the original Python rules unless the rule pack says so.

## Paths

Resolve paths relative to this skill directory:

- Main runner: `scripts/measure.sh`
- Zig parser setup: `scripts/prepare-zig-ast-grep.sh`
- Zig mapped rules: `rules/zig/mechanical.yml`
- Devenv workspace root: three directories above this `SKILL.md` (`../../..`)
- Parser cache: `${SCB_SKILL_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/slopcode-measurements}`

## Dependency setup

Preferred, reproducible path using the upstream devenv CLI. Use `--` before the measured command so `devenv shell` stops parsing flags:

```bash
cd ~/git/playground/slopcodebench
./devenv.sh -- skills/slopcode-measurements/scripts/measure.sh --language zig --mode both /path/to/repo
```

Or enter the shell first with `./devenv.sh`, then run scripts normally.

If the user already has dependencies installed, skip devenv and run:

```bash
/path/to/skill/scripts/measure.sh --language zig --mode both /path/to/repo
```

Required commands for direct use:

```text
uvx, ast-grep, tree-sitter, gcc, git, jq, python3.12+ for raw mode
```

## Commands

Raw only:

```bash
scripts/measure.sh --mode raw /path/to/repo
```

Mapped only:

```bash
scripts/measure.sh --language typescript --mode mapped /path/to/repo
scripts/measure.sh --language zig --mode mapped /path/to/repo
```

Bundled mapped languages: `python`, `javascript`, `typescript`, `tsx`, `rust`, `go`, `java`, `c`, `cpp`, `csharp`, `swift`, `kotlin`, `ruby`, `php`, `zig`. Aliases: `py`, `js`, `ts`, `rs`, `c++`, `cs`.

Both raw and mapped:

```bash
scripts/measure.sh --language zig --mode both /path/to/repo
```

Default excludes applied to both raw and mapped scans:

```text
.git, .zig-cache, zig-out, node_modules, out, .devenv, .cache
```

Add more with repeated `--exclude GLOB` flags.

Custom language/rules beyond the bundled packs:

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
- `mapped_total_loc`: approximate SLOC for files with the requested language extension after excludes
- `mapped_ast_grep_unique_start_loc`: unique start lines of mapped ast-grep hits
- `mapped_ast_grep_unique_span_loc` / `mapped_ast_grep_unique_loc`: unique full-span lines touched by mapped ast-grep hits
- `mapped_ast_grep_pct`: mapped span LOC divided by mapped language LOC; compare only within the same language/rule pack
- `unique_rule_line_pairs`: unique `(file, start line, rule)` triples; useful because mechanical mappings can intentionally map several Python source rules to the same language pattern
- `raw_plus_mapped_verbosity_upper_bound`: currently null; true combined verbosity requires line-level union with raw findings, which raw `scb-check` JSON does not expose
- `top_rules`, `top_files`

## Zig support

The Zig workflow uses ast-grep custom language support:

1. `scripts/prepare-zig-ast-grep.sh` clones `tree-sitter-grammars/tree-sitter-zig` into the user cache by default, not into the skill directory.
2. It builds a dynamic parser library with `tree-sitter build --output zig.so`.
3. It writes a custom `sgconfig.yml` registering Zig with `expandoChar: _`.
4. `measure.sh` scans using `rules/zig/mechanical.yml`.

See `docs/methodology.md` for mapped-rule methodology and cross-language caveats. Common-language mapped packs use broad ast-grep regex/AST hybrids for coverage; Zig is the most literal Python-rule port because custom Tree-sitter support was the original target.

The Zig mechanical rule pack is a one-to-one port of the Python slop rule IDs where possible:

- Python-specific rules with no direct Zig analogue are inert placeholders and carry `metadata.no_direct_zig_equivalent: true`.
- Active rules translate concepts such as boolean-literal comparisons, null/optional guard ladders, `.len` comparisons, `for (0..x.len)`, repeated validation calls, append loops, redundant trailing `continue`, nested `if`, wrapper functions, string concatenation, and redundant cast chains.
- The pack is intentionally mechanical, not a curated Zig style guide.

## Agent workflow

1. Identify the repository path and requested language(s). If unspecified and the repo is mostly Zig, use `--language zig`.
2. Prefer the upstream devenv command unless already inside `devenv shell` or dependencies are known installed.
3. Capture JSON output to a temp file for inspection:

   ```bash
   cd ~/git/playground/slopcodebench
   ./devenv.sh -- skills/slopcode-measurements/scripts/measure.sh --language zig --mode both /path/to/repo > /tmp/slopcode-report.json
   jq . /tmp/slopcode-report.json
   ```

4. Report:
   - raw verbosity, erosion, cognitive erosion
   - LOC, files scanned, clone LOC, AST-grep LOC
   - mapped hits, mapped unique LOC, top mapped rules
   - caveats: parser failures, rule-pack noise, raw-plus-mapped upper-bound behavior

5. Do not edit the target repository unless the user explicitly asks for fixes.
