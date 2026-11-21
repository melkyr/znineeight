// boat_test.zig — native M11 boat paint/cosmetic/overlay driver (§30, P31).
//
// Covers the pinned paint LUTs (Foam White / Abyss Teal / Leviathan Black),
// the hull bbox clip (outside-bbox, outline and porthole pixels stay base),
// highest-owned cosmetic selection per slot, the decal-figurehead-flag blit
// order, boss-variant accessors, the score/boat art path, and the boat art
// checksum from a pre-present in-memory 640x480 framebuffer dump.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/boat_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/boat_test"
//   "$OUT/boat_test"

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const file_mod = @import("std_file");
const def = @import("../def.zig");
const game = @import("../game.zig");
const art = @import("../render_art.zig");
const assets = @import("../assets.zig");
const boat = @import("../boat.zig");
const score = @import("../score.zig");
const core = @import("std_gfx_px_core.zig");

const ASSETS_DIR = "examples/z98/undersanded/assets";
const BOAT_GOLDEN = "examples/z98/undersanded/tests/fixtures/boat_art.golden";
const DUMP_BOAT = "examples/z98/undersanded/tests/fixtures/dump_grid_boat.golden";
const W: usize = 640;
const H: usize = 480;

var fails: usize = 0;
var arena_buf: [16 * 1024]u8 = undefined;
var arena: arena_mod.Arena = undefined;
var empty_px: [1]u8 = [1]u8{0};

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

