// main.zig — z9dbg session and command loop (P3-M2/M3).
//
// Session model (spec §7.4): `z9dbg <exe> [args…]` spawns the debuggee through
// the backend, loads the map next to the executable, resolves the entry
// function's first executable mapped source line through the debuggee's DWARF
// line table, and stops there. M3 installs the Linux ptrace backend; the M2
// headless harness still drives runSession with a stub/mock backend and gets
// the same scripted UX (live = false).
//
// Commands: break <file>:<line>, continue, step, backtrace,
//           dump variables [path], quit. There is no `run` command.

const std = @import("std");
const os = @import("std_os");
const file_mod = @import("std_file");
const stdin_mod = @import("std_stdin");
const map_reader = @import("map_reader.zig");
const dbg_core = @import("dbg_core.zig");
const backend = @import("backend.zig");
const backend_select = @import("backend_select.zig");
const dwarf = @import("dwarf_lines.zig");
const pe_debug = @import("pe_debug.zig");

// std_io writes through C stdio (fwrite), so z9dbg must flush before every
// resume: otherwise the debuggee's inherited/reopened stdout can appear ahead
// of the already-printed stop display, and the forked child inherits any
// pending parent buffer. fflush(NULL) flushes every output stream.
extern "c" fn fflush(stream: *void) i32;

fn flushOut() void {
    // The Win9x no-CRT shim has no fflush; its fwrite path is unbuffered.
    if (!@isWindows()) {
        _ = fflush(@ptrCast(*void, @intToPtr(*void, 0)));
    }
}

const SUFFIX_SYMS: []const u8 = ".z98dbg.syms";
const SUFFIX_SYMS_LEN: usize = 12;

// Fix F5 caps. Observed worst case in the test set / self-host maps: 215
// emitted C lines for one Z98 source line (z9torr), each with a few DWARF
// addresses. 4096 addresses per line and 65536 machine breakpoints (256 source
// lines x 256 addresses) hold the "int3 at every address" binding with a wide
// margin. Memory: main's g_bp is ~1 MiB BSS, the backend table ~512 KiB BSS;
// untouched pages do not count toward RSS.
const MAX_ADDRS: usize = 4096;
const MAX_MACHINE_BREAKS: usize = 65536;
// One source line can have many emitted-line runs; 1024 covers the observed
// maximum (215) with margin. Overflow is reported, not indexed past (F4).
const MAX_SPANS: usize = 1024;
const MAX_FRAMES: usize = 16;

var g_arena_buf: [16777216]u8 = undefined;

// Live-session state shared with runSession. The M2 headless tests call
// runSession directly without setting these; g_has_di = false keeps every live
// path dormant for the stub/mock backends.
var g_di: dwarf.DebugInfo = undefined;
var g_has_di: bool = false;
var g_reader: *map_reader.MapReader = undefined;
var g_entry_t0_us: u64 = 0;
var g_entry_timing: bool = false;

const BreakAddr = struct {
    addr: u32,
    src_file: []const u8,
    src_line: u32,
};

var g_bp: [MAX_MACHINE_BREAKS]BreakAddr = undefined;
var g_bp_n: usize = 0;

fn openMap(arena: *std.arena.Arena, prefix: []const u8) ?map_reader.MapReader {
    return map_reader.open(arena, prefix) catch return null;
}

fn openDebug(arena: *std.arena.Arena, exe: []const u8) ?dwarf.DebugInfo {
    var f = file_mod.open(arena, exe, file_mod.Mode.Read) catch return null;
    var magic: [4]u8 = undefined;
    var got = file_mod.read(&f, magic[0..]) catch {
        file_mod.close(&f);
        return null;
    };
    file_mod.close(&f);
    if (got >= 4 and magic[0] == 0x7f and magic[1] == 'E' and magic[2] == 'L' and magic[3] == 'F') {
        return dwarf.open(arena, exe) catch return null;
    }
    if (got >= 2 and magic[0] == 'M' and magic[1] == 'Z') {
        return pe_debug.open(arena, exe) catch return null;
    }
    return null;
}

pub fn defaultDumpPath(buf: []u8, counter: u32) []u8 {
    var n: usize = 0;
    var prefix: []const u8 = "z98-dump-";
    var i: usize = 0;
    while (i < prefix.len and n < buf.len) : (i += 1) {
        buf[n] = prefix[i];
        n += 1;
    }
    var tmp: [10]u8 = undefined;
    var tn: usize = 0;
    var v = counter;
    if (v == 0) {
        tmp[0] = '0';
        tn = 1;
    } else {
        while (v > 0) : (v = v / 10) {
            tmp[tn] = @intCast(u8, (v % 10) + 48);
            tn += 1;
        }
    }
    while (tn > 0) {
        tn -= 1;
        if (n < buf.len) {
            buf[n] = tmp[tn];
            n += 1;
        }
    }
    var ext: []const u8 = ".txt";
    i = 0;
    while (i < ext.len and n < buf.len) : (i += 1) {
        buf[n] = ext[i];
        n += 1;
    }
    return buf[0..n];
}

