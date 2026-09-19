// std_stream.zig — Z98 std lib L6: coroutine-aware composition over L3
// resources. Plan B landed the file half (operator ruling m1449/m1451, Model C
// cooperative-yield): `FileLineReader` over a caller-owned `*std_file.File`.
// Plan D Task 2 lands the socket half: `SocketLineReader` over a caller-owned
// `*std_net.Socket` (caller sets it non-blocking for the async path).
// `MsgReader` and an optional `std.async.wait(handle)` remain Plan D (recorded,
// not implemented).
//
// Model C: there is no executor and no poll loop. The caller drives the landed
// std.async scheduler with tick(); a coroutine yields only when it chooses to.
// `readFileLineAsync` is therefore a SEPARATE chunked implementation, not a wrapper
// over `readFileLineSync`: it reads a bounded chunk and calls the `@asyncSuspend`
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
// `catch unreachable`; every source error is propagated.

const file_mod = @import("std_file.zig");
const net_mod = @import("std_net.zig");

// R2: one error set per module. The file reader's source error set is
// std_file.FileError; aliasing it keeps the two in lockstep without a second
// definition. The socket reader's source error set is std_net.NetError, carried
// by its own inferred `!?[]u8` signatures (C1: the sync/async pair share it).
pub const StreamError = file_mod.FileError;

