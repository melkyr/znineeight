// buffer.zig — z9edit headless core: gap buffer over one file.
//
// Z98 subset only. Direct imports (no `std` barrel); arena-backed; GUI-free.
// The raw file bytes are stored exactly as loaded (CRLF stays CRLF), so
// load -> save with no edit is byte-identical. `bufInsert` rewrites a bare LF
// to CRLF when the loaded file used CRLF endings, so edits keep the file's
// ending. Line/col indexes here are 0-based; the GUI adds 1 for its status bar.
//
// Gap layout: bytes [0, gap_start) then the gap [gap_start, gap_end) then bytes
// [gap_end, cap). Content length is tracked in `len`; the gap size is
// cap - len. A move relocates the gap to the edit point; growth doubles the
// buffer and keeps the suffix at the end.

const arena_mod = @import("std_arena.zig");
const file_mod = @import("std_file.zig");

pub const BufError = error{ ReadFailed, WriteFailed, OutOfMemory, TooLarge };

const MAX_BUF: usize = 16 * 1024 * 1024;
const MIN_CAP: usize = 64;
const MIN_GAP: usize = 64;

const BufState = struct {
    arena: *arena_mod.Arena,
    buf: [*]u8,
    cap: usize,
    gap_start: usize,
    gap_end: usize,
    len: usize,
    uses_crlf: bool,
    dirty: bool,
};

// Opaque to callers: only a pointer to the private state is exposed.
pub const GapBuffer = struct { opaque: *BufState };

fn allocBytes(arena: *arena_mod.Arena, n: usize) BufError![*]u8 {
    if (n > MAX_BUF) return error.TooLarge;
    return arena_mod.alloc(arena, n) catch |e| {
        return error.OutOfMemory;
    };
}

fn newState(arena: *arena_mod.Arena, cap: usize) BufError!*BufState {
    var c = cap;
    if (c < MIN_CAP) c = MIN_CAP;
    if (c > MAX_BUF) return error.TooLarge;
    const raw_state = arena_mod.alloc(arena, @sizeOf(BufState)) catch |e| {
        return error.OutOfMemory;
    };
    const st: *BufState = @ptrCast(*BufState, raw_state);
    const raw_buf = try allocBytes(arena, c);
    st.arena = arena;
    st.buf = raw_buf;
    st.cap = c;
    st.gap_start = 0;
    st.gap_end = c;
    st.len = 0;
    st.uses_crlf = false;
    st.dirty = false;
    return st;
}

fn newGapBuffer(arena: *arena_mod.Arena, cap: usize) BufError!*GapBuffer {
    const raw_wrap = arena_mod.alloc(arena, @sizeOf(GapBuffer)) catch |e| {
        return error.OutOfMemory;
    };
    const wrap: *GapBuffer = @ptrCast(*GapBuffer, raw_wrap);
    wrap.opaque = try newState(arena, cap);
    return wrap;
}

fn state(b: *GapBuffer) *BufState {
    return b.opaque;
}

fn hasCrlf(data: []const u8) bool {
    var i: usize = 0;
    while (i + 1 < data.len) : (i += 1) {
        if (data[i] == '\r' and data[i + 1] == '\n') return true;
    }
    return false;
}

fn ensureGap(st: *BufState, need: usize) BufError!void {
    const gsize = st.gap_end - st.gap_start;
    if (gsize >= need) return;
    const need_cap = st.len + need;
    if (need_cap > MAX_BUF) return error.TooLarge;
    var new_cap = st.cap * 2;
    if (new_cap < need_cap + MIN_GAP) new_cap = need_cap + MIN_GAP;
    if (new_cap > MAX_BUF) new_cap = need_cap + MIN_GAP;
    if (new_cap > MAX_BUF) return error.TooLarge;
    const raw = try allocBytes(st.arena, new_cap);
    const nb: [*]u8 = raw;
    var i: usize = 0;
    while (i < st.gap_start) : (i += 1) {
        nb[i] = st.buf[i];
    }
    const suffix = st.cap - st.gap_end;
    const new_end = new_cap - suffix;
    i = 0;
    while (i < suffix) : (i += 1) {
        nb[new_end + i] = st.buf[st.gap_end + i];
    }
    st.buf = nb;
    st.cap = new_cap;
    st.gap_end = new_end;
}

