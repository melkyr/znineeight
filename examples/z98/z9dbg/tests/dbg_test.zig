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
const dwarf = @import("../dwarf_lines.zig");
const coff = @import("../coff_lines.zig");
const pe = @import("../pe_debug.zig");

var g_arena_buf: [1048576]u8 = undefined;
var g_img: [8192]u8 = undefined;
var g_fail: u32 = 0;
var g_mock_step_index: u32 = 0;
var g_mock_lines: [8]u32 = undefined;
var g_mock_line_count: u32 = 0;

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

fn strContains(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > hay.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        var j: usize = 0;
        var same = true;
        while (j < needle.len) : (j += 1) {
            if (hay[i + j] != needle[j]) same = false;
        }
        if (same) return true;
    }
    return false;
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

    var one_span: [1]map_reader.LineSpan = undefined;
    var span_overflow = false;
    var nspan = map_reader.lineSpansAt(&r, "main.zig", 16, one_span[0..], &span_overflow);
    expectUsize("hello lineSpansAt clamp count", nspan, 1);
    expectTrue("hello lineSpansAt overflow", span_overflow);

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

fn noResolve(state: *void, eip: u32, out: *dbg_core.StopState) bool {
    _ = state;
    _ = eip;
    _ = out;
    return false;
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
    var no_state: *void = @intToPtr(*void, 0);
    dbg_main.runSession(arena, &r, &be, start, no_state, noResolve);
}

fn testContinue(state: *void) backend.BackendError!void {
    _ = state;
}

fn testDetach(state: *void) backend.BackendError!void {
    _ = state;
}

fn mockSingleStep(state: *void) backend.BackendError!void {
    _ = state;
}

fn mockWait(state: *void) backend.BackendError!backend.StopEvent {
    _ = state;
    var idx = g_mock_step_index;
    g_mock_step_index += 1;
    return backend.StopEvent{ .reason = backend.STOP_SINGLE_STEP, .signo = 0, .eip = idx };
}

fn mockResolve(state: *void, eip: u32, out: *dbg_core.StopState) bool {
    _ = state;
    var idx: usize = @intCast(usize, eip);
    if (idx >= @intCast(usize, g_mock_line_count)) return false;
    out.* = dbg_core.StopState{
        .src_file = "examples/z98/z9dbg/tests/fixtures/hello/main.zig",
        .src_line = g_mock_lines[idx],
        .function_name = "main",
    };
    return true;
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
    var no_state: *void = @intToPtr(*void, 0);
    dbg_main.runSession(arena, &r, &be, start, no_state, noResolve);
}