pub const FileLineReader = struct {
    src: *file_mod.File,
    buf: []u8,
    pending: []u8,
    pending_cr: bool,
    overflow_cont: bool,
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
// next read can consume its `\n` as the same terminator. The carry needs room
// for the `\r` plus the next byte (buf.len > 1); a 1-byte buffer keeps the CR
// in the returned line rather than dropping a byte.
fn takeOverflow(lr: *FileLineReader) ?[]u8 {
    if (lr.pending.len < lr.buf.len) return null;
    var line: []u8 = lr.pending;
    lr.pending = lr.buf[0..0];
    if (lr.buf.len > 1 and line.len > 0 and line[line.len - 1] == '\r') {
        lr.pending_cr = true;
        line = line[0 .. line.len - 1];
    } else if (lr.buf.len > 1) {
        // The full buffer is a line prefix and the line continues; the next
        // read must consume this line's terminator before the next line.
        lr.overflow_cont = true;
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
        // Unreachable: takeOverflow only sets pending_cr when buf.len > 1.
        lr.pending = lr.buf[0..1];
    }
}

// Consume the terminator of an exact-multiple overflow line. After
// takeOverflow returned a full buffer as a line prefix, the line's \n (or
// \r\n) is still unread and must be consumed as THAT line's terminator, not
// surfaced as a new empty line. A non-terminator head byte is the line's
// continuation and is left buffered. Only called when `overflow_cont` is set,
// which takeOverflow only does for buf.len > 1, so the 1-byte boundary
// behaviour is untouched.
fn resolveOverflow(lr: *FileLineReader) StreamError!void {
    if (lr.pending.len == 0) {
        const got = try readChunk(lr, lr.buf.len);
        if (got == 0) {
            lr.overflow_cont = false;
            return;
        }
    }
    if (lr.pending[0] == '\n') {
        lr.pending = lr.pending[1..];
        lr.overflow_cont = false;
        return;
    }
    if (lr.pending[0] == '\r') {
        if (lr.pending.len < 2) _ = try readChunk(lr, 1);
        if (lr.pending.len >= 2 and lr.pending[1] == '\n') {
            lr.pending = lr.pending[2..];
        }
    }
    lr.overflow_cont = false;
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
    return FileLineReader{ .src = src, .buf = buf, .pending = buf[0..0], .pending_cr = false, .overflow_cont = false };
}

// Blocking: read until a line is buffered or EOF. No suspension.
pub fn readFileLineSync(lr: *FileLineReader) StreamError!?[]u8 {
    if (lr.buf.len == 0) return null;
    try resolvePending(lr);
    if (lr.overflow_cont) try resolveOverflow(lr);
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
// around here — no compiler/PAL file is touched (R8). `readFileLineAsync` maps the
// status to the line slice.
const LINE_EOF: u8 = 0;
const LINE_READY: u8 = 1;
const LINE_OVERFLOW: u8 = 2;

fn awaitLine(lr: *FileLineReader) StreamError!u8 {
    if (lr.buf.len == 0) return LINE_EOF;
    try resolvePending(lr);
    if (lr.overflow_cont) try resolveOverflow(lr);
    while (true) {
        if (hasLine(lr)) return LINE_READY;
        if (lr.pending.len >= lr.buf.len) return LINE_OVERFLOW;
        const got = try readChunk(lr, asyncChunk(lr));
        if (got == 0) return LINE_EOF;
        _ = @asyncSuspend(null);
    }
    return LINE_EOF;
}

// Cooperative-yield entry point. A SEPARATE implementation from readFileLineSync
// (it never calls it); it suspends once per incomplete read inside awaitLine.
pub fn readFileLineAsync(lr: *FileLineReader) StreamError!?[]u8 {
    const status = try awaitLine(lr);
    if (status == LINE_READY) return takeLine(lr);
    if (status == LINE_OVERFLOW) return takeOverflow(lr);
    return takeRest(lr);
}

// ============================================================================
// SocketLineReader (Plan D Task 2) — the socket half of the L6 reader surface.
//
// Same line contract as FileLineReader (strip \n / \r\n, return the final
// unterminated line, null at EOF, an overlong line returns a full-buffer prefix
// and never a spurious empty line). The source is a caller-owned `*Socket`
// already set non-blocking for the async path (std_net.setNonBlocking).
//
// C1: `readSocketLineSync`/`readSocketLineAsync` are the same module, same
// error set (std_net.NetError), same return type (`!?[]u8`). C3: the sync path
// never calls the async one — the read primitives are shared, but the suspend
// handling lives only in the await* wrappers. The async path yields on
// `error.WouldBlock` and is re-driven on the next tick (Model C).

pub const SocketLineReader = struct {
    src: *net_mod.Socket,
    buf: []u8,
    pending: []u8,
    pending_cr: bool,
    overflow_cont: bool,
};

// Move `pending` back to the front of `buf` so the tail is free for a read.
fn compactSocket(lr: *SocketLineReader) void {
    const off: usize = @ptrToInt(lr.pending.ptr) - @ptrToInt(lr.buf.ptr);
    if (off == 0) return;
    var i: usize = 0;
    while (i < lr.pending.len) : (i += 1) {
        lr.buf[i] = lr.pending[i];
    }
    lr.pending = lr.buf[0..lr.pending.len];
}

// Consume one complete line from `pending`, or null if none is buffered.
fn takeSocketLine(lr: *SocketLineReader) ?[]u8 {
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
fn takeSocketRest(lr: *SocketLineReader) ?[]u8 {
    if (lr.pending.len == 0) return null;
    var line: []u8 = lr.pending;
    lr.pending = lr.buf[0..0];
    if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
    return line;
}

// A line longer than `buf`: hand back the full buffer as a line prefix so the
// caller makes progress; the boundary CR carry mirrors takeOverflow.
fn takeSocketOverflow(lr: *SocketLineReader) ?[]u8 {
    if (lr.pending.len < lr.buf.len) return null;
    var line: []u8 = lr.pending;
    lr.pending = lr.buf[0..0];
    if (lr.buf.len > 1 and line.len > 0 and line[line.len - 1] == '\r') {
        lr.pending_cr = true;
        line = line[0 .. line.len - 1];
    } else if (lr.buf.len > 1) {
        lr.overflow_cont = true;
    }
    return line;
}

// True when a complete line is already buffered (does not consume it).
fn hasSocketLine(lr: *SocketLineReader) bool {
    var i: usize = 0;
    while (i < lr.pending.len) : (i += 1) {
        if (lr.pending[i] == '\n') return true;
    }
    return false;
}

// Async read granularity: a quarter of the caller buffer per chunk.
fn asyncSocketChunk(lr: *const SocketLineReader) usize {
    var c: usize = lr.buf.len / 4;
    if (c == 0) c = 1;
    return c;
}

// One non-blocking read attempt into the free tail of buf. Returns 1 with the
// byte count in `out_n` (0 = EOF) on success, 0 when the socket would block.
// A real socket error propagates. Retry-safe: on a would-block the pending
// slice is untouched, so the caller may yield and call again.
fn socketTryRead(lr: *SocketLineReader, want: usize, out_n: *usize) net_mod.NetError!u8 {
    compactSocket(lr);
    const remaining: usize = lr.buf.len - lr.pending.len;
    var n: usize = want;
    if (n > remaining) n = remaining;
    if (n == 0) {
        out_n.* = 0;
        return 1;
    }
    const got = net_mod.recvNonBlocking(lr.src, lr.buf[lr.pending.len .. lr.pending.len + n]) catch |e| {
        if (e == error.WouldBlock) return 0;
        return e;
    };
    if (got > 0) lr.pending = lr.buf[0 .. lr.pending.len + got];
    out_n.* = got;
    return 1;
}

// Resolve a boundary CR carried from a full-buffer overflow. Retry-safe: the
// pending_cr carry is cleared only after the 1-byte read succeeds.
fn resolveSocketPending(lr: *SocketLineReader) net_mod.NetError!bool {
    if (!lr.pending_cr) return true;
    if (lr.buf.len == 0) {
        lr.pending_cr = false;
        return true;
    }
    var n: usize = 0;
    const st = try socketTryRead(lr, 1, &n);
    if (st == 0) return false;
    lr.pending_cr = false;
    if (n == 0) {
        lr.buf[0] = '\r';
        lr.pending = lr.buf[0..1];
        return true;
    }
    if (lr.buf[0] == '\n') {
        // The carry's '\n' closes the CRLF: consume it (socketTryRead left it
        // in `pending`) so it is not surfaced as a spurious empty line.
        lr.pending = lr.buf[0..0];
        return true;
    }
    const b = lr.buf[0];
    lr.buf[0] = '\r';
    if (lr.buf.len >= 2) {
        lr.buf[1] = b;
        lr.pending = lr.buf[0..2];
    } else {
        lr.pending = lr.buf[0..1];
    }
    return true;
}

// Consume the terminator of an exact-multiple overflow line. Retry-safe: the
// overflow_cont flag is cleared only once the terminator decision is final.
fn resolveSocketOverflow(lr: *SocketLineReader) net_mod.NetError!bool {
    if (lr.pending.len == 0) {
        var n: usize = 0;
        const st = try socketTryRead(lr, lr.buf.len, &n);
        if (st == 0) return false;
        if (n == 0) {
            lr.overflow_cont = false;
            return true;
        }
    }
    if (lr.pending[0] == '\n') {
        lr.pending = lr.pending[1..];
        lr.overflow_cont = false;
        return true;
    }
    if (lr.pending[0] == '\r') {
        if (lr.pending.len < 2) {
            var n2: usize = 0;
            const st2 = try socketTryRead(lr, 1, &n2);
            if (st2 == 0) return false;
        }
        if (lr.pending.len >= 2 and lr.pending[1] == '\n') {
            lr.pending = lr.pending[2..];
        }
    }
    lr.overflow_cont = false;
    return true;
}

pub fn initSocketLineReader(src: *net_mod.Socket, buf: []u8) SocketLineReader {
    return SocketLineReader{ .src = src, .buf = buf, .pending = buf[0..0], .pending_cr = false, .overflow_cont = false };
}

// Blocking: read until a line is buffered or EOF. No suspension. The socket
// must be in blocking mode; a would-block read on a non-blocking socket is
// surfaced as error.WouldBlock.
pub fn readSocketLineSync(lr: *SocketLineReader) !?[]u8 {
    if (lr.buf.len == 0) return null;
    const rp = try resolveSocketPending(lr);
    if (!rp) return error.WouldBlock;
    if (lr.overflow_cont) {
        const ro = try resolveSocketOverflow(lr);
        if (!ro) return error.WouldBlock;
    }
    while (true) {
        if (takeSocketLine(lr)) |line| return line;
        if (takeSocketOverflow(lr)) |line| return line;
        var n: usize = 0;
        const st = try socketTryRead(lr, lr.buf.len, &n);
        if (st == 0) return error.WouldBlock;
        if (n == 0) return takeSocketRest(lr);
    }
    return null;
}

// --- async (Model C): suspend on WouldBlock, resume on the next tick ---

const SOCK_EOF: u8 = 0;
const SOCK_READY: u8 = 1;
const SOCK_OVERFLOW: u8 = 2;

// Suspend once per would-block and retry, so the caller is re-driven next tick.
fn awaitSocketReadChunk(lr: *SocketLineReader, want: usize) net_mod.NetError!usize {
    var n: usize = 0;
    while (true) {
        const st = try socketTryRead(lr, want, &n);
        if (st == 1) return n;
        _ = @asyncSuspend(null);
    }
    return 0;
}

fn awaitResolveSocketPending(lr: *SocketLineReader) net_mod.NetError!void {
    while (true) {
        const r = try resolveSocketPending(lr);
        if (r) return;
        _ = @asyncSuspend(null);
    }
}

fn awaitResolveSocketOverflow(lr: *SocketLineReader) net_mod.NetError!void {
    while (true) {
        const r = try resolveSocketOverflow(lr);
        if (r) return;
        _ = @asyncSuspend(null);
    }
}

// Cooperative-yield core returning a scalar status so the suspending loop and
// the `!?[]u8` result never share one frame (P2/P3 async frame-layout guard;
// the same workaround as awaitLine above). `readSocketLineAsync` maps it.
fn awaitSocketLine(lr: *SocketLineReader) net_mod.NetError!u8 {
    if (lr.buf.len == 0) return SOCK_EOF;
    try awaitResolveSocketPending(lr);
    if (lr.overflow_cont) try awaitResolveSocketOverflow(lr);
    while (true) {
        if (hasSocketLine(lr)) return SOCK_READY;
        if (lr.pending.len >= lr.buf.len) return SOCK_OVERFLOW;
        const got = try awaitSocketReadChunk(lr, asyncSocketChunk(lr));
        if (got == 0) return SOCK_EOF;
    }
    return SOCK_EOF;
}

// Cooperative-yield entry point. A SEPARATE implementation from
// readSocketLineSync (it never calls it); it suspends on error.WouldBlock.
pub fn readSocketLineAsync(lr: *SocketLineReader) !?[]u8 {
    const status = try awaitSocketLine(lr);
    if (status == SOCK_READY) return takeSocketLine(lr);
    if (status == SOCK_OVERFLOW) return takeSocketOverflow(lr);
    return takeSocketRest(lr);
}