fn moveGapTo(st: *BufState, pos: usize) void {
    if (pos < st.gap_start) {
        const delta = st.gap_start - pos;
        var i: usize = delta;
        while (i > 0) {
            i -= 1;
            st.buf[st.gap_end - delta + i] = st.buf[pos + i];
        }
        st.gap_end -= delta;
        st.gap_start = pos;
    } else if (pos > st.gap_start) {
        const delta = pos - st.gap_start;
        var i: usize = 0;
        while (i < delta) : (i += 1) {
            st.buf[st.gap_start + i] = st.buf[st.gap_end + i];
        }
        st.gap_start = pos;
        st.gap_end += delta;
    }
}

fn gapSize(st: *BufState) usize {
    return st.gap_end - st.gap_start;
}

fn lineCountOf(st: *BufState) usize {
    var n: usize = 1;
    var i: usize = 0;
    while (i < st.len) : (i += 1) {
        if (bufByteAtState(st, i) == '\n') n += 1;
    }
    return n;
}

fn bufByteAtState(st: *BufState, pos: usize) u8 {
    if (pos >= st.len) return 0;
    if (pos < st.gap_start) return st.buf[pos];
    return st.buf[pos + gapSize(st)];
}

fn lineStartOf(st: *BufState, line: usize) usize {
    var start: usize = 0;
    var cur: usize = 0;
    while (cur < line and start < st.len) : (cur += 1) {
        while (start < st.len and bufByteAtState(st, start) != '\n') : (start += 1) {}
        if (start < st.len) start += 1;
    }
    return start;
}

fn lineContentEnd(st: *BufState, start: usize) usize {
    var e = start;
    while (e < st.len and bufByteAtState(st, e) != '\n') : (e += 1) {}
    if (e > start and bufByteAtState(st, e - 1) == '\r') e -= 1;
    return e;
}

// --- public buffer API ------------------------------------------------------

pub fn bufInit(arena: *arena_mod.Arena, cap: usize) BufError!*GapBuffer {
    return newGapBuffer(arena, cap);
}

pub fn bufLoad(arena: *arena_mod.Arena, path: []const u8) BufError!*GapBuffer {
    const data = file_mod.readAll(arena, path) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.ReadFailed;
    };
    if (data.len > MAX_BUF) return error.TooLarge;
    var cap = data.len + MIN_GAP;
    if (cap < MIN_CAP) cap = MIN_CAP;
    const wrap = try newGapBuffer(arena, cap);
    const st = state(wrap);
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        st.buf[i] = data[i];
    }
    st.len = data.len;
    st.gap_start = data.len;
    st.gap_end = cap;
    st.uses_crlf = hasCrlf(data);
    st.dirty = false;
    return wrap;
}

pub fn bufSave(b: *GapBuffer, path: []const u8) BufError!void {
    const st = state(b);
    const tmp = try allocBytes(st.arena, st.len + 1);
    var i: usize = 0;
    while (i < st.len) : (i += 1) {
        tmp[i] = bufByteAtState(st, i);
    }
    file_mod.writeAll(path, tmp[0..st.len]) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.WriteFailed;
    };
    st.dirty = false;
}

pub fn bufLen(b: *GapBuffer) usize {
    return state(b).len;
}

pub fn bufUsesCrlf(b: *GapBuffer) bool {
    return state(b).uses_crlf;
}

pub fn bufDirty(b: *GapBuffer) bool {
    return state(b).dirty;
}

