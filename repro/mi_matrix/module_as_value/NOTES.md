# module_as_value — observability repro for Fix A (module-ident branch)

## zig0 oracle
zig0 accepts bare-module-in-value-position silently (rc=0, no error or warning).
Generated C compiles and runs.

## Expected zig1 behavior
- Compilable C (gcc rc=0, no undeclared variable)
- VOID temp (TYPE_VOID) — no C decl emitted
- Module branch in lower.zig ident_expr IS instrumented with WARN_3023
  ("module used as value expression").
- warning[3023] fires EXACTLY ONCE from `_ = h;` — the `_ =` discard pattern
  reaches the ident_expr handler and triggers the diagnostic.
- The `var v = h;` pattern still short-circuits before calling lowerExpr
  for module-typed init expressions (lower.zig:3684-3685), so no warning
  from that line.

## Corpus classification
OK (compilable C, gcc rc=0). Warning diagnostic is non-fatal;
one warning[3023] emitted from `_ = h;`.
