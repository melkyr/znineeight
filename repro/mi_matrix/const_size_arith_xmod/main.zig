// const_size_arith_xmod — module-level `const` whose initializer is an
// ARITHMETIC EXPRESSION over other module consts, used in ARRAY-SIZE position.
//
// Origin: Track-4 Task 3 (S11) found that `const CELLS = ROWS * COLS` (a
// const-of-consts expression) used as an array size is not folded; the size
// never resolves and the compiler emits no array type. This fixture isolates
// the `*`, `+`, `-`, `/`, `%` and nested (`A * B + 2`) shapes.
//
// GREEN (Task 2c-F, fixed point 960575b70302c78a19cf6bc0cc129df5): the `binary`
// (`add/sub/mul/div/mod_op`) and `negate` cases added to `evalConstU32Full`
// (`sf/src/type_resolver.zig`) fold the const initializer recursively, so every
// variant resolves. This fixture was RED at the Task-2b-F fixed point
// 0da3f1391075e3e77c54b626d5550e3b: the size recursed into the const's
// initializer (a `binary` node) with no `binary` case, returned 0xFFFFFFFF,
// `arr_resolved` stayed false, and the first use reported
// `error[20]: identifier '<var>' is not declared or imported in this module`
// (dump rc=2, 0 `.c`). If the arrays were never used, the same shape was
// SILENTLY emitted as invalid C (dump rc=0).
//
// GREEN contract: every variant folds (`C`=16, `D`=8, `E`=0, `F`=1, `G`=0,
// `H`=18); dump rc=0, gcc -m32 -std=c89 clean, link+run rc=0, no stdout.

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
