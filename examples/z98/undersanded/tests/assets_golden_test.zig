// assets_golden_test.zig — UNDERSANDED M10 decoded-asset golden driver.
//
// Decodes three representative committed `.ZSP` files (creature eel00,
// creature boss00, background bg_a) with the one runtime decoder (`zsp.zig`)
// and pins, for each: dimensions, key index, header ramp, full pixel-byte
// FNV-1a checksum, full LUT FNV-1a checksum, and three sample pixels
// (top-left, centre, bottom-right).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/assets_golden_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/assets_golden_test"
//   "$OUT/assets_golden_test"
//
// Env: M10_ASSETS_OUT  `.zsp` directory override (default the committed
//                       `examples/z98/undersanded/assets/out`; the M10 tier
//                       uses a mutated copy to prove the golden is non-vacuous).

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const file_mod = @import("std_file");
const paths = @import("../paths.zig");
const palette = @import("../palette.zig");
const text_scan = @import("../text_scan.zig");
const zsp = @import("../zsp.zig");

const DEFAULT_OUT = "examples/z98/undersanded/assets/out";
const MAX_FILE: usize = 64 * 1024;
const MAX_PIX: usize = 640 * 300;

// eel00: 96x96, ramp 6 (Fins), key 255.
const EEL_PIX_FNV: u32 = 0xf623b7c9;
const EEL_LUT_FNV: u32 = 0xd098bcc9;
const EEL_P0: u8 = 255;
const EEL_PC: u8 = 255;
const EEL_PZ: u8 = 255;

// boss00: 96x96, ramp 10 (Armor), key 255.
const BOSS_PIX_FNV: u32 = 0x8e4ac719;
const BOSS_LUT_FNV: u32 = 0xd098bcc9;
const BOSS_P0: u8 = 255;
const BOSS_PC: u8 = 160;
const BOSS_PZ: u8 = 255;

// bg_a: 640x300, ramp 1 (opaque background), key 255.
const BGA_PIX_FNV: u32 = 0x1722e7f4;
const BGA_LUT_FNV: u32 = 0xd098bcc9;
const BGA_P0: u8 = 21;
const BGA_PC: u8 = 21;
const BGA_PZ: u8 = 239;

var fails: usize = 0;
var g_file_buf: [MAX_FILE]u8 = undefined;
var g_pix: [MAX_PIX]u8 = undefined;
var g_lut: [256]u16 = undefined;

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

fn fnvBytes(data: []const u8) u32 {
    var h: u32 = 2166136261;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        h = (h ^ @intCast(u32, data[i])) *% 16777619;
    }
    return h;
}

fn fnvLut(lut: *const [256]u16) u32 {
    var h: u32 = 2166136261;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        h = (h ^ @intCast(u32, lut[i] & 0xFF)) *% 16777619;
        h = (h ^ @intCast(u32, lut[i] >> 8)) *% 16777619;
    }
    return h;
}

fn appendHex(out: []u8, p: *usize, v: u32) void {
    text_scan.appendText(out, p, "0x");
    var i: u32 = 8;
    while (i > 0) {
        i -= 1;
        const nib: u32 = (v >> @intCast(u32, i * 4)) & @intCast(u32, 15);
        var c: u8 = 0;
        if (nib < 10) {
            c = @intCast(u8, nib) + '0';
        } else {
            c = @intCast(u8, nib - 10) + 'a';
        }
        if (p.* < out.len) {
            out[p.*] = c;
            p.* += 1;
        }
    }
}

fn buildFileName(name: []const u8, out: []u8) ?[]const u8 {
    if (name.len + 4 > out.len) return null;
    var i: usize = 0;
    while (i < name.len) : (i += 1) out[i] = name[i];
    out[name.len] = '.';
    out[name.len + 1] = 'z';
    out[name.len + 2] = 's';
    out[name.len + 3] = 'p';
    return out[0 .. name.len + 4];
}

fn decodeInto(dir: []const u8, name: []const u8, pix_len: *i32,
    sprite: *zsp.Sprite, ramp: *u8) bool {
    var name_buf: [24]u8 = undefined;
    const file_name = buildFileName(name, name_buf[0..]) orelse return false;
    var path_buf: [512]u8 = undefined;
    const path = paths.join(dir, file_name, path_buf[0..]) orelse return false;

    var arena = arena_mod.init(g_file_buf[0..]);
    const data = file_mod.readAll(&arena, path) catch return false;
    if (data.len < 16 + 512) return false;
    ramp.* = data[9];
    return zsp.zspDecode(data, sprite, &g_lut, g_pix[0..], pix_len);
}

