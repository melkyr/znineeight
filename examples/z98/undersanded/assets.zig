// assets.zig — UNDERSANDED M10 asset arena loader (spec §30/§35).
//
// Runtime-only loader for the installed demo art set. It reads
// `<assets_dir>/assets.man` and `<assets_dir>/out/<name>.zsp`, decodes every
// A row into one arena of indexed pixels, and builds the 512-byte recolor LUT
// for every V row. render_art only ever sees the decoded Sprite/LUT pointers;
// it performs no file I/O.
//
// The manifest order is not trusted: A rows are matched by name and V rows by
// the pinned symbolic id. A missing/unreadable manifest, missing `.zsp`, or a
// malformed row is a deterministic load failure; callers then draw the M9
// placeholder (panel + first creature letter) with the flat background.

const file_mod = @import("std_file");
const arena_mod = @import("std_arena");
const parse = @import("std_parse");
const str = @import("std_str");
const paths = @import("paths.zig");
const zsp = @import("zsp.zig");
const px = @import("std_gfx_px_core.zig");

pub const A_COUNT: usize = 26;
pub const V_COUNT: usize = 12;

const PATH_MAX: usize = 512;
const MAX_MANIFEST: usize = 16 * 1024;
const MAX_ASSET_FILE: usize = 512 * 1024;
const MAX_ASSET_ARENA: usize = 1536 * 1024;
const MAX_NAME: usize = 16;

const HEADER_BYTES: usize = 16;

// Pinned A table order (same ledger as validate_assets.zig). A rows are the
// only indexed-byte source; V rows reuse the base pixels with a new LUT.
const A_NAMES: [A_COUNT][]const u8 = [A_COUNT][]const u8{
    "eel00", "tuna00", "crab00", "jelly00", "barn00", "anem00",
    "ray00", "squid00", "angler00", "wrasse00", "boss00",
    "bg_a", "bg_b", "bg_c", "bg_d", "bg_dock",
    "boat00",
    "fig_merm", "fig_angl", "fig_krak",
    "flag_pen", "flag_ref", "flag_trn",
    "dec_barn", "dec_sqid", "dec_boss",
};

const A_CREATURE_COUNT: usize = 11;

const A_EEL: i32 = 0;
const A_ANEM: i32 = 5;
const A_RAY: i32 = 6;
const A_SQUID: i32 = 7;
const A_ANGLER: i32 = 8;
const A_WRASSE: i32 = 9;
const A_BOSS: i32 = 10;
const A_BG_A: i32 = 11;
const A_BG_B: i32 = 12;
const A_BG_C: i32 = 13;
const A_BG_D: i32 = 14;

// Base identity rows: demo def id -> A index (validator's BASE_DEFS).
const DefBase = struct { id: i32, a: i32 };
const BASE_DEFS: [11]DefBase = [11]DefBase{
    DefBase{ .id = 1, .a = A_EEL },
    DefBase{ .id = 4, .a = 1 },
    DefBase{ .id = 7, .a = 2 },
    DefBase{ .id = 8, .a = 3 },
    DefBase{ .id = 9, .a = 4 },
    DefBase{ .id = 10, .a = A_ANEM },
    DefBase{ .id = 13, .a = A_RAY },
    DefBase{ .id = 14, .a = A_SQUID },
    DefBase{ .id = 15, .a = A_ANGLER },
    DefBase{ .id = 16, .a = A_WRASSE },
    DefBase{ .id = 17, .a = A_BOSS },
};

pub const Assets = struct {
    sprites: [A_COUNT]px.Sprite,
    base_luts: [A_COUNT * 256]u16,
    var_sprites: [V_COUNT]px.Sprite,
    var_luts: [V_COUNT * 256]u16,
    var_def_ids: [V_COUNT]i32,
    loaded: bool,
};

pub fn spriteForDef(a: *const Assets, def_id: i32) ?*const px.Sprite {
    var i: usize = 0;
    while (i < BASE_DEFS.len) : (i += 1) {
        if (BASE_DEFS[i].id == def_id) {
            const idx: usize = @intCast(usize, BASE_DEFS[i].a);
            return &a.sprites[idx];
        }
    }
    i = 0;
    while (i < V_COUNT) : (i += 1) {
        if (a.var_def_ids[i] == def_id) return &a.var_sprites[i];
    }
    return null;
}

