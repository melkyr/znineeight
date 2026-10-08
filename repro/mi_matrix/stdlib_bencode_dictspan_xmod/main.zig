// stdlib_bencode_dictspan_xmod — STDLIB std_bencode (M0 §4.2)
// dictValueSpan contract.
//
// `dictValueSpan(bytes, key)` walks ONLY the top-level dict and returns the raw
// byte span of the key's value WITHOUT decoding it and WITHOUT allocating.
// On `d4:infoli1ei2eee4:name3:abce` the `info` value occupies input bytes
// [7,15) = `li1ei2ee`; an absent key returns null. u32 offsets into the input.
//
// GREEN: deterministic byte-exact stdout (RUNRC=0):
//   info 7 15 li1ei2ee
//   absent null
//   dictspan ok
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
    var src: []const u8 = "d4:infoli1ei2eee4:name3:abce";

    var sp = ben.dictValueSpan(src, "info") catch @panic("span error");
    if (sp) |x| {
        ck(x.start == 7, "start");
        ck(x.end == 15, "end");
        const s: usize = @intCast(usize, x.start);
        const e: usize = @intCast(usize, x.end);
        const got: []const u8 = src[s..e];
        ck(eqBytes(got, "li1ei2ee"), "captured bytes");
        std.io.write("info ");
        std.io.printInt(@intCast(i32, x.start));
        std.io.write(" ");
        std.io.printInt(@intCast(i32, x.end));
        std.io.write(" ");
        std.io.write(got);
        std.io.write("\n");
    } else {
        @panic("info missing");
    }

    var sp2 = ben.dictValueSpan(src, "absent") catch @panic("span error 2");
    if (sp2) |_| {
        @panic("absent key found");
    } else {
        std.io.write("absent null\n");
    }

    std.io.write("dictspan ok\n");
}
