// const_size_cycle_xmod — a const CYCLE in array-size position must be a clean
// hard error, never an ICE / unbounded recursion.
//
// `const A = A + 1;` is self-referential, so folding `[A]u8` recurses
// `ident A -> binary (A + 1) -> ident A -> ...` without bound. This class
// already existed for direct ident cycles (`const A = B; const B = A`), but the
// Task-2c-F arithmetic `binary` case (`sf/src/type_resolver.zig` `evalConstU32Full`)
// newly enabled the `const A = A + 1` shape to loop too. `evalConstU32Full` had
// no depth cap, so the compiler crashed (SIGSEGV, rc=139) / hung before the fix.
//
// RED before the Task-2c-F fix round 1 (fixed point 960575b70302c78a19cf6bc0cc129df5):
//   `zig1 -ffast --dump-c89` -> rc=139 SIGSEGV (module-level self-cycle), 0 `.c`.
//   (The direct ident cycle `const A = B; const B = A` instead loops: rc=124
//   under `timeout`.) Both are ICEs, not a frontend diagnostic.
//
// GREEN contract (fix round 1): the new depth cap in `evalConstU32Full`
// (mirroring `resolveTypeExprFull`'s) makes the cycle fold to the unfoldable
// sentinel, so the array-size fallback reports the existing hard error:
//   error[3050]: array size is not a constant expression
// with a real filename/line pointing at the size expression; dump rc=2, 0 `.c`.
// Never `error[3042]`/`error[3043]` (ICE), never silent invalid C.
const A = A + 1;

var x: [A]u8 = undefined;

pub fn main() void {
    x[0] = 1;
    if (x.len != 1) {
        @panic("const_size_cycle_xmod: unexpected");
    }
}
