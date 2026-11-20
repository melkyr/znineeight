const io = @import("std_io");
const os = @import("std_os");
const palette = @import("../palette.zig");
const zsp = @import("../zsp.zig");

var fails: usize = 0;

fn report(name: []const u8, ok: bool) void {
    if (ok) {
        io.write("ok - ");
    } else {
        io.write("FAIL - ");
        fails += 1;
    }
    io.write(name);
    io.write("\n");
}

fn wr16(buf: []u8, off: usize, v: u16) void {
    buf[off] = @intCast(u8, v & 0xFF);
    buf[off + 1] = @intCast(u8, v >> 8);
}

fn wr32(buf: []u8, off: usize, v: u32) void {
    buf[off] = @intCast(u8, v & 0xFF);
    buf[off + 1] = @intCast(u8, (v >> 8) & 0xFF);
    buf[off + 2] = @intCast(u8, (v >> 16) & 0xFF);
    buf[off + 3] = @intCast(u8, (v >> 24) & 0xFF);
}

fn buildZsp(buf: []u8, w: u16, h: u16, key: u8, ramp: u8, runs: []const u8) usize {
    const total: usize = 16 + 512 + runs.len;
    if (buf.len < total) return 0;
    buf[0] = 'Z';
    buf[1] = 'S';
    buf[2] = 'P';
    buf[3] = '1';
    wr16(buf, 4, w);
    wr16(buf, 6, h);
    buf[8] = key;
    buf[9] = ramp;
    wr16(buf, 10, 0);
    wr32(buf, 12, 0);
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        wr16(buf, 16 + i * 2, palette.RGB565[i]);
    }
    i = 0;
    while (i < runs.len) : (i += 1) {
        buf[16 + 512 + i] = runs[i];
    }
    return total;
}

fn tPaletteAnchors() bool {
    const want: [64]u16 = [64]u16{
        0x08A4, 0x29C9, 0x5B4F, 0x9D57,
        0x0947, 0x12CE, 0x24D6, 0x669D,
        0x3842, 0x88A4, 0xD147, 0xFB4F,
        0x0943, 0x1347, 0x258D, 0x6F34,
        0x3921, 0x8AC2, 0xD4C5, 0xFE4C,
        0x3045, 0x78CC, 0xC1D3, 0xF3DA,
        0x0946, 0x130E, 0x1D56, 0x66FD,
        0x10E6, 0x2A2D, 0x4BB4, 0x8D9B,
        0x38C1, 0x8A02, 0xD3A5, 0xF56C,
        0x38A5, 0x8A2D, 0xC454, 0xF63B,
        0x10C3, 0x3A09, 0x6BAF, 0xA597,
        0x3844, 0x88CA, 0xD1D1, 0xFBD7,
        0x1143, 0x3347, 0x5D4D, 0x9ED5,
        0x1947, 0x430F, 0x8D58, 0xCF1E,
        0x20A1, 0x59C3, 0x8B06, 0xC4CB,
        0x0945, 0x134B, 0x2D51, 0x0000,
    };
    var r: usize = 0;
    while (r < 16) : (r += 1) {
        if (palette.RGB565[r * 16] != want[r * 4]) return false;
        if (palette.RGB565[r * 16 + 5] != want[r * 4 + 1]) return false;
        if (palette.RGB565[r * 16 + 10] != want[r * 4 + 2]) return false;
        if (palette.RGB565[r * 16 + 15] != want[r * 4 + 3]) return false;
    }
    return true;
}

fn tPaletteIntermediates() bool {
    const want: [16]u16 = [16]u16{
        0x08A4, 0x10E5, 0x1926, 0x2167,
        0x2188, 0x29C9, 0x322A, 0x3A6B,
        0x4AAD, 0x530E, 0x5B4F, 0x6BB0,
        0x7432, 0x8493, 0x8CF5, 0x9D57,
    };
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        if (palette.RGB565[i] != want[i]) return false;
    }
    if (palette.RGB565[240] != 0x0945) return false;
    if (palette.RGB565[241] != 0x09C6) return false;
    if (palette.RGB565[244] != 0x12EA) return false;
    if (palette.RGB565[249] != 0x24F0) return false;
    if (palette.RGB565[250] != 0x2D51) return false;
    if (palette.RGB565[252] != 0x45F3) return false;
    if (palette.RGB565[253] != 0x5655) return false;
    if (palette.RGB565[254] != 0x5EB6) return false;
    return true;
}

