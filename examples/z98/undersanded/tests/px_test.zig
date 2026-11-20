// px_test.zig — UNDERSANDED M9 native art-dump / terminal-parity driver.
//
// Prints the deterministic art-fight 640x480 565 framebuffer checksum, the four
// §28 button rects and the full tool-status line, then asserts:
//   * the checksum matches ART_GOLDEN (default committed art_fight.golden)
//   * the art dump is exactly 640*480*2 bytes
//   * the four button rects and hit-testing are pinned
//   * the tool-status line occupies at most 80 columns with a fixed width
//   * the perf log shape is the pinned `perf frames=...` line
//   * a simulated surface-lost restore forces a full repaint and re-rendering
//     the full frame reproduces the same 565 checksum
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/px_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/px_test"
//   "$OUT/px_test"
//
// Env: ART_GOLDEN  golden checksum path override (used by the tier for its
//                  non-vacuity mutation; the committed fixture is never
//                  regenerated).

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const file_mod = @import("std_file");
const def = @import("../def.zig");
const game = @import("../game.zig");
const fight = @import("../fight.zig");
const render = @import("../render_term.zig");
const art = @import("../render_art.zig");
const perf = @import("../perf.zig");
const core = @import("std_gfx_px_core.zig");

const GOLDEN_PATH = "examples/z98/undersanded/tests/fixtures/art_fight.golden";
const W: usize = 640;
const H: usize = 480;

var fails: usize = 0;
var arena_buf: [64 * 1024]u8 = undefined;
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

fn setJournalBit(g: *def.GameState, d: i32) void {
    if (d < 0 or d >= 64) return;
    const word: usize = @intCast(usize, d / 32);
    const bit: u32 = @intCast(u32, d % 32);
    var mask: *[2]u32 = &g.world.journal_mask;
    mask[word] = mask[word] | (@intCast(u32, 1) << bit);
}

fn baseFight(g: *def.GameState) void {
    game.newGame(g);
    game.startFight(g, 0);
    g.exp.active = 1;
    g.exp.zone = 0;
    g.exp.fight_index = 0;
    g.exp.seed = 98;
    g.world.phase = 1;
    g.world.money = 123;
    g.fight.hp = 42;
    g.fight.max_hp = 70;
    g.fight.res = 8;
    g.fight.max_res = 10;
    g.fight.hull = 80;
    g.fight.max_hull = 100;
    g.fight.margin_pct = 10;
    g.fight.tool = 4;
    g.fight.tool_charge = 1;
    g.fight.tool_broken = 0;
    g.fight.tool_active = 1;
    g.fight.round = 1;
    g.screen = def.SCREEN_FIGHT;
}

fn goldenFight(g: *def.GameState) void {
    baseFight(g);
    setJournalBit(g, g.fight.def_index);
    g.log_n = 3;
    g.log[0] = def.LogEntry{
        .class = def.LOG_NORMAL, .msg_id = def.MSG_STRIKE, .a = 17, .b = 0,
    };
    g.log[1] = def.LogEntry{
        .class = def.LOG_NORMAL, .msg_id = def.MSG_CREATURE_ATTACK,
        .a = 9, .b = 91,
    };
    g.log[2] = def.LogEntry{
        .class = def.LOG_NORMAL, .msg_id = def.MSG_INK, .a = 0, .b = 0,
    };
}

fn goldenDump() []const u8 {
    var g: def.GameState = undefined;
    goldenFight(&g);
    art.resetFrame();
    const handle = core.gfxPxOpenMemory(W, H) catch return empty_px[0..0];
    var sf = core.pxCoreSurface(handle.opaque);
    art.renderScreen(&sf, &g, "", true);
    return core.gfxPxDump(handle);
}

fn goldenMatches(got: u32) bool {
    const path = os.env("ART_GOLDEN") orelse GOLDEN_PATH;
    arena = arena_mod.init(arena_buf[0..]);
    const raw = file_mod.readAll(&arena, path) catch return false;
    return got == parseHex(raw);
}

fn tButtons() bool {
    if (art.BUTTON_Y != 372 or art.BUTTON_H != 56) return false;
    if (art.BUTTON_W != 160) return false;
    var b: i32 = 0;
    while (b < 4) : (b += 1) {
        const r = art.BUTTON_RECTS[@intCast(usize, b)];
        if (r.x != b * art.BUTTON_W or r.y != art.BUTTON_Y) return false;
        if (r.w != art.BUTTON_W or r.h != art.BUTTON_H) return false;
        if (art.hitButton(r.x + 2, r.y + 2) != b) return false;
    }
    if (art.hitButton(639, 371) != -1) return false;
    return art.hitButton(0, 480) == -1;
}

