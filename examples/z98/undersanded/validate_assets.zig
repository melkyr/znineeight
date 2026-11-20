// validate_assets.zig — committed Z98 asset/manifest validator (spec §30, P19).
//
// The expected A table, the A/V/F ledger and every dimension/ramp value below
// are hardcoded from the M10 preflight. The manifest is never trusted for
// asset specs: it is checked against this table, then every referenced `.ZSP`
// is decoded with the one runtime decoder (zsp.zig), re-encoded with the one
// canonical RLE rule and byte-compared, and the cumulative budget is checked.
//
// Pure tooling: no content install, no writes. validateManifest reads the
// `.ZSP` files from `assets_dir` (`<name>.zsp`); the F font row has no file.

const file_mod = @import("std_file");
const arena_mod = @import("std_arena");
const parse = @import("std_parse");
const palette = @import("palette.zig");
const zsp = @import("zsp.zig");
const paths = @import("paths.zig");
const text_scan = @import("text_scan.zig");

pub const KEY_INDEX: u8 = 255;

pub const A_COUNT: usize = 26;
pub const V_COUNT: usize = 12;

const HEADER_BYTES: usize = 16;
const PALETTE_BYTES: usize = 512;
const DATA_OFFSET: usize = HEADER_BYTES + PALETTE_BYTES;

const MAX_PIX: usize = 640 * 300;
const ASSET_FILE_MAX: usize = 512 * 1024;
const MAX_V_ROWS: usize = 32;
const MAX_LINE: usize = 512;

// Budgets (M10 binding): indexed = sum(w*h) over the 26 A rows; indexed + LUTs
// = 512*(A+V); each background encoded <= 120 KB; demo RLE disk <= 400 KB.
const INDEXED_MAX: i32 = 1350 * 1024;
const ARENA_MAX: i32 = 2 * 1024 * 1024;
const BG_MAX: i32 = 120 * 1024;
const RLE_MAX: i32 = 400 * 1024;

pub const Kind = enum { creature, bg, boat, overlay };

pub const AssetSpec = struct {
    name: []const u8,
    kind: Kind,
    w: u32,
    h: u32,
    allowed_ramps: []const u8,
};

pub const ValidateErr = enum {
    Ok,
    BadManifest,
    BadMagic,
    Truncated,
    BadHeader,
    BadDims,
    BadPalette,
    BadRuns,
    OffRamp,
    BadBorder,
    NonCanonical,
    BadName,
    DuplicateEntry,
    MissingEntry,
    BadLedger,
    OrphanVariant,
    DuplicateVariant,
    BadFromRamp,
    Budget,
    MissingFile,
    Io,
};