fn isBackgroundA(a: i32) bool {
    return a >= A_BG_A and a <= 15;
}

// Only decoded creature rows may back a V recolor. Backgrounds are loaded
// lazily and the boat/overlay rows are not recoloured, so accepting any A row
// here could build a LUT from a row whose pixels were never decoded.
fn isCreatureA(a: i32) bool {
    if (a < 0) return false;
    return @intCast(usize, a) < A_CREATURE_COUNT;
}

fn bgIndexForZone(zone: i32) i32 {
    if (zone == 1) return A_BG_B;
    if (zone == 2) return A_BG_C;
    if (zone == 8) return A_BG_D;
    return A_BG_A;
}

const BG_W: usize = 640;
const BG_H: usize = 300;

var g_assets: Assets = undefined;
var g_loaded: bool = false;
var g_manifest_buf: [MAX_MANIFEST]u8 = undefined;
var g_manifest_arena: arena_mod.Arena = undefined;
var g_file_buf: [MAX_ASSET_FILE]u8 = undefined;
var g_file_arena: arena_mod.Arena = undefined;
var g_asset_buf: [MAX_ASSET_ARENA]u8 = undefined;
var g_asset_arena: arena_mod.Arena = undefined;

// Exactly one resident background at a time. On-demand zone switches decode
// into this one pixel buffer and its LUT; the previous background is evicted
// by overwrite (no per-background arena allocation).
var g_bg_pix: [BG_W * BG_H]u8 = undefined;
var g_bg_lut: [256]u16 = undefined;
var g_bg_sprite: px.Sprite = undefined;
var g_bg_a: i32 = -1;
var g_bg_loaded: bool = false;
var g_assets_dir_buf: [PATH_MAX]u8 = undefined;
var g_assets_dir_len: usize = 0;

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r';
}

fn nextToken(line: []const u8, pos: *usize) []const u8 {
    var i = pos.*;
    while (i < line.len and isSpace(line[i])) : (i += 1) {}
    const start = i;
    while (i < line.len and !isSpace(line[i])) : (i += 1) {}
    pos.* = i;
    return line[start..i];
}

fn readU16(buf: []const u8, off: usize) u16 {
    return @intCast(u16, buf[off]) | (@intCast(u16, buf[off + 1]) << 8);
}