// Exact M2 stub text (headless harness expectations).
fn printBackendUnavailable() void {
    std.io.write("z9dbg: no live backend (M2)\n");
}

// Real live-backend failure (never claim the M2 stub is missing).
fn printBackendFailure() void {
    std.io.write("z9dbg: backend operation failed\n");
}

fn errStr(s: []const u8) void {
    @stderrWrite(s.ptr, s.len);
}

fn errU64(v: u64) void {
    var tmp: [20]u8 = undefined;
    var n: usize = 0;
    var x = v;
    if (x == 0) {
        tmp[0] = '0';
        n = 1;
    } else {
        while (x > 0) : (x = x / 10) {
            tmp[n] = @intCast(u8, (x % 10) + 48);
            n += 1;
        }
    }
    var out: [20]u8 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        out[i] = tmp[n - 1 - i];
    }
    @stderrWrite(&out[0], n);
}

// Monotonic high-resolution microseconds (fix round 1 latency method).
fn nowUs() u64 {
    var f = std.time.highResFreq();
    var h = std.time.highRes();
    if (f == 0) return @intCast(u64, std.time.ticksMs()) *% 1000;
    if (f >= 1000000) return h / (f / 1000000);
    return (h *% 1000000) / f;
}

fn parseU32(s: []const u8, out: *u32) bool {
    if (s.len == 0) return false;
    var v: u64 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] < '0' or s[i] > '9') return false;
        v = v * 10 + @intCast(u64, s[i] - '0');
        if (v > 4294967295) return false;
    }
    out.* = @intCast(u32, v);
    return true;
}

fn bpFind(addr: u32) ?usize {
    var i: usize = 0;
    while (i < g_bp_n) : (i += 1) {
        if (g_bp[i].addr == addr) return i;
    }
    return null;
}

fn bpAdd(addr: u32, src_file: []const u8, src_line: u32) void {
    if (bpFind(addr) != null) return;
    if (g_bp_n >= MAX_MACHINE_BREAKS) return;
    g_bp[g_bp_n] = BreakAddr{ .addr = addr, .src_file = src_file, .src_line = src_line };
    g_bp_n += 1;
}

fn bpClear() void {
    g_bp_n = 0;
}

fn cnameOf(reader: *map_reader.MapReader, name: []const u8) []const u8 {
    var c = map_reader.cnameFor(reader, name);
    if (c) |v| return v;
    return name;
}

fn functionEntryAddr(reader: *map_reader.MapReader, di: *dwarf.DebugInfo, function_name: []const u8) ?u32 {
    var cname = cnameOf(reader, function_name);
    var a = dwarf.funcAddr(di, cname);
    if (a) |v| return v;
    return dwarf.funcAddr(di, function_name);
}

// All runtime addresses whose emitted C lines belong to the mapped source line.
fn resolveAddrsForLine(reader: *map_reader.MapReader, di: *dwarf.DebugInfo, file: []const u8, line: u32, out: []u32) usize {
    var spans: [MAX_SPANS]map_reader.LineSpan = undefined;
    var overflow = false;
    var ns = map_reader.lineSpansAt(reader, file, line, spans[0..], &overflow);
    if (overflow) {
        errStr("z9dbg: source line maps to more than the span cap; breakpoint may be incomplete\n");
    }
    var n: usize = 0;
    var si: usize = 0;
    while (si < ns) : (si += 1) {
        var sp = spans[si];
        var ln = sp.out_start;
        var end = sp.out_start +% sp.out_count;
        var guard: u32 = 0;
        while (ln < end and guard < 4096) : (guard += 1) {
            if (n >= out.len) return n;
            n += dwarf.addrForLine(di, sp.out_file, ln, out[n..]);
            ln += 1;
        }
    }
    return n;
}

// Snap a mapped source line to the nearest line at/after it that has a machine
// address, stopping at the next function declaration (spec §7.4).
fn resolveBreakTarget(reader: *map_reader.MapReader, di: *dwarf.DebugInfo, file: []const u8, line: u32, out: []u32, count: *usize) ?u32 {
    var target = line;
    var iter: u32 = 0;
    while (iter < 256) : (iter += 1) {
        var n = resolveAddrsForLine(reader, di, file, target, out);
        if (n > 0) {
            count.* = n;
            return target;
        }
        var next_opt = map_reader.nextMappedLine(reader, file, target + 1);
        var next: u32 = 0;
        if (next_opt) |v| {
            next = v;
        } else {
            return null;
        }
        var nf_opt = dbg_core.nextFunctionLine(reader, file, target);
        if (nf_opt) |nf| {
            if (next >= nf) return null;
        }
        target = next;
    }
    return null;
}

fn liveResolve(state: *void, eip: u32, out: *dbg_core.StopState) bool {
    _ = state;
    if (!g_has_di) return false;
    var row = dwarf.rowForAddr(&g_di, eip) orelse return false;
    var fname = dwarf.rowFileName(&g_di, row);
    var lr = map_reader.reverseNearestAt(g_reader, fname, row.line) orelse return false;
    var fn_name: []const u8 = "??";
    var sym = map_reader.symbolAt(g_reader, lr.src_file, lr.src_line);
    if (sym) |s| fn_name = s.src_name;
    out.* = dbg_core.StopState{ .src_file = lr.src_file, .src_line = lr.src_line, .function_name = fn_name };
    return true;
}

