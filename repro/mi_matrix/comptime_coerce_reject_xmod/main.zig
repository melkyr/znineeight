// comptime_coerce_reject_xmod — Task 4 out-of-range materialisation rejects
// (lowering phase).
//
// Every site below is a folded comptime integer that does not fit its target
// slot; before Task 4 they were silently truncated (or, for the >64-bit value,
// silently unfolded and mis-run). Task 4 range-checks the exact value at each
// materialisation site and emits error[3000] "comptime integer value does not
// fit the target type".
//
// All sites are in the LOWERING phase (the pinned `materializeInto` /
// coercion-funnel / decl-slot / untyped-slot rules). The `@intCast`-fold class
// (`@intCast(u64, 0 - 1)`) is pinned by
// `repro/mi_matrix/comptime_cast64_range_reject_xmod` (site D) because a
// comptime-eval error stops the pipeline before lowering.
//
// Contract: dump rc=2, 0 `.c`, 7 × `error[3000]` — the canonical classifier's
// GREEN clean-reject bucket.
//
// | site | shape | target | oracle (Zig 0.15.2) |
// |---|---|---|---|
// | `U8FOLD` | `const U8FOLD: u8 = 250 + 60;` | typed decl slot (HIT) | reject `type 'u8' cannot represent integer value '310'` |
// | `BIGFOLD` | `const BIGFOLD = 1 << 100;` | untyped >64-bit | **accept** (bounded divergence, Task 1 §8 risk 1) |
// | `NEGU` | `const NEGU: u64 = @as(i64, -1);` | module decl slot vs `@as` target | reject `type 'u64' cannot represent integer value '-1'` |
// | `NEGI8` | `const NEGI8: i8 = @as(i32, -200);` | signed narrow decl | reject `type 'i8' cannot represent integer value '-200'` |
// | `take8` | `take8(@as(i32, 300));` | `u8` parameter | reject `type 'u8' cannot represent integer value '300'` |
// | `ret8` | `return @as(i32, -1);` in `fn ret8() u8` | `u8` return | reject `type 'u8' cannot represent integer value '-1'` |
// | `localBad` | `const NEG2: u8 = @as(i32, -1);` | local decl slot | reject `type 'u8' cannot represent integer value '-1'` |
//
// `BIGFOLD` is the one deliberate divergence: Z98 cannot represent a value
// beyond [i64 min, u64 max] in any runtime slot, so it refuses to emit wrong C
// (Task 1 §8 risk 1; the pre-Task-4 compiler accepted it and ran a wrong value).
//
// The in-range sides of every row live in
// `repro/mi_matrix/stdlib_comptime_coerce_typed_slots_xmod`.
const U8FOLD: u8 = 250 + 60;
const BIGFOLD = 1 << 100;
const NEGU: u64 = @as(i64, -1);
const NEGI8: i8 = @as(i32, -200);

fn take8(x: u8) void {
    _ = x;
}

fn ret8() u8 {
    return @as(i32, -1);
}

fn localBad() void {
    const NEG2: u8 = @as(i32, -1);
    _ = NEG2;
}

pub fn main() void {
    take8(@as(i32, 300));
    _ = ret8();
    localBad();
    _ = U8FOLD;
    _ = BIGFOLD;
    _ = NEGU;
    _ = NEGI8;
}