fn tPaletteKeyAndRamp15() bool {
    if (palette.KEY_INDEX != 255) return false;
    if (palette.RGB565[255] != 0x0000) return false;
    if (palette.RGB565[254] == palette.RGB565[255]) return false;
    if (palette.RGB565[239] != 0xC4CB) return false;
    return true;
}

fn tDecodeGolden() bool {
    var buf: [600]u8 = undefined;
    const runs: [6]u8 = [6]u8{ 2, 0x11, 1, 0x22, 3, 0xFE };
    const len = buildZsp(buf[0..], 3, 2, 255, 1, runs[0..]);
    if (len != 534) return false;

    var pix: [8]u8 = [8]u8{ 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA };
    var lut: [256]u16 = undefined;
    var sprite: zsp.Sprite = undefined;
    var pixel_len: i32 = -1;
    if (!zsp.zspDecode(buf[0..len], &sprite, &lut, pix[0..], &pixel_len)) return false;

    if (sprite.w != 3 or sprite.h != 2) return false;
    if (sprite.key != 255) return false;
    if (pixel_len != 6) return false;
    if (pix[0] != 0x11 or pix[1] != 0x11) return false;
    if (pix[2] != 0x22) return false;
    if (pix[3] != 0xFE or pix[4] != 0xFE or pix[5] != 0xFE) return false;
    if (pix[6] != 0xAA or pix[7] != 0xAA) return false;

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        if (lut[i] != palette.RGB565[i]) return false;
    }
    if (sprite.idx[0] != pix[0] or sprite.idx[5] != pix[5]) return false;
    if (sprite.lut[0] != lut[0] or sprite.lut[255] != lut[255]) return false;
    return true;
}

fn tDecodeRejects() bool {
    var buf: [600]u8 = undefined;
    const runs: [6]u8 = [6]u8{ 2, 0x11, 1, 0x22, 3, 0xFE };
    const len = buildZsp(buf[0..], 3, 2, 255, 1, runs[0..]);
    if (len == 0) return false;

    var pix: [8]u8 = undefined;
    var lut: [256]u16 = undefined;
    var sprite: zsp.Sprite = undefined;
    var pixel_len: i32 = 0;

    if (zsp.zspDecode(buf[0..15], &sprite, &lut, pix[0..], &pixel_len)) return false;
    if (zsp.zspDecode(buf[0..527], &sprite, &lut, pix[0..], &pixel_len)) return false;
    if (zsp.zspDecode(buf[0 .. len - 1], &sprite, &lut, pix[0..], &pixel_len)) return false;

    buf[0] = 'X';
    if (zsp.zspDecode(buf[0..len], &sprite, &lut, pix[0..], &pixel_len)) return false;
    buf[0] = 'Z';

    buf[10] = 1;
    if (zsp.zspDecode(buf[0..len], &sprite, &lut, pix[0..], &pixel_len)) return false;
    buf[10] = 0;

    buf[12] = 1;
    if (zsp.zspDecode(buf[0..len], &sprite, &lut, pix[0..], &pixel_len)) return false;
    buf[12] = 0;

    var bad: [600]u8 = undefined;
    const zero_run: [2]u8 = [2]u8{ 0, 1 };
    var n = buildZsp(bad[0..], 6, 1, 255, 1, zero_run[0..]);
    if (zsp.zspDecode(bad[0..n], &sprite, &lut, pix[0..], &pixel_len)) return false;

    const over_run: [4]u8 = [4]u8{ 4, 1, 4, 2 };
    n = buildZsp(bad[0..], 6, 1, 255, 1, over_run[0..]);
    if (zsp.zspDecode(bad[0..n], &sprite, &lut, pix[0..], &pixel_len)) return false;

    const short_run: [4]u8 = [4]u8{ 3, 1, 2, 2 };
    n = buildZsp(bad[0..], 6, 1, 255, 1, short_run[0..]);
    if (zsp.zspDecode(bad[0..n], &sprite, &lut, pix[0..], &pixel_len)) return false;

    const extra_run: [4]u8 = [4]u8{ 6, 1, 1, 2 };
    n = buildZsp(bad[0..], 6, 1, 255, 1, extra_run[0..]);
    if (zsp.zspDecode(bad[0..n], &sprite, &lut, pix[0..], &pixel_len)) return false;

    const odd_run: [3]u8 = [3]u8{ 6, 1, 2 };
    n = buildZsp(bad[0..], 6, 1, 255, 1, odd_run[0..]);
    if (zsp.zspDecode(bad[0..n], &sprite, &lut, pix[0..], &pixel_len)) return false;

    var tiny: [5]u8 = undefined;
    n = buildZsp(bad[0..], 3, 2, 255, 1, runs[0..]);
    if (zsp.zspDecode(bad[0..n], &sprite, &lut, tiny[0..], &pixel_len)) return false;
    return true;
}

