# comptime_fold_typed_payload — RED repro

## Form
Minimal tagged-union program: comptime-folded `@intCast(i64, 42)` used as payload
via explicit struct-init `Value{ .Int = @intCast(i64, 42) }`, followed by switch
read-back and `__bootstrap_print_int` of the recovered value.

## Expected output
`42`

## WITH-patch emission (current binary, Task 3 retype patch present)
```
zT_1.payload.Int._0 = zT_2;
```
GCC compiles cleanly. Prints `42`.

## WITHOUT-patch emission (temporary experiment, fully reverted)
```
zT_1.payload = zT_2;
```
GCC error: `incompatible types when assigning to type 'union <anonymous>' from type 'unsigned int'`

## Root cause
- `lower.zig:2262-2266` — the generic `comptime_values` fold path mints the folded
  temp as `nextTemp(TYPE_USIZE)` + `int_const`, ignoring the value's actual type
  (should be i64 when folded from `@intCast(i64, 42)`).
- `lower.zig:~2627-2629` — the Task 3 retype PATCH overwrites the hoisted-temp
  `type_id` to the variant field type, masking the upstream mistype.

## Prior art — what MUST remain TYPE_USIZE / TYPE_INT_LIT
Per `.opencode/plans/2026-07-05-canonical-type-arg-resolution.md` and
`.opencode/plans/2026-07-05-sema-sizeof-intlit.md`:
- `@sizeOf` / `@alignOf` results: sema types them as `TYPE_INT_LIT` (transient);
  the fold concretizes to `TYPE_USIZE` via `int_const` (protective — keeps the
  emitted value at correct width; never want bare `INT_LIT` in emitter).
- `@ptrToInt` at `lower.zig:2253-2260` — uses `TYPE_USIZE` (correct: pointer→integer
  yields usize).
- The `comptime_values` fold path (lines 2262-2266) is the GENERAL comptime-fold
  path. These usize-legitimate folds must NOT be disturbed by any fix.
- Any fix must be NARROW: only type the fold by the cast's target type when the fold
  originated from an `@intCast`/cast with a resolvable non-usize target.

## Cross-reference
- `repro/tagged_union_payload/main.zig` — the parent repro that exercises the same
  pattern (but currently GREEN because of the Task 3 retype patch).
