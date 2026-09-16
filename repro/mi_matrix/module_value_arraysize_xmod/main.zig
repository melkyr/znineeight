// module_value_arraysize_xmod — nested-module const in an ARRAY-SIZE position.
//
// `var a: [mid.leaf.HEADER_SIZE]u8 = undefined;` asks the parser/analyzer to use
// a nested-module `pub const` as an array length.
//
// RED (current, fixed point 286c9011691ccd39403534019baa12c6): the construct is
// blocked EARLIER by an UNRELATED pre-existing gap — a NAMED const as an array
// size is rejected at parse/analyze time:
//   error[20]: identifier 'a' is not declared or imported in this module
//   dump rc=2, 0 `.c`. Corpus classifier: FAIL (error[20] is not in the ICE
//   regex).
// Control: `const N: usize = 16; var a: [N]u8 = undefined;` (a purely LOCAL
// const, no module alias) fails with the SAME error[20] — so this position
// cannot currently isolate the nested-module value gap. Only a literal length
// (`[16]u8`) parses today.
//
// Expected GREEN contract (once BOTH gaps are fixed): `a.len == 16`; dump rc=0,
// gcc clean, link+run rc=0, no stdout.
const mid = @import("mid.zig");

pub fn main() void {
    var a: [mid.leaf.HEADER_SIZE]u8 = undefined;
    if (a.len != 16) {
        @panic("module_value_arraysize_xmod: array size mismatch");
    }
}
