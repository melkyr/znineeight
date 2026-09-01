# ice_literal_overflow — compiler ICE on literal >= 2^32  [4-item compiler gaps plan, Task F2, 2026-08-06]

## What it tests
A program containing integer literals >= 2^32 (5000000000, 4294967296) must not
crash the compiler. Pre-fix, the `int_literal` lowering marker at
`lower.zig` (the `ILR:i … v<value>` marker) called
`itoa_mod.itoa(@intCast(u32, val), …)` with `val` being the u64 literal value.
Since F1 (`@intCast` range-check) that cast is emitted as the checked
`__bootstrap_u32_from_u64` helper, so ANY program that lowers a literal >= 2^32
made the compiler itself abort with `PANIC: integer overflow in @intCast`
→ dump rc=134 (SIGABRT). The lowering pipeline is correct; only the marker was
broken. Fix: add `pal.markerWriteInt64` (itoa64-based, `[24]u8` buffer) and use
it for the value marker, rendering the full u64.

## Why the repro is NOT the brief's exact const-only source
The brief's exact source (`pub const X: u64 = 5000000000;` + `print_u64(X)`)
does **not** reproduce the ICE on the current tree: F8's ident_expr const-chain
fold resolves `X` at comptime, so the literal value never flows through the
`int_literal` runtime-lowering branch whose marker panics. Verified: const-only
form dumps rc=0 pre-fix. The repro therefore keeps the brief's const
declarations (X, Y — the KEY property: the program contains literals >= 2^32)
AND adds a runtime-lowered literal (`var sink: u64 = 5000000000;`) so the
marker path is actually exercised. Pre-fix this repro dumps rc=134; post-fix
rc=0.

## Why hi:lo printing instead of a single u64 printf
Same reason as `comptime_u64_fold_overflow` (F7): on -m32, `%lu` is 32-bit and
`%llu` reads adjacent varargs slots, so each u64 is printed as two i32 halves
computed at runtime (`hi = @intCast(u64, X) >> 32`, `lo = @intCast(u64, X) &
@intCast(u64, 4294967295)`). The `X`/`Y` consts are resolved at comptime, so
the emitted hi/lo ints are correct folded constants:
- X = 5000000000 = 0x1_2A05F200 → `1:705032704`.
- Y = 4294967296 = 0x1_00000000 → `1:0`.
Runtime prints `1:705032704 1:0`.

## Measured result
- **Pre-fix** (/tmp/zigpre/zig1, pristine HEAD): `zig1 --dump-c89` →
  dump rc=134, `PANIC: integer overflow in @intCast at zig_runtime.h:107`
  (the F1 checked `__bootstrap_u32_from_u64` in the value marker).
- **Post-fix** (/tmp/zigaps/zig1): dump rc=0, 1 `.c` emitted, emitted C
  contains `zT_1 = 5000000000;` (the runtime sink literal) and the folded
  hi/lo ints for X/Y; gcc-clean (rc=0); runs printing `1:705032704 1:0`,
  rc=0.
- The `--markers` ILR trace now shows `ILR:i<node>v5000000000` (full u64)
  instead of the pre-fix panic.

## Expected classification
- **Pre-fix: ICE** (dump rc=134, SIGABRT).
- **Post-fix: OK** — dump rc=0, gcc-clean, correct runtime output.
