// px_core_test.zig — native gate for the M9 Task 1 pure pixel core.
//
// Compiles sf/src/std_gfx_px_core.zig directly (no std_gfx/std_gfx_pal, no
// Windows headers): exact 565 LUT anchors, key skip, software clipping,
// pitch>w*2 dump, §27 bar math, the memory-target API, and one deterministic
// 320x200 framebuffer checksum.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/px_core_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/px_core_test"
//   "$OUT/px_core_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const core = @import("../../../../sf/src/std_gfx_px_core.zig");

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

fn openFails(w: u32, h: u32) bool {
    var ok = false;
    core.gfxPxOpenMemory(w, h) catch |err| {
        ok = err == error.OpenFailed;
    };
    return ok;
}

fn dumpPix(d: []const u8, x: usize, y: usize, w: usize) u16 {
    const off = (y * w + x) * 2;
    return @intCast(u16, d[off]) | (@intCast(u16, d[off + 1]) << 8);
}

fn surfPix(sf: *const core.Surface, x: i32, y: i32) u16 {
    const off = @intCast(usize, y) * @intCast(usize, sf.pitch) + @intCast(usize, x * 2);
    return @intCast(u16, sf.pixels[off]) | (@intCast(u16, sf.pixels[off + 1]) << 8);
}

fn tOpenMemory() bool {
    if (!openFails(0, 200)) return false;
    if (!openFails(320, 0)) return false;
    if (!openFails(641, 200)) return false;
    if (!openFails(320, 481)) return false;

    const g = core.gfxPxOpenMemory(320, 200) catch return false;
    if (core.gfxPxDump(g).len != 320 * 200 * 2) return false;

    const gmax = core.gfxPxOpenMemory(640, 480) catch return false;
    if (core.gfxPxDump(gmax).len != 640 * 480 * 2) return false;
    return true;
}

fn tRepaintFlagSemantics() bool {
    const g = core.gfxPxOpenMemory(8, 2) catch return false;
    if (core.pxCoreSurfaceLost(g.opaque)) return false;
    if (core.pxCoreNeedsFullRepaint(g.opaque)) return false;

    core.pxCoreMarkSurfaceLost(g.opaque);
    if (!core.pxCoreSurfaceLost(g.opaque)) return false;
    if (core.pxCoreNeedsFullRepaint(g.opaque)) return false;

    core.pxCoreMarkRestored(g.opaque);
    if (core.pxCoreSurfaceLost(g.opaque)) return false;
    if (!core.pxCoreNeedsFullRepaint(g.opaque)) return false;

    core.pxCoreClearFullRepaint(g.opaque);
    if (core.pxCoreNeedsFullRepaint(g.opaque)) return false;

    core.pxCoreMarkSurfaceLost(g.opaque);
    const g2 = core.gfxPxOpenMemory(8, 2) catch return false;
    if (g2 != g) return false;
    if (core.pxCoreSurfaceLost(g.opaque)) return false;
    if (core.pxCoreNeedsFullRepaint(g.opaque)) return false;
    return true;
}

fn tLutAnchors() bool {
    const g = core.gfxPxOpenMemory(8, 2) catch return false;
    const lut: [8]u16 = [8]u16{
        0x0000, 0xF800, 0x07E0, 0x001F, 0xFFFF, 0x8410, 0xF81F, 0x07FF,
    };
    const idx: [8]u8 = [8]u8{ 0, 1, 2, 3, 4, 5, 6, 7 };
    const s = core.Sprite{
        .w = 8,
        .h = 1,
        .idx = @ptrCast([*]const u8, &idx[0]),
        .lut = @ptrCast([*]const u16, &lut[0]),
        .key = 255,
    };
    core.gfxPxFill(g, 0, 0, 8, 2, 0x1234);
    core.gfxPxBlit(g, 0, 1, &s);
    const d = core.gfxPxDump(g);
    var x: usize = 0;
    while (x < 8) : (x += 1) {
        if (dumpPix(d, x, 1, 8) != lut[x]) return false;
        if (dumpPix(d, x, 0, 8) != 0x1234) return false;
    }
    return true;
}

