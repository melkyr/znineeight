// app.zig — UNDERSANDED M1 shared skeleton (spec §26/§32/§33, G15 scaffold).
//
// One implementation, two thin entries:
//   main.zig          GUI   (WINDOWS_GUI, gfxOpen window titled UNDERSANDED)
//   main_console.zig  CUI   (WINDOWS_CUI, gfxOpenMemory + stdout, no window)
//
// The skeleton proves the platform plumbing before any game code exists:
//   * init args/env
//   * install the trap handler with a PRE-ALLOCATED backtrace buffer
//     (no allocation inside the handler, spec §33)
//   * resolve the exe dir and the writable data dir (paths.zig)
//   * read sample.txt from the exe dir (installed content, spec §32)
//   * write probe_out.txt into the writable dir
//   * draw one line of text on the given surface
//   * exit 0
//
// Direct imports only (no std barrel): the compile graph stays small.

const gfx = @import("std_gfx.zig");
const gfx_px = @import("std_gfx_px.zig");
const io = @import("std_io.zig");
const os = @import("std_os.zig");
const debug = @import("std_debug.zig");
const arena_mod = @import("std_arena.zig");
const buf_mod = @import("std_buf.zig");
const file_mod = @import("std_file.zig");
const paths = @import("paths.zig");
const def = @import("def.zig");
const data = @import("data.zig");
const content_boot = @import("content_boot.zig");
const game = @import("game.zig");
const nav = @import("nav.zig");
const loop_gfx = @import("loop_gfx.zig");
const persist = @import("persist.zig");

const PATH_MAX: usize = 512;
const ARENA_SIZE: usize = 256 * 1024;
const BT_CAP: usize = 4096;
const LINE: []const u8 = "UNDERSANDED M1: skeleton OK";

var g_arena_buf: [ARENA_SIZE]u8 = undefined;
var g_arena: arena_mod.Arena = undefined;
var g_bt_buf: buf_mod.Buf = undefined;
var g_crash_dmp: [PATH_MAX]u8 = undefined;
var g_crash_dmp_len: usize = 0;
var g_crash_log: [PATH_MAX]u8 = undefined;
var g_crash_log_len: usize = 0;

// Fatal trap handler. Everything it touches is pre-allocated at startup:
// the arena/Buf for crash.log and the crash.* path strings. No allocation and
// no path resolution happen here (spec §33).
fn onTrap(ctx: *debug.TrapContext) void {
    debug.writeCoreDump(ctx, g_crash_dmp[0..g_crash_dmp_len]) catch {};
    buf_mod.clear(&g_bt_buf);
    debug.backtraceLimited(ctx, &g_bt_buf, 1024) catch {};
    file_mod.writeAll(g_crash_log[0..g_crash_log_len], buf_mod.slice(&g_bt_buf)) catch {};

    var msg: []const u8 = "UNDERSANDED: fatal trap; crash files written\n";
    @stderrWrite(msg.ptr, msg.len);
}

fn installTrap(writable_dir: []const u8) void {
    g_arena = arena_mod.init(g_arena_buf[0..]);
    g_bt_buf = buf_mod.initCapacity(&g_arena, BT_CAP) catch buf_mod.init(&g_arena);

    if (paths.join(writable_dir, "crash.dmp", g_crash_dmp[0..])) |p| {
        g_crash_dmp_len = p.len;
    }
    if (paths.join(writable_dir, "crash.log", g_crash_log[0..])) |p| {
        g_crash_log_len = p.len;
    }
    debug.setTrapHandler(onTrap);
}

fn hasArg(name: []const u8) bool {
    const nargs = os.argc();
    var i: usize = 1;
    while (i < nargs) : (i += 1) {
        const a = os.argv(i);
        if (a.len != name.len) continue;
        var same = true;
        var k: usize = 0;
        while (k < a.len) : (k += 1) {
            if (a[k] != name[k]) {
                same = false;
                break;
            }
        }
        if (same) return true;
    }
    return false;
}

fn fail(console_mode: bool, msg: []const u8) void {
    @stderrWrite(msg.ptr, msg.len);
    @stderrWrite("\n", 1);
    if (console_mode) {
        io.write(msg);
        io.write("\n");
    }
    os.exit(1);
}

pub fn run(g: *gfx.Gfx, argc: i32, argv: [*][*]u8, console_mode: bool) void {
    runMode(g, argc, argv, console_mode, false);
}

