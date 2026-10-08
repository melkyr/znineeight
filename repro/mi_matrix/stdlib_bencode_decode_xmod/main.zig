// stdlib_bencode_decode_xmod — STDLIB std_bencode (M0 §4.2) decode GREEN
// fixture.
//
// decodes a small nested dict `d1:ai1e1:b3:xyz1:il1:iee` (key `a` -> int 1,
// key `b` -> bytes "xyz", key `i` -> list [bytes "i"]) and prints each field
// in entry order. Contract: deterministic multi-line report ending `decode ok`.
//
// GREEN: deterministic byte-exact stdout (RUNRC=0):
//   dict len 3
//   a = int 1
//   b = bytes xyz
//   i = list 1
//   i[0] = bytes i
//   decode ok
const std = @import("std");
const ben = @import("std_bencode.zig");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
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

    var src: []const u8 = "d1:ai1e1:b3:xyz1:il1:iee";
    const v = ben.decode(&ar, src) catch @panic("decode failed");

    var d: []ben.Entry = undefined;
    switch (v) {
        .dict => |x| {
            d = x;
        },
        else => {
            @panic("top-level not dict");
        },
    }
    ck(d.len == 3, "dict len");

    std.io.write("dict len ");
    std.io.printInt(@intCast(i32, d.len));
    std.io.write("\n");

    ck(eqBytes(d[0].key, "a"), "key0");
    ck(eqBytes(d[1].key, "b"), "key1");
    ck(eqBytes(d[2].key, "i"), "key2");

    switch (d[0].value) {
        .int_val => |n| {
            ck(n == 1, "a val");
        },
        else => {
            @panic("a type");
        },
    }
    std.io.write("a = int 1\n");

    var bs: []const u8 = undefined;
    switch (d[1].value) {
        .bytes => |s| {
            bs = s;
        },
        else => {
            @panic("b type");
        },
    }
    ck(eqBytes(bs, "xyz"), "b val");
    std.io.write("b = bytes xyz\n");

    var lst: []ben.Value = undefined;
    switch (d[2].value) {
        .list => |x| {
            lst = x;
        },
        else => {
            @panic("i type");
        },
    }
    ck(lst.len == 1, "i len");
    std.io.write("i = list ");
    std.io.printInt(@intCast(i32, lst.len));
    std.io.write("\n");

    var s0: []const u8 = undefined;
    switch (lst[0]) {
        .bytes => |s| {
            s0 = s;
        },
        else => {
            @panic("i0 type");
        },
    }
    ck(eqBytes(s0, "i"), "i0 val");
    std.io.write("i[0] = bytes i\n");

    std.io.write("decode ok\n");
}
