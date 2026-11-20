// validate_assets_test.zig — native gate for the M10 Z98 asset validator.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/validate_assets_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/validate_assets_test"
//   "$OUT/validate_assets_test"
//
// The synthetic `.ZSP` files are constructed here (no committed converter);
// a full 26-A/12-V/F ledger is generated in /tmp for the manifest checks and
// for the `undtool --validate-assets` CLI probe. Prints `ok - <case>` /
// `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const file_mod = @import("std_file");
const text_scan = @import("../text_scan.zig");
const validate_assets = @import("../validate_assets.zig");
const zsp = @import("../zsp.zig");
const palette = @import("../palette.zig");

@cInclude("<sys/stat.h>");

extern "c" fn mkdir(path: [*]const u8, mode: u32) i32;

const DIR = "/tmp/z98_m10_validate_assets";
const A_COUNT: usize = validate_assets.A_COUNT;
const V_COUNT: usize = validate_assets.V_COUNT;
const BG_A_INDEX: usize = 11;

var fails: usize = 0;
var g_pix: [640 * 300]u8 = undefined;
var g_enc: [640 * 300 * 2]u8 = undefined;
var g_buf: [400 * 1024]u8 = undefined;
var g_len: [A_COUNT]usize = undefined;
var g_man: [8192]u8 = undefined;

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

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn wr16(buf: []u8, off: usize, v: u16) void {
    buf[off] = @intCast(u8, v & 0xFF);
    buf[off + 1] = @intCast(u8, v >> 8);
}

fn ensureDir(path: []const u8) void {
    var b: [256]u8 = undefined;
    if (path.len + 1 > b.len) return;
    var i: usize = 0;
    while (i < path.len) : (i += 1) b[i] = path[i];
    b[path.len] = 0;
    _ = mkdir(@ptrCast([*]const u8, &b[0]), 493);
}

fn makePath(dir: []const u8, name: []const u8, suffix: []const u8, out: []u8) ?[]u8 {
    var p: usize = 0;
    var i: usize = 0;
    while (i < dir.len) : (i += 1) {
        if (p >= out.len) return null;
        out[p] = dir[i];
        p += 1;
    }
    if (dir.len > 0 and dir[dir.len - 1] != '/') {
        if (p >= out.len) return null;
        out[p] = '/';
        p += 1;
    }
    i = 0;
    while (i < name.len) : (i += 1) {
        if (p >= out.len) return null;
        out[p] = name[i];
        p += 1;
    }
    i = 0;
    while (i < suffix.len) : (i += 1) {
        if (p >= out.len) return null;
        out[p] = suffix[i];
        p += 1;
    }
    return out[0..p];
}

fn firstRamp(csv: []const u8) u8 {
    var v: u8 = 0;
    var i: usize = 0;
    while (i < csv.len and csv[i] != ',') : (i += 1) {
        v = v * 10 + @intCast(u8, csv[i] - '0');
    }
    return v;
}

fn baseHeaderRamp(name: []const u8, spec: validate_assets.AssetSpec) u8 {
    if (eq(name, "eel00")) return 6;
    if (eq(name, "tuna00")) return 7;
    if (eq(name, "crab00")) return 8;
    if (eq(name, "jelly00")) return 9;
    if (eq(name, "barn00")) return 10;
    if (eq(name, "anem00")) return 11;
    if (eq(name, "ray00")) return 12;
    if (eq(name, "squid00")) return 13;
    if (eq(name, "angler00")) return 14;
    if (eq(name, "wrasse00")) return 15;
    if (eq(name, "boss00")) return 10;
    return firstRamp(spec.allowed_ramps);
}

fn kindToken(k: validate_assets.Kind) []const u8 {
    switch (k) {
        .creature => return "creature",
        .bg => return "bg",
        .boat => return "boat",
        .overlay => return "overlay",
        else => return "overlay",
    }
}