fn printButtons() void {
    var b: i32 = 0;
    while (b < 4) : (b += 1) {
        const r = art.BUTTON_RECTS[@intCast(usize, b)];
        io.write("button");
        io.printInt(b);
        io.write("=");
        io.printInt(r.x);
        io.write(",");
        io.printInt(r.y);
        io.write(",");
        io.printInt(r.w);
        io.write(",");
        io.printInt(r.h);
        io.write("\n");
    }
}

fn toolStatusWidth() usize {
    var g: def.GameState = undefined;
    baseFight(&g);
    var sc: render.Screen = undefined;
    render.clear(&sc);
    render.renderToolStatus(&sc, &g, 0);
    var last: usize = 0;
    var i: usize = 0;
    while (i < render.COLS) : (i += 1) {
        if (sc.cells[i] != ' ') last = i + 1;
    }
    return last;
}

fn printToolStatus() void {
    var g: def.GameState = undefined;
    baseFight(&g);
    var sc: render.Screen = undefined;
    render.clear(&sc);
    render.renderToolStatus(&sc, &g, 0);
    const last = toolStatusWidth();
    io.write("tool_status=");
    var i: usize = 0;
    while (i < last) : (i += 1) {
        io.writeByte(sc.cells[i]);
    }
    io.write("\n");
}

fn tToolStatus() bool {
    const last = toolStatusWidth();
    if (last != 69) return false;
    return last * 8 <= 640;
}

fn tPerfShape() bool {
    var p: perf.Perf = undefined;
    perf.reset(&p);
    perf.addMs(&p, 4);
    perf.addMs(&p, 1);
    perf.addMs(&p, 3);
    perf.addMs(&p, 2);
    var buf: [128]u8 = undefined;
    const line = perf.format(&p, buf[0..]);
    var want: []const u8 = "perf frames=4 p50=2ms p95=4ms p99=4ms";
    if (line.len != want.len) return false;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (line[i] != want[i]) return false;
    }
    return true;
}

fn printPerfShape() void {
    var p: perf.Perf = undefined;
    perf.reset(&p);
    perf.addMs(&p, 4);
    perf.addMs(&p, 1);
    perf.addMs(&p, 3);
    perf.addMs(&p, 2);
    var buf: [128]u8 = undefined;
    const line = perf.format(&p, buf[0..]);
    io.write("perf_shape=");
    io.write(line);
    io.write("\n");
}

fn tSurfaceLostRepaint() bool {
    var g: def.GameState = undefined;
    goldenFight(&g);
    const handle = core.gfxPxOpenMemory(W, H) catch return false;
    art.resetFrame();
    var sf = core.pxCoreSurface(handle.opaque);
    art.renderScreen(&sf, &g, "", true);
    const c1 = fnv(core.gfxPxDump(handle));
    if (!goldenMatches(c1)) return false;

    // The loss must set the restored/full-repaint transition, and the buffer
    // is poisoned so a skipped re-render cannot pass vacuously.
    core.pxCoreMarkSurfaceLost(handle.opaque);
    if (!core.pxCoreSurfaceLost(handle.opaque)) return false;
    sf = core.pxCoreSurface(handle.opaque);
    core.pxCoreFill(&sf, 0, 0, def.SCREEN_W, def.SCREEN_H, 0xDEAD);
    if (fnv(core.gfxPxDump(handle)) == c1) return false;

    core.pxCoreMarkRestored(handle.opaque);
    if (core.pxCoreSurfaceLost(handle.opaque)) return false;
    if (!core.pxCoreNeedsFullRepaint(handle.opaque)) return false;

    art.resetFrame();
    sf = core.pxCoreSurface(handle.opaque);
    art.renderScreen(&sf, &g, "", true);
    const c2 = fnv(core.gfxPxDump(handle));
    core.pxCoreClearFullRepaint(handle.opaque);
    if (core.pxCoreNeedsFullRepaint(handle.opaque)) return false;
    return goldenMatches(c2);
}

pub fn main() void {
    const dump = goldenDump();
    const got = fnv(dump);
    io.write("art_fight_checksum=");
    writeHex8(got);
    io.write("\n");
    printButtons();
    printToolStatus();
    printPerfShape();

    report("art_fight_640x480_565_dump", dump.len == W * H * 2);
    report("art_fight_checksum_matches_golden", dump.len == W * H * 2 and goldenMatches(got));
    report("button_rects_four", tButtons());
    report("tool_status_line_69_cols", tToolStatus());
    report("perf_log_shape_pinned", tPerfShape());
    report("surface_lost_full_repaint_after_restore", tSurfaceLostRepaint());

    if (fails != 0) {
        io.write("px_test FAIL\n");
        os.exit(1);
        return;
    }
    io.write("px_test PASS\n");
}
