# repro: comptime_i64_negative

## Form
```zig
extern fn __bootstrap_print_int(x: i32) void;

pub fn main() void {
    var r: i64 = @intCast(i64, -1);
    __bootstrap_print_int(@intCast(i32, r));
}
```

`@intCast(i64, -1)` → `@intCast(i32, r)` — wider-than-u32 negative literal cast.

## Expected correct output
`-1`

## Actual (RED, on HEAD 39b8c14b)
zig1 **itself aborts at compile time**:

- `sf/build/out_release/zig1 --dump-c89 repro/comptime_i64_negative/main.zig` → dump **rc=134**.
- Emits `PANIC: integer overflow in @intCast at sf/build/out_release/zig_runtime.h:107`.
- No usable C emitted. Both casts (i64 and i32) would need to carry sign through the fold pipeline, but the untyped u64 representation loses sign immediately.

## Root cause (verified read-only)
- `sf/src/comptime_eval.zig:103-108` — the `negate` fold computes `nv = @intCast(u64,0) - v` in `u64`, so `-1` folds to `0xFFFFFFFFFFFFFFFF`.
- `sf/src/comptime_eval.zig:85-88` — the `@intCast` fold (`child_0 == int_cast_id`) returns `comptimeEvalEvaluate(inner)` without checking the target type, handing u64-max to the bootstrap cast guard.
- `sf/src/main.zig:377` — checked u32 store panics.
- `sf/src/c89_emit.zig:2824` — unsigned u32 `itoa` would emit unsigned if compilation succeeded.

## Cross-link
Same ICE class as `repro/negative_intcast_ice/` (commit `dc40af40`) and `repro/comptime_signed_negate/`. The i64 variant tests the wider-type path — even if the i32 cast were bypassed, the i64 fold still runs through the same untyped negate pipeline.
