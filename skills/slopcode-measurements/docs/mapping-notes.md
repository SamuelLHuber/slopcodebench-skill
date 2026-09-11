# Mapping notes

The bundled Zig rule pack is a mechanical, conservative translation of the Python
`scb-check` slop rules. It preserves the original Python rule IDs as
`metadata.source_python_rule` and prefixes active rule IDs with `zig-`.

## Categories with direct-ish Zig ports

- Boolean literal comparisons: `x == true`, `x == false`, etc.
- Optional/null guards: `x == null`, `x != null`, guard-return/continue/break patterns.
- Length checks: `x.len == 0`, `x.len > 0`, etc.
- Index loops: `for (0..x.len) |i|`.
- Manual min/max-ish `if` expressions using comparisons.
- Repeated neighboring guards.
- Repeated `validate*` / `verify*` calls.
- Append/put loops and consecutive append calls.
- Wrapper functions that only return another call.
- Redundant cast chains such as nested `@as`.
- Decorative section banner comments.

## Categories left inert

Many Python rules have no safe mechanical Zig analogue and are emitted as inert
placeholders (`regex: 'a^'`) with `metadata.no_direct_zig_equivalent: true`:

- Python dict/list/set comprehensions.
- Python `typing`/`Any`/dataclasses.
- Python exceptions and `try/except` idioms.
- Python truthiness-only rewrites.
- Python `json`, `os.walk`, lambda, f-string, and string method idioms.

## Scoring caveat

Mapped verbosity currently reports mapped ast-grep unique LOC and an upper-bound
combined verbosity. It does not line-by-line union mapped LOC with raw scb-check
clone/Python AST-grep LOC because raw scb-check JSON does not expose the raw line
sets. Treat `raw_plus_mapped_verbosity_upper_bound` as conservative/noisy.