fn contains(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (eq(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn fnv(data: []const u8) u32 {
    var h: u32 = 2166136261;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        h = (h ^ @intCast(u32, data[i])) *% 16777619;
    }
    return h;
}

fn parseHex(text: []const u8) u32 {
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (c == '0' and i + 1 < text.len and (text[i + 1] == 'x' or text[i + 1] == 'X')) {
            i += 2;
            break;
        }
        if ((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')) break;
    }
    var v: u32 = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        var d: u32 = 0;
        if (c >= '0' and c <= '9') {
            d = @intCast(u32, c - '0');
        } else if (c >= 'a' and c <= 'f') {
            d = @intCast(u32, c - 'a') + 10;
        } else if (c >= 'A' and c <= 'F') {
            d = @intCast(u32, c - 'A') + 10;
        } else {
            break;
        }
        v = v * 16 + d;
    }
    return v;
}

fn writeHex8(v: u32) void {
    io.write("0x");
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
        io.writeByte(c);
    }
}

fn dumpPix(d: []const u8, x: i32, y: i32) u16 {
    const off = (@intCast(usize, y) * W + @intCast(usize, x)) * 2;
    return @intCast(u16, d[off]) | (@intCast(u16, d[off + 1]) << 8);
}

fn setBit(w: *def.World, index: i32) void {
    if (index < 0 or index >= 32) return;
    const bit = @intCast(u32, 1) << @intCast(u32, index);
    w.cosmetics_owned = w.cosmetics_owned | bit;
}

fn fullView(a: *const assets.Assets) art.ArtAssets {
    var v = art.emptyAssets();
    v.boat = assets.boatSprite(a);
    v.paints = assets.boatPaints(a);
    v.overlays = assets.overlays(a);
    return v;
}

fn renderBoatWorld(w: *const def.World, view: art.ArtAssets, ox: i32, oy: i32) []const u8 {
    const handle = core.gfxPxOpenMemory(640, 480) catch return empty_px[0..0];
    var sf = core.pxCoreSurface(handle.opaque);
    core.pxCoreFill(&sf, 0, 0, def.SCREEN_W, def.SCREEN_H, art.C_BG);
    art.drawBoat(&sf, w, view, ox, oy);
    return core.gfxPxDump(handle);
}

fn findBoatShade(sprite: *const core.Sprite, want: u8, inside: bool,
    out_x: *i32, out_y: *i32) bool {
    var y: i32 = 0;
    while (y < boat.BOAT_H) : (y += 1) {
        var x: i32 = 0;
        while (x < boat.BOAT_W) : (x += 1) {
            const idx = sprite.idx[@intCast(usize, y) * @intCast(usize, sprite.w)
                + @intCast(usize, x)];
            if (idx != want) continue;
            const in_hull = x >= boat.HULL_X and x < boat.HULL_X + boat.HULL_W
                and y >= boat.HULL_Y and y < boat.HULL_Y + boat.HULL_H;
            if (in_hull == inside) {
                out_x.* = x;
                out_y.* = y;
                return true;
            }
        }
    }
    return false;
}

fn findBoatHullAny(sprite: *const core.Sprite, inside: bool,
    out_x: *i32, out_y: *i32) bool {
    var y: i32 = 0;
    while (y < boat.BOAT_H) : (y += 1) {
        var x: i32 = 0;
        while (x < boat.BOAT_W) : (x += 1) {
            const idx = sprite.idx[@intCast(usize, y) * @intCast(usize, sprite.w)
                + @intCast(usize, x)];
            if (idx != 5 and idx != 10 and idx != 15) continue;
            const in_hull = x >= boat.HULL_X and x < boat.HULL_X + boat.HULL_W
                and y >= boat.HULL_Y and y < boat.HULL_Y + boat.HULL_H;
            if (in_hull == inside) {
                out_x.* = x;
                out_y.* = y;
                return true;
            }
        }
    }
    return false;
}

fn findBoatRamp(sprite: *const core.Sprite, ramp: u8, inside: bool,
    out_x: *i32, out_y: *i32) bool {
    var y: i32 = 0;
    while (y < boat.BOAT_H) : (y += 1) {
        var x: i32 = 0;
        while (x < boat.BOAT_W) : (x += 1) {
            const idx = sprite.idx[@intCast(usize, y) * @intCast(usize, sprite.w)
                + @intCast(usize, x)];
            if ((idx >> 4) != ramp) continue;
            const in_hull = x >= boat.HULL_X and x < boat.HULL_X + boat.HULL_W
                and y >= boat.HULL_Y and y < boat.HULL_Y + boat.HULL_H;
            if (in_hull == inside) {
                out_x.* = x;
                out_y.* = y;
                return true;
            }
        }
    }
    return false;
}

fn tAccessors() bool {
    const a = assets.current() orelse return false;
    const base = assets.boatSprite(a) orelse return false;
    if (base.w != 200 or base.h != 150) return false;
    if (assets.boatPaint(a, -1) != null) return false;
    if (assets.boatPaint(a, 3) != null) return false;

    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const p = assets.boatPaint(a, i) orelse return false;
        if (p.idx != base.idx or p.w != base.w or p.h != base.h) return false;
    }

    if (assets.overlayForCosmetic(a, 2) != null) return false;
    if (assets.overlayForCosmetic(a, 12) != null) return false;
    i = 3;
    while (i <= 11) : (i += 1) {
        if (assets.overlayForCosmetic(a, i) == null) return false;
    }

    const armor = assets.bossVariant(a, 0) orelse return false;
    const via_def = assets.spriteForDef(a, 17) orelse return false;
    if (armor.idx != via_def.idx or armor.lut != via_def.lut) return false;
    if (assets.bossVariant(a, 5) != null) return false;
    i = 1;
    while (i <= 4) : (i += 1) {
        const v = assets.bossVariant(a, i) orelse return false;
        if (v.lut == armor.lut) return false;
        const prev = assets.bossVariant(a, i - 1) orelse return false;
        if (prev.lut == v.lut) return false;
    }
    return true;
}