fn buildAsset(spec: validate_assets.AssetSpec, header_ramp: u8, fill_ramp: u8, border_key: bool, out: []u8) usize {
    const w: usize = @intCast(usize, spec.w);
    const h: usize = @intCast(usize, spec.h);
    const total: usize = w * h;
    if (total > g_pix.len) return 0;
    const fill_index: u8 = @intCast(u8, @intCast(u32, fill_ramp) * 16 + 5);

    var y: usize = 0;
    while (y < h) : (y += 1) {
        var x: usize = 0;
        while (x < w) : (x += 1) {
            var idx = fill_index;
            if (border_key and (x == 0 or y == 0 or x == w - 1 or y == h - 1)) idx = 255;
            g_pix[y * w + x] = idx;
        }
    }

    const n = zsp.zspCanonicalEncode(g_pix[0..total], spec.w, spec.h, g_enc[0..]);
    if (n == 0) return 0;
    const len = 16 + 512 + n;
    if (len > out.len) return 0;

    out[0] = 'Z';
    out[1] = 'S';
    out[2] = 'P';
    out[3] = '1';
    wr16(out, 4, @intCast(u16, spec.w));
    wr16(out, 6, @intCast(u16, spec.h));
    out[8] = 255;
    out[9] = header_ramp;
    wr16(out, 10, 0);
    out[12] = 0;
    out[13] = 0;
    out[14] = 0;
    out[15] = 0;
    var i: usize = 0;
    while (i < 256) : (i += 1) wr16(out, 16 + i * 2, palette.RGB565[i]);
    i = 0;
    while (i < n) : (i += 1) out[528 + i] = g_enc[i];
    return len;
}

fn buildWideBg(spec: validate_assets.AssetSpec, out: []u8) usize {
    const w: usize = @intCast(usize, spec.w);
    const h: usize = @intCast(usize, spec.h);
    const total: usize = w * h;
    if (total > g_pix.len) return 0;
    var i: usize = 0;
    while (i < total) : (i += 1) {
        if ((i & 1) == 0) {
            g_pix[i] = 5;
        } else {
            g_pix[i] = 21;
        }
    }
    const n = zsp.zspCanonicalEncode(g_pix[0..total], spec.w, spec.h, g_enc[0..]);
    if (n == 0) return 0;
    const len = 16 + 512 + n;
    if (len > out.len) return 0;
    out[0] = 'Z';
    out[1] = 'S';
    out[2] = 'P';
    out[3] = '1';
    wr16(out, 4, @intCast(u16, spec.w));
    wr16(out, 6, @intCast(u16, spec.h));
    out[8] = 255;
    out[9] = firstRamp(spec.allowed_ramps);
    wr16(out, 10, 0);
    out[12] = 0;
    out[13] = 0;
    out[14] = 0;
    out[15] = 0;
    i = 0;
    while (i < 256) : (i += 1) wr16(out, 16 + i * 2, palette.RGB565[i]);
    i = 0;
    while (i < n) : (i += 1) out[528 + i] = g_enc[i];
    return len;
}

fn writeFile(dir: []const u8, name: []const u8, suffix: []const u8, buf: []const u8) bool {
    var path_buf: [600]u8 = undefined;
    const path = makePath(dir, name, suffix, path_buf[0..]) orelse return false;
    file_mod.writeAll(path, buf) catch return false;
    return true;
}

fn buildAllFiles(dir: []const u8) bool {
    var i: usize = 0;
    while (i < A_COUNT) : (i += 1) {
        const spec = validate_assets.EXPECTED_A[i];
        const hr = baseHeaderRamp(spec.name, spec);
        const len = buildAsset(spec, hr, hr, spec.kind == .creature, g_buf[0..]);
        if (len == 0) return false;
        if (!writeFile(dir, spec.name, ".zsp", g_buf[0..len])) return false;
        g_len[i] = len;
    }
    return true;
}

fn appendV(out: []u8, p: *usize, id: []const u8, base: []const u8, from_ramp: u8, to_ramp: u8) void {
    text_scan.appendText(out, p, "V ");
    text_scan.appendText(out, p, id);
    text_scan.appendText(out, p, " ");
    text_scan.appendText(out, p, base);
    text_scan.appendText(out, p, " ");
    text_scan.appendInt(out, p, @intCast(i64, from_ramp));
    text_scan.appendText(out, p, " ");
    text_scan.appendInt(out, p, @intCast(i64, to_ramp));
    text_scan.appendText(out, p, "\n");
}

