# module_as_value — observability repro for Fix A (module-ident branch)

## zig0 oracle
zig0 accepts bare-module-in-value-position silently (rc=0, no error or warning).
Generated C compiles and runs.

## Expected zig1 behavior
- Compilable C (gcc rc=0, no undeclared variable)
- VOID temp (TYPE_VOID) — no C decl emitted
- Module branch in lower.zig ident_expr IS instrumented with WARN_3012
  ("module used as value expression"), but the var_decl handler short-circuits
  before calling lowerExpr for module-typed init expressions (lower.zig:3684-3685),
  so the warning does NOT fire for this specific var-decl repro pattern.
  The branch fires when the ident_expr handler is reached in non-var_decl
  contexts (e.g. statement expressions, return expressions).

## Corpus classification
OK (compilable C, gcc rc=0). Warning diagnostic is non-fatal when it fires;
not triggered in this var-decl repro due to upstream short-circuit.