fn sourceForEip(reader: *map_reader.MapReader, eip: u32, out: *dbg_core.StopState) bool {
    if (!g_has_di) return false;
    var row = dwarf.rowForAddr(&g_di, eip) orelse return false;
    var fname = dwarf.rowFileName(&g_di, row);
    var lr = map_reader.reverseNearestAt(reader, fname, row.line) orelse return false;
    var fn_name: []const u8 = "??";
    var sym = map_reader.symbolAt(reader, lr.src_file, lr.src_line);
    if (sym) |s| fn_name = s.src_name;
    out.* = dbg_core.StopState{ .src_file = lr.src_file, .src_line = lr.src_line, .function_name = fn_name };
    return true;
}

fn plantMachine(be: *backend.Backend, reader: *map_reader.MapReader, addrs: []const u32, n: usize, file: []const u8, line: u32) void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (i >= addrs.len) return;
        bpAdd(addrs[i], file, line);
        be.plant_fn(be.state, addrs[i]) catch {};
    }
}

// M3 break handler. The M2 path (live = false) is byte-identical to the
// headless harness expectations.
fn handleBreak(line: []const u8, reader: *map_reader.MapReader, table: *dbg_core.BreakTable, arena: *std.arena.Arena, stopped: bool, be: *backend.Backend) void {
    if (!stopped) {
        std.io.write("break: only valid while stopped\n");
        return;
    }
    if (line.len <= 6) {
        std.io.write("break: expected <file>:<line>\n");
        return;
    }
    var rest = line[6..];
    var colon = std.str.lastIndexOf(rest, ":") orelse {
        std.io.write("break: expected <file>:<line>\n");
        return;
    };
    if (colon == 0 or colon + 1 >= rest.len) {
        std.io.write("break: expected <file>:<line>\n");
        return;
    }
    var file = rest[0..colon];
    var num_s = rest[colon + 1 ..];
    var n: u32 = 0;
    if (!parseU32(num_s, &n)) {
        std.io.write("break: expected <file>:<line>\n");
        return;
    }
    var res = dbg_core.requestBreak(reader, table, arena, file, n);
    if (!be.live) {
        dbg_core.printBreakResult(res);
        return;
    }
    if (res.outcome == .table_full) {
        dbg_core.printBreakResult(res);
        return;
    }
    if (res.outcome == .no_code) {
        dbg_core.printBreakResult(res);
        return;
    }
    if (!g_has_di) {
        var sym = map_reader.symbolAt(reader, res.src_file, res.line) orelse {
            dbg_core.breakTableRemove(table, res.src_file, res.line);
            std.io.write("break: cannot resolve function entry for line ");
            std.io.printInt(@intCast(i32, n));
            std.io.write("\n");
            return;
        };
        var addr_opt = functionEntryAddr(reader, &g_di, sym.src_name);
        var addr: u32 = 0;
        if (addr_opt) |a| {
            addr = a;
        } else {
            dbg_core.breakTableRemove(table, res.src_file, res.line);
            std.io.write("break: cannot resolve function entry for line ");
            std.io.printInt(@intCast(i32, n));
            std.io.write("\n");
            return;
        }
        std.io.write("break: no debug info\n");
        var one: [1]u32 = undefined;
        one[0] = addr;
        plantMachine(be, reader, one[0..], 1, sym.src_file, sym.src_line);
        return;
    }

    var addrs: [MAX_ADDRS]u32 = undefined;
    var naddr: usize = 0;
    var target_opt = resolveBreakTarget(reader, &g_di, res.src_file, res.line, addrs[0..], &naddr);
    if (target_opt == null or naddr == 0) {
        std.io.write("break: no executable code at line ");
        std.io.printInt(@intCast(i32, res.line));
        std.io.write("\n");
        return;
    }
    var target: u32 = 0;
    if (target_opt) |t| target = t;

    if (res.outcome == .moved) {
        std.io.write("break: moved to line ");
        std.io.printInt(@intCast(i32, target));
        std.io.write("\n");
        if (target != res.line) dbg_core.breakTableForceAdd(table, res.src_file, target);
    } else if (res.outcome == .duplicate and target == res.line) {
        std.io.write("break: already set at line ");
        std.io.printInt(@intCast(i32, target));
        std.io.write("\n");
    } else if (target != res.line) {
        std.io.write("break: moved to line ");
        std.io.printInt(@intCast(i32, target));
        std.io.write("\n");
        dbg_core.breakTableForceAdd(table, res.src_file, target);
    } else {
        std.io.write("break: set at line ");
        std.io.printInt(@intCast(i32, target));
        std.io.write("\n");
    }
    plantMachine(be, reader, addrs[0..], naddr, res.src_file, target);
}

fn sameSourceLine(idx: usize, file: []const u8, line: u32) bool {
    return std.str.eql(g_bp[idx].src_file, file) and g_bp[idx].src_line == line;
}

