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

`scb-check` computes clone lines, function complexity/mass, and bundled Python AST-grep slop-rule lines.

## Protocol

1. Enter the reproducible tool environment:

   ```sh
   cd ~/git/playground/slopcodebench
   ./devenv.sh
   ```

2. Run raw measurements:

   ```sh
   skills/slopcode-measurements/scripts/measure.sh --mode raw /path/to/repo
   ```

   This is the direct `scb-check` report. For Python, it includes bundled Python slop rules. For supported non-Python languages, it still includes LOC, clones, erosion, and cognitive erosion, but not language-specific slop rules unless `scb-check` supports them.

3. Run mapped language measurements:

   ```sh
   skills/slopcode-measurements/scripts/measure.sh --language zig --mode mapped /path/to/repo
   ```

   Mapped mode runs ast-grep rules translated to the target language. For Zig, the script builds and registers a Tree-sitter Zig parser as an ast-grep custom language, then runs `rules/zig/mechanical.yml`.

4. Run both together:

   ```sh
   skills/slopcode-measurements/scripts/measure.sh --language zig --mode both /path/to/repo > report.json
   ```

## Output

- `raw`: canonical `scb-check` JSON.
- `mapped.ast_grep_hits`: number of mapped rule matches.
- `mapped.mapped_ast_grep_unique_start_loc`: unique starting lines of mapped matches; useful as a conservative sanity check.
- `mapped.mapped_ast_grep_unique_span_loc`: unique full-span lines covered by mapped matches; closer to flagged-line semantics but noisy for large AST matches.
- `mapped.raw_plus_mapped_verbosity_upper_bound`: `(raw verbosity_flagged_loc + mapped span LOC) / raw total_loc`; an upper bound because raw and mapped line sets are not deduplicated together.

## Scientific caveats

- Raw `scb-check` is the baseline measurement; mapped rules are experimental and rule-pack dependent.
- Mechanical translations preserve the *intent* of Python rules where possible, but are not semantically identical across languages.
- Some Python rules have no direct Zig analogue and are inert placeholders in the Zig pack.
- Tree-sitter parser failures or unsupported syntax must be reported with results.
- Do not compare mapped scores across languages unless the rule packs have been calibrated against the same corpus and reviewed for equivalent sensitivity.