fn findA(name: []const u8) i32 {
    var i: usize = 0;
    while (i < A_COUNT) : (i += 1) {
        if (eq(A_NAMES[i], name)) return @intCast(i32, i);
    }
    return -1;
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

fn decodeAsset(assets_dir: []const u8, name: []const u8, a: i32, out_ramp: *u8) bool {
    var out_buf: [PATH_MAX]u8 = undefined;
    const out_dir = paths.join(assets_dir, "out", out_buf[0..]) orelse return false;

    var name_buf: [MAX_NAME]u8 = undefined;
    const file_name = buildFileName(name, name_buf[0..]) orelse return false;

    var path_buf: [PATH_MAX]u8 = undefined;
    const path = paths.join(out_dir, file_name, path_buf[0..]) orelse return false;

    arena_mod.reset(&g_file_arena);
    const data = file_mod.readAll(&g_file_arena, path) catch return false;
    if (data.len < HEADER_BYTES + 512) return false;

    const w = readU16(data, 4);
    const h = readU16(data, 6);
    if (w == 0 or h == 0) return false;
    const total32: u32 = @intCast(u32, w) * @intCast(u32, h);
    if (total32 == 0 or total32 > 2147483647) return false;
    const total: usize = @intCast(usize, total32);

    const raw = arena_mod.alloc(&g_asset_arena, total) catch return false;
    const pix = raw[0..total];

    const idx: usize = @intCast(usize, a);
    var sprite: px.Sprite = undefined;
    var pix_len: i32 = 0;
    var tmp_lut: [256]u16 = undefined;
    if (!zsp.zspDecode(data, &sprite, &tmp_lut, pix, &pix_len)) return false;
    if (pix_len != @intCast(i32, total32)) return false;
    out_ramp.* = data[9];

    var sprites: *[A_COUNT]px.Sprite = &g_assets.sprites;
    var base_luts: *[A_COUNT * 256]u16 = &g_assets.base_luts;
    const off: usize = idx * 256;
    var i: usize = 0;
    while (i < 256) : (i += 1) base_luts[off + i] = tmp_lut[i];
    sprite.lut = @ptrCast([*]const u16, &base_luts[off]);
    sprites[idx] = sprite;
    return true;
}

fn decodeBackground(assets_dir: []const u8, name: []const u8, a: i32) bool {
    var out_buf: [PATH_MAX]u8 = undefined;
    const out_dir = paths.join(assets_dir, "out", out_buf[0..]) orelse return false;

    var name_buf: [MAX_NAME]u8 = undefined;
    const file_name = buildFileName(name, name_buf[0..]) orelse return false;

    var path_buf: [PATH_MAX]u8 = undefined;
    const path = paths.join(out_dir, file_name, path_buf[0..]) orelse return false;

    arena_mod.reset(&g_file_arena);
    const data = file_mod.readAll(&g_file_arena, path) catch return false;
    if (data.len < HEADER_BYTES + 512) return false;

    const w = readU16(data, 4);
    const h = readU16(data, 6);
    if (@intCast(usize, w) != BG_W or @intCast(usize, h) != BG_H) return false;
    const total: usize = BG_W * BG_H;

    var sprite: px.Sprite = undefined;
    var pix_len: i32 = 0;
    var lut: *[256]u16 = &g_bg_lut;
    if (!zsp.zspDecode(data, &sprite, lut, g_bg_pix[0..total], &pix_len)) {
        g_bg_loaded = false;
        g_bg_a = -1;
        return false;
    }
    if (pix_len != @intCast(i32, total)) {
        g_bg_loaded = false;
        g_bg_a = -1;
        return false;
    }
    g_bg_sprite = sprite;
    g_bg_a = a;
    g_bg_loaded = true;
    return true;
}

// Decode the zone's background only when it differs from the resident one.
// The loop calls this before rendering; render_art still receives a pointer
// and performs no file I/O.
pub fn ensureBackgroundZone(zone: i32) ?*const px.Sprite {
    if (!g_loaded) return null;
    const idx = bgIndexForZone(zone);
    if (g_bg_loaded and g_bg_a == idx) return &g_bg_sprite;
    if (g_assets_dir_len == 0) return null;

    const a: usize = @intCast(usize, idx);
    if (!decodeBackground(g_assets_dir_buf[0..g_assets_dir_len], A_NAMES[a], idx)) {
        return null;
    }
    return &g_bg_sprite;
}

pub fn backgroundLoaded() bool {
    return g_bg_loaded;
}

fn parseFromTo(token: []const u8, out: *u8) bool {
    const v = parse.parseInt(token) orelse return false;
    if (v < 0 or v > 15) return false;
    out.* = @intCast(u8, v);
    return true;
}

fn buildVariants(manifest: []const u8, base_ramps: []const u8) bool {
    var var_count: usize = 0;
    var start: usize = 0;
    while (start < manifest.len) {
        var end = start;
        while (end < manifest.len and manifest[end] != '\n') : (end += 1) {}
        var line = manifest[start..end];
        start = end + 1;
        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0 .. line.len - 1];
        }
        if (line.len == 0) continue;

        var pos: usize = 0;
        const tag = nextToken(line, &pos);
        if (!eq(tag, "V")) continue;
        const id = nextToken(line, &pos);
        const base_name = nextToken(line, &pos);
        const from_tok = nextToken(line, &pos);
        const to_tok = nextToken(line, &pos);

        const base = findA(base_name);
        if (base < 0) return false;
        if (!isCreatureA(base)) return false;
        var from_ramp: u8 = 0;
        var to_ramp: u8 = 0;
        if (!parseFromTo(from_tok, &from_ramp)) return false;
        if (!parseFromTo(to_tok, &to_ramp)) return false;
        if (from_ramp == to_ramp) return false;
        if (from_ramp != base_ramps[@intCast(usize, base)]) return false;
        if (var_count >= V_COUNT) return false;

        var def_id: i32 = -1;
        if (id.len > 2 and id[0] == 'i' and id[1] == 'd') {
            def_id = parse.parseInt(id[2..]) orelse -1;
        }

        var sprites: *[A_COUNT]px.Sprite = &g_assets.sprites;
        var base_luts: *[A_COUNT * 256]u16 = &g_assets.base_luts;
        var var_sprites: *[V_COUNT]px.Sprite = &g_assets.var_sprites;
        var var_luts: *[V_COUNT * 256]u16 = &g_assets.var_luts;
        var var_ids: *[V_COUNT]i32 = &g_assets.var_def_ids;

        const base_idx: usize = @intCast(usize, base);
        const base_off: usize = base_idx * 256;
        var base_lut: [256]u16 = undefined;
        var i: usize = 0;
        while (i < 256) : (i += 1) base_lut[i] = base_luts[base_off + i];

        var var_lut: [256]u16 = undefined;
        zsp.zspRecolorLut(&var_lut, &base_lut, from_ramp, to_ramp);

        const var_off: usize = var_count * 256;
        i = 0;
        while (i < 256) : (i += 1) var_luts[var_off + i] = var_lut[i];

        var sprite = sprites[base_idx];
        sprite.lut = @ptrCast([*]const u16, &var_luts[var_off]);
        var_sprites[var_count] = sprite;
        var_ids[var_count] = def_id;
        var_count += 1;
    }
    return var_count == V_COUNT;
}