fn stopFromBp(reader: *map_reader.MapReader, idx: usize) dbg_core.StopState {
    var st = dbg_core.StopState{ .src_file = g_bp[idx].src_file, .src_line = g_bp[idx].src_line, .function_name = "??" };
    var sym = map_reader.symbolAt(reader, st.src_file, st.src_line);
    if (sym) |s| st.function_name = s.src_name;
    return st;
}

fn presentEvent(reader: *map_reader.MapReader, arena: *std.arena.Arena, ev: backend.StopEvent, out_stop: *dbg_core.StopState) bool {
    if (ev.reason == backend.STOP_EXITED) {
        std.io.write("z9dbg: debuggee exited\n");
        return false;
    }
    if (ev.reason == backend.STOP_SIGNALED_EXIT) {
        std.io.write("z9dbg: debuggee terminated by signal ");
        std.io.printInt(@intCast(i32, ev.signo));
        std.io.write("\n");
        return false;
    }
    var st: dbg_core.StopState = undefined;
    var have = false;
    if (ev.reason == backend.STOP_BREAKPOINT) {
        if (bpFind(ev.eip)) |idx| {
            st = stopFromBp(reader, idx);
            have = true;
        }
    }
    if (!have) {
        if (sourceForEip(reader, ev.eip, &st)) {
            have = true;
        }
    }
    if (!have) {
        if (ev.reason == backend.STOP_SIGNAL) {
            std.io.write("z9dbg: debuggee stopped by signal ");
            std.io.printInt(@intCast(i32, ev.signo));
            std.io.write("\n");
        } else {
            std.io.write("z9dbg: stopped at an unmapped address\n");
        }
        return false;
    }
    out_stop.* = st;
    dbg_core.printStop(reader, arena, st);
    return true;
}

// Resume handling for a hit source breakpoint. Every machine address mapped to
// a source line carries an int3, and those addresses can be consecutive
// instructions, so one SINGLESTEP can land on the next int3 of the *same*
// source line. Step (with all breakpoints restored to their original bytes)
// until the PC leaves the line, then reinsert everything except the current PC
// and CONT. Breakpoints disabled by the last wait are restored by restoreAll.
fn resumeAndShow(reader: *map_reader.MapReader, arena: *std.arena.Arena, be: *backend.Backend, out_stop: *dbg_core.StopState) bool {
    if (be.live) {
        flushOut();
        var regs: backend.Registers = undefined;
        var have_regs = true;
        be.getRegs_fn(be.state, &regs) catch {
            have_regs = false;
        };
        var at_idx: ?usize = null;
        if (have_regs) at_idx = bpFind(regs.eip);
        if (at_idx) |cur_idx| {
            var cur_file = g_bp[cur_idx].src_file;
            var cur_line = g_bp[cur_idx].src_line;
            be.restoreAll_fn(be.state);
            var cur_eip = regs.eip;
            var stepped_addr = regs.eip;
            var guard: u32 = 0;
            while (guard < 64) : (guard += 1) {
                stepped_addr = cur_eip;
                be.singleStep_fn(be.state) catch break;
                var sev = be.wait_fn(be.state) catch {
                    printBackendFailure();
                    return false;
                };
                if (sev.reason == backend.STOP_EXITED) {
                    std.io.write("z9dbg: debuggee exited\n");
                    return false;
                }
                if (sev.reason == backend.STOP_SIGNALED_EXIT) {
                    std.io.write("z9dbg: debuggee terminated by signal ");
                    std.io.printInt(@intCast(i32, sev.signo));
                    std.io.write("\n");
                    return false;
                }
                if (sev.reason == backend.STOP_SIGNAL and sev.signo != 5) {
                    std.io.write("z9dbg: debuggee stopped by signal ");
                    std.io.printInt(@intCast(i32, sev.signo));
                    std.io.write("\n");
                    return false;
                }
                var r2: backend.Registers = undefined;
                var r2_ok = true;
                be.getRegs_fn(be.state, &r2) catch {
                    r2_ok = false;
                };
                if (!r2_ok) break;
                cur_eip = r2.eip;
                if (bpFind(r2.eip)) |idx2| {
                    if (sameSourceLine(idx2, cur_file, cur_line)) continue;
                    be.installAllExcept_fn(be.state, r2.eip);
                    var st2 = stopFromBp(reader, idx2);
                    out_stop.* = st2;
                    dbg_core.printStop(reader, arena, st2);
                    return true;
                }
                // Keep stepping while the resolved line is still the line we
                // are leaving; its remaining int3 addresses may be a few
                // instructions ahead of the first hit.
                var tmp: dbg_core.StopState = undefined;
                if (sourceForEip(reader, r2.eip, &tmp)) {
                    if (std.str.eql(tmp.src_file, cur_file) and tmp.src_line == cur_line) continue;
                }
                break;
            }
            // F3: re-arm every breakpoint except the instruction we actually
            // stepped over. If the current PC is a different same-line
            // address it is re-armed here (rather than left disabled).
            be.installAllExcept_fn(be.state, stepped_addr);
        }
    }
    var timing = os.env("Z9DBG_TIMING") != null;
    var t0: u64 = 0;
    if (timing) t0 = nowUs();
    be.continue_fn(be.state) catch {
        printBackendFailure();
        return false;
    };
    var ev = be.wait_fn(be.state) catch {
        printBackendFailure();
        return false;
    };
    var shown = presentEvent(reader, arena, ev, out_stop);
    if (timing and shown) {
        var dt = nowUs() -% t0;
        errStr("z9dbg: breakpoint latency ");
        errU64(dt);
        errStr(" us\n");
    }
    return shown;
}

