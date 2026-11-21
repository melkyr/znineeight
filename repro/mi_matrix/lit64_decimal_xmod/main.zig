// lit64_decimal_xmod — Plan C Task 2b-I RED pin (the I half of the Task 2b I/F
// pair, operator ruling m1703) for the 64-bit decimal-literal truncation
// limitation found in Plan C Task 2.
//
// TRIGGER. A decimal integer literal that does not fit in 32 bits, declared at
// container scope and assigned to a u64:
//
//     const TWO63: u64 = 9223372036854775808;   // 2^63
//     ...
//     var lim: u64 = TWO63;
//
// RED today (fixed point ab7187cc988e39dc5907b95ccc182f9f): the literal
// materializes in a 32-bit (`unsigned int`) temp and truncates before being
// widened, so `lim` is 0 (2^63 mod 2^32). The emitted C is:
//
//     unsigned int zT_1;
//     zT_1 = 9223372036854775808ULL;
//     lim = zT_1;
//
// so `lim == @intCast(u64, 0x8000000000000000)` is false and the `ck` assert
// traps (SIGTRAP, rc 133). The emitted C is gcc-clean, so the corpus
// `-ffast` dump+gcc classifier buckets this dir OK; the RED is RUNTIME-only.
//
// WORKAROUND (used by `sf/src/std_parse.zig`): write the constant as
// `@intCast(u64, 0x8000000000000000)` / `@bitCast`, which lowers correctly.
//
// RED -> GREEN contract (Task 2b-F). The decimal literal materializes in a
// 64-bit temp; this program runs and prints exactly `lit64 ok` with exit code
// 0. The committed goldens (`expected.txt`/`expected.rc`) encode this DESIRED
// GREEN behaviour, so this pin is RED until Task 2b-F.
//
// This is a compiler-graph pin only: no `sf/src` change here, and the fixed
// point stays UNMOVED at ab7187cc988e39dc5907b95ccc182f9f.
const std = @import("std");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

// Container-scope decimal literal >= 2^32 (here 2^63); today emitted into a
// 32-bit temp.
const TWO63: u64 = 9223372036854775808;
// The established working idiom, for an independent reference value.
const TWO63_REF: u64 = @intCast(u64, 0x8000000000000000);

pub fn main() void {
    var lim: u64 = TWO63;
    ck(lim == TWO63_REF, "64-bit decimal literal survives widening");

    // The truncated value also poisons arithmetic that depends on the high half.
    var hi: u64 = lim >> 32;
    ck(hi == @intCast(u64, 2147483648), "high 32 bits of the literal");

    if (g_fail == 0) {
        std.io.write("lit64 ok\n");
    } else {
        std.io.write("lit64 FAIL\n");
    }
}
