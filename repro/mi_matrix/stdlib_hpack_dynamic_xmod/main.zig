// stdlib_hpack_dynamic_xmod — HPACK dynamic-table insert/index/evict fixture.
//
// Uses a 160-byte caller storage and a sequence that inserts four entries,
// forces O(1) ring eviction of the two oldest, indexes the survivors by dynamic
// index (62/63), then applies a table-size update to 0. Prints the table size
// and survivor headers.
//
// GREEN (contract): deterministic byte-exact stdout, exit code 0.

const std = @import("std");
const hp = @import("std_hpack.zig");

fn printHeader(hh: hp.HpackHeader) void {
    std.io.write(hh.name);
    std.io.write(": ");
    std.io.write(hh.value);
    std.io.writeByte('\n');
}

fn show(label: []const u8, h: *hp.Hpack, block: []const u8, ar: *std.arena.Arena) usize {
    std.io.write(label);
    std.io.writeByte('\n');
    std.arena.reset(ar);
    var out: [16]hp.HpackHeader = undefined;
    var n = hp.hpackDecode(h, block, out[0..], ar) catch {
        std.io.write("decode-fail\n");
        return 0;
    };
    var i: usize = 0;
    while (i < n) : (i += 1) printHeader(out[i]);
    return n;
}

fn showSize(h: *hp.Hpack) void {
    std.io.write("size=");
    std.io.printInt(@intCast(i32, hp.hpackDynamicSize(h)));
    std.io.writeByte('\n');
    std.io.write("count=");
    std.io.printInt(@intCast(i32, hp.hpackDynamicCount(h)));
    std.io.writeByte('\n');
}

pub fn main() void {
    var ar_backing: [65536]u8 = undefined;
    var ar = std.arena.init(ar_backing[0..]);
    var storage: [160]u8 = undefined;
    var h: hp.Hpack = undefined;
    hp.hpackInit(&h, storage[0..]);

    var a = [_]u8{ 0x40, 0x0a, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x6b, 0x65, 0x79, 0x0d, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x68, 0x65, 0x61, 0x64, 0x65, 0x72 };
    _ = show("insert-A", &h, a[0..], &ar);

    var b = [_]u8{ 0x58, 0x08, 0x6e, 0x6f, 0x2d, 0x63, 0x61, 0x63, 0x68, 0x65 };
    _ = show("insert-B", &h, b[0..], &ar);

    var c = [_]u8{ 0x7a, 0x04, 0x74, 0x65, 0x73, 0x74 };
    _ = show("insert-C", &h, c[0..], &ar);

    var d: [48]u8 = undefined;
    d[0] = 0x40;
    d[1] = 0x05;
    d[2] = 'x';
    d[3] = '-';
    d[4] = 'b';
    d[5] = 'i';
    d[6] = 'g';
    d[7] = 0x28;
    var k: usize = 0;
    while (k < 40) : (k += 1) d[8 + k] = 'a';
    _ = show("insert-D", &h, d[0..], &ar);

    showSize(&h);

    var survivors = [_]u8{ 0xbe, 0xbf };
    _ = show("survivors", &h, survivors[0..], &ar);

    var clear = [_]u8{0x20};
    _ = show("update-0", &h, clear[0..], &ar);
    showSize(&h);
}