fn tKeySkip() bool {
    const g = core.gfxPxOpenMemory(6, 3) catch return false;
    const lut: [6]u16 = [6]u16{ 0xF800, 0x07E0, 0x001F, 0xFFFF, 0x8410, 0x1234 };
    const idx: [4]u8 = [4]u8{ 5, 1, 5, 2 };
    const s = core.Sprite{
        .w = 4,
        .h = 1,
        .idx = @ptrCast([*]const u8, &idx[0]),
        .lut = @ptrCast([*]const u16, &lut[0]),
        .key = 5,
    };
    core.gfxPxFill(g, 0, 0, 6, 3, 0xABCD);
    core.gfxPxBlit(g, 1, 1, &s);
    const d = core.gfxPxDump(g);
    if (dumpPix(d, 1, 1, 6) != 0xABCD) return false;
    if (dumpPix(d, 2, 1, 6) != 0x07E0) return false;
    if (dumpPix(d, 3, 1, 6) != 0xABCD) return false;
    if (dumpPix(d, 4, 1, 6) != 0x001F) return false;
    return true;
}

fn tFillClip() bool {
    var buf: [128]u8 = [128]u8{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    };
    const sf = core.Surface{
        .pixels = @ptrCast([*]u8, &buf[0]),
        .pitch = 16,
        .w = 8,
        .h = 8,
    };
    core.pxCoreFill(&sf, 0, 0, 8, 8, 0x0101);
    core.pxCoreFill(&sf, -2, -3, 5, 5, 0xAAAA);
    if (surfPix(&sf, 0, 0) != 0xAAAA) return false;
    if (surfPix(&sf, 2, 1) != 0xAAAA) return false;
    if (surfPix(&sf, 3, 0) != 0x0101) return false;
    if (surfPix(&sf, 0, 2) != 0x0101) return false;

    core.pxCoreFill(&sf, 6, 6, 10, 10, 0xBBBB);
    if (surfPix(&sf, 6, 6) != 0xBBBB) return false;
    if (surfPix(&sf, 7, 7) != 0xBBBB) return false;
    if (surfPix(&sf, 5, 6) != 0x0101) return false;
    if (surfPix(&sf, 7, 5) != 0x0101) return false;

    core.pxCoreFill(&sf, -100, -100, 50, 50, 0xCCCC);
    core.pxCoreFill(&sf, 8, 0, 1, 1, 0xCCCC);
    if (surfPix(&sf, 0, 0) != 0xAAAA) return false;
    return true;
}

fn tBlitClip() bool {
    var buf: [128]u8 = [128]u8{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    };
    const sf = core.Surface{
        .pixels = @ptrCast([*]u8, &buf[0]),
        .pitch = 16,
        .w = 8,
        .h = 8,
    };
    const lut: [9]u16 = [9]u16{
        0x0000, 0x1001, 0x1002, 0x1003, 0x1004,
        0x1005, 0x1006, 0x1007, 0x1008,
    };
    const idx: [16]u8 = [16]u8{
        1, 2, 3, 4,
        5, 6, 7, 8,
        1, 2, 3, 4,
        5, 6, 7, 8,
    };
    const s = core.Sprite{
        .w = 4,
        .h = 4,
        .idx = @ptrCast([*]const u8, &idx[0]),
        .lut = @ptrCast([*]const u16, &lut[0]),
        .key = 0,
    };

    core.pxCoreFill(&sf, 0, 0, 8, 8, 0xBEEF);
    core.pxCoreBlit(&sf, -1, -1, &s);
    if (surfPix(&sf, 0, 0) != 0x1006) return false;
    if (surfPix(&sf, 1, 0) != 0x1007) return false;
    if (surfPix(&sf, 2, 2) != 0x1008) return false;
    if (surfPix(&sf, 3, 2) != 0xBEEF) return false;
    if (surfPix(&sf, 0, 3) != 0xBEEF) return false;

    core.pxCoreFill(&sf, 0, 0, 8, 8, 0xBEEF);
    core.pxCoreBlit(&sf, 6, 6, &s);
    if (surfPix(&sf, 6, 6) != 0x1001) return false;
    if (surfPix(&sf, 7, 7) != 0x1006) return false;
    if (surfPix(&sf, 5, 6) != 0xBEEF) return false;
    if (surfPix(&sf, 6, 5) != 0xBEEF) return false;
    return true;
}