fn modeSessionStep(arena: *std.arena.Arena, prefix: []const u8) void {
    var r = map_reader.open(arena, prefix) catch {
        fail("step session open");
        return;
    };
    var start = dbg_core.entryStop(&r, arena) orelse {
        fail("step session entryStop");
        return;
    };
    g_mock_step_index = 0;
    g_mock_line_count = 3;
    g_mock_lines[0] = 14;
    g_mock_lines[1] = 15;
    g_mock_lines[2] = 16;
    var be = backend.stubBackend();
    be.singleStep_fn = mockSingleStep;
    be.wait_fn = mockWait;
    be.continue_fn = testContinue;
    be.detach_fn = testDetach;
    var no_state: *void = @intToPtr(*void, 0);
    dbg_main.runSession(arena, &r, &be, start, no_state, mockResolve);
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

fn modeMapNoCnames(arena: *std.arena.Arena, prefix: []const u8) void {
    var r = map_reader.open(arena, prefix) catch {
        fail("nocnames open");
        return;
    };
    expectUsize("nocnames symbol count 3", map_reader.symbolCount(&r), 3);
    expectUsize("nocnames group count 1", map_reader.groupCount(&r), 1);
    expectUsize("nocnames line run count 6", map_reader.lineRunCount(&r), 6);
    expectUsize("nocnames cname count 0", map_reader.cnameCount(&r), 0);
    expectTrue("nocnames cnameFor null", map_reader.cnameFor(&r, "main") == null);
    var sym = map_reader.symbolAt(&r, "main.zig", 14);
    if (sym) |s| {
        expectStr("nocnames symbolAt main", s.src_name, "main");
    } else {
        fail("nocnames symbolAt main");
    }
    var row = map_reader.lineAt(&r, "main.zig", 16);
    expectTrue("nocnames lineAt 16", row != null);
    var start = dbg_core.entryStop(&r, arena);
    if (start) |st| {
        expectU32("nocnames entryStop line", st.src_line, 14);
    } else {
        fail("nocnames entryStop");
    }
}

fn modeBench(arena: *std.arena.Arena, prefix: []const u8, full: bool) void {
    var r = map_reader.open(arena, prefix) catch {
        fail("bench open");
        return;
    };
    write("bench counts symbols=");
    std.io.printInt(@intCast(i32, map_reader.symbolCount(&r)));
    write(" groups=");
    std.io.printInt(@intCast(i32, map_reader.groupCount(&r)));
    write(" runs=");
    std.io.printInt(@intCast(i32, map_reader.lineRunCount(&r)));
    write(" cnames=");
    std.io.printInt(@intCast(i32, map_reader.cnameCount(&r)));
    write("\n");
    if (!full) {
        ok("bench open");
        return;
    }
    var start = dbg_core.entryStop(&r, arena) orelse {
        fail("bench entryStop");
        return;
    };
    var rows: [8]map_reader.LineRow = undefined;
    var nrows = map_reader.lineRowsAt(&r, start.src_file, start.src_line, rows[0..]);
    expectTrue("bench lineRowsAt", nrows > 0);
    var row = map_reader.lineAt(&r, start.src_file, start.src_line);
    var rev_ok = false;
    if (row) |rv| {
        var back = map_reader.reverseRowAt(&r, rv.out_file, rv.out_line);
        rev_ok = back != null;
    }
    expectTrue("bench reverseRowAt", rev_ok);
    var sym = map_reader.symbolAt(&r, start.src_file, start.src_line);
    expectTrue("bench symbolAt", sym != null);
    var cn = map_reader.cnameFor(&r, "main");
    expectTrue("bench cnameFor", cn != null);
}

fn imgZero(n: usize) void {
    var i: usize = 0;
    while (i < n and i < g_img.len) : (i += 1) g_img[i] = 0;
}

fn imgU16(off: usize, v: u16) void {
    g_img[off] = @intCast(u8, v & @intCast(u16, 0xff));
    g_img[off + 1] = @intCast(u8, v >> @intCast(u16, 8));
}

fn imgU32(off: usize, v: u32) void {
    g_img[off] = @intCast(u8, v & @intCast(u32, 0xff));
    g_img[off + 1] = @intCast(u8, (v >> @intCast(u32, 8)) & @intCast(u32, 0xff));
    g_img[off + 2] = @intCast(u8, (v >> @intCast(u32, 16)) & @intCast(u32, 0xff));
    g_img[off + 3] = @intCast(u8, v >> @intCast(u32, 24));
}

fn imgStr(off: usize, s: []const u8) void {
    var i: usize = 0;
    while (i < s.len) : (i += 1) g_img[off + i] = s[i];
}

// One-section PE32 with a Type-1 COFF debug directory blob, built strictly to
// the documented §15.1 layout: FILE aux (C:\src\hello.c + CRLF), a STATIC
// .text section definition owning four line records, an EXTERNAL function with
// a format-1 aux, a STATIC function with an aux, a STATIC data symbol (Type 0,
// no aux) that must be ignored, and an EXTERNAL long name resolved through the
// COFF string table. Line Records carry code RVAs. No real compiler output is
// involved.
fn buildCoffImage() void {
    imgZero(2048);
    imgU16(0, 0x5a4d);
    imgU32(0x3c, 0x80);
    imgStr(0x80, "PE");
    // COFF header at 0x84.
    imgU16(0x84, 0x014c);
    imgU16(0x86, 1);
    imgU16(0x94, 0x00e0);
    imgU16(0x96, 0x0102);
    // PE32 optional header at 0x98.
    imgU16(0x98, 0x010b);
    imgU32(0xb4, 0x00400000);
    imgU32(0xf4, 16);
    imgU32(0x128, 0x00001000);
    imgU32(0x12c, 28);
    // Section table at 0x178.
    imgStr(0x178, ".text");
    imgU32(0x180, 0x00001000);
    imgU32(0x184, 0x00001000);
    imgU32(0x188, 0x00000200);
    imgU32(0x18c, 0x00000400);
    // Debug directory entry at file 0x400 (RVA 0x1000); blob at 0x41c.
    imgU32(0x40c, 1);
    imgU32(0x410, 262);
    imgU32(0x414, 0x0000101c);
    imgU32(0x418, 0x0000041c);
    // IMAGE_COFF_SYMBOLS_HEADER at 0x41c: 11 symbols, 4 line records.
    imgU32(0x41c, 11);
    imgU32(0x420, 16);
    imgU32(0x424, 4);
    imgU32(0x428, 238);
    // Symbol 0: FILE, aux format 4 names the source file.
    imgStr(0x42c, ".file");
    imgU16(0x438, 0xfffe);
    g_img[0x43c] = 103;
    g_img[0x43d] = 1;
    imgStr(0x43e, "C:\\src\\hello.c\r");
    // Symbol 2: STATIC section definition (Type 0), aux carries nlnno=4.
    imgStr(0x450, ".text");
    imgU16(0x45c, 1);
    g_img[0x460] = 3;
    g_img[0x461] = 1;
    imgU32(0x462, 0x00000100);
    imgU16(0x468, 4);
    // Symbol 4: EXTERNAL function, aux format 1 carries TotalSize.
    imgStr(0x474, "_hello");
    imgU16(0x480, 1);
    imgU16(0x482, 0x0020);
    g_img[0x484] = 2;
    g_img[0x485] = 1;
    imgU32(0x48a, 0x00000100);
    // Symbol 6: STATIC function (Type 0x20) with an aux; size stays 0.
    imgStr(0x498, "_sfunc");
    imgU32(0x4a0, 0x40);
    imgU16(0x4a4, 1);
    imgU16(0x4a6, 0x0020);
    g_img[0x4a8] = 3;
    g_img[0x4a9] = 1;
    // Symbol 8: STATIC data (Type 0, no aux) — must NOT become a function.
    imgStr(0x4bc, "_sdata");
    imgU32(0x4c4, 0x20);
    imgU16(0x4c8, 1);
    g_img[0x4cc] = 3;
    g_img[0x4cd] = 0;
    // Symbol 9: EXTERNAL long name via the string table at offset 4.
    imgU32(0x4ce, 0);
    imgU32(0x4d2, 4);
    imgU32(0x4d6, 0x80);
    imgU16(0x4da, 1);
    imgU16(0x4dc, 0x0020);
    g_img[0x4de] = 2;
    g_img[0x4df] = 1;
    imgU32(0x4e4, 0x80);
    // COFF string table immediately after the symbol records (size + names).
    imgU32(0x4f2, 24);
    imgStr(0x4f6, "_zF_LONGNAME_hello");
    // Line records at blob+238 (0x50a): header, then three code-RVA rows.
    imgU32(0x50a, 4);
    imgU16(0x50e, 0);
    imgU32(0x510, 0x1010);
    imgU16(0x514, 2);
    imgU32(0x516, 0x1014);
    imgU16(0x51a, 3);
    imgU32(0x51c, 0x1018);
    imgU16(0x520, 3);
}

fn modeCoff(arena: *std.arena.Arena) void {
    buildCoffImage();
    var di = coff.openBytes(arena, g_img[0..], 0x00400000) catch {
        fail("coff open");
        return;
    };
    expectTrue("coff has line", di.has_line);
    expectU32("coff image base", di.image_base, 0x00400000);
    expectUsize("coff row count", di.row_n, 3);
    expectUsize("coff file count", di.file_n, 1);
    expectUsize("coff func count", di.func_n, 3);
    if (di.row_n >= 3) {
        expectU32("coff row0 addr", di.rows[0].addr, 0x00401010);
        expectU32("coff row0 line", di.rows[0].line, 2);
        expectU32("coff row2 addr", di.rows[2].addr, 0x00401018);
    } else {
        fail("coff rows");
    }
    if (di.file_n >= 1) {
        expectStr("coff file normalized", di.files[0], "src/hello.c");
    } else {
        fail("coff files");
    }
    if (di.func_n >= 3) {
        expectStr("coff func underscore stripped", di.funcs[0].name, "hello");
        expectU32("coff func addr", di.funcs[0].addr, 0x00401000);
        expectU32("coff func size", di.funcs[0].size, 0x100);
        expectStr("coff static function with aux", di.funcs[1].name, "sfunc");
        expectU32("coff static function addr", di.funcs[1].addr, 0x00401040);
        expectStr("coff long name via string table", di.funcs[2].name, "zF_LONGNAME_hello");
        expectU32("coff long function addr", di.funcs[2].addr, 0x00401080);
    } else {
        fail("coff funcs");
    }
    expectTrue("coff static data excluded", dwarf.funcAddr(&di, "sdata") == null);
    var long_addr = dwarf.funcAddr(&di, "zF_LONGNAME_hello");
    if (long_addr) |la| {
        expectU32("coff long func lookup", la, 0x00401080);
    } else {
        fail("coff long func lookup");
    }
    di.base = 0;
    var out: [8]u32 = undefined;
    var n = dwarf.addrForLine(&di, "hello.c", 2, out[0..]);
    if (n >= 1) {
        expectU32("coff addrForLine line 2", out[0], 0x00401010);
    } else {
        fail("coff addrForLine line 2");
    }
    var n2 = dwarf.addrForLine(&di, "C:\\src\\hello.c", 3, out[0..]);
    expectTrue("coff addrForLine drive path", n2 >= 2);
    var f = dwarf.funcByAddr(&di, 0x00401005);
    if (f) |fv| {
        expectStr("coff funcByAddr", fv.name, "hello");
    } else {
        fail("coff funcByAddr");
    }
}

fn modePe(arena: *std.arena.Arena, path: []const u8) void {
    var di = pe.open(arena, path) catch {
        fail("pe open");
        return;
    };
    expectTrue("pe has line", di.has_line);
    expectTrue("pe image base nonzero", di.image_base != 0);
    expectTrue("pe rows", di.row_n > 0);
    expectTrue("pe files", di.file_n > 0);
    expectTrue("pe funcs", di.func_n > 0);
    // Real mingw symbol table: _g_atexit_fns is STATIC Type-0 data with no aux
    // (must be excluded); _zig_ovf_sext is a STATIC function carrying an aux
    // (must be included).
    expectTrue("pe static data excluded", dwarf.funcAddr(&di, "g_atexit_fns") == null);
    expectTrue("pe static function with aux included", dwarf.funcAddr(&di, "zig_ovf_sext") != null);
    // The session layer applies runtime_base - image_base; use a runtime image
    // base equal to the link image base (bias 0) to query link-time VAs.
    di.base = 0;
    var out: [64]u32 = undefined;
    var pick: usize = 0;
    var found = false;
    var i: usize = 0;
    while (i < di.row_n) : (i += 1) {
        var nm = dwarf.rowFileName(&di, di.rows[i]);
        if (strContains(nm, "main_")) {
            pick = i;
            found = true;
            break;
        }
    }
    var fname = dwarf.rowFileName(&di, di.rows[pick]);
    var line = di.rows[pick].line;
    var n = dwarf.addrForLine(&di, fname, line, out[0..]);
    expectTrue("pe addrForLine generated C row", n > 0);
    if (found) {
        expectTrue("pe main module line table", n > 0);
    } else {
        fail("pe main module line table");
    }
    if (di.row_n > 0) {
        expectTrue("pe row file nonempty", dwarf.rowFileName(&di, di.rows[0]).len > 0);
        expectTrue("pe row link VA", di.rows[0].addr >= di.image_base);
        var rr = dwarf.rowForAddr(&di, di.rows[0].addr);
        expectTrue("pe rowForAddr", rr != null);
    }
    if (di.func_n > 0) {
        var a = dwarf.funcAddr(&di, di.funcs[0].name);
        expectTrue("pe funcAddr first name", a != null);
    }
}

fn modeSourceCrlf(arena: *std.arena.Arena, path: []const u8) void {
    var text = dbg_core.readSourceLine(arena, path, 2) orelse {
        fail("crlf read");
        return;
    };
    expectStr("crlf trailing byte stripped", text, "int b;");
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
    } else if (std.str.eql(mode, "session-step")) {
        modeSessionStep(&arena, prefix);
    } else if (std.str.eql(mode, "map-nocnames")) {
        modeMapNoCnames(&arena, prefix);
    } else if (std.str.eql(mode, "bench-open")) {
        modeBench(&arena, prefix, false);
    } else if (std.str.eql(mode, "bench-full")) {
        modeBench(&arena, prefix, true);
    } else if (std.str.eql(mode, "dump-regs")) {
        if (os.argc() < 4) {
            writeLine("usage: dbg_test dump-regs <map-prefix> <path>");
            os.exit(2);
        }
        modeDumpRegs(&arena, prefix, os.argv(3));
    } else if (std.str.eql(mode, "coff")) {
        modeCoff(&arena);
    } else if (std.str.eql(mode, "pe")) {
        if (os.argc() < 4) {
            writeLine("usage: dbg_test pe <ignored> <pe-path>");
            os.exit(2);
        }
        modePe(&arena, os.argv(3));
    } else if (std.str.eql(mode, "source-crlf")) {
        if (os.argc() < 4) {
            writeLine("usage: dbg_test source-crlf <ignored> <source-path>");
            os.exit(2);
        }
        modeSourceCrlf(&arena, os.argv(3));
    } else if (std.str.eql(mode, "open-error")) {
        modeOpenError(&arena, prefix);
    } else {
        writeLine("unknown mode");
        os.exit(2);
    }
    if (g_fail != 0) os.exit(1);
}
