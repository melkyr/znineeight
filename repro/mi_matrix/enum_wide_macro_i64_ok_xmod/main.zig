// enum_wide_macro_i64_ok_xmod — a signed `enum(i64)` with wide members above
// 2^32 in magnitude. The per-member `#define` bodies must be portable C89:
// `(-Z98_I64_C(4294967297))` for the negative member and
// `Z98_U64_C(4294967297)` for the positive one, not raw unsuffixed decimals.
//
// Contract: both members are used; `N` matches and `P` matches, so stdout
// `3\n`, rc 0. The emitted C is compiled by gate_warn_clean.sh scope (c) under
// `gcc -m32 -std=c89 -pedantic -Werror -Wno-long-long`.
const std = @import("std");

const E = enum(i64) { N = -4294967297, P = 4294967297 };

pub fn main() void {
    const n: E = E.N;
    const p: E = E.P;
    var r: i32 = 0;
    if (@enumToInt(n) == -4294967297) {
        r = r + 1;
    }
    if (@enumToInt(p) == 4294967297) {
        r = r + 2;
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