// Hardcoded expected A table (M10 Task 0 preflight, binding). The manifest is
// never trusted for these values; kind tokens are creature/bg/boat/overlay.
pub const EXPECTED_A: [A_COUNT]AssetSpec = [A_COUNT]AssetSpec{
    AssetSpec{ .name = "eel00", .kind = .creature, .w = 96, .h = 96, .allowed_ramps = "0,6" },
    AssetSpec{ .name = "tuna00", .kind = .creature, .w = 96, .h = 96, .allowed_ramps = "0,7" },
    AssetSpec{ .name = "crab00", .kind = .creature, .w = 96, .h = 96, .allowed_ramps = "0,5,8" },
    AssetSpec{ .name = "jelly00", .kind = .creature, .w = 96, .h = 96, .allowed_ramps = "0,5,9" },
    AssetSpec{ .name = "barn00", .kind = .creature, .w = 96, .h = 96, .allowed_ramps = "0,10" },
    AssetSpec{ .name = "anem00", .kind = .creature, .w = 96, .h = 96, .allowed_ramps = "0,4,11" },
    AssetSpec{ .name = "ray00", .kind = .creature, .w = 96, .h = 96, .allowed_ramps = "0,3,12" },
    AssetSpec{ .name = "squid00", .kind = .creature, .w = 96, .h = 96, .allowed_ramps = "0,13" },
    AssetSpec{ .name = "angler00", .kind = .creature, .w = 96, .h = 96, .allowed_ramps = "0,4,9,14" },
    AssetSpec{ .name = "wrasse00", .kind = .creature, .w = 96, .h = 96, .allowed_ramps = "0,15" },
    AssetSpec{ .name = "boss00", .kind = .creature, .w = 96, .h = 96, .allowed_ramps = "0,2,4,10" },
    AssetSpec{ .name = "bg_a", .kind = .bg, .w = 640, .h = 300, .allowed_ramps = "0,1,14" },
    AssetSpec{ .name = "bg_b", .kind = .bg, .w = 640, .h = 300, .allowed_ramps = "0,1,6,8,14" },
    AssetSpec{ .name = "bg_c", .kind = .bg, .w = 640, .h = 300, .allowed_ramps = "0,1,3,5,6,10,15" },
    AssetSpec{ .name = "bg_d", .kind = .bg, .w = 640, .h = 300, .allowed_ramps = "2,4,10,14" },
    AssetSpec{ .name = "bg_dock", .kind = .bg, .w = 640, .h = 300, .allowed_ramps = "0,1,2,4,10,14" },
    AssetSpec{ .name = "boat00", .kind = .boat, .w = 200, .h = 150, .allowed_ramps = "0,1,10" },
    AssetSpec{ .name = "fig_merm", .kind = .overlay, .w = 64, .h = 64, .allowed_ramps = "0,14" },
    AssetSpec{ .name = "fig_angl", .kind = .overlay, .w = 64, .h = 64, .allowed_ramps = "0,4,14" },
    AssetSpec{ .name = "fig_krak", .kind = .overlay, .w = 64, .h = 64, .allowed_ramps = "0,4" },
    AssetSpec{ .name = "flag_pen", .kind = .overlay, .w = 64, .h = 64, .allowed_ramps = "0,9,14" },
    AssetSpec{ .name = "flag_ref", .kind = .overlay, .w = 64, .h = 64, .allowed_ramps = "0,5,8,14" },
    AssetSpec{ .name = "flag_trn", .kind = .overlay, .w = 64, .h = 64, .allowed_ramps = "0,6,10" },
    AssetSpec{ .name = "dec_barn", .kind = .overlay, .w = 64, .h = 64, .allowed_ramps = "0,10" },
    AssetSpec{ .name = "dec_sqid", .kind = .overlay, .w = 64, .h = 64, .allowed_ramps = "0,13" },
    AssetSpec{ .name = "dec_boss", .kind = .overlay, .w = 64, .h = 64, .allowed_ramps = "0,2,14" },
};

pub const ExpectedV = struct {
    id: []const u8,
    base: []const u8,
    from_ramp: u8,
    to_ramp: u8,
};

// Hardcoded V ledger (exact; 12 rows). Numeric variant ids are demo def
// mappings; the boss rows are symbolic identities, not def ids.
pub const EXPECTED_V: [V_COUNT]ExpectedV = [V_COUNT]ExpectedV{
    ExpectedV{ .id = "id2", .base = "eel00", .from_ramp = 6, .to_ramp = 1 },
    ExpectedV{ .id = "id3", .base = "eel00", .from_ramp = 6, .to_ramp = 5 },
    ExpectedV{ .id = "id5", .base = "tuna00", .from_ramp = 7, .to_ramp = 14 },
    ExpectedV{ .id = "id6", .base = "tuna00", .from_ramp = 7, .to_ramp = 10 },
    ExpectedV{ .id = "id11", .base = "crab00", .from_ramp = 8, .to_ramp = 11 },
    ExpectedV{ .id = "id12", .base = "jelly00", .from_ramp = 9, .to_ramp = 5 },
    ExpectedV{ .id = "id18", .base = "anem00", .from_ramp = 11, .to_ramp = 5 },
    ExpectedV{ .id = "id19", .base = "tuna00", .from_ramp = 7, .to_ramp = 1 },
    ExpectedV{ .id = "boss00:sliver", .base = "boss00", .from_ramp = 10, .to_ramp = 2 },
    ExpectedV{ .id = "boss00:hoard", .base = "boss00", .from_ramp = 10, .to_ramp = 4 },
    ExpectedV{ .id = "boss00:drown", .base = "boss00", .from_ramp = 10, .to_ramp = 13 },
    ExpectedV{ .id = "boss00:blur", .base = "boss00", .from_ramp = 10, .to_ramp = 5 },
};

