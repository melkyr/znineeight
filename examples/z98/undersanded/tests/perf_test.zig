// perf_test.zig — UNDERSANDED M9 native perf math + scripted walk driver.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/perf_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/perf_test"
//   "$OUT/perf_test"

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const game = @import("../game.zig");
const fight = @import("../fight.zig");
const expedition = @import("../expedition.zig");
const nav = @import("../nav.zig");
const input = @import("../input.zig");
const render = @import("../render_term.zig");
const art = @import("../render_art.zig");
const core = @import("std_gfx_px_core.zig");
const perf = @import("../perf.zig");

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

fn key(c: u8) input.Key {
    return input.Key{ .ch = c, .code = 0 };
}

fn newNav() nav.NavState {
    return nav.initState();
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn contains(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > hay.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len and hay[i + j] == needle[j]) : (j += 1) {}
        if (j == needle.len) return true;
    }
    return false;
}

fn tPercentiles() bool {
    var p: perf.Perf = undefined;
    perf.reset(&p);
    var i: i64 = 1;
    while (i <= 10) : (i += 1) perf.addMs(&p, i);

    var scratch: [perf.MAX_FRAMES]i64 = undefined;
    const n = perf.sortedCopy(&p, scratch[0..]);
    if (n != 10) return false;
    if (perf.percentileSorted(scratch[0..n], 50) != 5) return false;
    if (perf.percentileSorted(scratch[0..n], 95) != 10) return false;
    if (perf.percentileSorted(scratch[0..n], 99) != 10) return false;
    if (perf.percentileSorted(scratch[0..1], 99) != 1) return false;
    if (perf.percentileSorted(scratch[0..0], 50) != 0) return false;
    return true;
}

fn tFormatShape() bool {
    var p: perf.Perf = undefined;
    perf.reset(&p);
    perf.addMs(&p, 4);
    perf.addMs(&p, 1);
    perf.addMs(&p, 3);
    perf.addMs(&p, 2);

    var buf: [128]u8 = undefined;
    const line = perf.format(&p, buf[0..]);
    if (!eq(line, "perf frames=4 p50=2ms p95=4ms p99=4ms")) return false;

    perf.reset(&p);
    const empty = perf.format(&p, buf[0..]);
    return eq(empty, "perf frames=0 p50=0ms p95=0ms p99=0ms");
}

fn tTicksAndSort() bool {
    if (perf.ticksToMs(0, 1000) != 0) return false;
    if (perf.ticksToMs(1, 1000) != 1) return false;
    if (perf.ticksToMs(2500, 1000) != 2500) return false;
    if (perf.ticksToMs(100, 0) != 0) return false;

    var p: perf.Perf = undefined;
    perf.reset(&p);
    perf.addMs(&p, 30);
    perf.addMs(&p, 10);
    perf.addMs(&p, 20);
    var scratch: [perf.MAX_FRAMES]i64 = undefined;
    const n = perf.sortedCopy(&p, scratch[0..]);
    if (n != 3) return false;
    return scratch[0] == 10 and scratch[1] == 20 and scratch[2] == 30;
}

fn tCap() bool {
    var p: perf.Perf = undefined;
    perf.reset(&p);
    var i: usize = 0;
    while (i < perf.MAX_FRAMES + 8) : (i += 1) perf.addMs(&p, 1);
    return p.n == perf.MAX_FRAMES;
}

// The pure filter is the one contract both stdin readKey and the window
// gameplay loop apply: line endings/space ignored, 0/255 end the stream.
fn filterStream(stream: []const u8, out: []u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < stream.len) : (i += 1) {
        const k = input.Key{ .ch = stream[i], .code = 0 };
        if (input.filterKey(k)) |f| {
            if (n < out.len) {
                out[n] = f.ch;
                n += 1;
            }
        } else if (stream[i] == 0 or stream[i] == 255) {
            break;
        }
    }
    return n;
}