fn makeManifest(out: []u8, skip_a: i32, bad_name: bool, add_orphan: bool, dup_v: bool, wrong_from: bool) usize {
    var p: usize = 0;
    var i: usize = 0;
    while (i < A_COUNT) : (i += 1) {
        if (@intCast(i32, i) != skip_a) {
            const spec = validate_assets.EXPECTED_A[i];
            text_scan.appendText(out, &p, "A ");
            if (bad_name and i == 0) {
                text_scan.appendText(out, &p, "EEL00");
            } else {
                text_scan.appendText(out, &p, spec.name);
            }
            text_scan.appendText(out, &p, " ");
            text_scan.appendText(out, &p, kindToken(spec.kind));
            text_scan.appendText(out, &p, " ");
            text_scan.appendInt(out, &p, @intCast(i64, spec.w));
            text_scan.appendText(out, &p, " ");
            text_scan.appendInt(out, &p, @intCast(i64, spec.h));
            text_scan.appendText(out, &p, " ");
            text_scan.appendInt(out, &p, @intCast(i64, g_len[i]));
            text_scan.appendText(out, &p, " ");
            text_scan.appendText(out, &p, spec.allowed_ramps);
            text_scan.appendText(out, &p, "\n");
        }
    }
    i = 0;
    while (i < V_COUNT) : (i += 1) {
        const v = validate_assets.EXPECTED_V[i];
        const from = if (wrong_from and i == 0) @intCast(u8, 5) else v.from_ramp;
        appendV(out, &p, v.id, v.base, from, v.to_ramp);
        if (dup_v and i == 0) appendV(out, &p, v.id, v.base, from, v.to_ramp);
    }
    if (add_orphan) appendV(out, &p, "orphan", "nope", 1, 2);
    text_scan.appendText(out, &p, "F font8x16 95 16\n");
    return p;
}

fn goodAssetLen() usize {
    return buildAsset(validate_assets.EXPECTED_A[0], 6, 6, true, g_buf[0..]);
}

fn tGoodAsset() bool {
    const len = goodAssetLen();
    if (len == 0) return false;
    return validate_assets.validateAsset(g_buf[0..len], validate_assets.EXPECTED_A[0]) == .Ok;
}

fn tBadMagic() bool {
    const len = goodAssetLen();
    if (len == 0) return false;
    g_buf[0] = 'X';
    return validate_assets.validateAsset(g_buf[0..len], validate_assets.EXPECTED_A[0]) == .BadMagic;
}

fn tTruncatedRun() bool {
    const len = goodAssetLen();
    if (len == 0) return false;
    return validate_assets.validateAsset(g_buf[0 .. len - 1], validate_assets.EXPECTED_A[0]) == .Truncated;
}

fn tOversizedDims() bool {
    const len = goodAssetLen();
    if (len == 0) return false;
    wr16(g_buf[0..], 4, 0xFFFF);
    wr16(g_buf[0..], 6, 0xFFFF);
    return validate_assets.validateAsset(g_buf[0..len], validate_assets.EXPECTED_A[0]) == .BadDims;
}

fn tOffRamp() bool {
    const len = buildAsset(validate_assets.EXPECTED_A[0], 6, 7, true, g_buf[0..]);
    if (len == 0) return false;
    return validate_assets.validateAsset(g_buf[0..len], validate_assets.EXPECTED_A[0]) == .OffRamp;
}

fn tBadPalette() bool {
    const len = goodAssetLen();
    if (len == 0) return false;
    g_buf[16] = g_buf[16] ^ 1;
    return validate_assets.validateAsset(g_buf[0..len], validate_assets.EXPECTED_A[0]) == .BadPalette;
}

fn tBadBorder() bool {
    const len = buildAsset(validate_assets.EXPECTED_A[0], 6, 6, false, g_buf[0..]);
    if (len == 0) return false;
    return validate_assets.validateAsset(g_buf[0..len], validate_assets.EXPECTED_A[0]) == .BadBorder;
}

fn tNonCanonical() bool {
    const len = goodAssetLen();
    if (len == 0) return false;
    const first = g_buf[528];
    if (first < 2 or g_buf[529] != 255) return false;
    var k: usize = len;
    while (k > 528) {
        k -= 1;
        g_buf[k + 2] = g_buf[k];
    }
    g_buf[528] = first - 1;
    g_buf[529] = 255;
    g_buf[530] = 1;
    g_buf[531] = 255;
    return validate_assets.validateAsset(g_buf[0 .. len + 2], validate_assets.EXPECTED_A[0]) == .NonCanonical;
}

