// main.zig — z9dbg session and command loop (P3-M2).
//
// Session model (spec §7.4): `z9dbg <exe> [args…]` loads the map next to the
// executable and stops at the entry function's first mapped source line. M2
// has no live process backend yet (M3), so continue/step report that plainly;
// break/backtrace/dump and all UX strings are live and tested headlessly.
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

const SUFFIX_SYMS: []const u8 = ".z98dbg.syms";
const SUFFIX_SYMS_LEN: usize = 12;

var g_arena_buf: [4194304]u8 = undefined;

fn openMap(arena: *std.arena.Arena, prefix: []const u8) ?map_reader.MapReader {
    return map_reader.open(arena, prefix) catch return null;
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

fn printBackendUnavailable() void {
    std.io.write("z9dbg: no live backend (M2)\n");
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

fn handleBreak(line: []const u8, reader: *map_reader.MapReader, table: *dbg_core.BreakTable, arena: *std.arena.Arena, stopped: bool) void {
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
    dbg_core.printBreakResult(res);
}

fn handleDump(arena: *std.arena.Arena, reader: *map_reader.MapReader, be: *backend.Backend, stop: dbg_core.StopState, counter: *u32, path_opt: ?[]const u8) bool {
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
    if (dbg_core.writeDump(reader, arena, stop, path, regs, regs_ok)) {
        std.io.write("dump: wrote ");
        std.io.write(path);
        std.io.write("\n");
    } else {
        std.io.write("dump: write failed\n");
    }
    be.continue_fn(be.state) catch {
        printBackendUnavailable();
        return false;
    };
    return true;
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
    var table = dbg_core.breakTableInit();
    var stopped = true;
    var counter: u32 = 1;
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
            be.detach_fn(be.state) catch {};
            return;
        }
        if (std.str.startsWith(line, "break")) {
            if (std.str.eql(line, "break") or std.str.startsWith(line, "break ")) {
                handleBreak(line, reader, &table, arena, stopped);
            } else {
                std.io.write("unknown command: ");
                std.io.write(line);
                std.io.write("\n");
            }
            continue;
        }
        if (std.str.eql(line, "continue")) {
            be.continue_fn(be.state) catch {
                printBackendUnavailable();
                continue;
            };
            stopped = false;
            continue;
        }
        if (std.str.eql(line, "step")) {
            var out: dbg_core.StopState = start;
            var res = dbg_core.stepInto(reader, be, resolve_state, resolve_fn, start, 100000, &out);
            switch (res) {
                .stepped => {
                    start = out;
                    stopped = true;
                    dbg_core.printStop(reader, arena, start);
                },
                .exited => {
                    std.io.write("z9dbg: debuggee exited\n");
                    stopped = false;
                },
                .unavailable => {
                    printBackendUnavailable();
                },
                else => {
                    std.io.write("z9dbg: step limit reached\n");
                },
            }
            continue;
        }
        if (std.str.eql(line, "backtrace")) {
            std.io.write("#0 ");
            std.io.write(start.function_name);
            std.io.write(" at ");
            std.io.write(start.src_file);
            std.io.write(":");
            std.io.printInt(@intCast(i32, start.src_line));
            std.io.write("\n");
            continue;
        }
        if (std.str.eql(line, "dump variables")) {
            if (handleDump(arena, reader, be, start, &counter, null)) stopped = false;
            continue;
        }
        if (std.str.startsWith(line, "dump variables ")) {
            var p = line[15..];
            if (handleDump(arena, reader, be, start, &counter, p)) stopped = false;
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

fn findMapPrefix(arena: *std.arena.Arena, exe: []const u8) ?[]const u8 {
    var dir = dirnameOf(exe);
    var d = file_mod.openDir(arena, dir) catch return null;
    var found: ?[]const u8 = null;
    while (true) {
        var entry_opt = file_mod.readDir(arena, &d) catch {
            file_mod.closeDir(&d);
            return null;
        };
        var entry: file_mod.DirEntry = undefined;
        if (entry_opt) |e| {
            entry = e;
        } else {
            break;
        }
        if (entry.is_dir) continue;
        if (!std.str.endsWith(entry.name, SUFFIX_SYMS)) continue;
        var stem = entry.name[0 .. entry.name.len - SUFFIX_SYMS_LEN];
        var sep: []const u8 = "/";
        if (std.str.eql(dir, "/")) sep = "";
        var prefix = appendParts(arena, dir, sep) orelse {
            file_mod.closeDir(&d);
            return null;
        };
        var full = appendParts(arena, prefix, stem) orelse {
            file_mod.closeDir(&d);
            return null;
        };
        found = full;
    }
    file_mod.closeDir(&d);
    return found;
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
    var prefix_opt = findMapPrefix(&ar, exe);
    if (prefix_opt) |p| {
        prefix = p;
    } else {
        std.io.write("z9dbg: no .z98dbg.syms next to the executable\n");
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
    var be = backend.stubBackend();
    var no_state: *void = @intToPtr(*void, 0);
    runSession(&ar, &reader, &be, start, no_state, noResolve);
}
