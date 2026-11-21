// stdlib_hpack_huffman_xmod — HPACK Huffman decode + malformed-input fixture.
//
// Decodes the RFC 7541 C.4 Huffman request examples (which exercise the
// two-level 8-bit table), a value containing long/rare codes that force the
// canonical bit-walk tail, and three fail-closed cases: a truncated code, an
// EOS symbol, and non-EOS padding.
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

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

pub fn main() void {
    var ar_backing: [65536]u8 = undefined;
    var ar = std.arena.init(ar_backing[0..]);
    var storage: [4096]u8 = undefined;
    var h: hp.Hpack = undefined;
    hp.hpackInit(&h, storage[0..]);

    var c41 = [_]u8{ 0x82, 0x86, 0x84, 0x41, 0x8c, 0xf1, 0xe3, 0xc2, 0xe5, 0xf2, 0x3a, 0x6b, 0xa0, 0xab, 0x90, 0xf4, 0xff };
    show("C.4.1", &h, c41[0..], &ar);

    var c42 = [_]u8{ 0x82, 0x86, 0x84, 0xbe, 0x58, 0x86, 0xa8, 0xeb, 0x10, 0x64, 0x9c, 0xbf };
    show("C.4.2", &h, c42[0..], &ar);

    var c43 = [_]u8{ 0x82, 0x87, 0x85, 0xbf, 0x40, 0x88, 0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xa9, 0x7d, 0x7f, 0x89, 0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xb8, 0xe8, 0xb4, 0xbf };
    show("C.4.3", &h, c43[0..], &ar);

    // Literal indexed-name :authority, Huffman value for the raw bytes
    // 00 01 92 7f ff (13/23/24/27/26-bit codes -> rare bit-walk tail).
    hp.hpackInit(&h, storage[0..]);
    var rare = [_]u8{ 0x41, 0x8e, 0xff, 0xc7, 0xff, 0xfd, 0x8f, 0xff, 0xf5, 0xff, 0xff, 0xff, 0xf3, 0xff, 0xff, 0xee };
    std.arena.reset(&ar);
    var out: [8]hp.HpackHeader = undefined;
    var n = hp.hpackDecode(&h, rare[0..], out[0..], &ar) catch {
        std.io.write("huff-rare fail\n");
        return;
    };
    var want = [_]u8{ 0x00, 0x01, 0x92, 0x7f, 0xff };
    if (n == 1 and eqBytes(out[0].value, want[0..])) {
        std.io.write("huff-rare ok\n");
    } else {
        std.io.write("huff-rare fail\n");
    }

    // Truncated EOS prefix (one 0xff byte).
    hp.hpackInit(&h, storage[0..]);
    var truncated = [_]u8{ 0x41, 0x81, 0xff };
    expectCorrupt(&h, truncated[0..], &ar);

    // EOS encoded as a symbol (30 one-bits + 2 one-bit padding).
    hp.hpackInit(&h, storage[0..]);
    var eos = [_]u8{ 0x41, 0x84, 0xff, 0xff, 0xff, 0xff };
    expectCorrupt(&h, eos[0..], &ar);

    // Non-EOS padding (symbol '0' then 000 padding).
    hp.hpackInit(&h, storage[0..]);
    var badpad = [_]u8{ 0x41, 0x81, 0x00 };
    expectCorrupt(&h, badpad[0..], &ar);
}
