# Methodology

## Measurement layers

1. **Raw baseline**: pinned `scb-check==0.1.3`.
   - Reports SlopCodeBench-style `verbosity`, `erosion`, and `cog_erosion`.
   - Verbosity is clone lines unioned with bundled AST-grep slop-rule lines, divided by LOC.
   - Bundled AST-grep slop rules are Python-origin rules. Parser/LOC/clone/complexity language coverage is whatever this pinned `scb-check` release supports.

2. **Mapped language scan**: ast-grep rule packs under `rules/<language>/mechanical.yml`.
   - These are mechanical, language-specific translations of common slop motifs.
   - They are not calibrated replacements for `scb-check`'s Python rules.
   - They report mapped ast-grep counts and mapped flagged LOC over the requested language's files.

## Bundled mapped languages

- Python: original bundled `scb-check` Python slop rules, concatenated for direct ast-grep mapped scans.
- JavaScript / TypeScript / TSX
- Rust
- Go
- Java
- C / C++
- C#
- Swift
- Kotlin
- Ruby
- PHP
- Zig, via ast-grep custom language and Tree-sitter Zig.

## Mapping principles

Rules are ported by intent, not by claiming semantic equivalence. Common motifs include:

- Boolean literal comparisons.
- Null/nil/optional guard ladders.
- Length/size/count checks against zero.
- Index loops over collection length.
- If/else branches returning boolean literals.
- Nested ifs and repeated guard clauses.
- Repeated validation calls.
- Append/push/add loops and consecutive append calls.
- String concatenation in loops.
- Thin identity wrapper functions.
- String equality dispatch chains.
- Decorative banner comments.
- Language-specific panic/sentinel shortcuts where obvious (`unwrap`, `!!`, broad rescue/catch, etc.).

## Reporting semantics

Mapped output reports both:

- `mapped_ast_grep_unique_start_loc`: unique start lines of matches. This is conservative and stable for broad AST spans.
- `mapped_ast_grep_unique_span_loc`: every line covered by matched AST spans. This better approximates flagged LOC but can be noisy when rules match large blocks.

`raw_plus_mapped_verbosity_upper_bound` is deliberately `null`: a scientifically valid combined verbosity requires a line-level union across clone lines, raw AST-grep lines, structural-rule lines, and mapped-rule lines. Raw `scb-check` JSON does not expose those line sets.

## Exclusions

The wrapper excludes generated/vendor/cache directories by default:

```text
.git, .zig-cache, zig-out, node_modules, out, .devenv, .cache
```

Add repeated `--exclude GLOB` flags for project-specific generated trees. Prefer measuring intended source directories when a monorepo vendors large external repositories.
