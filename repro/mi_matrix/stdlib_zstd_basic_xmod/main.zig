// stdlib_zstd_basic_xmod — std_zstd (L4) RFC 8878 subset GREEN fixture.
//
// Covers: embedded corpus vectors (text/binary/incompressible at 1 KB), empty
// content, raw and RLE blocks, WindowTooBig at window_log 22 vs max 21, max 24
// accepts it, truncations and bit-flips -> error.Corrupt, dst-too-small ->
// error.OutputTooSmall, skippable frame + valid frame decodes the valid frame.
// The cross fixture round-trips ALL committed corpus vectors (the harness runs
// fixtures from a scratch CWD, so the basic fixture embeds its samples).
//
// GREEN (contract): deterministic byte-exact stdout `zstd basic ok\n` (rc 0).
const io = @import("std_io.zig");
const zstd = @import("std_zstd.zig");
const vec = @import("vectors_data.zig");

var g_dst: [65536]u8 = undefined;

const raw_frame = [_]u8{
    0x28, 0xB5, 0x2F, 0xFD, 0x20, 0x03, 0x19, 0x00, 0x00, 0x61, 0x62, 0x63,
};

const rle_frame = [_]u8{
    0x28, 0xB5, 0x2F, 0xFD, 0x20, 0x05, 0x2B, 0x00, 0x00, 0x41,
};

const empty_frame = [_]u8{
    0x28, 0xB5, 0x2F, 0xFD, 0x20, 0x00, 0x01, 0x00, 0x00,
};

const window22_frame = [_]u8{
    0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x60, 0x19, 0x00, 0x00, 0x61, 0x62, 0x63,
};

const reserved_frame = [_]u8{
    0x28, 0xB5, 0x2F, 0xFD, 0x28, 0x03, 0x19, 0x00, 0x00, 0x61, 0x62, 0x63,
};

const bad_magic_frame = [_]u8{
    0x28, 0xB5, 0x2F, 0xFC, 0x20, 0x03, 0x19, 0x00, 0x00, 0x61, 0x62, 0x63,
};

const skippable_and_raw = [_]u8{
    0x50, 0x2A, 0x4D, 0x18, 0x03, 0x00, 0x00, 0x00, 0x78, 0x79, 0x7A,
    0x28, 0xB5, 0x2F, 0xFD, 0x20, 0x03, 0x19, 0x00, 0x00, 0x61, 0x62, 0x63,
};

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn expectBytes(src: []const u8, want: []const u8, max_log: u8, what: []const u8) void {
    const n = zstd.zstdDecompress(src, g_dst[0..], max_log) catch {
        @panic(what);
    };
    ck(@intCast(usize, n) == want.len, what);
    var i: usize = 0;
    while (i < want.len) : (i += 1) {
        ck(g_dst[i] == want[i], what);
    }
}

fn expectCorrupt(src: []const u8, max_log: u8, what: []const u8) void {
    const n = zstd.zstdDecompress(src, g_dst[0..], max_log) catch |e| {
        if (e == error.Corrupt) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

fn expectWindowTooBig(src: []const u8, max_log: u8, what: []const u8) void {
    const n = zstd.zstdDecompress(src, g_dst[0..], max_log) catch |e| {
        if (e == error.WindowTooBig) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

fn expectTooSmall(src: []const u8, dst: []u8, max_log: u8, what: []const u8) void {
    const n = zstd.zstdDecompress(src, dst, max_log) catch |e| {
        if (e == error.OutputTooSmall) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

pub fn main() void {
    expectBytes(vec.text1k_w10_l19_in_slice(), vec.text1k_w10_l19_expected_slice(), 21, "corpus text l19 w10");
    expectBytes(vec.text1k_w21_l19_in_slice(), vec.text1k_w21_l19_expected_slice(), 21, "corpus text l19 w21");
    expectBytes(vec.binary1k_w10_l1_in_slice(), vec.binary1k_w10_l1_expected_slice(), 21, "corpus binary l1 w10");
    expectBytes(vec.random1k_w10_l1_in_slice(), vec.random1k_w10_l1_expected_slice(), 21, "corpus random l1 w10");
    expectBytes(empty_frame[0..], raw_frame[0..0], 21, "empty content frame");

    const abc = [_]u8{ 0x61, 0x62, 0x63 };
    const rle_want = [_]u8{ 0x41, 0x41, 0x41, 0x41, 0x41 };

    expectBytes(raw_frame[0..], abc[0..], 21, "raw block");
    expectBytes(rle_frame[0..], rle_want[0..], 21, "rle block");
    expectBytes(skippable_and_raw[0..], abc[0..], 21, "skippable + raw");

    expectWindowTooBig(window22_frame[0..], 21, "window 22 vs cap 21");
    expectBytes(window22_frame[0..], abc[0..], 24, "window 22 with cap 24");

    expectCorrupt(raw_frame[0..0], 21, "empty source");
    expectCorrupt(raw_frame[0..4], 21, "magic only");
    expectCorrupt(raw_frame[0..9], 21, "header truncation");
    expectCorrupt(raw_frame[0..10], 21, "block data truncation");
    expectCorrupt(reserved_frame[0..], 21, "reserved frame bit");
    expectCorrupt(bad_magic_frame[0..], 21, "bitflip magic");

    var small: [2]u8 = undefined;
    expectTooSmall(raw_frame[0..], small[0..], 21, "dst too small raw");
    var small_rle: [4]u8 = undefined;
    expectTooSmall(rle_frame[0..], small_rle[0..], 21, "dst too small rle");

    io.write("zstd basic ok\n");
}