fn handleDump(arena: *std.arena.Arena, reader: *map_reader.MapReader, be: *backend.Backend, stop: *dbg_core.StopState, counter: *u32, path_opt: ?[]const u8) bool {
    var nbuf: [64]u8 = undefined;
    var path: []const u8 = undefined;
    if (path_opt) |p| {
        path = p;
    } else {
        path = defaultDumpPath(nbuf[0..], counter.*);
        counter.* += 1;
    }
    var regs: backend.Registers = undefined;
    var regs_ok = true;
    be.getRegs_fn(be.state, &regs) catch {
        regs_ok = false;
    };
    var frames: [MAX_FRAMES]dbg_core.DumpFrame = undefined;
    var unreliable = false;
    var no_cnames = false;
    var frame_n = collectFrames(reader, be, stop.*, frames[0..], &unreliable, &no_cnames);
    if (dbg_core.writeDumpFrames(reader, arena, stop.*, path, regs, regs_ok, frames[0..frame_n])) {
        std.io.write("dump: wrote ");
        std.io.write(path);
        std.io.write("\n");
    } else {
        std.io.write("dump: write failed\n");
    }
    if (be.live) {
        return resumeAndShow(reader, arena, be, stop);
    }
    be.continue_fn(be.state) catch {
        printBackendUnavailable();
        return false;
    };
    return false;
}

fn readU32Le(buf: []const u8, off: usize) u32 {
    var b0: u32 = @intCast(u32, buf[off]);
    var b1: u32 = @intCast(u32, buf[off + 1]);
    var b2: u32 = @intCast(u32, buf[off + 2]);
    var b3: u32 = @intCast(u32, buf[off + 3]);
    return b0 | (b1 << @intCast(u32, 8)) | (b2 << @intCast(u32, 16)) | (b3 << @intCast(u32, 24));
}

fn printFrame(depth: u32, name: []const u8, file: []const u8, line: u32, decl: bool) void {
    std.io.write("#");
    std.io.printInt(@intCast(i32, depth));
    std.io.write(" ");
    std.io.write(name);
    std.io.write(" at ");
    std.io.write(file);
    std.io.write(":");
    std.io.printInt(@intCast(i32, line));
    if (decl) std.io.write(" (decl)");
    std.io.write("\n");
}

// Shared backtrace/dump frame walk. Caller frames carry the function's map
// declaration line (decl = true); `unreliable` is set for the review's clearly
// broken chain cases, `no_cnames` when the optional map file is absent.
fn collectFrames(reader: *map_reader.MapReader, be: *backend.Backend, stop: dbg_core.StopState, frames: []dbg_core.DumpFrame, unreliable: *bool, no_cnames: *bool) usize {
    unreliable.* = false;
    no_cnames.* = false;
    frames[0] = dbg_core.DumpFrame{ .name = stop.function_name, .src_file = stop.src_file, .src_line = stop.src_line, .decl = false };
    if (!be.live) return 1;
    if (map_reader.cnameCount(reader) == 0) {
        no_cnames.* = true;
        return 1;
    }
    var regs: backend.Registers = undefined;
    be.getRegs_fn(be.state, &regs) catch {
        unreliable.* = true;
        return 1;
    };
    var ebp = regs.ebp;
    var n: usize = 1;
    while (n < frames.len) {
        var buf: [8]u8 = undefined;
        be.readMemory_fn(be.state, ebp, buf[0..]) catch {
            unreliable.* = true;
            break;
        };
        var prev = readU32Le(buf[0..], 0);
        var ret = readU32Le(buf[0..], 4);
        if (prev == 0 or prev <= ebp or ret == 0) {
            unreliable.* = true;
            break;
        }
        var f_opt = dwarf.funcByAddr(&g_di, ret - 1);
        var f: dwarf.Func = undefined;
        if (f_opt) |v| {
            f = v;
        } else {
            // Return address outside every STT_FUNC range: libc is normally
            // reached only through the emitted C `main` wrapper, which is an
            // STT_FUNC and is stopped at below. Anything else is corruption.
            unreliable.* = true;
            break;
        }
        var sname_opt = map_reader.srcNameForCname(reader, f.name);
        if (sname_opt == null) {
            // The plain C `main` wrapper is the ordinary end of the Z98 stack.
            if (std.str.eql(f.name, "main")) break;
            unreliable.* = true;
            break;
        }
        var sname: []const u8 = undefined;
        if (sname_opt) |v| {
            sname = v;
        } else {
            break;
        }
        var sym_opt = map_reader.functionByName(reader, sname);
        var sym: map_reader.Symbol = undefined;
        if (sym_opt) |v| {
            sym = v;
        } else {
            unreliable.* = true;
            break;
        }
        frames[n] = dbg_core.DumpFrame{ .name = sname, .src_file = sym.src_file, .src_line = sym.src_line, .decl = true };
        n += 1;
        ebp = prev;
    }
    return n;
}