fn tManifestGood() bool {
    const n = makeManifest(g_man[0..], -1, false, false, false, false);
    return validate_assets.validateManifest(g_man[0..n], DIR) == .Ok;
}

fn tManifestBadName() bool {
    const n = makeManifest(g_man[0..], -1, true, false, false, false);
    return validate_assets.validateManifest(g_man[0..n], DIR) == .BadName;
}

fn tManifestMissingEntry() bool {
    const n = makeManifest(g_man[0..], 0, false, false, false, false);
    return validate_assets.validateManifest(g_man[0..n], DIR) == .MissingEntry;
}

fn tManifestOrphanV() bool {
    const n = makeManifest(g_man[0..], -1, false, true, false, false);
    return validate_assets.validateManifest(g_man[0..n], DIR) == .OrphanVariant;
}

fn tManifestDuplicateV() bool {
    const n = makeManifest(g_man[0..], -1, false, false, true, false);
    return validate_assets.validateManifest(g_man[0..n], DIR) == .DuplicateVariant;
}

fn tManifestWrongFromRamp() bool {
    const n = makeManifest(g_man[0..], -1, false, false, false, true);
    return validate_assets.validateManifest(g_man[0..n], DIR) == .BadFromRamp;
}

fn tManifestBudgetOverrun() bool {
    const spec = validate_assets.EXPECTED_A[BG_A_INDEX];
    const len = buildWideBg(spec, g_buf[0..]);
    if (len == 0) return false;
    if (!writeFile(DIR, spec.name, ".zsp", g_buf[0..len])) return false;
    const saved = g_len[BG_A_INDEX];
    g_len[BG_A_INDEX] = len;
    const n = makeManifest(g_man[0..], -1, false, false, false, false);
    const e = validate_assets.validateManifest(g_man[0..n], DIR);
    g_len[BG_A_INDEX] = saved;
    return e == .Budget;
}

fn restoreGoodBg() bool {
    const spec = validate_assets.EXPECTED_A[BG_A_INDEX];
    const hr = baseHeaderRamp(spec.name, spec);
    const len = buildAsset(spec, hr, hr, false, g_buf[0..]);
    if (len == 0) return false;
    if (!writeFile(DIR, spec.name, ".zsp", g_buf[0..len])) return false;
    g_len[BG_A_INDEX] = len;
    return true;
}

pub fn main() void {
    ensureDir(DIR);

    const files_ok = buildAllFiles(DIR);
    report("setup_synthetic_assets", files_ok);

    report("asset_accepts_known_good", tGoodAsset());
    report("asset_rejects_bad_magic", tBadMagic());
    report("asset_rejects_truncated_run", tTruncatedRun());
    report("asset_rejects_oversized_dims", tOversizedDims());
    report("asset_rejects_off_ramp_pixel", tOffRamp());
    report("asset_rejects_bad_palette", tBadPalette());
    report("asset_rejects_noncanonical_rle", tNonCanonical());
    report("asset_rejects_missing_creature_border", tBadBorder());

    report("manifest_accepts_full_ledger", tManifestGood());
    report("manifest_rejects_bad_8_3_name", tManifestBadName());
    report("manifest_rejects_missing_entry", tManifestMissingEntry());
    report("manifest_rejects_orphan_v", tManifestOrphanV());
    report("manifest_rejects_duplicate_v", tManifestDuplicateV());
    report("manifest_rejects_wrong_from_ramp", tManifestWrongFromRamp());
    report("manifest_rejects_budget_overrun", tManifestBudgetOverrun());

    const restored = restoreGoodBg();
    report("setup_restore_good_bg", restored);

    if (restored) {
        const good_n = makeManifest(g_man[0..], -1, false, false, false, false);
        const wrote_good = writeFile(DIR, "good", ".man", g_man[0..good_n]);
        const bad_n = makeManifest(g_man[0..], -1, false, false, true, false);
        const wrote_bad = writeFile(DIR, "bad", ".man", g_man[0..bad_n]);
        report("setup_cli_manifests", wrote_good and wrote_bad);
    }

    if (fails != 0) os.exit(1);
    io.write("validate_assets_test PASS\n");
}
