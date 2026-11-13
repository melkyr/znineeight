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
const io = @import("std_io.zig");
const os = @import("std_os.zig");
const debug = @import("std_debug.zig");
const arena_mod = @import("std_arena.zig");
const buf_mod = @import("std_buf.zig");
const file_mod = @import("std_file.zig");
const paths = @import("paths.zig");

const PATH_MAX: usize = 512;
const ARENA_SIZE: usize = 64 * 1024;
const BT_CAP: usize = 4096;
const LINE: []const u8 = "UNDERSANDED M1: skeleton OK";

var g_arena_buf: [ARENA_SIZE]u8 = undefined;
var g_arena: arena_mod.Arena = undefined;
var g_bt_buf: buf_mod.Buf = undefined;
var g_crash_dmp: [PATH_MAX]u8 = undefined;
var g_crash_dmp_len: usize = 0;
var g_crash_log: [PATH_MAX]u8 = undefined;
var g_crash_log_len: usize = 0;

fn joinPath(dir: []const u8, name: []const u8, out: []u8) ?[]u8 {
    var sep: u8 = '/';
    if (@isWindows()) sep = '\\';

    var add_sep = false;
    if (dir.len > 0) {
        const last = dir[dir.len - 1];
        if (last != '\\' and last != '/') add_sep = true;
    }

    var need: usize = dir.len + name.len;
    if (add_sep) need += 1;
    if (need > out.len) return null;

    var o: usize = 0;
    var i: usize = 0;
    while (i < dir.len) : (i += 1) {
        out[o] = dir[i];
        o += 1;
    }
    if (add_sep) {
        out[o] = sep;
        o += 1;
    }
    i = 0;
    while (i < name.len) : (i += 1) {
        out[o] = name[i];
        o += 1;
    }
    return out[0..need];
}

fn putPath(dst: []u8, src: []const u8) usize {
    var n: usize = src.len;
    if (n > dst.len) n = dst.len;
    var i: usize = 0;
    while (i < n) : (i += 1) dst[i] = src[i];
    return n;
}

// Fatal trap handler. Everything it touches is pre-allocated at startup:
// the arena/Buf for crash.log and the crash.* path strings. No allocation and
// no path resolution happen here (spec §33).
fn onTrap(ctx: *debug.TrapContext) void {
    debug.writeCoreDump(ctx, g_crash_dmp[0..g_crash_dmp_len]) catch {};
    buf_mod.clear(&g_bt_buf);
    debug.backtrace(ctx, &g_bt_buf) catch {};
    file_mod.writeAll(g_crash_log[0..g_crash_log_len], buf_mod.slice(&g_bt_buf)) catch {};

    var msg: []const u8 = "UNDERSANDED: fatal trap; crash files written\n";
    @stderrWrite(msg.ptr, msg.len);
}

fn installTrap(writable_dir: []const u8) void {
    g_arena = arena_mod.init(g_arena_buf[0..]);
    g_bt_buf = buf_mod.initCapacity(&g_arena, BT_CAP) catch buf_mod.init(&g_arena);

    if (joinPath(writable_dir, "crash.dmp", g_crash_dmp[0..])) |p| {
        g_crash_dmp_len = p.len;
    }
    if (joinPath(writable_dir, "crash.log", g_crash_log[0..])) |p| {
        g_crash_log_len = p.len;
    }
    debug.setTrapHandler(onTrap);
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

    var sample_buf: [PATH_MAX]u8 = undefined;
    const sample_path = joinPath(exe_dir, "sample.txt", sample_buf[0..]) orelse {
        fail(console_mode, "UNDERSANDED: sample path too long");
        return;
    };
    const sample = file_mod.readAll(&g_arena, sample_path) catch {
        fail(console_mode, "UNDERSANDED: sample.txt missing beside the exe");
        return;
    };

    var out_buf: [PATH_MAX]u8 = undefined;
    const out_path = joinPath(writable_dir, "probe_out.txt", out_buf[0..]) orelse {
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
}
