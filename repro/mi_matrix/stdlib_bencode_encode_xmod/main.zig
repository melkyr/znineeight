// stdlib_bencode_encode_xmod — STDLIB std_bencode (M0 §4.2) encode GREEN
// fixture.
//
// Builds the Value tree
//   { a: -5, b: "xyz", l: [0, ""], d: { k: "v" } }
// (keys in stored order a,b,l,d), encodes it with std_bencode.encode, and
// asserts the canonical encoding equals the hand-written expected
//   d1:ai-5e1:b3:xyz1:lli0e0:e1:dd1:k1:vee
// The integer case is negative (`i<n>e` must emit the '-' sign), the list
// contains an integer and a zero-length byte string, and the nested dict has a
// single entry. The fixture prints the encoded bytes both as lowercase hex and
// raw.
//
// GREEN: deterministic byte-exact stdout (RUNRC=0):
//   enc hex 64313a61692d3565313a62333a78797a313a6c6c693065303a65313a6464313a6b313a766565
//   enc raw d1:ai-5e1:b3:xyz1:lli0e0:e1:dd1:k1:vee
//   encode ok
const std = @import("std");
const ben = @import("std_bencode.zig");
const hex = @import("std_hex.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

pub fn main() void {
    var backing: [4096]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    var k0: []const u8 = "a";
    var k1: []const u8 = "b";
    var k2: []const u8 = "l";
    var k3: []const u8 = "d";
    var kk: []const u8 = "k";
    var vv: []const u8 = "v";
    var vy: []const u8 = "xyz";
    var empty: []const u8 = "";

    var zero = ben.Value{ .int_val = 0 };
    var eb = ben.Value{ .bytes = empty };
    var la = [_]ben.Value{ zero, eb };

    var kv = ben.Value{ .bytes = vv };
    var de = [_]ben.Entry{ben.Entry{ .key = kk, .value = kv }};

    var neg = ben.Value{ .int_val = -5 };
    var byz = ben.Value{ .bytes = vy };
    var lst = ben.Value{ .list = la[0..] };
    var dst = ben.Value{ .dict = de[0..] };

    var entries = [_]ben.Entry{
        ben.Entry{ .key = k0, .value = neg },
        ben.Entry{ .key = k1, .value = byz },
        ben.Entry{ .key = k2, .value = lst },
        ben.Entry{ .key = k3, .value = dst },
    };
    var root = ben.Value{ .dict = entries[0..] };

    var got = ben.encode(&ar, root) catch @panic("encode failed");
    var want: []const u8 = "d1:ai-5e1:b3:xyz1:lli0e0:e1:dd1:k1:vee";
    ck(eqBytes(got, want), "canonical equality");

    var hx = hex.encodeLower(&ar, got) catch @panic("hex failed");
    std.io.write("enc hex ");
    std.io.write(hx);
    std.io.write("\n");
    std.io.write("enc raw ");
    std.io.write(got);
    std.io.write("\n");

    ck(g_fail == 0, "failures");
    std.io.write("encode ok\n");
}