fn tPaintLut() bool {
    const a = assets.current() orelse return false;
    const base = assets.boatSprite(a) orelse return false;
    const shades = [3]usize{ 5, 10, 15 };
    const targets = [3][3]usize{
        [3]usize{ 10, 15, 15 },
        [3]usize{ 21, 26, 31 },
        [3]usize{ 0, 5, 10 },
    };

    var p: i32 = 0;
    while (p < 3) : (p += 1) {
        const ps = assets.boatPaint(a, p) orelse return false;
        var i: usize = 0;
        while (i < 256) : (i += 1) {
            var want = base.lut[i];
            var s: usize = 0;
            while (s < shades.len) : (s += 1) {
                if (i == shades[s]) want = base.lut[targets[@intCast(usize, p)][s]];
            }
            if (ps.lut[i] != want) return false;
        }
    }
    return true;
}

fn tPaintClip() bool {
    const a = assets.current() orelse return false;
    const base = assets.boatSprite(a) orelse return false;
    var view = fullView(a);
    var w: def.World = undefined;
    game.zeroWorld(&w);

    var in_x: i32 = 0;
    var in_y: i32 = 0;
    var out_x: i32 = 0;
    var out_y: i32 = 0;
    if (!findBoatShade(base, 5, true, &in_x, &in_y)) return false;
    if (!findBoatHullAny(base, false, &out_x, &out_y)) return false;

    var outline_x: i32 = 0;
    var outline_y: i32 = 0;
    if (!findBoatShade(base, 0, true, &outline_x, &outline_y)) return false;
    var port_x: i32 = 0;
    var port_y: i32 = 0;
    if (!findBoatRamp(base, 1, true, &port_x, &port_y)) return false;

    const plain = renderBoatWorld(&w, view, 10, 10);
    if (plain.len != W * H * 2) return false;
    const plain_in = dumpPix(plain, in_x + 10, in_y + 10);
    const plain_out = dumpPix(plain, out_x + 10, out_y + 10);
    const plain_outline = dumpPix(plain, outline_x + 10, outline_y + 10);
    const plain_port = dumpPix(plain, port_x + 10, port_y + 10);

    var p: i32 = 0;
    while (p < 3) : (p += 1) {
        w.cosmetics_owned = 0;
        setBit(&w, p);
        const painted = renderBoatWorld(&w, view, 10, 10);
        if (dumpPix(painted, in_x + 10, in_y + 10) == plain_in) return false;
        if (dumpPix(painted, out_x + 10, out_y + 10) != plain_out) return false;
        if (dumpPix(painted, outline_x + 10, outline_y + 10) != plain_outline) {
            return false;
        }
        if (dumpPix(painted, port_x + 10, port_y + 10) != plain_port) {
            return false;
        }
    }
    return true;
}

fn tSelection() bool {
    var w: def.World = undefined;
    game.zeroWorld(&w);
    if (boat.paintIndex(&w) != -1) return false;
    if (boat.figureheadIndex(&w) != -1) return false;
    if (boat.flagIndex(&w) != -1) return false;
    if (boat.decalIndex(&w) != -1) return false;

    setBit(&w, 0);
    if (boat.paintIndex(&w) != boat.PAINT_FOAM) return false;
    setBit(&w, 2);
    if (boat.paintIndex(&w) != boat.PAINT_BLACK) return false;
    setBit(&w, 1);
    if (boat.paintIndex(&w) != boat.PAINT_BLACK) return false;

    setBit(&w, 3);
    setBit(&w, 5);
    if (boat.figureheadIndex(&w) != 5) return false;
    setBit(&w, 6);
    setBit(&w, 8);
    if (boat.flagIndex(&w) != 8) return false;
    setBit(&w, 9);
    setBit(&w, 11);
    if (boat.decalIndex(&w) != 11) return false;
    if (boat.selectedCosmetic(&w, boat.SLOT_FIGUREHEAD) != 5) return false;
    if (boat.selectedCosmetic(&w, boat.SLOT_FLAG) != 8) return false;
    if (boat.selectedCosmetic(&w, boat.SLOT_DECAL) != 11) return false;
    return true;
}