// Base identity mappings (no V): 11 demo defs.
const BaseDef = struct { id: u8, name: []const u8 };
const BASE_DEFS: [11]BaseDef = [11]BaseDef{
    BaseDef{ .id = 1, .name = "eel00" },
    BaseDef{ .id = 4, .name = "tuna00" },
    BaseDef{ .id = 7, .name = "crab00" },
    BaseDef{ .id = 8, .name = "jelly00" },
    BaseDef{ .id = 9, .name = "barn00" },
    BaseDef{ .id = 10, .name = "anem00" },
    BaseDef{ .id = 13, .name = "ray00" },
    BaseDef{ .id = 14, .name = "squid00" },
    BaseDef{ .id = 15, .name = "angler00" },
    BaseDef{ .id = 16, .name = "wrasse00" },
    BaseDef{ .id = 17, .name = "boss00" },
};

// Shared scratch: one asset at a time. MAX_PIX is the largest expected row and
// MAX_PIX*2 bounds a canonical encode (two bytes per single-pixel run).
var g_pix: [MAX_PIX]u8 = undefined;
var g_enc: [MAX_PIX * 2]u8 = undefined;
var g_file_arena_buf: [ASSET_FILE_MAX]u8 = undefined;

const VRow = struct {
    id: []const u8,
    base: []const u8,
    from_ramp: u8,
    to_ramp: u8,
};

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn readU16(buf: []const u8, off: usize) u16 {
    return @intCast(u16, buf[off]) | (@intCast(u16, buf[off + 1]) << 8);
}

fn is83Char(c: u8) bool {
    if (c >= 'a' and c <= 'z') return true;
    if (c >= '0' and c <= '9') return true;
    return c == '_' or c == '-';
}

// Lowercase 8.3 (optional extension of 1..3 chars), no spaces.
fn isLower83(name: []const u8) bool {
    if (name.len == 0) return false;
    var base_end: usize = name.len;
    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        if (name[i] == '.') {
            if (base_end != name.len) return false;
            base_end = i;
            const ext_len = name.len - i - 1;
            if (ext_len < 1 or ext_len > 3) return false;
            var e: usize = i + 1;
            while (e < name.len) : (e += 1) {
                if (!is83Char(name[e])) return false;
            }
        }
    }
    if (base_end < 1 or base_end > 8) return false;
    i = 0;
    while (i < base_end) : (i += 1) {
        if (!is83Char(name[i])) return false;
    }
    return true;
}

fn kindFromToken(t: []const u8, out: *Kind) bool {
    if (eq(t, "creature")) {
        out.* = .creature;
        return true;
    }
    if (eq(t, "bg")) {
        out.* = .bg;
        return true;
    }
    if (eq(t, "boat")) {
        out.* = .boat;
        return true;
    }
    if (eq(t, "overlay")) {
        out.* = .overlay;
        return true;
    }
    return false;
}

fn kindToken(k: Kind) []const u8 {
    switch (k) {
        .creature => return "creature",
        .bg => return "bg",
        .boat => return "boat",
        .overlay => return "overlay",
        else => return "overlay",
    }
}

fn expectedAIndex(name: []const u8) ?usize {
    var i: usize = 0;
    while (i < A_COUNT) : (i += 1) {
        if (eq(EXPECTED_A[i].name, name)) return i;
    }
    return null;
}

fn expectedVIndex(id: []const u8) ?usize {
    var i: usize = 0;
    while (i < V_COUNT) : (i += 1) {
        if (eq(EXPECTED_V[i].id, id)) return i;
    }
    return null;
}

fn parseAllowed(csv: []const u8, out: *[16]bool) bool {
    var i: usize = 0;
    while (i < 16) : (i += 1) out[i] = false;

    var start: usize = 0;
    var any: bool = false;
    while (start <= csv.len) {
        var end: usize = start;
        while (end < csv.len and csv[end] != ',') : (end += 1) {}
        if (end == start) return false;

        var v: u32 = 0;
        var j: usize = start;
        while (j < end) : (j += 1) {
            const c = csv[j];
            if (c < '0' or c > '9') return false;
            v = v * 10 + @intCast(u32, c - '0');
            if (v > 15) return false;
        }
        out[@intCast(usize, v)] = true;
        any = true;

        if (end == csv.len) break;
        start = end + 1;
    }
    return any;
}