fn handleBacktrace(reader: *map_reader.MapReader, be: *backend.Backend, stop: dbg_core.StopState) void {
    var frames: [MAX_FRAMES]dbg_core.DumpFrame = undefined;
    var unreliable = false;
    var no_cnames = false;
    var n = collectFrames(reader, be, stop, frames[0..], &unreliable, &no_cnames);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        printFrame(@intCast(u32, i), frames[i].name, frames[i].src_file, frames[i].src_line, frames[i].decl);
    }
    if (no_cnames) {
        std.io.write("backtrace limited: no .cnames\n");
    } else if (unreliable) {
        std.io.write("backtrace: frame chain unreliable; build with -fno-omit-frame-pointer\n");
    }
}

fn noResolve(state: *void, eip: u32, out: *dbg_core.StopState) bool {
    _ = state;
    _ = eip;
    _ = out;
    return false;
}

pub fn runSession(arena: *std.arena.Arena, reader: *map_reader.MapReader, be: *backend.Backend, start_in: dbg_core.StopState, resolve_state: *void, resolve_fn: dbg_core.ResolveFn) void {
    var start = start_in;
    std.io.write("Z98 debugger has started...\n");
    dbg_core.printStop(reader, arena, start);
    if (g_entry_timing) {
        var dt = nowUs() -% g_entry_t0_us;
        errStr("z9dbg: entry latency ");
        errU64(dt);
        errStr(" us\n");
        g_entry_timing = false;
    }
    var table = dbg_core.breakTableInit();
    var stopped = true;
    var counter: u32 = 1;
    g_bp_n = 0;
    var buf: [512]u8 = undefined;
    while (true) {
        std.io.write("(z9dbg) ");
        var got = stdin_mod.readLine(buf[0..]) catch return;
        var line: []const u8 = "";
        if (got) |g| {
            line = std.str.trim(g);
        } else {
            return;
        }
        if (line.len == 0) continue;
        if (std.str.eql(line, "quit")) {
            std.io.write("z9dbg: exiting\n");
            if (be.live) {
                flushOut();
                be.restoreAll_fn(be.state);
            }
            be.detach_fn(be.state) catch {};
            return;
        }
        if (std.str.startsWith(line, "break")) {
            if (std.str.eql(line, "break") or std.str.startsWith(line, "break ")) {
                handleBreak(line, reader, &table, arena, stopped, be);
            } else {
                std.io.write("unknown command: ");
                std.io.write(line);
                std.io.write("\n");
            }
            continue;
        }
        if (std.str.eql(line, "continue")) {
            if (be.live) {
                stopped = resumeAndShow(reader, arena, be, &start);
            } else {
                be.continue_fn(be.state) catch {
                    printBackendUnavailable();
                    continue;
                };
                stopped = false;
            }
            continue;
        }
        if (std.str.eql(line, "step")) {
            var out: dbg_core.StopState = start;
            if (be.live) {
                flushOut();
                be.restoreAll_fn(be.state);
            }
            var res = dbg_core.stepInto(reader, be, resolve_state, resolve_fn, start, 100000, &out);
            switch (res) {
                .stepped => {
                    start = out;
                    stopped = true;
                    if (be.live) {
                        var regs: backend.Registers = undefined;
                        var ok = true;
                        be.getRegs_fn(be.state, &regs) catch {
                            ok = false;
                        };
                        if (ok) be.installAllExcept_fn(be.state, regs.eip);
                    }
                    dbg_core.printStop(reader, arena, start);
                },
                .exited => {
                    std.io.write("z9dbg: debuggee exited\n");
                    stopped = false;
                },
                .signaled => {
                    std.io.write("z9dbg: debuggee terminated by signal while stepping\n");
                    stopped = false;
                },
                .unavailable => {
                    if (be.live) {
                        printBackendFailure();
                    } else {
                        printBackendUnavailable();
                    }
                },
                else => {
                    std.io.write("z9dbg: step limit reached\n");
                },
            }
            continue;
        }
        if (std.str.eql(line, "backtrace")) {
            handleBacktrace(reader, be, start);
            continue;
        }
        if (std.str.eql(line, "dump variables")) {
            if (handleDump(arena, reader, be, &start, &counter, null)) {
                stopped = true;
            } else {
                stopped = false;
            }
            continue;
        }
        if (std.str.startsWith(line, "dump variables ")) {
            var p = line[15..];
            if (handleDump(arena, reader, be, &start, &counter, p)) {
                stopped = true;
            } else {
                stopped = false;
            }
            continue;
        }
        if (std.str.startsWith(line, "dump")) {
            std.io.write("dump: expected variables [path]\n");
            continue;
        }
        std.io.write("unknown command: ");
        std.io.write(line);
        std.io.write("\n");
    }
}

