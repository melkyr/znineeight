# comptime_i64_big_negative repro

## Form
A comptime i64 fold with magnitude > 2^32 (`@intCast(i64, -5000000000)`), which
exercises the signed-negative magnitude path in c89_emit int_const emission.

## Expected
- RED (before fix): --dump-c89 aborts rc=134 with "PANIC: integer overflow in @intCast"
- GREEN (after fix): dump rc=0; emitted C literal contains `-5000000000`;
  gcc -m32 -std=c89 compiles+links; binary prints `1`.

## RED evidence (HEAD 8340a6e1)
dump rc=134 (SIGABRT)
PANIC: integer overflow in @intCast at sf/build/out_release/zig_runtime.h:107

## Root cause
The comptime int_const emitter in c89_emit.zig narrows its render value from u64 to u32
via `@intCast(u32, value)` before calling `itoa()` (which only accepts `u32`).
When magnitude > 2^32, the @intCast panics.

## Fix
Added `itoa64()` (u64 → digits, parallel to `itoa`) in `sf/src/util/itoa.zig`.
Changed the two int_const emit sites in `sf/src/c89_emit.zig` to use `itoa64()`.