fn splitTokens(line: []const u8, out: *[8][]const u8, n: *usize) bool {
    var count: usize = 0;
    var i: usize = 0;
    while (i < line.len) {
        while (i < line.len and (line[i] == ' ' or line[i] == '\t')) : (i += 1) {}
        if (i >= line.len) break;
        const start = i;
        while (i < line.len and line[i] != ' ' and line[i] != '\t') : (i += 1) {}
        if (count >= out.len) return false;
        out[count] = line[start..i];
        count += 1;
    }
    n.* = count;
    return true;
}

// Demo def variant ids are `id<N>`; symbolic boss ids return null.
fn variantDefId(s: []const u8) ?u32 {
    if (s.len < 3 or s[0] != 'i' or s[1] != 'd') return null;
    var v: u32 = 0;
    var i: usize = 2;
    while (i < s.len) : (i += 1) {
        if (s[i] < '0' or s[i] > '9') return null;
        v = v * 10 + @intCast(u32, s[i] - '0');
        if (v > 99) return null;
    }
    return v;
}

// `<assets_dir>/<name>.zsp`, platform separator (Win98 backslash).
fn assetPath(assets_dir: []const u8, name: []const u8, out: []u8) ?[]u8 {
    if (name.len > 12) return null;
    var fname: [20]u8 = undefined;
    var o: usize = 0;
    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        fname[o] = name[i];
        o += 1;
    }
    fname[o] = '.';
    o += 1;
    fname[o] = 'z';
    o += 1;
    fname[o] = 's';
    o += 1;
    fname[o] = 'p';
    o += 1;
    return paths.join(assets_dir, fname[0..o], out);
}

// validateAsset checks one `.ZSP` against the hardcoded expected A row.
pub fn validateAsset(buf: []const u8, expect: AssetSpec) ValidateErr {
    if (!isLower83(expect.name)) return .BadName;
    if (expect.w == 0 or expect.h == 0 or expect.w > 65535 or expect.h > 65535) return .BadDims;
    if (buf.len < DATA_OFFSET) return .Truncated;
    if (buf[0] != 'Z' or buf[1] != 'S' or buf[2] != 'P' or buf[3] != '1') return .BadMagic;

    const w = readU16(buf, 4);
    const h = readU16(buf, 6);
    if (w != @intCast(u16, expect.w) or h != @intCast(u16, expect.h)) return .BadDims;
    if (w == 0 or h == 0) return .BadDims;

    const key = buf[8];
    if (key != KEY_INDEX) return .BadHeader;
    if (readU16(buf, 10) != 0) return .BadHeader;
    if (@intCast(u32, buf[12]) != 0 or @intCast(u32, buf[13]) != 0 or
        @intCast(u32, buf[14]) != 0 or @intCast(u32, buf[15]) != 0)
    {
        return .BadHeader;
    }

    var p: usize = 0;
    while (p < 256) : (p += 1) {
        if (readU16(buf, HEADER_BYTES + p * 2) != palette.RGB565[p]) return .BadPalette;
    }

    const total32: u32 = @intCast(u32, w) * @intCast(u32, h);
    const total: usize = @intCast(usize, total32);
    if (total > MAX_PIX) return .BadDims;

    const data_len = buf.len - DATA_OFFSET;
    if (data_len == 0 or (data_len & 1) != 0) return .Truncated;

    var allowed: [16]bool = undefined;
    if (!parseAllowed(expect.allowed_ramps, &allowed)) return .BadManifest;

    var sprite: zsp.Sprite = undefined;
    var lut: [256]u16 = undefined;
    var pixel_len: i32 = 0;
    if (!zsp.zspDecode(buf, &sprite, &lut, g_pix[0..total], &pixel_len)) return .BadRuns;
    if (pixel_len != @intCast(i32, total32)) return .BadRuns;

    var i: usize = 0;
    while (i < total) : (i += 1) {
        const index = g_pix[i];
        if (index == key) continue;
        const ramp: u8 = @intCast(u8, index >> 4);
        if (!allowed[@intCast(usize, ramp)]) return .OffRamp;
    }

    if (expect.kind == .creature) {
        const wi: usize = @intCast(usize, w);
        const hi: usize = @intCast(usize, h);
        i = 0;
        while (i < wi) : (i += 1) {
            if (g_pix[i] != key) return .BadBorder;
            if (g_pix[(hi - 1) * wi + i] != key) return .BadBorder;
        }
        i = 0;
        while (i < hi) : (i += 1) {
            if (g_pix[i * wi] != key) return .BadBorder;
            if (g_pix[i * wi + (wi - 1)] != key) return .BadBorder;
        }
    }

    const n = zsp.zspCanonicalEncode(g_pix[0..total], @intCast(u32, w), @intCast(u32, h), g_enc[0..]);
    if (n == 0 or n != data_len) return .NonCanonical;
    i = 0;
    while (i < n) : (i += 1) {
        if (g_enc[i] != buf[DATA_OFFSET + i]) return .NonCanonical;
    }
    return .Ok;
}

