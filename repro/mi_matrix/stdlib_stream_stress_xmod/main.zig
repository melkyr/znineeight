// stdlib_stream_stress_xmod — STDLIB std_stream (L6) hand-written stress table.
//
// No PRNG: every input is an explicit, deterministic pattern. File-only (the
// L6 reader is file-only); the blocking readFileLineSync path is stressed:
//   - a long line (250 bytes) through a 100-byte buffer: two full 100-byte
//     overflow chunks then a 50-byte remainder (250 % 100 != 0, so the
//     terminator is consumed in the last chunk, no spurious empty line).
//   - a final line with no trailing newline (returned by the EOF path).
//   - an empty source (null immediately, no line).
//   - a CRLF line (the \r of \r\n stripped).
//   - interleaved readers: two independent FileLineReaders over two files,
//     each with a 150-byte line, alternated call-by-call so each reader's
//     pending buffer must survive the other's reads unchanged.
//
// GREEN (contract): deterministic byte-exact stdout `stream stress ok\n` (rc 0).
const f = @import("std_file.zig");
const st = @import("std_stream.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);
var g_fill: [512]u8 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn makeLine(path: []const u8, ch: u8, len: usize) void {
    var i: usize = 0;
    while (i < len) : (i += 1) g_fill[i] = ch;
    g_fill[len] = '\n';
    f.writeAll(path, g_fill[0 .. len + 1]) catch @panic("writeAll");
}

fn expectChunk(lr: *st.FileLineReader, ch: u8, len: usize, what: []const u8) void {
    const m = st.readFileLineSync(lr) catch @panic(what);
    if (m) |line| {
        ck(line.len == len, what);
        var i: usize = 0;
        while (i < len) : (i += 1) ck(line[i] == ch, what);
    } else {
        @panic(what);
    }
}

fn expectText(lr: *st.FileLineReader, want: []const u8, what: []const u8) void {
    const m = st.readFileLineSync(lr) catch @panic(what);
    if (m) |line| {
        ck(line.len == want.len, what);
        var i: usize = 0;
        while (i < want.len) : (i += 1) ck(line[i] == want[i], what);
    } else {
        @panic(what);
    }
}

fn expectNull(lr: *st.FileLineReader, what: []const u8) void {
    if ((st.readFileLineSync(lr) catch @panic(what)) != null) @panic(what);
}

pub fn main() void {
    // --- long line ----------------------------------------------------------
    makeLine("t_stream_stress_long.txt", 'a', 250);
    var file = f.open(&g_arena, "t_stream_stress_long.txt", f.Mode.Read) catch @panic("open long");
    var buf: [100]u8 = undefined;
    var lr = st.initFileLineReader(&file, buf[0..]);
    expectChunk(&lr, 'a', 100, "long chunk 1");
    expectChunk(&lr, 'a', 100, "long chunk 2");
    expectChunk(&lr, 'a', 50, "long remainder");
    expectNull(&lr, "long EOF");
    f.close(&file);

    // --- no trailing newline ------------------------------------------------
    f.writeAll("t_stream_stress_noeof.txt", "xyz") catch @panic("write noeof");
    var nf = f.open(&g_arena, "t_stream_stress_noeof.txt", f.Mode.Read) catch @panic("open noeof");
    var nbuf: [100]u8 = undefined;
    var nlr = st.initFileLineReader(&nf, nbuf[0..]);
    expectText(&nlr, "xyz", "noeof final line");
    expectNull(&nlr, "noeof EOF");
    f.close(&nf);

    // --- empty source -------------------------------------------------------
    f.writeAll("t_stream_stress_empty.txt", "") catch @panic("write empty");
    var ef = f.open(&g_arena, "t_stream_stress_empty.txt", f.Mode.Read) catch @panic("open empty");
    var ebuf: [100]u8 = undefined;
    var elr = st.initFileLineReader(&ef, ebuf[0..]);
    expectNull(&elr, "empty EOF");
    f.close(&ef);

    // --- CRLF ---------------------------------------------------------------
    f.writeAll("t_stream_stress_crlf.txt", "cr\r\nlf\n") catch @panic("write crlf");
    var cf = f.open(&g_arena, "t_stream_stress_crlf.txt", f.Mode.Read) catch @panic("open crlf");
    var cbuf: [100]u8 = undefined;
    var clr = st.initFileLineReader(&cf, cbuf[0..]);
    expectText(&clr, "cr", "crlf first");
    expectText(&clr, "lf", "crlf second");
    expectNull(&clr, "crlf EOF");
    f.close(&cf);

    // --- interleaved readers ------------------------------------------------
    makeLine("t_stream_stress_ia.txt", 'a', 150);
    makeLine("t_stream_stress_ib.txt", 'b', 150);
    var af = f.open(&g_arena, "t_stream_stress_ia.txt", f.Mode.Read) catch @panic("open ia");
    var bf = f.open(&g_arena, "t_stream_stress_ib.txt", f.Mode.Read) catch @panic("open ib");
    var abuf: [100]u8 = undefined;
    var bbuf: [100]u8 = undefined;
    var alr = st.initFileLineReader(&af, abuf[0..]);
    var blr = st.initFileLineReader(&bf, bbuf[0..]);
    expectChunk(&alr, 'a', 100, "interleave a1");
    expectChunk(&blr, 'b', 100, "interleave b1");
    expectChunk(&alr, 'a', 50, "interleave a2");
    expectChunk(&blr, 'b', 50, "interleave b2");
    expectNull(&alr, "interleave a EOF");
    expectNull(&blr, "interleave b EOF");
    f.close(&af);
    f.close(&bf);

    f.remove("t_stream_stress_long.txt") catch {};
    f.remove("t_stream_stress_noeof.txt") catch {};
    f.remove("t_stream_stress_empty.txt") catch {};
    f.remove("t_stream_stress_crlf.txt") catch {};
    f.remove("t_stream_stress_ia.txt") catch {};
    f.remove("t_stream_stress_ib.txt") catch {};
    io.write("stream stress ok\n");
}
