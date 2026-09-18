// stdlib_file_stress_xmod — STDLIB std_file (L3) hand-written stress table.
//
// No PRNG: every input is an explicit, deterministic formula/table. Stresses:
//   - a large writeAll/readAll round-trip (10000 bytes) whose explicit pattern
//     embeds binary `\r` (13), `\n` (10) and NUL (0) bytes at pinned offsets
//     (0..2, 1234..1236, 4321, SIZE-2/SIZE-1), so binary safety is byte-exact.
//   - a chunked sequential read (777-byte reads) that walks to EOF; the read
//     AFTER the last byte returns 0 (the EOF boundary, not an error).
//   - seek Set/End/Cur round-trips, a zero-length read, and reads at and past
//     EOF (both return 0).
//   - an in-place overwrite round-trip (Mode.ReadWrite, seek to 2500, write a
//     second 500-byte pattern) verifying the changed region and that the bytes
//     before/after it are preserved exactly.
//
// GREEN (contract): deterministic byte-exact stdout `file stress ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

const SIZE: usize = 10000;
const OVW_OFF: usize = 2500;
const OVW_LEN: usize = 500;

var g_storage: [262144]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);
var g_pat: [SIZE]u8 = undefined;
var g_ovw: [OVW_LEN]u8 = undefined;
var g_tmp: [SIZE]u8 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn fillTables() void {
    var i: usize = 0;
    while (i < SIZE) : (i += 1) {
        g_pat[i] = @intCast(u8, (i * 31 + 7) % 256);
    }
    // Binary bytes at pinned offsets: NUL, CR, LF.
    g_pat[0] = 0;
    g_pat[1] = 13;
    g_pat[2] = 10;
    g_pat[1234] = 0;
    g_pat[1235] = 13;
    g_pat[1236] = 10;
    g_pat[4321] = 0;
    g_pat[SIZE - 2] = 13;
    g_pat[SIZE - 1] = 10;

    i = 0;
    while (i < OVW_LEN) : (i += 1) {
        g_ovw[i] = @intCast(u8, (i * 101 + 200) % 256);
    }
}

fn bytesEqual(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn checkRange(buf: []const u8, base: usize, want: []const u8, what: []const u8) void {
    var i: usize = 0;
    while (i < want.len) : (i += 1) {
        ck(buf[base + i] == want[i], what);
    }
}

pub fn main() void {
    fillTables();

    // --- large writeAll / readAll round-trip --------------------------------
    f.writeAll("t_file_stress.bin", g_pat[0..SIZE]) catch @panic("writeAll");
    var back = f.readAll(&g_arena, "t_file_stress.bin") catch @panic("readAll");
    ck(back.len == SIZE, "readAll length");
    ck(bytesEqual(back, g_pat[0..SIZE]), "readAll byte-exact");

    // --- chunked sequential read to EOF -------------------------------------
    var file = f.open(&g_arena, "t_file_stress.bin", f.Mode.Read) catch @panic("open");
    const sz = f.size(&file) catch @panic("size");
    ck(sz == @intCast(i64, SIZE), "size");
    var off: usize = 0;
    while (off < SIZE) {
        var want: usize = SIZE - off;
        if (want > 777) want = 777;
        const got = f.read(&file, g_tmp[0..want]) catch @panic("read chunk");
        ck(got == want, "read chunk length");
        checkRange(g_tmp[0..got], 0, g_pat[off..off + got], "read chunk bytes");
        off += got;
    }
    const eof = f.read(&file, g_tmp[0..16]) catch @panic("read eof");
    ck(eof == 0, "read at EOF returns 0");
    const zero = f.read(&file, g_tmp[0..0]) catch @panic("read zero");
    ck(zero == 0, "zero-length read returns 0");

    // --- seek Set/End/Cur + reads at/past EOF -------------------------------
    var pos = f.seek(&file, @intCast(i64, OVW_OFF), f.SeekWhence.Set) catch @panic("seek set");
    ck(pos == @intCast(i64, OVW_OFF), "seek set pos");
    const mid = f.read(&file, g_tmp[0..100]) catch @panic("read mid");
    ck(mid == 100, "read mid length");
    checkRange(g_tmp[0..100], 0, g_pat[OVW_OFF..OVW_OFF + 100], "read mid bytes");

    pos = f.seek(&file, @intCast(i64, -10), f.SeekWhence.End) catch @panic("seek end");
    ck(pos == @intCast(i64, SIZE - 10), "seek end pos");
    const tail = f.read(&file, g_tmp[0..10]) catch @panic("read tail");
    ck(tail == 10, "read tail length");
    checkRange(g_tmp[0..10], 0, g_pat[SIZE - 10..SIZE], "read tail bytes");

    pos = f.seek(&file, @intCast(i64, 0), f.SeekWhence.Cur) catch @panic("seek cur");
    ck(pos == @intCast(i64, SIZE), "seek cur pos at EOF");
    pos = f.seek(&file, @intCast(i64, SIZE), f.SeekWhence.Set) catch @panic("seek at eof");
    const at_eof = f.read(&file, g_tmp[0..16]) catch @panic("read at eof");
    ck(at_eof == 0, "read at exact EOF returns 0");
    pos = f.seek(&file, @intCast(i64, SIZE + 5), f.SeekWhence.Set) catch @panic("seek past eof");
    const past = f.read(&file, g_tmp[0..16]) catch @panic("read past eof");
    ck(past == 0, "read past EOF returns 0");
    f.close(&file);

    // --- in-place overwrite round-trip --------------------------------------
    var rw = f.open(&g_arena, "t_file_stress.bin", f.Mode.ReadWrite) catch @panic("open rw");
    pos = f.seek(&rw, @intCast(i64, OVW_OFF), f.SeekWhence.Set) catch @panic("seek rw");
    ck(pos == @intCast(i64, OVW_OFF), "seek rw pos");
    const wrote = f.write(&rw, g_ovw[0..OVW_LEN]) catch @panic("write rw");
    ck(wrote == OVW_LEN, "write rw length");
    f.flush(&rw) catch @panic("flush rw");
    f.close(&rw);

    var back2 = f.readAll(&g_arena, "t_file_stress.bin") catch @panic("readAll 2");
    ck(back2.len == SIZE, "overwrite readAll length");
    checkRange(back2, 0, g_pat[0..OVW_OFF], "overwrite prefix preserved");
    checkRange(back2, OVW_OFF, g_ovw[0..OVW_LEN], "overwrite region changed");
    checkRange(back2, OVW_OFF + OVW_LEN, g_pat[OVW_OFF + OVW_LEN..SIZE], "overwrite suffix preserved");

    f.remove("t_file_stress.bin") catch {};
    io.write("file stress ok\n");
}
