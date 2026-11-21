// module_value_arraysize_xmod — nested-module const in an ARRAY-SIZE position.
//
// `var a: [mid.leaf.HEADER_SIZE]u8 = undefined;` asks the parser/analyzer to use
// a nested-module `pub const` as an array length.
//
// STILL RED at the Task 2a-F fixed point 43d41bfb903d56c153ebf653131aef6d
// (declared residual gap, out of 2a-F scope): the construct is blocked EARLIER
// by an UNRELATED pre-existing gap — a NON-LITERAL / FIELD-ACCESS expression in
// array-size position is rejected at parse/analyze time:
//   error[20]: identifier 'a' is not declared or imported in this module
//   dump rc=2, 0 `.c`. Corpus classifier: FAIL (error[20] is not in the ICE
//   regex).
// The blocker is NESTING-INDEPENDENT: `var a: [leaf.HEADER_SIZE]u8` with a
// 1-level DIRECT import (`const leaf = @import("leaf.zig")`) fails identically.
// Control (same compiler): a MODULE-LEVEL named const IS accepted —
// `const N: usize = 16; var a: [N]u8 = undefined;` (and `const M = N`) → rc=0,
// 4 `.c` (GREEN). So this position cannot isolate the nested-module value gap.
// (A function-body `const N` as an array size also errors — a separate
// statement-scope issue, not this gap.)
//
// Expected GREEN contract (once BOTH gaps are fixed): `a.len == 16`; dump rc=0,
// gcc clean, link+run rc=0, no stdout.
//
// GREEN (Task 2b-F, fixed point 0da3f1391075e3e77c54b626d5550e3b): dump rc=0,
// 5 `.c`, gcc -m32 -std=c89 clean, link+run rc=0, no stdout. `evalConstU32Full`
// gained a `field_access` arm that walks the module-alias chain
// (`evalConstModuleOfExpr`) and folds the member const's initializer; the
// `array_type` arm also has an `else` const-eval fallback. Emitted evidence:
// `a.len` folds to the literal 16 (`zT_4 = 16;`). Variants a (`[leaf.HEADER_SIZE]`),
// b (`[mid.leaf.HEADER_SIZE]`), and d (module-level `const N = mid.leaf.HEADER_SIZE`)
// are all GREEN. Variant e (function-local `const N = ...; [N]`) stays RED — a
// separate statement-scope gap (`const N = 16; [N]` fails identically on both
// base and fix), declared out of this gap by the Task 2b-I investigation and
// operator-ruled OUT OF SCOPE for Task 2b-F; fixing it needs local-const scope
// threading into the type resolver. See `repro/mi_matrix/EXPECTED_FAIL.md` v105.
const mid = @import("mid.zig");

pub fn main() void {
    var a: [mid.leaf.HEADER_SIZE]u8 = undefined;
    if (a.len != 16) {
        @panic("module_value_arraysize_xmod: array size mismatch");
    }
}
