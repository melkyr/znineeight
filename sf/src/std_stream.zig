// std_stream.zig — Z98 std lib L6: coroutine-aware composition over L3
// resources. Plan B is FILE-ONLY (operator ruling m1449/m1451, Model C
// cooperative-yield): `FileLineReader` over a caller-owned `*std_file.File`.
// `SocketLineReader`, `MsgReader`, the non-blocking socket primitives, and an
// optional `std.async.wait(handle)` are Plan D (recorded, not implemented).
//
// Model C: there is no executor and no poll loop. The caller drives the landed
// std.async scheduler with tick(); a coroutine yields only when it chooses to.
// `readLineAsync` is therefore a SEPARATE chunked implementation, not a wrapper
// over `readLineSync`: it reads a bounded chunk and calls the `@asyncSuspend`
// builtin once per incomplete read. The scheduler is caller-provided and owned
// by main; this module never calls `tick`/`waitFor`/`waitAll` (C2). The
// `@asyncSuspend` builtin is the language-level async facility — the module
// does not need (and does not import) the std_async scheduler module, so a
// program that only imports std_file/std_net/std_stdin does not link it (C3).
//
// The caller owns all memory (R1): the reader never allocates. `buf` is the
// line-accumulation buffer and `pending` is the unconsumed slice into it. The
// returned line aliases `buf` and is valid until the next call.
//
// CRLF at the buffer boundary: when a `\r` lands as the last byte of a full
// overflow buffer, `takeOverflow` strips it and sets the caller-held
// `pending_cr` carry; the next read consumes the following `\n` as the same
// terminator, so no `\r` is leaked and no spurious empty line is produced.
//
// One error set at the top (R2), aliased from the source's error set. No
// `catch unreachable`; every file error is propagated.

const file_mod = @import("std_file.zig");

// R2: one error set per module. The file reader's source error set is
// std_file.FileError; aliasing it keeps the two in lockstep without a second
// definition. A future socket reader would carry its own source error set.
pub const StreamError = file_mod.FileError;

pub const FileLineReader = struct {
    src: *file_mod.File,
    buf: []u8,
    pending: []u8,
    pending_cr: bool,
};

// Async read granularity: at most a quarter of the caller buffer per chunk, so
// a line can span several reads — and therefore several cooperative yields —
// before the buffer fills. The sync path reads the whole remaining buffer in
// one call (it never yields).
fn asyncChunk(lr: *const FileLineReader) usize {
    var c: usize = lr.buf.len / 4;
    if (c == 0) c = 1;
    return c;
}

// Move `pending` back to the front of `buf` so the tail is free for a read.
// Called only when no returned line slice is outstanding.
fn compact(lr: *FileLineReader) void {
    const off: usize = @ptrToInt(lr.pending.ptr) - @ptrToInt(lr.buf.ptr);
    if (off == 0) return;
    var i: usize = 0;
    while (i < lr.pending.len) : (i += 1) {
        lr.buf[i] = lr.pending[i];
    }
    lr.pending = lr.buf[0..lr.pending.len];
}

// Consume one complete line from `pending`, or null if none is buffered.
// Strips the terminating \n and the \r of \r\n. The returned slice aliases buf.
fn takeLine(lr: *FileLineReader) ?[]u8 {
    var i: usize = 0;
    while (i < lr.pending.len) : (i += 1) {
        if (lr.pending[i] == '\n') {
            var line: []u8 = lr.pending[0..i];
            if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
            lr.pending = lr.pending[i + 1 ..];
            return line;
        }
    }
    return null;
}

// The final unterminated line at EOF, or null when nothing remains.
fn takeRest(lr: *FileLineReader) ?[]u8 {
    if (lr.pending.len == 0) return null;
    var line: []u8 = lr.pending;
    lr.pending = lr.buf[0..0];
    if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
    return line;
}

// A line longer than `buf`: hand back the full buffer as a line so the caller
// makes progress; the rest of the line is returned by subsequent calls. A
// trailing `\r` at the boundary is stripped and carried in `pending_cr` so the
// next read can consume its `\n` as the same terminator.
fn takeOverflow(lr: *FileLineReader) ?[]u8 {
    if (lr.pending.len < lr.buf.len) return null;
    var line: []u8 = lr.pending;
    lr.pending = lr.buf[0..0];
    if (line.len > 0 and line[line.len - 1] == '\r') {
        lr.pending_cr = true;
        line = line[0 .. line.len - 1];
    }
    return line;
}