fn dirnameOf(path: []const u8) []const u8 {
    var i = std.str.lastIndexOf(path, "/") orelse return ".";
    if (i == 0) return "/";
    return path[0..i];
}

fn appendParts(arena: *std.arena.Arena, a: []const u8, b: []const u8) ?[]u8 {
    var total = a.len + b.len;
    var raw = std.arena.alloc(arena, total) catch return null;
    var i: usize = 0;
    while (i < a.len) : (i += 1) raw[i] = a[i];
    var j: usize = 0;
    while (j < b.len) : (j += 1) raw[a.len + j] = b[j];
    return raw[0..total];
}

fn baseName(path: []const u8) []const u8 {
    var i: usize = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/') return path[i + 1 ..];
    }
    return path;
}

fn stemOf(path: []const u8) []const u8 {
    var name = baseName(path);
    var i: usize = name.len;
    while (i > 0) {
        i -= 1;
        if (name[i] == '.') return name[0..i];
    }
    return name;
}

const MapFind = struct {
    prefix: ?[]const u8,
    ambiguous: bool,
    count: u32,
};

// Map discovery (fix honest-minor 11): prefer the sidecar whose stem matches
// the executable stem, otherwise accept a single unambiguous sidecar. Multiple
// candidates with no match are reported as ambiguous instead of silently
// picking the last directory entry.
fn findMapPrefix(arena: *std.arena.Arena, exe: []const u8) MapFind {
    var dir = dirnameOf(exe);
    var d = file_mod.openDir(arena, dir) catch return MapFind{ .prefix = null, .ambiguous = false, .count = 0 };
    var cands: [8][]const u8 = undefined;
    var n: usize = 0;
    var total: u32 = 0;
    while (true) {
        var entry_opt = file_mod.readDir(arena, &d) catch {
            file_mod.closeDir(&d);
            return MapFind{ .prefix = null, .ambiguous = total > 1, .count = total };
        };
        var entry: file_mod.DirEntry = undefined;
        if (entry_opt) |e| {
            entry = e;
        } else {
            break;
        }
        if (entry.is_dir) continue;
        if (!std.str.endsWith(entry.name, SUFFIX_SYMS)) continue;
        total += 1;
        if (n >= 8) continue;
        var stem = entry.name[0 .. entry.name.len - SUFFIX_SYMS_LEN];
        var sep: []const u8 = "/";
        if (std.str.eql(dir, "/")) sep = "";
        var prefix = appendParts(arena, dir, sep) orelse continue;
        var full = appendParts(arena, prefix, stem) orelse continue;
        cands[n] = full;
        n += 1;
    }
    file_mod.closeDir(&d);
    if (total == 0) return MapFind{ .prefix = null, .ambiguous = false, .count = 0 };
    var want = stemOf(exe);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (std.str.eql(stemOf(cands[i]), want)) {
            return MapFind{ .prefix = cands[i], .ambiguous = false, .count = total };
        }
    }
    if (total == 1 and n >= 1) return MapFind{ .prefix = cands[0], .ambiguous = false, .count = 1 };
    return MapFind{ .prefix = null, .ambiguous = true, .count = total };
}

fn liveEntryStop(arena: *std.arena.Arena, reader: *map_reader.MapReader, be: *backend.Backend, start_in: dbg_core.StopState) bool {
    var start = start_in;
    var addrs: [MAX_ADDRS]u32 = undefined;
    var naddr: usize = 0;
    // Entry stop: use the first mapped line only if it has a machine address.
    // If it does not (hoisted declarations often own the first rows), fall
    // back to the entry function's symbol address instead of snapping forward
    // into the function body: a forward snap can land past an early exit
    // (hello/mud_server/lisp test-set shapes) and never trap.
    if (g_has_di) {
        naddr = resolveAddrsForLine(reader, &g_di, start.src_file, start.src_line, addrs[0..]);
    }
    if (naddr == 0) {
        var fa_opt = functionEntryAddr(reader, &g_di, start.function_name);
        if (fa_opt) |fa| {
            addrs[0] = fa;
            naddr = 1;
        } else {
            std.io.write("z9dbg: no executable entry address\n");
            return false;
        }
    }
    var i: usize = 0;
    while (i < naddr) : (i += 1) {
        be.plant_fn(be.state, addrs[i]) catch {};
    }
    var timing = os.env("Z9DBG_TIMING") != null;
    var t0: u64 = 0;
    if (timing) t0 = nowUs();
    flushOut();
    be.continue_fn(be.state) catch {
        std.io.write("z9dbg: cannot resume debuggee\n");
        return false;
    };
    var ev = be.wait_fn(be.state) catch {
        std.io.write("z9dbg: cannot wait for debuggee\n");
        return false;
    };
    i = 0;
    while (i < naddr) : (i += 1) {
        be.removeBreak_fn(be.state, addrs[i]);
    }
    if (ev.reason == backend.STOP_EXITED) {
        std.io.write("z9dbg: debuggee exited before entry stop\n");
        return false;
    }
    if (ev.reason == backend.STOP_SIGNALED_EXIT) {
        std.io.write("z9dbg: debuggee terminated by signal ");
        std.io.printInt(@intCast(i32, ev.signo));
        std.io.write(" before entry breakpoint\n");
        return false;
    }
    if (ev.reason == backend.STOP_SIGNAL) {
        std.io.write("z9dbg: debuggee stopped by signal ");
        std.io.printInt(@intCast(i32, ev.signo));
        std.io.write(" before entry breakpoint\n");
        return false;
    }
    if (ev.reason != backend.STOP_BREAKPOINT) {
        std.io.write("z9dbg: unexpected stop before entry breakpoint\n");
        return false;
    }
    var matched = false;
    i = 0;
    while (i < naddr) : (i += 1) {
        if (ev.eip == addrs[i]) matched = true;
    }
    if (!matched) {
        std.io.write("z9dbg: unexpected stop before entry breakpoint\n");
        return false;
    }
    g_entry_t0_us = t0;
    g_entry_timing = timing;
    runSessionLive(arena, reader, be, start);
    return true;
}

