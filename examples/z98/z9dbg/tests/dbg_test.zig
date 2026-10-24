// dbg_test.zig — headless P3-M2 harness for the z9dbg map reader and core.
//
// The live process backend is M3; this harness exercises only map parsing,
// breakpoint classification/snap, the source/stop display, the dump writer,
// and the scripted command loop (stdin -> stdout).

const std = @import("std");
const os = @import("std_os");
const map_reader = @import("../map_reader.zig");
const dbg_core = @import("../dbg_core.zig");
const dbg_main = @import("../main.zig");
const backend = @import("../backend.zig");

var g_arena_buf: [1048576]u8 = undefined;
var g_fail: u32 = 0;

fn write(s: []const u8) void {
    std.io.write(s);
}

fn writeLine(s: []const u8) void {
    std.io.write(s);
    std.io.write("\n");
}

fn ok(name: []const u8) void {
    write("ok - ");
    writeLine(name);
}

fn fail(name: []const u8) void {
    write("FAIL - ");
    writeLine(name);
    g_fail += 1;
}

fn expectStr(name: []const u8, got: []const u8, want: []const u8) void {
    if (std.str.eql(got, want)) {
        ok(name);
    } else {
        fail(name);
        write("  got: ");
        writeLine(got);
        write("  want: ");
        writeLine(want);
    }
}

fn expectU32(name: []const u8, got: u32, want: u32) void {
    if (got == want) {
        ok(name);
    } else {
        fail(name);
        write("  got: ");
        std.io.printInt(@intCast(i32, got));
        write(" want: ");
        std.io.printInt(@intCast(i32, want));
        write("\n");
    }
}

fn expectUsize(name: []const u8, got: usize, want: usize) void {
    expectU32(name, @intCast(u32, got), @intCast(u32, want));
}

fn expectTrue(name: []const u8, cond: bool) void {
    if (cond) {
        ok(name);
    } else {
        fail(name);
    }
}

fn modeMapHello(arena: *std.arena.Arena, prefix: []const u8) void {
    var r = map_reader.open(arena, prefix) catch {
        fail("hello open");
        return;
    };
    expectUsize("hello symbol count 3", map_reader.symbolCount(&r), 3);
    expectUsize("hello group count 1", map_reader.groupCount(&r), 1);
    expectUsize("hello line run count 6", map_reader.lineRunCount(&r), 6);
    expectUsize("hello cname count 3", map_reader.cnameCount(&r), 3);

    var resolved = map_reader.resolveFile(&r, "main.zig");
    if (resolved) |f| {
        expectStr("hello resolveFile basename", f, "examples/z98/z9dbg/tests/fixtures/hello/main.zig");
    } else {
        fail("hello resolveFile basename");
    }
    var resolved2 = map_reader.resolveFile(&r, "fixtures/hello/main.zig");
    if (resolved2) |f2| {
        expectStr("hello resolveFile suffix", f2, "examples/z98/z9dbg/tests/fixtures/hello/main.zig");
    } else {
        fail("hello resolveFile suffix");
    }

    var main_sym = map_reader.symbolAt(&r, "main.zig", 14);
    if (main_sym) |s| {
        expectStr("hello symbolAt main name", s.src_name, "main");
        expectU32("hello symbolAt main line", s.src_line, 13);
    } else {
        fail("hello symbolAt main");
    }
    var add_sym = map_reader.symbolAt(&r, "main.zig", 9);
    if (add_sym) |s2| {
        expectStr("hello symbolAt addOne name", s2.src_name, "addOne");
        expectU32("hello symbolAt addOne line", s2.src_line, 8);
    } else {
        fail("hello symbolAt addOne");
    }
    expectTrue("hello symbolAt before first null", map_reader.symbolAt(&r, "main.zig", 0) == null);

    var row14 = map_reader.lineAt(&r, "main.zig", 14);
    if (row14) |row| {
        expectU32("hello lineAt 14 out line", row.out_line, 21);
        expectStr("hello lineAt 14 out file", row.out_file, "main_BDA8D6C7.c");
        expectU32("hello lineAt 14 src line", row.src_line, 14);
    } else {
        fail("hello lineAt 14");
    }
    var row14b = map_reader.lineAt(&r, "fixtures/hello/main.zig", 14);
    expectTrue("hello lineAt basename", row14b != null);

    var rows: [8]map_reader.LineRow = undefined;
    var n16 = map_reader.lineRowsAt(&r, "main.zig", 16, rows[0..]);
    expectUsize("hello lineRowsAt 16 count", n16, 2);
    if (n16 == 2) {
        expectU32("hello lineRowsAt 16 row0", rows[0].out_line, 25);
        expectU32("hello lineRowsAt 16 row1", rows[1].out_line, 28);
    } else {
        fail("hello lineRowsAt 16 rows");
    }

    var rev = map_reader.reverseRowAt(&r, "main_BDA8D6C7.c", 28);
    if (rev) |rv| {
        expectU32("hello reverseRowAt 28 src line", rv.src_line, 16);
        expectU32("hello reverseRowAt 28 out line", rv.out_line, 28);
    } else {
        fail("hello reverseRowAt 28");
    }

    expectTrue("hello lineAt absent null", map_reader.lineAt(&r, "main.zig", 3) == null);

    var cn = map_reader.cnameFor(&r, "main");
    if (cn) |c| {
        expectStr("hello cname main", c, "zF_EA90E208_main");
    } else {
        fail("hello cname main");
    }
    var cng = map_reader.cnameFor(&r, "counter_value");
    if (cng) |cg| {
        expectStr("hello cname global", cg, "zG_43B300ED_counter_value");
    } else {
        fail("hello cname global");
    }

    var start = dbg_core.entryStop(&r, arena);
    if (start) |st| {
        expectU32("hello entryStop line", st.src_line, 14);
        expectStr("hello entryStop function", st.function_name, "main");
    } else {
        fail("hello entryStop");
    }

    var nbuf: [32]u8 = undefined;
    var default_name = dbg_main.defaultDumpPath(nbuf[0..], 1);
    expectStr("hello default dump name", default_name, "z98-dump-1.txt");

    var row1 = map_reader.lineAt(&r, "main.zig", 1);
    expectTrue("hello global init line 1 mapped", row1 != null);
}