fn lutMatchesPalette() bool {
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        if (g_lut[i] != palette.RGB565[i]) return false;
    }
    return true;
}

fn checkAsset(dir: []const u8, name: []const u8, want_w: u32, want_h: u32,
    want_ramp: u8, want_pix_fnv: u32, want_lut_fnv: u32,
    want_p0: u8, want_pc: u8, want_pz: u8, label: []const u8) void {
    var sprite: zsp.Sprite = undefined;
    var pix_len: i32 = -1;
    var ramp: u8 = 0;
    const decoded = decodeInto(dir, name, &pix_len, &sprite, &ramp);

    var ok = decoded;
    if (ok) {
        const total: usize = @intCast(usize, want_w) * @intCast(usize, want_h);
        const wi: usize = @intCast(usize, want_w);
        const hi: usize = @intCast(usize, want_h);
        const ci: usize = (hi / 2) * wi + wi / 2;
        const zi: usize = (hi - 1) * wi + (wi - 1);

        if (sprite.w != want_w or sprite.h != want_h) ok = false;
        if (sprite.key != palette.KEY_INDEX) ok = false;
        if (ramp != want_ramp) ok = false;
        if (pix_len != @intCast(i32, total)) ok = false;
        if (!lutMatchesPalette()) ok = false;
        const pix_fnv = fnvBytes(g_pix[0..total]);
        const lut_fnv = fnvLut(&g_lut);
        if (pix_fnv != want_pix_fnv) ok = false;
        if (lut_fnv != want_lut_fnv) ok = false;
        if (g_pix[0] != want_p0) ok = false;
        if (g_pix[ci] != want_pc) ok = false;
        if (g_pix[zi] != want_pz) ok = false;

        var line: [256]u8 = undefined;
        var p: usize = 0;
        text_scan.appendText(line[0..], &p, "golden ");
        text_scan.appendText(line[0..], &p, name);
        text_scan.appendText(line[0..], &p, " ");
        text_scan.appendInt(line[0..], &p, @intCast(i64, want_w));
        text_scan.appendText(line[0..], &p, "x");
        text_scan.appendInt(line[0..], &p, @intCast(i64, want_h));
        text_scan.appendText(line[0..], &p, " key=255 ramp=");
        text_scan.appendInt(line[0..], &p, @intCast(i64, want_ramp));
        text_scan.appendText(line[0..], &p, " pix_fnv=");
        appendHex(line[0..], &p, pix_fnv);
        text_scan.appendText(line[0..], &p, " lut_fnv=");
        appendHex(line[0..], &p, lut_fnv);
        text_scan.appendText(line[0..], &p, " p0=");
        text_scan.appendInt(line[0..], &p, @intCast(i64, g_pix[0]));
        text_scan.appendText(line[0..], &p, " pc=");
        text_scan.appendInt(line[0..], &p, @intCast(i64, g_pix[ci]));
        text_scan.appendText(line[0..], &p, " pz=");
        text_scan.appendInt(line[0..], &p, @intCast(i64, g_pix[zi]));
        text_scan.appendText(line[0..], &p, "\n");
        io.write(line[0..p]);
    }

    report(label, ok);
}

pub fn main() void {
    const dir = os.env("M10_ASSETS_OUT") orelse DEFAULT_OUT;

    checkAsset(dir, "eel00", 96, 96, 6, EEL_PIX_FNV, EEL_LUT_FNV,
        EEL_P0, EEL_PC, EEL_PZ, "golden_decode_eel00");
    checkAsset(dir, "boss00", 96, 96, 10, BOSS_PIX_FNV, BOSS_LUT_FNV,
        BOSS_P0, BOSS_PC, BOSS_PZ, "golden_decode_boss00");
    checkAsset(dir, "bg_a", 640, 300, 1, BGA_PIX_FNV, BGA_LUT_FNV,
        BGA_P0, BGA_PC, BGA_PZ, "golden_decode_bg_a");

    if (fails != 0) os.exit(1);
    io.write("assets_golden_test PASS\n");
}