fn tDecodeOversize() bool {
    var buf: [600]u8 = undefined;
    const runs: [2]u8 = [2]u8{ 6, 1 };
    var len = buildZsp(buf[0..], 100, 100, 255, 1, runs[0..]);
    var pix: [8]u8 = undefined;
    var lut: [256]u16 = undefined;
    var sprite: zsp.Sprite = undefined;
    var pixel_len: i32 = 0;
    if (zsp.zspDecode(buf[0..len], &sprite, &lut, pix[0..], &pixel_len)) return false;

    len = buildZsp(buf[0..], 0xFFFF, 0xFFFF, 255, 1, runs[0..]);
    if (zsp.zspDecode(buf[0..len], &sprite, &lut, pix[0..], &pixel_len)) return false;
    return true;
}

fn tDecodeFailureNoWrites() bool {
    var buf: [600]u8 = undefined;
    const runs: [6]u8 = [6]u8{ 2, 0x11, 1, 0x22, 3, 0xFE };
    const len = buildZsp(buf[0..], 3, 2, 255, 1, runs[0..]);

    const dummy_idx: [1]u8 = [1]u8{0};
    const dummy_lut: [1]u16 = [1]u16{0};
    var sprite = zsp.Sprite{
        .w = 123,
        .h = 456,
        .idx = @ptrCast([*]const u8, &dummy_idx[0]),
        .lut = @ptrCast([*]const u16, &dummy_lut[0]),
        .key = 7,
    };
    var lut: [256]u16 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        lut[i] = 0xABCD;
    }
    var pix: [6]u8 = undefined;
    i = 0;
    while (i < 6) : (i += 1) {
        pix[i] = 0x5A;
    }
    var pixel_len: i32 = -1;

    if (zsp.zspDecode(buf[0 .. len - 1], &sprite, &lut, pix[0..], &pixel_len)) return false;
    if (sprite.w != 123 or sprite.h != 456 or sprite.key != 7) return false;
    if (pixel_len != -1) return false;
    i = 0;
    while (i < 256) : (i += 1) {
        if (lut[i] != 0xABCD) return false;
    }
    return true;
}

fn checkRecolor(base: *const [256]u16, from_ramp: u8, to_ramp: u8) bool {
    var out: [256]u16 = undefined;
    zsp.zspRecolorLut(&out, base, from_ramp, to_ramp);
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        var want = base[i];
        if (i < 255) {
            const ramp: u8 = @intCast(u8, i >> 4);
            if (ramp == from_ramp) {
                const shade: u8 = @intCast(u8, i & 15);
                var src: usize = @intCast(usize, to_ramp) * 16 + @intCast(usize, shade);
                if (to_ramp == 15 and shade == 15) src = 254;
                want = base[src];
            }
        }
        if (out[i] != want) return false;
    }
    return true;
}

