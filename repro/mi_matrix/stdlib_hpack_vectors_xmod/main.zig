// stdlib_hpack_vectors_xmod — RFC 7541 C.2/C.3/C.4 HPACK decode vectors.
//
// Decodes the RFC header-representation examples (C.2.1..C.2.4), the three
// request examples without Huffman (C.3.1..C.3.3), and the three request
// examples with Huffman (C.4.1..C.4.3), printing each decoded `name: value`.
// Also checks fail-closed behavior (overlong integer, table-size update above
// configured storage, and a header list exceeding `out.len`).
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

fn show(label: []const u8, h: *hp.Hpack, block: []const u8, ar: *std.arena.Arena) void {
    std.io.write(label);
    std.io.writeByte('\n');
    std.arena.reset(ar);
    var out: [64]hp.HpackHeader = undefined;
    var n = hp.hpackDecode(h, block, out[0..], ar) catch {
        std.io.write("decode-fail\n");
        return;
    };
    var i: usize = 0;
    while (i < n) : (i += 1) printHeader(out[i]);
}

fn expectCorrupt(h: *hp.Hpack, block: []const u8, ar: *std.arena.Arena) void {
    std.arena.reset(ar);
    var out: [8]hp.HpackHeader = undefined;
    var n = hp.hpackDecode(h, block, out[0..], ar) catch {
        std.io.write("corrupt\n");
        return;
    };
    _ = n;
    std.io.write("unexpected-ok\n");
}

fn expectCorruptOut0(h: *hp.Hpack, block: []const u8, ar: *std.arena.Arena) void {
    std.arena.reset(ar);
    var out: [0]hp.HpackHeader = undefined;
    var n = hp.hpackDecode(h, block, out[0..], ar) catch {
        std.io.write("corrupt\n");
        return;
    };
    _ = n;
    std.io.write("unexpected-ok\n");
}

pub fn main() void {
    var ar_backing: [65536]u8 = undefined;
    var ar = std.arena.init(ar_backing[0..]);
    var storage: [4096]u8 = undefined;
    var h: hp.Hpack = undefined;
    hp.hpackInit(&h, storage[0..]);

    var c21 = [_]u8{ 0x40, 0x0a, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x6b, 0x65, 0x79, 0x0d, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x68, 0x65, 0x61, 0x64, 0x65, 0x72 };
    show("C.2.1", &h, c21[0..], &ar);

    var c22 = [_]u8{ 0x04, 0x0c, 0x2f, 0x73, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x2f, 0x70, 0x61, 0x74, 0x68 };
    show("C.2.2", &h, c22[0..], &ar);

    var c23 = [_]u8{ 0x10, 0x08, 0x70, 0x61, 0x73, 0x73, 0x77, 0x6f, 0x72, 0x64, 0x06, 0x73, 0x65, 0x63, 0x72, 0x65, 0x74 };
    show("C.2.3", &h, c23[0..], &ar);

    var c24 = [_]u8{0x82};
    show("C.2.4", &h, c24[0..], &ar);

    hp.hpackInit(&h, storage[0..]);

    var c31 = [_]u8{ 0x82, 0x86, 0x84, 0x41, 0x0f, 0x77, 0x77, 0x77, 0x2e, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x2e, 0x63, 0x6f, 0x6d };
    show("C.3.1", &h, c31[0..], &ar);

    var c32 = [_]u8{ 0x82, 0x86, 0x84, 0xbe, 0x58, 0x08, 0x6e, 0x6f, 0x2d, 0x63, 0x61, 0x63, 0x68, 0x65 };
    show("C.3.2", &h, c32[0..], &ar);

    var c33 = [_]u8{ 0x82, 0x87, 0x85, 0xbf, 0x40, 0x0a, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x6b, 0x65, 0x79, 0x0c, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x76, 0x61, 0x6c, 0x75, 0x65 };
    show("C.3.3", &h, c33[0..], &ar);

    hp.hpackInit(&h, storage[0..]);

    var c41 = [_]u8{ 0x82, 0x86, 0x84, 0x41, 0x8c, 0xf1, 0xe3, 0xc2, 0xe5, 0xf2, 0x3a, 0x6b, 0xa0, 0xab, 0x90, 0xf4, 0xff };
    show("C.4.1", &h, c41[0..], &ar);

    var c42 = [_]u8{ 0x82, 0x86, 0x84, 0xbe, 0x58, 0x86, 0xa8, 0xeb, 0x10, 0x64, 0x9c, 0xbf };
    show("C.4.2", &h, c42[0..], &ar);

    var c43 = [_]u8{ 0x82, 0x87, 0x85, 0xbf, 0x40, 0x88, 0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xa9, 0x7d, 0x7f, 0x89, 0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xb8, 0xe8, 0xb4, 0xbf };
    show("C.4.3", &h, c43[0..], &ar);

    var enc_backing: [4096]u8 = undefined;
    var enc_ar = std.arena.init(enc_backing[0..]);
    var eb = std.buf.init(&enc_ar);
    var encoded_headers = [_]hp.HpackHeader{
        .{ .name = ":method", .value = "GET" },
        .{ .name = ":path", .value = "/xyz" },
        .{ .name = "x-test", .value = "value" },
    };
    hp.hpackEncode(encoded_headers[0..], &eb) catch {
        std.io.write("encode-fail\n");
    };
    hp.hpackInit(&h, storage[0..]);
    var enc_slice = std.buf.slice(&eb);
    show("encode-roundtrip", &h, enc_slice, &ar);

    hp.hpackInit(&h, storage[0..]);
    var overlong_int = [_]u8{ 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff };
    expectCorrupt(&h, overlong_int[0..], &ar);

    var too_big_update = [_]u8{ 0x3f, 0xe2, 0x1f };
    expectCorrupt(&h, too_big_update[0..], &ar);

    var one_header = [_]u8{0x82};
    expectCorruptOut0(&h, one_header[0..], &ar);
}
