# repro: comptime_signed_divmod

## Form
```zig
extern fn __bootstrap_print_int(x: i32) void;

pub fn main() void {
    var r: i32 = @intCast(i32, -6 / 2);
    __bootstrap_print_int(r);
}
```

`@intCast(i32, -6 / 2)` — signed division fold + cast.

## Expected correct output
`-3`

## Actual (RED, on HEAD 39b8c14b)
zig1 **itself aborts at compile time** (the negate sub-expression `-6` triggers the same ICE):

- `sf/build/out_release/zig1 --dump-c89 repro/comptime_signed_divmod/main.zig` → dump **rc=134**.
- Emits `PANIC: integer overflow in @intCast at sf/build/out_release/zig_runtime.h:107`.
- If the negate were fixed but div remained unsigned, `-6` (u64-max - 5) divided by 2 would produce a wrong unsigned quotient — but the negate ICE fires first on this HEAD.

## Root cause (verified read-only)
- `sf/src/comptime_eval.zig:36-56` — binary ops (including division) fold in unsigned u64; signed semantics lost.
- `sf/src/comptime_eval.zig:103-108` — the `negate` fold computes `nv = @intCast(u64,0) - v` in `u64`, so `-6` folds to u64-max - 5.
- `sf/src/comptime_eval.zig:85-88` — the `@intCast` fold discards `ec[0]` (unsigned-only flow).

## Cross-link
Related to `repro/comptime_signed_negate/` (negate ICE) and `repro/negative_intcast_ice/` (original negative-cast ICE, commit `dc40af40`). The signed-div facet is secondary to the negate bug on this HEAD — once negate is typed, `-6 / 2` must produce -3, not the unsigned quotient.