fn tRecolorExact() bool {
    var base: [256]u16 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        base[i] = @intCast(u16, i) | (@intCast(u16, i) << 8);
    }
    if (!checkRecolor(&base, 6, 1)) return false;
    if (!checkRecolor(&base, 8, 11)) return false;
    if (!checkRecolor(&base, 11, 5)) return false;
    if (!checkRecolor(&base, 1, 6)) return false;
    return true;
}

fn tRecolorRamp15() bool {
    var base: [256]u16 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        base[i] = @intCast(u16, i) | (@intCast(u16, i) << 8);
    }
    if (!checkRecolor(&base, 6, 15)) return false;
    if (!checkRecolor(&base, 15, 1)) return false;

    var out: [256]u16 = undefined;
    zsp.zspRecolorLut(&out, &base, 6, 15);
    if (out[6 * 16 + 15] != base[254]) return false;
    if (out[6 * 16 + 14] != base[254]) return false;
    if (out[6 * 16 + 0] != base[240]) return false;
    if (out[255] != base[255]) return false;
    return true;
}

fn tRecolorDegenerateSafe() bool {
    var base: [256]u16 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        base[i] = @intCast(u16, i) | (@intCast(u16, i) << 8);
    }
    if (!checkRecolor(&base, 5, 5)) return false;
    if (!checkRecolor(&base, 0, 2)) return false;

    var out: [256]u16 = undefined;
    zsp.zspRecolorLut(&out, &base, 5, 5);
    i = 0;
    while (i < 256) : (i += 1) {
        if (out[i] != base[i]) return false;
    }
    zsp.zspRecolorLut(&out, &base, 0, 2);
    if (out[0] != base[32]) return false;
    if (out[15] != base[47]) return false;
    if (out[255] != base[255]) return false;
    return true;
}

fn tCanonicalEncode() bool {
    var pix: [265]u8 = undefined;
    var i: usize = 0;
    while (i < 260) : (i += 1) pix[i] = 0;
    while (i < 262) : (i += 1) pix[i] = 1;
    while (i < 265) : (i += 1) pix[i] = 2;

    var out: [8]u8 = undefined;
    const want: [8]u8 = [8]u8{ 255, 0, 5, 0, 2, 1, 3, 2 };
    var n = zsp.zspCanonicalEncode(pix[0..], 265, 1, out[0..]);
    if (n != 8) return false;
    i = 0;
    while (i < 8) : (i += 1) {
        if (out[i] != want[i]) return false;
    }

    var a: [256]u8 = undefined;
    i = 0;
    while (i < 256) : (i += 1) a[i] = 0;
    var o2: [4]u8 = undefined;
    n = zsp.zspCanonicalEncode(a[0..], 256, 1, o2[0..]);
    if (n != 4 or o2[0] != 255 or o2[1] != 0 or o2[2] != 1 or o2[3] != 0) return false;

    var b: [510]u8 = undefined;
    i = 0;
    while (i < 510) : (i += 1) b[i] = 0;
    var o3: [4]u8 = undefined;
    n = zsp.zspCanonicalEncode(b[0..], 510, 1, o3[0..]);
    if (n != 4 or o3[0] != 255 or o3[1] != 0 or o3[2] != 255 or o3[3] != 0) return false;

    var c: [511]u8 = undefined;
    i = 0;
    while (i < 511) : (i += 1) c[i] = 0;
    var o4: [6]u8 = undefined;
    n = zsp.zspCanonicalEncode(c[0..], 511, 1, o4[0..]);
    if (n != 6) return false;
    if (o4[0] != 255 or o4[1] != 0 or o4[2] != 255 or o4[3] != 0) return false;
    if (o4[4] != 1 or o4[5] != 0) return false;
    return true;
}

