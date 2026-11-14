// stdlib_file_seek64_xmod — STDLIB std_file (L3) 64-bit offsets GREEN fixture.
//
// Contract (spec 2026-10-08 §12 risk 7, M5 amendment lift): std_file.seek/size
// use 64-bit offsets on POSIX (the _llseek syscall + O_LARGEFILE), so a sparse
// file may be seeked/written PAST the 2 GiB mark; size() and seek(End) report
// the full i64 length. Windows already used SetFilePointerEx (i64) /
// GetFileSizeEx, so its branch is unchanged. The old POSIX code rejected offset
// > i32 max (2 GiB - 1) with SeekFailed, and open() without O_LARGEFILE failed
// the write EFBIG.
//
// The file is SPARSE: one marker byte at offset BIG creates a > 2 GiB file
// without writing 2 GiB of payload (on-disk blocks stay tiny). BIG is 2 GiB +
// 1 KiB = 2147484672, past the old i32 off_t ceiling (2147483647). The fixture
// seeks to BIG, writes one byte, closes, reopens, and asserts size(), seek(End)
// and a re-seek all report the full 64-bit offset.
//
// GREEN (contract): deterministic byte-exact stdout `seek64 = 2147484673\n`
// (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

// 2 GiB + 1 KiB, past the old i32 off_t ceiling (2147483647).
const BIG: i64 = 2147484672;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    var w = f.open(&g_arena, "t_seek64.bin", f.Mode.Write) catch @panic("open w");
    var pos = f.seek(&w, BIG, f.SeekWhence.Set) catch @panic("seek set");
    ck(pos == BIG, "seek set 64-bit pos");
    var marker: [1]u8 = undefined;
    marker[0] = 'Z';
    var n = f.write(&w, marker[0..]) catch @panic("write");
    ck(n == 1, "write one");
    f.close(&w);

    var r = f.open(&g_arena, "t_seek64.bin", f.Mode.Read) catch @panic("open r");
    var sz = f.size(&r) catch @panic("size");
    ck(sz == BIG + 1, "size 64-bit");

    pos = f.seek(&r, @intCast(i64, 0), f.SeekWhence.End) catch @panic("seek end");
    ck(pos == BIG + 1, "seek end 64-bit");

    pos = f.seek(&r, BIG, f.SeekWhence.Set) catch @panic("seek set2");
    ck(pos == BIG, "re-seek 64-bit");
    var b: [1]u8 = undefined;
    n = f.read(&r, b[0..]) catch @panic("read");
    ck(n == 1, "read one");
    ck(b[0] == 'Z', "marker byte");
    f.close(&r);
    f.remove("t_seek64.bin") catch {};

    io.print("seek64 = {}\n", .{sz});
}
