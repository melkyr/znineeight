// const_size_arith_xmod — module-level `const` whose initializer is an
// ARITHMETIC EXPRESSION over other module consts, used in ARRAY-SIZE position.
//
// Origin: Track-4 Task 3 (S11) found that `const CELLS = ROWS * COLS` (a
// const-of-consts expression) used as an array size is not folded; the size
// never resolves and the compiler emits no array type. This fixture isolates
// the `*`, `+`, `-`, `/`, `%` and nested (`A * B + 2`) shapes.
//
// RED today (Task 2b-F fixed point 0da3f1391075e3e77c54b626d5550e3b): the size
// expression recurses through `evalConstU32Full` (`sf/src/type_resolver.zig:744`)
// into the const's initializer, which is a `binary` node — and `evalConstU32Full`
// has NO `binary` case, so it returns 0xFFFFFFFF. `arr_resolved` stays false, the
// array type is `TYPE_UNDEFINED` (`:1173`), the local is never registered, and the
// first use reports:
//   error[20]: identifier '<var>' is not declared or imported in this module
// (dump rc=2, 0 `.c`; corpus classifier FAIL — `error[20]` is not an ICE code).
// An INLINE `[A * B]u8` already folds: the `array_type` arm handles
// add/sub/mul/div/mod directly (`:1123-1139`), so only the const-behind-an-
// expression case is broken. If the arrays are never used, the same shape is
// SILENTLY emitted as invalid C (dump rc=0) — see `const_size_unfoldable_xmod`.
//
// Expected GREEN contract (Task 2c-F): every variant folds (`C`=16, `D`=8,
// `E`=0, `F`=1, `G`=0, `H`=18); dump rc=0, gcc -m32 -std=c89 clean, link+run
// rc=0, no stdout.
//
// Fix locus: add a `binary` (and `negate`) case to `evalConstU32Full`
// (`sf/src/type_resolver.zig:744`) so a const initializer that is an arithmetic
// expression folds recursively. See report Q3/Q6.
const A: usize = 4;
const B: usize = 4;
const C = A * B;
const D = A + B;
const E = A - B;
const F = A / B;
const G = A % B;
const H = A * B + 2;

pub fn main() void {
    var xc: [C]u8 = undefined;
    var xd: [D]u8 = undefined;
    var xe: [E]u8 = undefined;
    var xf: [F]u8 = undefined;
    var xg: [G]u8 = undefined;
    var xh: [H]u8 = undefined;
    if (xc.len != 16) { @panic("C"); }
    if (xd.len != 8) { @panic("D"); }
    if (xe.len != 0) { @panic("E"); }
    if (xf.len != 1) { @panic("F"); }
    if (xg.len != 0) { @panic("G"); }
    if (xh.len != 18) { @panic("H"); }
}
