// comptime_coerce_reject_xmod — Task 4 out-of-range materialisation rejects
// (lowering phase), extended by the Task 4 fix round (review Importants 1/2/4).
//
// Every site below is a comptime integer that does not fit its target slot;
// before Task 4 they were silently truncated (or, for the >64-bit value,
// silently unfolded and mis-run), and the fix-round sites additionally escaped
// the first implementation. The materialisation sites now range-check the exact
// value and emit error[3000] "comptime integer value does not fit the target
// type".
//
// All sites are in the LOWERING phase (the pinned `materializeInto` /
// coercion-funnel / decl-slot / untyped-slot rules + the fix-round
// argument/return literal and declaration-init rules). The `@intCast`-fold
// class (`@intCast(u64, 0 - 1)`) is pinned by
// `repro/mi_matrix/comptime_cast64_range_reject_xmod` (site D) because a
// comptime-eval error stops the pipeline before lowering.
//
// Contract: dump rc=2, 0 `.c`, 12 × `error[3000]` — the canonical classifier's
// GREEN clean-reject bucket.
//
// | site | shape | target | oracle (Zig 0.15.2) |
// |---|---|---|---|
// | `U8FOLD` | `const U8FOLD: u8 = 250 + 60;` | typed decl slot (HIT) | reject `type 'u8' cannot represent integer value '310'` |
// | `BIGFOLD` | `const BIGFOLD = 1 << 100;` | untyped >64-bit | **accept** (bounded divergence, Task 1 §8 risk 1) |
// | `NEGU` | `const NEGU: u64 = @as(i64, -1);` | module decl slot vs `@as` target | reject `type 'u64' cannot represent integer value '-1'` |
// | `NEGI8` | `const NEGI8: i8 = @as(i32, -200);` | signed narrow decl | reject `type 'i8' cannot represent integer value '-200'` |
// | `take8` | `take8(@as(i32, 300));` | `u8` parameter (folded arg) | reject `type 'u8' cannot represent integer value '300'` |
// | `ret8` | `return @as(i32, -1);` in `fn ret8() u8` | `u8` return | reject `type 'u8' cannot represent integer value '-1'` |
// | `localBad` | `const NEG2: u8 = @as(i32, -1);` | local decl slot | reject `type 'u8' cannot represent integer value '-1'` |
// | `varBad` (fix Important 1) | `var y: u32 = 0 - 1;` | `var` decl slot, arithmetic init | reject `type 'u32' cannot represent integer value '-1'` |
// | `takeLit` (fix Important 2) | `take8(300);` | `u8` parameter, bare literal | reject `type 'u8' cannot represent integer value '300'` |
// | `retLit` (fix Important 2) | `return 300;` in `fn retLit() u8` | `u8` return, bare literal | reject `type 'u8' cannot represent integer value '300'` |
// | `takeOpt` (fix Important 4) | `takeOpt8(@as(i32, 300));` | `?u8` payload parameter | reject `expected type '?u8', found 'i32'` |
// | `localOpt` (fix Important 4) | `var o: ?u8 = @as(i32, 300);` | `?u8` decl slot | reject `expected type '?u8', found 'i32'` |
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

fn takeOpt8(x: ?u8) void {
    _ = x;
}

fn ret8() u8 {
    return @as(i32, -1);
}

fn retLit() u8 {
    return 300;
}

fn localBad() void {
    const NEG2: u8 = @as(i32, -1);
    _ = NEG2;
}

fn varBad() void {
    var y: u32 = 0 - 1;
    _ = y;
}

fn localOpt() void {
    var o: ?u8 = @as(i32, 300);
    _ = o;
}

pub fn main() void {
    take8(@as(i32, 300));
    take8(300);
    _ = ret8();
    _ = retLit();
    localBad();
    varBad();
    localOpt();
    takeOpt8(@as(i32, 300));
    _ = U8FOLD;
    _ = BIGFOLD;
    _ = NEGU;
    _ = NEGI8;
}
