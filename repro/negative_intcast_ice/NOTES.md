# repro: negative_intcast_ice

## Form
```zig
extern fn __bootstrap_print_int(x: i32) void;

pub fn main() void {
    var r: i32 = @intCast(i32, -1);
    __bootstrap_print_int(r);
}
```

`@intCast(i32, -1)` — any negative literal cast.

## Expected correct output
`-1`

## Actual (RED, on HEAD 5fc78550 — Task 3 fix descendant HEAD)
zig1 **itself aborts at compile time**:

- `sf/build/out_release/zig1 --dump-c89 repro/negative_intcast_ice/main.zig` → dump **rc=134** (Aborted / core dumped).
- Emits `PANIC: integer overflow in @intCast at sf/build/out_release/zig_runtime.h:107`.
- No usable C emitted (only the panic line, ~78 bytes; no translation unit).

(Note: on this HEAD the PANIC line is written to **stdout** — captured in `/tmp/ni.c` — rather than
stderr/`/tmp/ni.err`, which was empty. The abort itself and `rc=134` are as the model predicts; the
ICE is confirmed regardless of which stream the panic text lands on.)

## Root cause (verified read-only)
- `sf/src/comptime_eval.zig:103-107` — the `negate` fold computes `nv = @intCast(u64,0) - v` in
  `u64`, so `-1` folds to `0xFFFFFFFFFFFFFFFF`.
- `sf/src/comptime_eval.zig:85-88` — the `@intCast` fold
  (`node.child_0 == self.int_cast_id` → returns `comptimeEvalEvaluate(inner)`) hands that u64-max
  value straight to the bootstrap `__bootstrap_i32_from_*` guard, which panics on overflow.

## Cross-link
This is the **negative-cast variant that the `repro/tagged_union_payload` repro deliberately
avoids** (Task 1 uses `@intCast(i32, 0)` in its `.Nil` prongs specifically to dodge this ICE).
This bug is INDEPENDENT of the tagged-union payload store — it is purely the comptime negate +
`@intCast` fold overflowing the bootstrap cast guard.