fn addV(rows: *[MAX_V_ROWS]VRow, count: *usize, id: []const u8, base: []const u8, from_ramp: u8, to_ramp: u8) ValidateErr {
    var i: usize = 0;
    while (i < count.*) : (i += 1) {
        if (eq(rows[i].id, id)) return .DuplicateVariant;
    }
    if (count.* >= MAX_V_ROWS) return .BadLedger;
    rows[count.*] = VRow{ .id = id, .base = base, .from_ramp = from_ramp, .to_ramp = to_ramp };
    count.* += 1;
    return .Ok;
}

// validateManifest checks the exact A/V/F ledger, every `.ZSP`, the V base
// header ramps, demo def coverage, and the cumulative budget.
pub fn validateManifest(man: []const u8, assets_dir: []const u8) ValidateErr {
    var a_seen: [A_COUNT]bool = undefined;
    var a_ramp: [A_COUNT]u8 = undefined;
    var v_rows: [MAX_V_ROWS]VRow = undefined;
    var v_count: usize = 0;
    var f_seen: bool = false;
    var encoded_total: i32 = 0;

    var i: usize = 0;
    while (i < A_COUNT) : (i += 1) {
        a_seen[i] = false;
        a_ramp[i] = 0;
    }

    var line_start: usize = 0;
    while (line_start <= man.len) {
        var line_end: usize = line_start;
        while (line_end < man.len and man[line_end] != '\n') : (line_end += 1) {}
        const line = text_scan.stripCR(man[line_start..line_end]);
        if (line.len > MAX_LINE) return .BadManifest;

        var toks: [8][]const u8 = undefined;
        var nt: usize = 0;
        if (!splitTokens(line, &toks, &nt)) return .BadManifest;

        if (nt != 0) {
            if (eq(toks[0], "A")) {
                if (nt != 7) return .BadManifest;
                const name = toks[1];
                if (!isLower83(name)) return .BadName;
                const ai = expectedAIndex(name) orelse return .BadLedger;
                if (a_seen[ai]) return .DuplicateEntry;
                const spec = EXPECTED_A[ai];

                var kind: Kind = .creature;
                if (!kindFromToken(toks[2], &kind)) return .BadManifest;
                const mw = parse.parseUint(toks[3]) orelse return .BadManifest;
                const mh = parse.parseUint(toks[4]) orelse return .BadManifest;
                const enc = parse.parseUint(toks[5]) orelse return .BadManifest;
                if (kind != spec.kind or mw != spec.w or mh != spec.h) return .BadLedger;
                if (!eq(toks[6], spec.allowed_ramps)) return .BadLedger;

                var allowed: [16]bool = undefined;
                if (!parseAllowed(toks[6], &allowed)) return .BadManifest;

                var path_buf: [600]u8 = undefined;
                const path = assetPath(assets_dir, name, path_buf[0..]) orelse return .BadName;
                var arena = arena_mod.init(g_file_arena_buf[0..]);
                const buf = file_mod.readAll(&arena, path) catch return .MissingFile;
                if (buf.len != @intCast(usize, enc)) return .BadLedger;

                const ae = validateAsset(buf, spec);
                if (ae != .Ok) return ae;

                a_seen[ai] = true;
                a_ramp[ai] = buf[9];
                encoded_total += @intCast(i32, buf.len);
                if (spec.kind == .bg and @intCast(i32, buf.len) > BG_MAX) return .Budget;
            } else if (eq(toks[0], "V")) {
                if (nt != 5) return .BadManifest;
                const from = parse.parseUint(toks[3]) orelse return .BadManifest;
                const to = parse.parseUint(toks[4]) orelse return .BadManifest;
                if (from > 15 or to > 15) return .BadManifest;
                const av = addV(&v_rows, &v_count, toks[1], toks[2], @intCast(u8, from), @intCast(u8, to));
                if (av != .Ok) return av;
            } else if (eq(toks[0], "F")) {
                if (nt != 4) return .BadLedger;
                if (!isLower83(toks[1])) return .BadName;
                if (!eq(toks[1], "font8x16") or !eq(toks[2], "95") or !eq(toks[3], "16")) return .BadLedger;
                if (f_seen) return .BadLedger;
                f_seen = true;
            } else {
                return .BadManifest;
            }
        }

        if (line_end == man.len) break;
        line_start = line_end + 1;
    }

    i = 0;
    while (i < A_COUNT) : (i += 1) {
        if (!a_seen[i]) return .MissingEntry;
    }
    if (!f_seen) return .MissingEntry;

    var v_seen: [V_COUNT]bool = undefined;
    i = 0;
    while (i < V_COUNT) : (i += 1) v_seen[i] = false;

    var def_count: [20]u8 = undefined;
    i = 0;
    while (i < 20) : (i += 1) def_count[i] = 0;
    i = 0;
    while (i < BASE_DEFS.len) : (i += 1) def_count[@intCast(usize, BASE_DEFS[i].id)] += 1;

    i = 0;
    while (i < v_count) : (i += 1) {
        const row = v_rows[i];
        const bi = expectedAIndex(row.base) orelse return .OrphanVariant;
        if (!a_seen[bi]) return .MissingEntry;
        const vi = expectedVIndex(row.id) orelse return .BadLedger;
        if (v_seen[vi]) return .DuplicateVariant;

        if (EXPECTED_A[bi].kind == .creature and row.from_ramp == 0) return .BadFromRamp;
        if (row.from_ramp == row.to_ramp) return .BadFromRamp;
        if (row.from_ramp != a_ramp[bi]) return .BadFromRamp;

        if (!eq(row.base, EXPECTED_V[vi].base) or
            row.from_ramp != EXPECTED_V[vi].from_ramp or
            row.to_ramp != EXPECTED_V[vi].to_ramp)
        {
            return .BadLedger;
        }
        v_seen[vi] = true;

        const maybe_id = variantDefId(row.id);
        if (maybe_id) |did| {
            if (did >= 1 and did <= 19) def_count[@intCast(usize, did)] += 1;
        }
    }

    i = 0;
    while (i < V_COUNT) : (i += 1) {
        if (!v_seen[i]) return .MissingEntry;
    }
    var d: usize = 1;
    while (d <= 19) : (d += 1) {
        if (def_count[d] != 1) return .BadLedger;
    }

    var indexed: i32 = 0;
    i = 0;
    while (i < A_COUNT) : (i += 1) {
        const w: i32 = @intCast(i32, EXPECTED_A[i].w);
        const h: i32 = @intCast(i32, EXPECTED_A[i].h);
        indexed += w * h;
    }
    const luts: i32 = @intCast(i32, PALETTE_BYTES) * @intCast(i32, A_COUNT + V_COUNT);
    if (indexed > INDEXED_MAX) return .Budget;
    if (indexed + luts > ARENA_MAX) return .Budget;
    if (encoded_total > RLE_MAX) return .Budget;
    return .Ok;
}

pub fn errorText(e: ValidateErr) []const u8 {
    switch (e) {
        .Ok => return "ok",
        .BadManifest => return "bad manifest",
        .BadMagic => return "bad magic",
        .Truncated => return "truncated",
        .BadHeader => return "bad header",
        .BadDims => return "bad dimensions",
        .BadPalette => return "bad palette",
        .BadRuns => return "bad runs",
        .OffRamp => return "off-ramp pixel",
        .BadBorder => return "creature border not key",
        .NonCanonical => return "non-canonical RLE",
        .BadName => return "bad 8.3 name",
        .DuplicateEntry => return "duplicate entry",
        .MissingEntry => return "missing entry",
        .BadLedger => return "ledger mismatch",
        .OrphanVariant => return "orphan variant",
        .DuplicateVariant => return "duplicate variant",
        .BadFromRamp => return "wrong from_ramp",
        .Budget => return "budget overrun",
        .MissingFile => return "missing file",
        .Io => return "io error",
        else => return "invalid",
    }
}