// Resolve a boundary CR carried from a full-buffer overflow (`pending_cr`).
// Read the next byte: '\n' closes the CRLF (the overflow call already returned
// that line's text, so this is not a new empty line); any other byte makes the
// CR a literal first byte of the continuation. Called only while `pending` is
// empty (takeOverflow clears it before setting `pending_cr`).
fn resolvePending(lr: *FileLineReader) StreamError!void {
    if (!lr.pending_cr) return;
    lr.pending_cr = false;
    if (lr.buf.len == 0) return;
    const got = try file_mod.read(lr.src, lr.buf[0..1]);
    if (got == 0) {
        lr.buf[0] = '\r';
        lr.pending = lr.buf[0..1];
        return;
    }
    if (lr.buf[0] == '\n') return;
    const b = lr.buf[0];
    lr.buf[0] = '\r';
    if (lr.buf.len >= 2) {
        lr.buf[1] = b;
        lr.pending = lr.buf[0..2];
    } else {
        lr.pending = lr.buf[0..1];
    }
}

// Read up to `want` bytes (bounded by the free tail of buf) into `pending`.
// Returns the byte count; 0 means EOF or no free space (disambiguated by the
// caller via takeOverflow/takeRest).
fn readChunk(lr: *FileLineReader, want: usize) StreamError!usize {
    compact(lr);
    const remaining: usize = lr.buf.len - lr.pending.len;
    var n: usize = want;
    if (n > remaining) n = remaining;
    if (n == 0) return 0;
    const got = try file_mod.read(lr.src, lr.buf[lr.pending.len .. lr.pending.len + n]);
    if (got > 0) lr.pending = lr.buf[0 .. lr.pending.len + got];
    return got;
}

pub fn initFileLineReader(src: *file_mod.File, buf: []u8) FileLineReader {
    return FileLineReader{ .src = src, .buf = buf, .pending = buf[0..0], .pending_cr = false };
}

// Blocking: read until a line is buffered or EOF. No suspension.
pub fn readLineSync(lr: *FileLineReader) StreamError!?[]u8 {
    if (lr.buf.len == 0) return null;
    try resolvePending(lr);
    while (true) {
        if (takeLine(lr)) |line| return line;
        if (takeOverflow(lr)) |line| return line;
        const got = try readChunk(lr, lr.buf.len);
        if (got == 0) return takeRest(lr);
    }
    return null;
}

// True when a complete line is already buffered (does not consume it).
fn hasLine(lr: *FileLineReader) bool {
    var i: usize = 0;
    while (i < lr.pending.len) : (i += 1) {
        if (lr.pending[i] == '\n') return true;
    }
    return false;
}

// Cooperative-yield core: read one chunk; if it did not complete a line, yield
// via @asyncSuspend and resume on the next tick. It returns a scalar status so
// the suspending loop and the `!?[]u8` result never share one frame: the landed
// async frame-layout pass rejects a `while` loop whose suspending function
// returns `!?[]u8` (P2/P3 size guard). This is a compiler limitation, worked
// around here — no compiler/PAL file is touched (R8). `readLineAsync` maps the
// status to the line slice.
const LINE_EOF: u8 = 0;
const LINE_READY: u8 = 1;
const LINE_OVERFLOW: u8 = 2;

fn awaitLine(lr: *FileLineReader) StreamError!u8 {
    if (lr.buf.len == 0) return LINE_EOF;
    try resolvePending(lr);
    while (true) {
        if (hasLine(lr)) return LINE_READY;
        if (lr.pending.len >= lr.buf.len) return LINE_OVERFLOW;
        const got = try readChunk(lr, asyncChunk(lr));
        if (got == 0) return LINE_EOF;
        _ = @asyncSuspend(null);
    }
    return LINE_EOF;
}

// Cooperative-yield entry point. A SEPARATE implementation from readLineSync
// (it never calls it); it suspends once per incomplete read inside awaitLine.
pub fn readLineAsync(lr: *FileLineReader) StreamError!?[]u8 {
    const status = try awaitLine(lr);
    if (status == LINE_READY) return takeLine(lr);
    if (status == LINE_OVERFLOW) return takeOverflow(lr);
    return takeRest(lr);
}