// Console entry: same init/probe path as `run`, then the playable text fight
// instead of the M1 skeleton surface. The GUI entry stays on `run`.
pub fn runConsoleFight(g: *gfx.Gfx, argc: i32, argv: [*][*]u8) void {
    runMode(g, argc, argv, true, true);
}

fn runMode(g: *gfx.Gfx, argc: i32, argv: [*][*]u8, console_mode: bool, fight_mode: bool) void {
    os.initArgs(argc, argv);

    // Exe dir = installed content (sample.txt). Writability is probed on the
    // exe dir; the writable dir is the exe dir when writable, else the temp
    // fallback (paths.dataDirOrFallback).
    var exe_buf: [PATH_MAX]u8 = undefined;
    const exe_dir = paths.resolveDataDir(exe_buf[0..]);
    const exe_writable = paths.probeWritable(exe_dir);

    var writable_buf: [PATH_MAX]u8 = undefined;
    const writable_dir = paths.dataDirOrFallback(writable_buf[0..]);

    installTrap(writable_dir);

    const boot = content_boot.loadFromDir(&g_arena, &data.g_tables, exe_dir);
    switch (boot.result) {
        content_boot.BootResult.Loaded => {},
        content_boot.BootResult.Missing => {
            content_boot.writeFailure(console_mode, def.MSG_MISSING);
            os.exit(1);
            return;
        },
        content_boot.BootResult.Damaged => {
            var msg_buf: [80]u8 = undefined;
            content_boot.writeFailure(console_mode, content_boot.damagedText(boot.line, msg_buf[0..]));
            os.exit(1);
            return;
        },
        else => {},
    }

    var sample_buf: [PATH_MAX]u8 = undefined;
    const sample_path = paths.join(exe_dir, "sample.txt", sample_buf[0..]) orelse {
        fail(console_mode, "UNDERSANDED: sample path too long");
        return;
    };
    const sample = file_mod.readAll(&g_arena, sample_path) catch {
        fail(console_mode, "UNDERSANDED: sample.txt missing beside the exe");
        return;
    };

    var out_buf: [PATH_MAX]u8 = undefined;
    const out_path = paths.join(writable_dir, "probe_out.txt", out_buf[0..]) orelse {
        fail(console_mode, "UNDERSANDED: probe_out path too long");
        return;
    };
    file_mod.writeAll(out_path, sample) catch {
        fail(console_mode, "UNDERSANDED: probe_out.txt write failed");
        return;
    };

    _ = gfx.gfxBeginFrame(g);
    gfx.gfxClear(g, 0);
    gfx.gfxDrawText(g, 0, 0, LINE, 15, 0);
    _ = gfx.gfxEndFrame(g);

    if (console_mode) {
        io.write("UNDERSANDED console mode (gfxOpenMemory, no window)\n");
        io.write("exe_dir=");
        io.write(exe_dir);
        if (exe_writable) {
            io.write(" (writable)\n");
        } else {
            io.write(" (read-only)\n");
        }
        io.write("writable_dir=");
        io.write(writable_dir);
        io.write("\nprobe_out=");
        io.write(out_path);
        io.write("\nsurface: ");
        io.write(LINE);
        io.write("\nsample: ");
        io.write(sample);
    }

    if (fight_mode) {
        var s: def.GameState = undefined;
        game.newGame(&s);
        nav.navRun(&s);
        return;
    }

    if (!console_mode) {
        // GUI: one window for the session. px attach is attempted once; null
        // (or a <16bpp refusal inside attach) means every screen stays cell.
        const perf_on = hasArg("--perf");
        if (perf_on) loop_gfx.perfReset();

        var s: def.GameState = undefined;
        var p: ?*gfx_px.Gfx = gfx_px.gfxPxAttach(g);
        if (p == null) {
            persist.logError(writable_dir, "px: attach unavailable; cell fallback");
        }
        const reached = loop_gfx.bootGfx(g, &s, writable_dir, perf_on);
        if (reached) loop_gfx.navRunGfx(&s, p, perf_on);

        if (perf_on) {
            const line = loop_gfx.perfLine();
            if (line.len > 0) persist.logError(writable_dir, line);
        }
        if (p) |pp| gfx_px.gfxPxClose(pp);
        return;
    }

    var s: def.GameState = undefined;
    if (nav.boot(&s, writable_dir)) nav.navRun(&s);
}
