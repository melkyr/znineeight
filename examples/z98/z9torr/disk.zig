// disk.zig — z9torr: single-file write-through target + read-back.
//
// Spec 2026-10-08 §7: one output file. Each received block is written at
// `piece_index*piece_length + block_begin` immediately (write-through); a whole
// piece is read back for SHA-1 verification. `openTarget` creates or extends
// the file to `total_length` (seek to end-1 + write one zero, portable to FAT —
// no sparse-file or truncate primitive). `t.name` was already sanitized in M1's
// `torrent.load` (no '/', '\\', or ".." path); a name that is a directory or is
// otherwise unopenable surfaces as `DiskError.OpenFailed`.
//
// Z98 D2: a slice `[]T` is safe only when `T` is primitive or a *named* type.
// This module crosses no `[]`-of-synthetic boundary: `openTarget` returns the
// imported named `std_file.File`, and `readPiece`/`writeBlock` take `[]u8`.

const std = @import("std");
const filemod = @import("std_file.zig");
const torrent = @import("torrent.zig");

pub const DiskError = error{
    OpenFailed,
    ReadFailed,
    WriteFailed,
    SeekFailed,
    SizeFailed,
    BadName,
};

fn pieceStart(t: torrent.Torrent, index: u32) u64 {
    return @intCast(u64, index) * @intCast(u64, t.piece_length);
}

// Length of piece `index` (the last piece may be shorter than piece_length).
// 0 when `index` is out of range.
pub fn pieceLength(t: torrent.Torrent, index: u32) u32 {
    var start: u64 = pieceStart(t, index);
    if (start >= t.total_length) return 0;
    var remain: u64 = t.total_length - start;
    var pl: u64 = @intCast(u64, t.piece_length);
    if (remain < pl) return @intCast(u32, remain);
    return @intCast(u32, pl);
}

// Output file offset of the first byte of a block.
fn blockOffset(t: torrent.Torrent, piece_index: u32, block_begin: u32) u64 {
    return pieceStart(t, piece_index) + @intCast(u64, block_begin);
}

// Create/open `t.name` ReadWrite and ensure its size is at least `total_length`.
// `total_length == 0` leaves an empty file.
pub fn openTarget(arena: *std.arena.Arena, t: torrent.Torrent) DiskError!filemod.File {
    if (t.name.len == 0) return error.BadName;
    var f = filemod.open(arena, t.name, filemod.Mode.ReadWrite) catch return error.OpenFailed;
    if (t.total_length > 0) {
        var sz: i64 = filemod.size(&f) catch {
            filemod.close(&f);
            return error.SizeFailed;
        };
        if (sz < 0) {
            filemod.close(&f);
            return error.SizeFailed;
        }
        if (@intCast(u64, sz) < t.total_length) {
            var last: i64 = @intCast(i64, t.total_length - 1);
            _ = filemod.seek(&f, last, filemod.SeekWhence.Set) catch {
                filemod.close(&f);
                return error.SeekFailed;
            };
            var zero: [1]u8 = undefined;
            zero[0] = 0;
            _ = filemod.write(&f, zero[0..]) catch {
                filemod.close(&f);
                return error.WriteFailed;
            };
        }
    }
    return f;
}

// Write one block at `piece_index*piece_length + block_begin` (write-through).
pub fn writeBlock(f: *filemod.File, t: torrent.Torrent, piece_index: u32, block_begin: u32, bytes: []const u8) DiskError!void {
    var off: u64 = blockOffset(t, piece_index, block_begin);
    _ = filemod.seek(f, @intCast(i64, off), filemod.SeekWhence.Set) catch return error.SeekFailed;
    var done: usize = 0;
    while (done < bytes.len) {
        var w = filemod.write(f, bytes[done..bytes.len]) catch return error.WriteFailed;
        if (w == 0) return error.WriteFailed;
        done += w;
    }
}

// Read piece `index` into `out`; returns the number of bytes read (the piece
// length, or `out.len` if smaller). Short reads stop at EOF.
pub fn readPiece(f: *filemod.File, t: torrent.Torrent, index: u32, out: []u8) DiskError!usize {
    var plen: u32 = pieceLength(t, index);
    if (plen == 0) return 0;
    var want: usize = @intCast(usize, plen);
    if (want > out.len) want = out.len;
    var start: u64 = pieceStart(t, index);
    _ = filemod.seek(f, @intCast(i64, start), filemod.SeekWhence.Set) catch return error.SeekFailed;
    var got: usize = 0;
    while (got < want) {
        var r = filemod.read(f, out[got..want]) catch return error.ReadFailed;
        if (r == 0) break;
        got += r;
    }
    return got;
}