pub fn bufInsert(b: *GapBuffer, pos: usize, bytes: []const u8) BufError!void {
    const st = state(b);
    var at = pos;
    if (at > st.len) at = st.len;

    // CRLF files: a bare LF in `bytes` becomes CRLF. Existing CR already in
    // `bytes` (or immediately before `at`) is not doubled.
    var extra: usize = 0;
    if (st.uses_crlf) {
        var i: usize = 0;
        while (i < bytes.len) : (i += 1) {
            if (bytes[i] == '\n') {
                if (i == 0) {
                    if (at == 0 or bufByteAtState(st, at - 1) != '\r') extra += 1;
                } else if (bytes[i - 1] != '\r') {
                    extra += 1;
                }
            }
        }
    }
    if (extra == 0) {
        try ensureGap(st, bytes.len);
        moveGapTo(st, at);
        var i: usize = 0;
        while (i < bytes.len) : (i += 1) {
            st.buf[st.gap_start + i] = bytes[i];
        }
        st.gap_start += bytes.len;
        st.len += bytes.len;
        st.dirty = true;
        return;
    }

    const out_len = bytes.len + extra;
    if (st.len + out_len > MAX_BUF) return error.TooLarge;
    const tmp = try allocBytes(st.arena, out_len + 1);
    var src: usize = 0;
    var dst: usize = 0;
    while (src < bytes.len) : (src += 1) {
        if (bytes[src] == '\n') {
            var needs_cr = false;
            if (src == 0) {
                needs_cr = at == 0 or bufByteAtState(st, at - 1) != '\r';
            } else {
                needs_cr = bytes[src - 1] != '\r';
            }
            if (needs_cr) {
                tmp[dst] = '\r';
                dst += 1;
            }
        }
        tmp[dst] = bytes[src];
        dst += 1;
    }
    try ensureGap(st, dst);
    moveGapTo(st, at);
    src = 0;
    while (src < dst) : (src += 1) {
        st.buf[st.gap_start + src] = tmp[src];
    }
    st.gap_start += dst;
    st.len += dst;
    st.dirty = true;
}

pub fn bufDelete(b: *GapBuffer, pos: usize, count: usize) BufError!void {
    const st = state(b);
    if (pos >= st.len or count == 0) return;
    var n = count;
    if (n > st.len - pos) n = st.len - pos;
    moveGapTo(st, pos);
    st.gap_end += n;
    st.len -= n;
    st.dirty = true;
}

pub fn bufByteAt(b: *GapBuffer, pos: usize) u8 {
    return bufByteAtState(state(b), pos);
}

pub fn bufCopy(b: *GapBuffer, pos: usize, count: usize, out: []u8) usize {
    const st = state(b);
    if (pos >= st.len or count == 0 or out.len == 0) return 0;
    var n = count;
    if (n > st.len - pos) n = st.len - pos;
    if (n > out.len) n = out.len;
    const gs = gapSize(st);
    var i: usize = 0;
    if (pos < st.gap_start) {
        var take = n;
        if (take > st.gap_start - pos) take = st.gap_start - pos;
        while (i < take) : (i += 1) {
            out[i] = st.buf[pos + i];
        }
        while (i < n) : (i += 1) {
            out[i] = st.buf[pos + i + gs];
        }
    } else {
        while (i < n) : (i += 1) {
            out[i] = st.buf[pos + i + gs];
        }
    }
    return n;
}

pub fn bufLineCount(b: *GapBuffer) usize {
    return lineCountOf(state(b));
}

pub fn bufLineRange(b: *GapBuffer, line: usize, start: *usize, len: *usize) void {
    const st = state(b);
    const count = lineCountOf(st);
    var ln = line;
    if (ln >= count) {
        start.* = st.len;
        len.* = 0;
        return;
    }
    const s = lineStartOf(st, ln);
    const e = lineContentEnd(st, s);
    start.* = s;
    len.* = e - s;
}

pub fn bufOffsetOf(b: *GapBuffer, line: usize, col: usize) usize {
    const st = state(b);
    const count = lineCountOf(st);
    if (line >= count) return st.len;
    const s = lineStartOf(st, line);
    const e = lineContentEnd(st, s);
    const line_len = e - s;
    if (col >= line_len) return e;
    return s + col;
}

pub fn bufLineColOf(b: *GapBuffer, pos: usize, line: *usize, col: *usize) void {
    const st = state(b);
    var p = pos;
    if (p > st.len) p = st.len;
    var ln: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i < p) : (i += 1) {
        if (bufByteAtState(st, i) == '\n') {
            ln += 1;
            start = i + 1;
        }
    }
    line.* = ln;
    col.* = p - start;
}
