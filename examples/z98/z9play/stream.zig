// stream.zig — bounded buffered file over std_file (z9play M9 Task 1).
//
// Pure Z98 free functions. `BufferedFile` owns its `std_file.File` by value and
// borrows the caller's arena; the arena and the backing storage must outlive the
// BufferedFile. `open` allocates exactly one STREAM_BUF_SIZE buffer from that
// arena; reads, reads of one byte, seeks and tells never allocate.
//
// EOF/short-read semantics: `bufferedFileRead` copies as many bytes as are
// available and refills the buffer as needed. It returns a short count only at
// true EOF (or when fewer than `out.len` bytes remain in the file); the next
// call returns 0. `bufferedFileReadByte` returns null at EOF. Close is
// idempotent and a second close is a no-op.

const std = @import("std");
const std_file = @import("std_file");

pub const STREAM_BUF_SIZE: usize = 64 * 1024;

pub const StreamError = error{ OpenFailed, ReadFailed, SeekFailed, SizeFailed, OutOfMemory };

pub const BufferedFile = struct {
    file: std_file.File,
    arena: *std.arena.Arena,
    buf: []u8,
    start: u64,
    len: usize,
    pos: usize,
    closed: bool,
};

fn nullHandle() *void {
    return @intToPtr(*void, 0);
}

// Refill an exhausted buffer. The OS file offset is always start + len before
// the reset (open, seek and every prior refill maintain that invariant), so the
// new start is the old start plus the old valid length.
fn refill(bf: *BufferedFile) StreamError!void {
    if (bf.closed) return error.ReadFailed;
    bf.start = bf.start + @intCast(u64, bf.len);
    bf.len = 0;
    bf.pos = 0;
    while (bf.len < bf.buf.len) {
        var got: usize = std_file.read(&bf.file, bf.buf[bf.len..]) catch return error.ReadFailed;
        if (got == 0) return;
        bf.len += got;
    }
}

pub fn bufferedFileOpen(arena: *std.arena.Arena, path: []const u8) StreamError!BufferedFile {
    var f: std_file.File = std_file.open(arena, path, .Read) catch return error.OpenFailed;
    var sz: i64 = std_file.size(&f) catch {
        std_file.close(&f);
        return error.SizeFailed;
    };
    if (sz < 0) {
        std_file.close(&f);
        return error.SizeFailed;
    }
    var raw: [*]u8 = std.arena.alloc(arena, STREAM_BUF_SIZE) catch {
        std_file.close(&f);
        return error.OutOfMemory;
    };
    return BufferedFile{
        .file = f,
        .arena = arena,
        .buf = raw[0..STREAM_BUF_SIZE],
        .start = 0,
        .len = 0,
        .pos = 0,
        .closed = false,
    };
}

pub fn bufferedFileClose(bf: *BufferedFile) void {
    if (@ptrToInt(bf.file.handle) == 0) return;
    std_file.close(&bf.file);
    bf.file.handle = nullHandle();
    bf.closed = true;
}

pub fn bufferedFileReadByte(bf: *BufferedFile) StreamError!?u8 {
    if (bf.pos == bf.len) {
        try refill(bf);
        if (bf.len == 0) return null;
    }
    var b: u8 = bf.buf[bf.pos];
    bf.pos += 1;
    return b;
}

pub fn bufferedFileRead(bf: *BufferedFile, out: []u8) StreamError!usize {
    var total: usize = 0;
    while (total < out.len) {
        if (bf.pos == bf.len) {
            try refill(bf);
            if (bf.len == 0) break;
        }
        var avail: usize = bf.len - bf.pos;
        var n: usize = avail;
        if (out.len - total < n) n = out.len - total;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            out[total + i] = bf.buf[bf.pos + i];
        }
        bf.pos += n;
        total += n;
    }
    return total;
}

pub fn bufferedFileSeek(bf: *BufferedFile, offset: u64) StreamError!void {
    if (bf.closed) return error.SeekFailed;
    _ = std_file.seek(&bf.file, @intCast(i64, offset), .Set) catch return error.SeekFailed;
    bf.start = offset;
    bf.len = 0;
    bf.pos = 0;
}

pub fn bufferedFileTell(bf: *BufferedFile) u64 {
    return bf.start + @intCast(u64, bf.pos);
}

pub fn bufferedFileSize(bf: *BufferedFile) u64 {
    if (bf.file.size_cache < 0) return 0;
    return @intCast(u64, bf.file.size_cache);
}
