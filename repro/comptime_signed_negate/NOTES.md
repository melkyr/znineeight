# repro: comptime_signed_negate

## Form
```zig
extern fn __bootstrap_print_int(x: i32) void;

pub fn main() void {
    var r: i32 = @intCast(i32, -1);
    __bootstrap_print_int(r);
}
```

`@intCast(i32, -1)` — negative literal negate-fold + cast.

## Expected correct output
`-1`

## Actual (RED, on HEAD 39b8c14b)
zig1 **itself aborts at compile time** (same class as `repro/negative_intcast_ice`):

- `sf/build/out_release/zig1 --dump-c89 repro/comptime_signed_negate/main.zig` → dump **rc=134** (Aborted / core dumped).
- Emits `PANIC: integer overflow in @intCast at sf/build/out_release/zig_runtime.h:107`.
- No usable C emitted.

## Root cause (verified read-only)
- `sf/src/comptime_eval.zig:103-108` — the `negate` fold computes `nv = @intCast(u64,0) - v` in `u64`, so `-1` folds to `0xFFFFFFFFFFFFFFFF` (unsigned max).
- `sf/src/comptime_eval.zig:85-88` — the `@intCast` fold (`child_0 == int_cast_id` → returns `comptimeEvalEvaluate(inner)`) hands that u64-max value to the bootstrap `__bootstrap_i32_from_*` guard.
- `sf/src/main.zig:377` — the checked u32 store panics on overflow.
- `sf/src/c89_emit.zig:2824` — unsigned u32 `itoa` uses unsigned interpretation.

## Cross-link
Same ICE class as `repro/negative_intcast_ice/` (created in tagged-union plan Task 9 Step 1, commit `dc40af40`). This repro kept as a self-contained gate for the typed-comptime-values plan.