// The highest owned index per slot must be the one drawn, not an earlier bit.
fn tHighestOwnedRender() bool {
    const a = assets.current() orelse return false;
    const view = fullView(a);
    var hi: def.World = undefined;
    var lo: def.World = undefined;
    game.zeroWorld(&hi);
    game.zeroWorld(&lo);

    setBit(&hi, 0);
    setBit(&hi, 1);
    setBit(&hi, 2);
    setBit(&lo, 2);
    const hp = fnv(renderBoatWorld(&hi, view, 0, 0));
    const lp = fnv(renderBoatWorld(&lo, view, 0, 0));
    if (hp != lp) return false;

    setBit(&hi, 3);
    setBit(&hi, 4);
    setBit(&hi, 5);
    setBit(&lo, 5);
    const hf = fnv(renderBoatWorld(&hi, view, 0, 0));
    const lf = fnv(renderBoatWorld(&lo, view, 0, 0));
    if (hf != lf) return false;

    setBit(&hi, 6);
    setBit(&hi, 7);
    setBit(&hi, 8);
    setBit(&lo, 8);
    const hg = fnv(renderBoatWorld(&hi, view, 0, 0));
    const lg = fnv(renderBoatWorld(&lo, view, 0, 0));
    if (hg != lg) return false;

    setBit(&hi, 9);
    setBit(&hi, 10);
    setBit(&hi, 11);
    setBit(&lo, 11);
    const hd = fnv(renderBoatWorld(&hi, view, 0, 0));
    const ld = fnv(renderBoatWorld(&lo, view, 0, 0));
    return hd == ld;
}

fn tOverlayAnchorsAndOrder() bool {
    if (boat.OVERLAY_DRAW_ORDER[0] != boat.SLOT_DECAL) return false;
    if (boat.OVERLAY_DRAW_ORDER[1] != boat.SLOT_FIGUREHEAD) return false;
    if (boat.OVERLAY_DRAW_ORDER[2] != boat.SLOT_FLAG) return false;
    if (boat.anchorX(boat.SLOT_FIGUREHEAD) != 24) return false;
    if (boat.anchorY(boat.SLOT_FIGUREHEAD) != 40) return false;
    if (boat.anchorX(boat.SLOT_FLAG) != 150) return false;
    if (boat.anchorY(boat.SLOT_FLAG) != 18) return false;
    if (boat.anchorX(boat.SLOT_DECAL) != 96) return false;
    if (boat.anchorY(boat.SLOT_DECAL) != 96) return false;

    const a = assets.current() orelse return false;
    const view = fullView(a);
    const overlays = view.overlays orelse return false;
    var w: def.World = undefined;
    game.zeroWorld(&w);
    setBit(&w, 3);
    setBit(&w, 6);
    setBit(&w, 9);
    const d = renderBoatWorld(&w, view, 0, 0);
    if (d.len != W * H * 2) return false;

    // Each selected overlay contributes at least one non-key pixel at its
    // authored anchor; the decal anchor also lies inside the painted hull.
    var slot_i: usize = 0;
    while (slot_i < boat.OVERLAY_DRAW_ORDER.len) : (slot_i += 1) {
        const slot = boat.OVERLAY_DRAW_ORDER[slot_i];
        const cosmetic = boat.selectedCosmetic(&w, slot);
        if (cosmetic < 0) continue;
        const local: usize = @intCast(usize,
            cosmetic - boat.COSMETIC_OVERLAY_FIRST);
        const ov = &overlays[local];
        var found = false;
        var y: i32 = 0;
        while (y < @intCast(i32, ov.h) and !found) : (y += 1) {
            var x: i32 = 0;
            while (x < @intCast(i32, ov.w)) : (x += 1) {
                const idx = ov.idx[@intCast(usize, y) * @intCast(usize, ov.w)
                    + @intCast(usize, x)];
                if (idx == ov.key) continue;
                const px = boat.anchorX(slot) + x;
                const py = boat.anchorY(slot) + y;
                if (dumpPix(d, px, py) == ov.lut[idx]) {
                    found = true;
                    break;
                }
            }
        }
        if (!found) return false;
    }
    return true;
}