fn modeMapFib(arena: *std.arena.Arena, prefix: []const u8) void {
    var r = map_reader.open(arena, prefix) catch {
        fail("fib open");
        return;
    };
    expectUsize("fib symbol count 2", map_reader.symbolCount(&r), 2);
    expectUsize("fib group count 1", map_reader.groupCount(&r), 1);
    expectUsize("fib line run count 6", map_reader.lineRunCount(&r), 6);
    expectUsize("fib cname count 2", map_reader.cnameCount(&r), 2);

    var rows: [8]map_reader.LineRow = undefined;
    var n2 = map_reader.lineRowsAt(&r, "main.zig", 2, rows[0..]);
    expectUsize("fib lineRowsAt 2 count", n2, 2);
    if (n2 == 2) {
        expectU32("fib lineRowsAt 2 row0", rows[0].out_line, 4);
        expectU32("fib lineRowsAt 2 row1", rows[1].out_line, 25);
    } else {
        fail("fib lineRowsAt 2 rows");
    }
    var rev = map_reader.reverseRowAt(&r, "main_4DFBF9C3.c", 25);
    if (rev) |rv| {
        expectU32("fib reverseRowAt 25 src line", rv.src_line, 2);
    } else {
        fail("fib reverseRowAt 25");
    }
    var sym = map_reader.symbolAt(&r, "main.zig", 7);
    if (sym) |s| {
        expectStr("fib symbolAt main name", s.src_name, "main");
        expectU32("fib symbolAt main line", s.src_line, 6);
    } else {
        fail("fib symbolAt main");
    }
    var start = dbg_core.entryStop(&r, arena);
    if (start) |st| {
        expectU32("fib entryStop line", st.src_line, 7);
        expectStr("fib entryStop function", st.function_name, "main");
    } else {
        fail("fib entryStop");
    }
}

fn snapCase(r: *map_reader.MapReader, table: *dbg_core.BreakTable, arena: *std.arena.Arena, file: []const u8, line: u32) void {
    write("break ");
    write(file);
    write(":");
    std.io.printInt(@intCast(i32, line));
    write(" -> ");
    var res = dbg_core.requestBreak(r, table, arena, file, line);
    dbg_core.printBreakResult(res);
}