fn runSessionLive(arena: *std.arena.Arena, reader: *map_reader.MapReader, be: *backend.Backend, start: dbg_core.StopState) void {
    var no_state: *void = @intToPtr(*void, 0);
    runSession(arena, reader, be, start, no_state, liveResolve);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    os.initArgs(argc, argv);
    if (os.argc() < 2) {
        std.io.write("usage: z9dbg <exe> [args...]\n");
        os.exit(2);
    }
    var ar = std.arena.init(g_arena_buf[0..]);
    var exe = os.argv(1);
    var prefix: []const u8 = "";
    var mf = findMapPrefix(&ar, exe);
    if (mf.prefix) |p| {
        prefix = p;
    } else {
        if (mf.ambiguous) {
            std.io.write("z9dbg: ambiguous debug map: ");
            std.io.printInt(@intCast(i32, mf.count));
            std.io.write(" .z98dbg.syms candidates next to the executable\n");
        } else {
            std.io.write("z9dbg: no .z98dbg.syms next to the executable\n");
        }
        os.exit(1);
    }
    var reader_opt = openMap(&ar, prefix);
    var reader: map_reader.MapReader = undefined;
    if (reader_opt) |rr| {
        reader = rr;
    } else {
        std.io.write("z9dbg: cannot read the debug map\n");
        os.exit(1);
    }
    var start_opt = dbg_core.entryStop(&reader, &ar);
    var start: dbg_core.StopState = undefined;
    if (start_opt) |st| {
        start = st;
    } else {
        std.io.write("z9dbg: no executable entry line in the map\n");
        os.exit(1);
    }

    // Headless/diagnostic switch used by the M2 map-core gate: keep the
    // scripted stub session (no process launch). Normal M3 sessions are live.
    if (os.env("Z9DBG_STUB") != null) {
        var stub = backend.stubBackend();
        var stub_state: *void = @intToPtr(*void, 0);
        runSession(&ar, &reader, &stub, start, stub_state, noResolve);
        return;
    }

    var child_args: [64][]const u8 = undefined;
    var na: usize = 0;
    var ai: usize = 2;
    while (ai < os.argc() and na < 64) : (ai += 1) {
        child_args[na] = os.argv(ai);
        na += 1;
    }

    var be = backend_select.select();
    flushOut();
    be.launch_fn(be.state, exe, child_args[0..na]) catch {
        std.io.write("z9dbg: cannot launch ");
        std.io.write(exe);
        std.io.write("\n");
        os.exit(1);
    };

    var di: dwarf.DebugInfo = undefined;
    var di_opt = openDebug(&ar, exe);
    if (di_opt) |d| {
        di = d;
    } else {
        std.io.write("z9dbg: cannot read the debuggee ELF or PE image\n");
        be.detach_fn(be.state) catch {};
        os.exit(1);
    }
    g_di = di;
    g_has_di = g_di.has_line;
    if (g_di.e_type == 0) {
        // PE: rows/functions are link-time VAs; bias by the runtime image base.
        var runtime_base = be.imageBase_fn(be.state);
        if (runtime_base == 0) {
            g_di.base = 0;
            g_di.bias_unknown = true;
            errStr("z9dbg: cannot resolve PE runtime image base; breakpoint addresses may be wrong\n");
        } else {
            g_di.base = runtime_base -% g_di.image_base;
        }
    } else {
        var bias_ok = dwarf.setLoadBase(&g_di, exe, be.pid_fn(be.state));
        if (!bias_ok) {
            errStr("z9dbg: cannot resolve PIE load bias; breakpoint addresses may be wrong\n");
        }
    }
    if (!g_has_di and g_di.unsupported_version) {
        errStr("z9dbg: debug info present but unsupported DWARF version (only 2/3/4); using function-entry breakpoints\n");
    }
    g_reader = &reader;

    bpClear();
    if (!liveEntryStop(&ar, &reader, &be, start)) {
        be.detach_fn(be.state) catch {};
        os.exit(1);
    }
}