fn renderScoreArt(w: *def.World, view: art.ArtAssets) []const u8 {
    var g: def.GameState = undefined;
    game.newGame(&g);
    g.world = w.*;
    g.screen = def.NAV_SCORE;
    const handle = core.gfxPxOpenMemory(640, 480) catch return empty_px[0..0];
    var sf = core.pxCoreSurface(handle.opaque);
    art.resetFrame();
    art.renderScreen(&sf, &g, "", true, view);
    return core.gfxPxDump(handle);
}

fn tScoreArtBoat() bool {
    const a = assets.current() orelse return false;
    const view = fullView(a);
    var w: def.World = undefined;
    game.zeroWorld(&w);
    setBit(&w, 1);
    setBit(&w, 3);
    setBit(&w, 6);
    setBit(&w, 9);

    const with_boat = fnv(renderScoreArt(&w, view));
    var none = view;
    none.boat = null;
    const without_boat = fnv(renderScoreArt(&w, none));
    return with_boat != without_boat;
}

fn tGoldenChecksum(path: []const u8, got: u32) bool {
    arena = arena_mod.init(arena_buf[0..]);
    const raw = file_mod.readAll(&arena, path) catch return false;
    return got == parseHex(raw);
}

fn tGoldenDump() bool {
    var buf: [8192]u8 = undefined;
    const text = undtoolDumpBoat(buf[0..]) orelse return false;
    arena = arena_mod.init(arena_buf[0..]);
    const raw = file_mod.readAll(&arena, DUMP_BOAT) catch return false;
    return eq(raw, text);
}

// Keep the undtool import local to the dump test so the driver still builds
// when only the boat renderer is under test.
const undtool = @import("../undtool.zig");

fn undtoolDumpBoat(out: []u8) ?[]const u8 {
    return undtool.dumpFixedScreen("boat", out);
}

pub fn main() void {
    if (!assets.load(ASSETS_DIR)) {
        report("assets_load", false);
        if (fails != 0) os.exit(1);
        return;
    }
    report("assets_load", true);
    report("boat_overlay_boss_accessors", tAccessors());
    report("boat_paint_lut_pinned", tPaintLut());
    report("boat_paint_clip_bbox", tPaintClip());
    report("cosmetic_highest_owned_selection", tSelection());
    report("cosmetic_highest_owned_render", tHighestOwnedRender());
    report("overlay_anchors_and_blit_order", tOverlayAnchorsAndOrder());
    report("score_art_draws_boat", tScoreArtBoat());
    report("dump_grid_boat_golden", tGoldenDump());

    const a = assets.current() orelse {
        report("boat_art_checksum_pre_present", false);
        if (fails != 0) os.exit(1);
        return;
    };
    const view = fullView(a);
    var w: def.World = undefined;
    game.zeroWorld(&w);
    setBit(&w, 1);
    setBit(&w, 3);
    setBit(&w, 6);
    setBit(&w, 9);
    const handle = core.gfxPxOpenMemory(640, 480) catch {
        report("boat_art_checksum_pre_present", false);
        if (fails != 0) os.exit(1);
        return;
    };
    var sf = core.pxCoreSurface(handle.opaque);
    art.drawBoatScreen(&sf, &w, view);
    const dump = core.gfxPxDump(handle);
    const got = fnv(dump);
    io.write("boat_art_checksum=");
    writeHex8(got);
    io.write("\n");
    report("boat_art_checksum_pre_present",
        dump.len == W * H * 2 and tGoldenChecksum(BOAT_GOLDEN, got));

    if (fails != 0) {
        io.write("boat_test FAIL\n");
        os.exit(1);
        return;
    }
    io.write("boat_test PASS\n");
}