// Load one installed asset directory (`<exe dir>/assets`). On success the
// module keeps the decoded set and `current()` returns it. On any failure the
// previous decoded set is dropped and callers use the placeholder fallback.
pub fn load(assets_dir: []const u8) bool {
    g_loaded = false;
    g_bg_loaded = false;
    g_bg_a = -1;

    var manifest_path_buf: [PATH_MAX]u8 = undefined;
    const manifest_path =
        paths.join(assets_dir, "assets.man", manifest_path_buf[0..]) orelse return false;

    g_manifest_arena = arena_mod.init(g_manifest_buf[0..]);
    const manifest = file_mod.readAll(&g_manifest_arena, manifest_path) catch return false;
    if (manifest.len == 0) return false;

    g_asset_arena = arena_mod.init(g_asset_buf[0..]);
    g_file_arena = arena_mod.init(g_file_buf[0..]);

    var seen: [A_COUNT]bool = undefined;
    var a_ramp: [A_COUNT]u8 = undefined;
    var i: usize = 0;
    while (i < A_COUNT) : (i += 1) {
        seen[i] = false;
        a_ramp[i] = 0;
    }

    var a_count: usize = 0;
    var start: usize = 0;
    while (start < manifest.len) {
        var end = start;
        while (end < manifest.len and manifest[end] != '\n') : (end += 1) {}
        var line = manifest[start..end];
        start = end + 1;
        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0 .. line.len - 1];
        }
        if (line.len == 0) continue;

        var pos: usize = 0;
        const tag = nextToken(line, &pos);
        if (!eq(tag, "A")) continue;
        const name = nextToken(line, &pos);
        const a = findA(name);
        if (a < 0) return false;
        const idx: usize = @intCast(usize, a);
        if (seen[idx]) return false;
        if (!isBackgroundA(a)) {
            if (!decodeAsset(assets_dir, name, a, &a_ramp[idx])) return false;
        }
        seen[idx] = true;
        a_count += 1;
    }
    if (a_count != A_COUNT) return false;

    i = 0;
    while (i < A_COUNT) : (i += 1) {
        if (!seen[i]) return false;
    }
    if (!buildVariants(manifest, a_ramp[0..])) return false;
    if (assets_dir.len > g_assets_dir_buf.len) return false;
    str.copy(g_assets_dir_buf[0..], assets_dir);
    g_assets_dir_len = assets_dir.len;

    g_loaded = true;
    return true;
}

// Convenience for the GUI entry: load `<exe dir>/assets`.
pub fn loadFromExeDir(exe_dir: []const u8) bool {
    var dir_buf: [PATH_MAX]u8 = undefined;
    const assets_dir = paths.join(exe_dir, "assets", dir_buf[0..]) orelse return false;
    return load(assets_dir);
}

pub fn current() ?*const Assets {
    if (!g_loaded) return null;
    return &g_assets;
}

pub fn available() bool {
    return g_loaded;
}