fn tBlitPartClip() bool {
    var buf: [128]u8 = [128]u8{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    };
    const sf = core.Surface{
        .pixels = @ptrCast([*]u8, &buf[0]),
        .pitch = 16,
        .w = 8,
        .h = 8,
    };
    const lut: [5]u16 = [5]u16{ 0x0000, 0x1001, 0x1002, 0x1003, 0x1004 };
    const idx: [25]u8 = [25]u8{
        1, 2, 3, 4, 1,
        2, 3, 4, 1, 2,
        3, 4, 1, 2, 3,
        4, 1, 2, 3, 4,
        1, 2, 3, 4, 1,
    };
    const s = core.Sprite{
        .w = 5,
        .h = 5,
        .idx = @ptrCast([*]const u8, &idx[0]),
        .lut = @ptrCast([*]const u16, &lut[0]),
        .key = 0,
    };

    core.pxCoreFill(&sf, 0, 0, 8, 8, 0x0000);
    core.pxCoreBlitPart(&sf, 2, 1, &s, 1, 2, 3, 2);
    if (surfPix(&sf, 2, 1) != 0x1004) return false;
    if (surfPix(&sf, 3, 1) != 0x1001) return false;
    if (surfPix(&sf, 4, 1) != 0x1002) return false;
    if (surfPix(&sf, 2, 2) != 0x1001) return false;
    if (surfPix(&sf, 3, 2) != 0x1002) return false;
    if (surfPix(&sf, 4, 2) != 0x1003) return false;
    if (surfPix(&sf, 1, 1) != 0x0000) return false;
    if (surfPix(&sf, 5, 2) != 0x0000) return false;
    if (surfPix(&sf, 2, 0) != 0x0000) return false;

    core.pxCoreFill(&sf, 0, 0, 8, 8, 0x0000);
    core.pxCoreBlitPart(&sf, 0, 0, &s, -1, -1, 3, 3);
    if (surfPix(&sf, 1, 1) != 0x1001) return false;
    if (surfPix(&sf, 2, 1) != 0x1002) return false;
    if (surfPix(&sf, 1, 2) != 0x1002) return false;
    if (surfPix(&sf, 2, 2) != 0x1003) return false;
    if (surfPix(&sf, 0, 0) != 0x0000) return false;
    if (surfPix(&sf, 3, 3) != 0x0000) return false;

    core.pxCoreFill(&sf, 0, 0, 8, 8, 0x0000);
    core.pxCoreBlitPart(&sf, 0, 0, &s, 4, 4, 5, 5);
    if (surfPix(&sf, 0, 0) != 0x1001) return false;
    if (surfPix(&sf, 1, 1) != 0x0000) return false;

    core.pxCoreFill(&sf, 0, 0, 8, 8, 0x0000);
    core.pxCoreBlitPart(&sf, 0, 0, &s, 0, 0, 0, 5);
    core.pxCoreBlitPart(&sf, 0, 0, &s, 0, 0, 5, -1);
    if (surfPix(&sf, 0, 0) != 0x0000) return false;
    return true;
}

fn tPitchAndDump() bool {
    var buf: [64]u8 = [64]u8{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    };
    const sf = core.Surface{
        .pixels = @ptrCast([*]u8, &buf[0]),
        .pitch = 12,
        .w = 4,
        .h = 3,
    };
    core.pxCoreFill(&sf, 0, 0, 4, 1, 0x1111);
    core.pxCoreFill(&sf, 0, 1, 4, 1, 0x2222);
    core.pxCoreFill(&sf, 0, 2, 4, 1, 0x3333);

    if (surfPix(&sf, 0, 1) != 0x2222) return false;
    if (surfPix(&sf, 3, 2) != 0x3333) return false;
    if (buf[8] != 0 or buf[9] != 0 or buf[10] != 0 or buf[11] != 0) return false;
    if (buf[20] != 0 or buf[21] != 0 or buf[22] != 0 or buf[23] != 0) return false;
    if (buf[32] != 0 or buf[33] != 0 or buf[34] != 0 or buf[35] != 0) return false;

    var out: [24]u8 = [24]u8{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    };
    core.pxCoreDump(&sf, out[0..]);
    if (out[0] != 0x11 or out[1] != 0x11) return false;
    if (out[8] != 0x22 or out[9] != 0x22) return false;
    if (out[16] != 0x33 or out[17] != 0x33) return false;
    if (out[6] != 0x11 or out[7] != 0x11) return false;
    return true;
}

