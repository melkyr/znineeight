# Tagged Union Slice-Payload Construction Bug — RED Reproduction

## Expected Behavior
Program should print `5` (length of "hello").

## Actual Behavior (HEAD a307d35a, build sf/build/out_release/zig1)

- `zig1 --dump-c89` → rc=0
- `gcc -m32 -std=c89` → rc=1
- gcc error:
  ```
  /tmp/tsp.c:127:21: error: incompatible types when assigning to type 'union <anonymous>' from type 'zT_8F083A69_Slice_zT_0B42B2F8_u'
  ```
- Bare `.payload =` in emitted C at line 127:
  ```c
  zT_36.payload = s;
  ```
  (also line 128: `zT_38.data.payload = zT_36;` — outer error-union wrap)

## Root Causes

### A. `semantic_analyzer.zig:1602` — Slice Type Resolution
The slice expression `self.input[start..self.pos]` correctly resolves to a slice type via `typeRegistryGetOrCreateSlice`. The semantic analyzer returns the correct type ID. The lowerer then uses this type when constructing the tagged union `Tok{ .Sym = s }`, but emits a bare `.payload = s` instead of `.payload.Sym._0 = s` in the generated C.

### B. Commit `cce4b70f` — Retype Patch Removal
```
fix(lower): type comptime-folded cast value by target (was TYPE_USIZE); remove tagged-union retype patch
```
This commit removed a retype patch in `lower.zig` that previously masked the issue by overwriting `hoisted_temps[].type_id` to match the variant field type. Without this patch, the underlying bare `.payload = ` emission is exposed, causing the gcc type mismatch on slice payloads.

## Cross-References
- `examples/zig0/lisp_interpreter_diag/token.zig:61` — `return Token{ .Symbol = sym }` — the original pattern that this repro mirrors
- `.superpowers/sdd/comptime-fold-task-10-report.md` §2.1 — analysis of tagged-union payload emission and the (now-removed) retype patch