fn tKeyFilterParity() bool {
    const stream = [_]u8{ 10, 13, ' ', 'd', '2', ' ', 27, 'q' };
    const expected = [_]u8{ 'd', '2', 27, 'q' };
    var got: [8]u8 = undefined;
    const n = filterStream(stream[0..], got[0..]);
    if (n != expected.len) return false;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (got[i] != expected[i]) return false;
    }

    const eof0 = [_]u8{ 'd', 0, '2' };
    const eof255 = [_]u8{ 'd', 255, '2' };
    if (filterStream(eof0[0..], got[0..]) != 1 or got[0] != 'd') return false;
    if (filterStream(eof255[0..], got[0..]) != 1 or got[0] != 'd') return false;

    if (input.filterKey(input.Key{ .ch = 10, .code = 0 }) != null) return false;
    if (input.filterKey(input.Key{ .ch = 13, .code = 0 }) != null) return false;
    if (input.filterKey(input.Key{ .ch = ' ', .code = 0 }) != null) return false;
    if (input.filterKey(input.Key{ .ch = 0, .code = 0 }) != null) return false;
    if (input.filterKey(input.Key{ .ch = 255, .code = 0 }) != null) return false;
    if (input.filterKey(input.Key{ .ch = '?', .code = 0 }) == null) return false;
    return true;
}

fn renderOk(g: *def.GameState, st: *const nav.NavState, expect: []const u8) bool {
    var sc: render.Screen = undefined;
    var buf: [8192]u8 = undefined;
    nav.drawScreen(g, st, &sc);
    const text = render.dump(&sc, buf[0..]);
    if (expect.len == 0) return true;
    return contains(text, expect);
}

fn renderArtOk(g: *def.GameState) bool {
    const handle = core.gfxPxOpenMemory(640, 480) catch return false;
    var sf = core.pxCoreSurface(handle.opaque);
    art.renderScreen(&sf, g, "", true,
        art.ArtAssets{ .bg = null, .sprite = null });
    return true;
}

// Scripted dock -> map -> node -> fight -> settle -> dock walk; each state is
// rendered through the shared cell screen with no crash.
fn tWalk() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    var st = newNav();

    if (nav.navStep(&g, &st, key('d')) != def.NAV_MAP) return false;
    if (!renderOk(&g, &st, "UNDERSANDED  MAP")) return false;

    if (nav.navStep(&g, &st, key('2')) != def.NAV_NODE) return false;
    if (!renderOk(&g, &st, "UNDERSANDED  NODE")) return false;

    _ = nav.navStep(&g, &st, key('h'));
    var guard: i32 = 0;
    while (expedition.isInFight(&g) and guard < 200) : (guard += 1) {
        if (!renderArtOk(&g)) return false;
        if (g.screen == def.SCREEN_SUBDUE or g.screen == def.SCREEN_SUBDUE_POST) {
            _ = nav.navStep(&g, &st, key('a'));
            if (!renderOk(&g, &st, "")) return false;
        } else if (g.fight.hp * 100 > g.fight.max_hp * 50) {
            _ = nav.navStep(&g, &st, key('s'));
            if (!renderOk(&g, &st, "")) return false;
        } else {
            _ = nav.navStep(&g, &st, key('r'));
            if (!renderOk(&g, &st, "")) return false;
        }
    }
    if (expedition.isInFight(&g)) return false;
    if (g.screen != def.NAV_SUBDUE_INTRO) return false;
    if (!renderOk(&g, &st, "SUBDUED")) return false;

    if (nav.navStep(&g, &st, key('c')) != def.NAV_SETTLE) return false;
    if (!renderOk(&g, &st, "UNDERSANDED  SETTLE")) return false;

    if (nav.navStep(&g, &st, key('1')) != def.NAV_NODE) return false;
    if (!renderOk(&g, &st, "UNDERSANDED  NODE")) return false;

    if (nav.navStep(&g, &st, key('s')) != def.NAV_DOCK) return false;
    if (!renderOk(&g, &st, "UNDERSANDED  DOCK")) return false;
    return true;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    _ = argc;
    _ = argv;
    report("percentiles_nearest_rank", tPercentiles());
    report("format_pinned_shape", tFormatShape());
    report("ticks_to_ms_and_sort", tTicksAndSort());
    report("sample_cap", tCap());
    report("key_filter_parity", tKeyFilterParity());
    report("scripted_walk_dock_map_node_fight_settle_dock", tWalk());

    if (fails != 0) {
        io.write("perf_test FAIL\n");
        os.exit(1);
        return;
    }
    io.write("perf_test PASS\n");
}
