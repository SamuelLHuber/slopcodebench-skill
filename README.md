# SlopCodeBench-style Code Sloppiness Measurements

This workspace provides a reproducible protocol and agent skill for measuring code sloppiness using the metrics described by Earendil and SlopCodeBench.

## References

- Earendil blog: <https://earendil.com/posts/measuring-code-sloppiness/>
- SlopCodeBench paper: <https://arxiv.org/abs/2603.24755>
- `scb-check`: <https://github.com/gabeorlanski/scb-check>
- ast-grep custom languages: <https://ast-grep.github.io/advanced/custom-language>
- Zig Tree-sitter grammar: <https://github.com/tree-sitter-grammars/tree-sitter-zig>

## Metrics

Let `LOC` be logical source lines of code.

- **Verbosity**: `|AST-grep flagged lines ∪ clone lines| / LOC`
- **Erosion**: `sum(mass(f) for CC(f) > 10) / sum(mass(f) for all f)`
- **Mass**: `CC(f) * sqrt(SLOC(f))`
- **Cognitive erosion**: same as erosion, using cognitive complexity instead of cyclomatic complexity.

Raw mode uses pinned `scb-check==0.1.3`. Its bundled AST-grep slop rules are Python-specific; its LOC/clone/parser/complexity support depends on that `scb-check` release and may include non-Python languages.

## Protocol

1. Run commands through the reproducible tool environment from this repository. Use `--` before the command so `devenv shell` stops parsing options:

   ```sh
   cd ~/git/playground/slopcodebench
   ./devenv.sh -- skills/slopcode-measurements/scripts/measure.sh --mode raw /path/to/repo
   ```

   Or enter the shell first with `./devenv.sh` and run the scripts normally.

2. Run raw measurements from inside `devenv shell`:

   ```sh
   skills/slopcode-measurements/scripts/measure.sh --mode raw /path/to/repo
   ```

   This is the direct `scb-check` report. For Python, it includes bundled Python slop rules. For supported non-Python languages, it still includes LOC, clones, erosion, and cognitive erosion, but not language-specific slop rules unless `scb-check` supports them.

3. Run mapped language measurements:

   ```sh
   skills/slopcode-measurements/scripts/measure.sh --language zig --mode mapped /path/to/repo
   ```

   Mapped mode runs ast-grep rules translated to the target language. For Zig, the script builds and registers a Tree-sitter Zig parser as an ast-grep custom language, then runs `rules/zig/mechanical.yml`.

4. Run both together through devenv:

   ```sh
   ./devenv.sh -- skills/slopcode-measurements/scripts/measure.sh --language zig --mode both /path/to/repo > report.json
   ```

## Default excludes

The runner excludes common generated/vendor/cache directories from both raw and mapped scans:

```text
.git, .zig-cache, zig-out, node_modules, out, .devenv, .cache
```

Add more excludes with repeated `--exclude GLOB` flags.

## Output

- `raw`: canonical `scb-check` JSON.
- `mapped.ast_grep_hits`: number of mapped rule matches.
- `mapped.mapped_total_loc`: approximate SLOC for files with the requested language extension after excludes.
- `mapped.mapped_ast_grep_unique_start_loc`: unique starting lines of mapped matches; useful as a conservative sanity check.
- `mapped.mapped_ast_grep_unique_span_loc`: unique full-span lines covered by mapped matches; closer to flagged-line semantics but noisy for large AST matches.
- `mapped.unique_rule_line_pairs`: unique `(file, start line, rule)` triples; useful because mechanical mappings can intentionally map several Python source rules to the same language pattern.
- `mapped.raw_plus_mapped_verbosity_upper_bound`: currently `null`; the true combined SlopCodeBench verbosity requires line-level union of raw and mapped findings, which raw `scb-check` JSON does not expose.

## Scientific caveats

- Raw `scb-check==0.1.3` is the baseline measurement; mapped rules are experimental and rule-pack dependent.
- Mechanical translations preserve the *intent* of Python rules where possible, but are not semantically identical across languages.
- Some Python rules have no direct Zig analogue and are inert placeholders in the Zig pack.
- Tree-sitter parser failures or unsupported syntax must be reported with results.
- Do not compare mapped scores across languages unless the rule packs have been calibrated against the same corpus and reviewed for equivalent sensitivity.
- By default the runner excludes `.git`, `.zig-cache`, `zig-out`, `node_modules`, `out`, `.devenv`, and `.cache`; pass a source subdirectory or additional `--exclude` flags if generated files live elsewhere.