fn tBarMath() bool {
    const zero = core.pxCoreBar(100, 0, 100, 10);
    if (zero.fill != 0 or zero.red != 15) return false;
    const half = core.pxCoreBar(100, 50, 100, 10);
    if (half.fill != 50 or half.red != 15) return false;
    const full = core.pxCoreBar(100, 100, 100, 10);
    if (full.fill != 100 or full.red != 15) return false;
    const m25 = core.pxCoreBar(100, 50, 100, 25);
    if (m25.fill != 50 or m25.red != 0) return false;
    const wide = core.pxCoreBar(200, 100, 100, 10);
    if (wide.fill != 200 or wide.red != 30) return false;
    const clampRed = core.pxCoreBar(100, 50, 100, -100);
    if (clampRed.fill != 50 or clampRed.red != 100) return false;
    const over = core.pxCoreBar(100, 150, 100, 10);
    if (over.fill != 100 or over.red != 15) return false;
    const under = core.pxCoreBar(100, -10, 100, 10);
    if (under.fill != 0 or under.red != 15) return false;
    const noMax = core.pxCoreBar(100, 50, 0, 10);
    if (noMax.fill != 0 or noMax.red != 0) return false;
    const negMax = core.pxCoreBar(100, 50, -5, 10);
    if (negMax.fill != 0 or negMax.red != 0) return false;
    return true;
}

fn checksum(data: []const u8) u32 {
    var h: u32 = 2166136261;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        h = (h ^ @intCast(u32, data[i])) *% 16777619;
    }
    return h;
}

// One deterministic 320x200 framebuffer golden. Expected FNV-1a 32 value is
// pinned after the first correct run; the composition below is frozen.
const GOLDEN_320X200: u32 = 0xFB462D0F;

fn tGolden320x200() bool {
    const g = core.gfxPxOpenMemory(320, 200) catch return false;
    core.gfxPxFill(g, 0, 0, 320, 200, 0x0020);
    core.gfxPxFill(g, 16, 16, 96, 96, 0x09E0);
    core.gfxPxFill(g, 128, 32, 180, 12, 0x7BEF);
    const b = core.pxCoreBar(180, 62, 100, 10);
    core.gfxPxFill(g, 128 + b.fill, 32, b.red, 12, 0xF800);

    const lut: [4]u16 = [4]u16{ 0x0000, 0xF800, 0x07E0, 0x001F };
    const idx: [16]u8 = [16]u8{
        1, 2, 3, 1,
        2, 3, 1, 2,
        3, 1, 2, 3,
        1, 2, 3, 1,
    };
    const s = core.Sprite{
        .w = 4,
        .h = 4,
        .idx = @ptrCast([*]const u8, &idx[0]),
        .lut = @ptrCast([*]const u16, &lut[0]),
        .key = 0,
    };
    core.gfxPxBlit(g, 200, 100, &s);
    const d = core.gfxPxDump(g);
    if (d.len != 320 * 200 * 2) return false;
    return checksum(d) == GOLDEN_320X200;
}

pub fn main() void {
    report("memory_open_dimensions", tOpenMemory());
    report("repaint_flag_set_clear", tRepaintFlagSemantics());
    report("lut_565_anchors", tLutAnchors());
    report("key_byte_skip", tKeySkip());
    report("fill_clip_all_edges", tFillClip());
    report("blit_clip_negative_edges", tBlitClip());
    report("blit_part_source_clip", tBlitPartClip());
    report("pitch_pad_and_tight_dump", tPitchAndDump());
    report("bar_math_spec27", tBarMath());
    report("golden_320x200_framebuffer", tGolden320x200());

    if (fails != 0) os.exit(1);
    io.write("px_core_test PASS\n");
}