fn tCanonicalRoundTrip() bool {
    var pix: [267]u8 = undefined;
    var i: usize = 0;
    while (i < 260) : (i += 1) pix[i] = 0;
    while (i < 267) : (i += 1) pix[i] = 1;

    var data: [8]u8 = undefined;
    const n = zsp.zspCanonicalEncode(pix[0..], 267, 1, data[0..]);
    if (n != 6) return false;

    var buf: [600]u8 = undefined;
    const len = buildZsp(buf[0..], 267, 1, 255, 6, data[0..n]);
    var got: [267]u8 = undefined;
    var lut: [256]u16 = undefined;
    var sprite: zsp.Sprite = undefined;
    var pixel_len: i32 = 0;
    if (!zsp.zspDecode(buf[0..len], &sprite, &lut, got[0..], &pixel_len)) return false;
    if (pixel_len != 267) return false;
    i = 0;
    while (i < 267) : (i += 1) {
        if (got[i] != pix[i]) return false;
    }
    return true;
}

fn tNonCanonicalRejected() bool {
    const noncanonical: [8]u8 = [8]u8{ 1, 0, 1, 0, 1, 0, 2, 1 };
    var buf: [600]u8 = undefined;
    const len = buildZsp(buf[0..], 5, 1, 255, 1, noncanonical[0..]);
    var pix: [5]u8 = undefined;
    var lut: [256]u16 = undefined;
    var sprite: zsp.Sprite = undefined;
    var pixel_len: i32 = 0;
    if (!zsp.zspDecode(buf[0..len], &sprite, &lut, pix[0..], &pixel_len)) return false;
    if (pix[0] != 0 or pix[1] != 0 or pix[2] != 0 or pix[3] != 1 or pix[4] != 1) return false;

    var canon: [4]u8 = undefined;
    const n = zsp.zspCanonicalEncode(pix[0..], 5, 1, canon[0..]);
    if (n != 4) return false;
    if (canon[0] != 3 or canon[1] != 0 or canon[2] != 2 or canon[3] != 1) return false;
    if (n == noncanonical.len) return false;
    return true;
}

fn tEncodeOverflow() bool {
    const pix: [4]u8 = [4]u8{ 1, 1, 2, 2 };
    var tiny: [1]u8 = undefined;
    if (zsp.zspCanonicalEncode(pix[0..], 4, 1, tiny[0..]) != 0) return false;
    var out: [16]u8 = undefined;
    if (zsp.zspCanonicalEncode(pix[0..], 5, 1, out[0..]) != 0) return false;
    if (zsp.zspCanonicalEncode(pix[0..], 0, 0, out[0..]) != 0) return false;
    if (zsp.zspCanonicalEncode(pix[0..], 0xFFFFFFFF, 2, out[0..]) != 0) return false;
    return true;
}

pub fn main() void {
    report("palette_anchors_0_5_10_15", tPaletteAnchors());
    report("palette_intermediate_rounding", tPaletteIntermediates());
    report("palette_key_255_ramp15", tPaletteKeyAndRamp15());
    report("decode_golden_pixels_lut", tDecodeGolden());
    report("decode_rejects_truncated_garbage_runs", tDecodeRejects());
    report("decode_rejects_oversize", tDecodeOversize());
    report("decode_failure_writes_nothing_outside_pix", tDecodeFailureNoWrites());
    report("recolor_lut_exact", tRecolorExact());
    report("recolor_lut_ramp15_base254", tRecolorRamp15());
    report("recolor_lut_from_eq_to_and_ramp0_safe", tRecolorDegenerateSafe());
    report("canonical_encode_greedy_255", tCanonicalEncode());
    report("canonical_encode_round_trip", tCanonicalRoundTrip());
    report("canonical_rejects_noncanonical_bytes", tNonCanonicalRejected());
    report("canonical_encode_overflow_zero", tEncodeOverflow());

    if (fails != 0) os.exit(1);
    io.write("zsp_test PASS\n");
}