fn modeSnap(arena: *std.arena.Arena, prefix: []const u8) void {
    var r = map_reader.open(arena, prefix) catch {
        fail("snap open");
        return;
    };
    var table = dbg_core.breakTableInit();
    snapCase(&r, &table, arena, "main.zig", 1);
    snapCase(&r, &table, arena, "main.zig", 2);
    snapCase(&r, &table, arena, "main.zig", 4);
    snapCase(&r, &table, arena, "main.zig", 7);
    snapCase(&r, &table, arena, "main.zig", 11);
    snapCase(&r, &table, arena, "main.zig", 15);
    snapCase(&r, &table, arena, "main.zig", 17);
    snapCase(&r, &table, arena, "main.zig", 13);
    snapCase(&r, &table, arena, "main.zig", 8);
    snapCase(&r, &table, arena, "main.zig", 9);
    snapCase(&r, &table, arena, "main.zig", 9);
    snapCase(&r, &table, arena, "main.zig", 0);
    snapCase(&r, &table, arena, "main.zig", 99);
    snapCase(&r, &table, arena, "fixtures/hello/main.zig", 16);
    snapCase(&r, &table, arena, "missing.zig", 9);
}

fn modeSession(arena: *std.arena.Arena, prefix: []const u8) void {
    var r = map_reader.open(arena, prefix) catch {
        fail("session open");
        return;
    };
    var start = dbg_core.entryStop(&r, arena) orelse {
        fail("session entryStop");
        return;
    };
    var be = backend.stubBackend();
    dbg_main.runSession(arena, &r, &be, start);
}

fn testContinue(state: *void) backend.BackendError!void {
    _ = state;
}

fn testDetach(state: *void) backend.BackendError!void {
    _ = state;
}

fn modeSessionRunning(arena: *std.arena.Arena, prefix: []const u8) void {
    var r = map_reader.open(arena, prefix) catch {
        fail("running session open");
        return;
    };
    var start = dbg_core.entryStop(&r, arena) orelse {
        fail("running session entryStop");
        return;
    };
    var be = backend.stubBackend();
    be.continue_fn = testContinue;
    be.singleStep_fn = testContinue;
    be.detach_fn = testDetach;
    dbg_main.runSession(arena, &r, &be, start);
}

fn modeDumpRegs(arena: *std.arena.Arena, prefix: []const u8, path: []const u8) void {
    var r = map_reader.open(arena, prefix) catch {
        fail("dump open");
        return;
    };
    var start = dbg_core.entryStop(&r, arena) orelse {
        fail("dump entryStop");
        return;
    };
    var regs = backend.Registers{
        .eax = 1,
        .ecx = 2,
        .edx = 3,
        .ebx = 4,
        .esp = 5,
        .ebp = 6,
        .esi = 7,
        .edi = 8,
        .eip = 9,
        .eflags = 10,
    };
    if (dbg_core.writeDump(&r, arena, start, path, regs, true)) {
        ok("dump wrote");
    } else {
        fail("dump wrote");
    }
}

fn modeOpenError(arena: *std.arena.Arena, prefix: []const u8) void {
    var r = map_reader.open(arena, prefix) catch {
        ok("open rejected");
        return;
    };
    _ = r;
    fail("open accepted");
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    os.initArgs(argc, argv);
    if (os.argc() < 3) {
        writeLine("usage: dbg_test <mode> <map-prefix> [path]");
        os.exit(2);
    }
    var arena = std.arena.init(g_arena_buf[0..]);
    var mode = os.argv(1);
    var prefix = os.argv(2);
    if (std.str.eql(mode, "map-hello")) {
        modeMapHello(&arena, prefix);
    } else if (std.str.eql(mode, "map-fib")) {
        modeMapFib(&arena, prefix);
    } else if (std.str.eql(mode, "snap")) {
        modeSnap(&arena, prefix);
    } else if (std.str.eql(mode, "session")) {
        modeSession(&arena, prefix);
    } else if (std.str.eql(mode, "session-running")) {
        modeSessionRunning(&arena, prefix);
    } else if (std.str.eql(mode, "dump-regs")) {
        if (os.argc() < 4) {
            writeLine("usage: dbg_test dump-regs <map-prefix> <path>");
            os.exit(2);
        }
        modeDumpRegs(&arena, prefix, os.argv(3));
    } else if (std.str.eql(mode, "open-error")) {
        modeOpenError(&arena, prefix);
    } else {
        writeLine("unknown mode");
        os.exit(2);
    }
    if (g_fail != 0) os.exit(1);
}
