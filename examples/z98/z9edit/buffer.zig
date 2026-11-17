// buffer.zig — z9edit headless core: gap buffer over one file.
//
// Z98 subset only. Direct imports (no `std` barrel); arena-backed; GUI-free.
// INTERNAL BYTES ARE ALWAYS CANONICAL LF. `bufLoad` folds every CRLF to LF and
// remembers the file's ending in `uses_crlf`; `bufInsert` folds CRLF in its
// input the same way; `bufSave` expands every canonical LF back to CRLF when
// `uses_crlf` is set. Pure CRLF and pure LF files therefore load -> save with
// no edit byte-identically. A mixed file is classified CRLF when it contains
// any CRLF and is saved with CRLF endings (documented choice); it is not
// byte-identical across a mixed-ending round trip. `bufLen` and every position
// the API returns/counts are canonical-LF byte offsets. Line/col indexes are
// 0-based; the GUI adds 1 for its status bar.
//
// Gap layout: bytes [0, gap_start) then the gap [gap_start, gap_end) then bytes
// [gap_end, cap). Content length is tracked in `len`; the gap size is
// cap - len. A move relocates the gap to the edit point; growth doubles the
// buffer and keeps the suffix at the end.

const arena_mod = @import("std_arena.zig");
const file_mod = @import("std_file.zig");
const mem_mod = @import("std_mem.zig");

pub const BufError = error{ ReadFailed, WriteFailed, OutOfMemory, TooLarge };

const MAX_BUF: usize = 16 * 1024 * 1024;
const MIN_CAP: usize = 64;
const MIN_GAP: usize = 64;
const MAX_LINE_CACHE: usize = 131072;

// The line-start map is keyed by `edit_gen`; it is rebuilt lazily on the first
// cached access after a mutation. `starts` is allocated at most once from the
// buffer arena and reused for every rebuild. Files with more than
// MAX_LINE_CACHE lines (or an allocation failure) set `fallback` and every
// cached accessor uses the naive scan instead.
const LineMap = struct {
    starts: [*]u32,
    count: usize,
    edit_gen: u64,
    valid: bool,
    fallback: bool,
    allocated: bool,
};

const BufState = struct {
    arena: *arena_mod.Arena,
    buf: [*]u8,
    cap: usize,
    gap_start: usize,
    gap_end: usize,
    len: usize,
    uses_crlf: bool,
    dirty: bool,
    edit_gen: u64,
    map: LineMap,
};

var g_dummy_u32: [1]u32 = undefined;

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
    st.edit_gen = 0;
    st.map.starts = @ptrCast([*]u32, &g_dummy_u32[0]);
    st.map.count = 0;
    st.map.edit_gen = 0;
    st.map.valid = false;
    st.map.fallback = false;
    st.map.allocated = false;
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

fn countCrlf(data: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i + 1 < data.len) : (i += 1) {
        if (data[i] == '\r' and data[i + 1] == '\n') n += 1;
    }
    return n;
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
    return e;
}

fn buildLineMap(st: *BufState) void {
    st.map.fallback = false;
    if (!st.map.allocated) {
        const raw = arena_mod.alloc(st.arena, MAX_LINE_CACHE * @sizeOf(u32)) catch {
            st.map.fallback = true;
            st.map.count = 0;
            st.map.edit_gen = st.edit_gen;
            st.map.valid = true;
            return;
        };
        st.map.starts = @ptrCast([*]u32, raw);
        st.map.allocated = true;
    }
    st.map.starts[0] = 0;
    var idx: usize = 1;
    var i: usize = 0;
    while (i < st.len) : (i += 1) {
        if (bufByteAtState(st, i) == '\n') {
            if (idx >= MAX_LINE_CACHE) {
                st.map.fallback = true;
                st.map.count = 0;
                st.map.edit_gen = st.edit_gen;
                st.map.valid = true;
                return;
            }
            st.map.starts[idx] = @intCast(u32, i + 1);
            idx += 1;
        }
    }
    st.map.count = idx;
    st.map.edit_gen = st.edit_gen;
    st.map.valid = true;
}

fn ensureLineMap(st: *BufState) void {
    if (st.map.valid and st.map.edit_gen == st.edit_gen) return;
    buildLineMap(st);
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
    const canon_len = data.len - countCrlf(data);
    var cap = canon_len + MIN_GAP;
    if (cap < MIN_CAP) cap = MIN_CAP;
    const wrap = try newGapBuffer(arena, cap);
    const st = state(wrap);
    var src: usize = 0;
    var dst: usize = 0;
    while (src < data.len) {
        // On CRLF, skip only the CR; the following LF is copied.
        if (data[src] == '\r' and src + 1 < data.len and data[src + 1] == '\n') {
            src += 1;
        }
        st.buf[dst] = data[src];
        dst += 1;
        src += 1;
    }
    st.len = dst;
    st.gap_start = dst;
    st.gap_end = cap;
    st.uses_crlf = hasCrlf(data);
    st.dirty = false;
    st.edit_gen += 1;
    return wrap;
}

// True only when the path opens as a directory. A failure to decide (including
// OOM) returns false so bufSave keeps its pre-existing behavior.
fn isDirectory(st: *BufState, path: []const u8) bool {
    var d = file_mod.openDir(st.arena, path) catch {
        return false;
    };
    file_mod.closeDir(&d);
    return true;
}

pub fn bufSave(b: *GapBuffer, path: []const u8) BufError!void {
    const st = state(b);
    var out_len = st.len;
    if (st.uses_crlf) {
        var i: usize = 0;
        while (i < st.len) : (i += 1) {
            if (bufByteAtState(st, i) == '\n' and
                (i == 0 or bufByteAtState(st, i - 1) != '\r')) out_len += 1;
        }
    }
    const tmp = try allocBytes(st.arena, out_len + 1);
    var src: usize = 0;
    var dst: usize = 0;
    while (src < st.len) : (src += 1) {
        const c = bufByteAtState(st, src);
        if (st.uses_crlf and c == '\n' and
            (src == 0 or bufByteAtState(st, src - 1) != '\r')) {
            tmp[dst] = '\r';
            dst += 1;
        }
        tmp[dst] = c;
        dst += 1;
    }

    // Save atomically: write <path>.z9tmp in the same directory, flush+close,
    // then rename over the target. A failed write never touches the original.
    // On Windows (MoveFileA does not replace) a completed temp is swapped in
    // via a <path>.z9bak backup, so a failed replace restores the original.
    const tmp_path = try allocBytes(st.arena, path.len + 6);
    var suffix: []const u8 = ".z9tmp";
    var pi: usize = 0;
    while (pi < path.len) : (pi += 1) tmp_path[pi] = path[pi];
    var si: usize = 0;
    while (si < 6) : (si += 1) tmp_path[pi + si] = suffix[si];
    const tmp_s = tmp_path[0 .. path.len + 6];

    file_mod.writeAll(tmp_s, tmp[0..dst]) catch |e| {
        _ = file_mod.remove(tmp_s) catch {};
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.WriteFailed;
    };

    var renamed = true;
    file_mod.rename(tmp_s, path) catch {
        renamed = false;
    };
    if (!renamed) {
        if (@isWindows() and file_mod.exists(path)) {
            // Never replace a directory with a file. If openDir cannot decide,
            // keep the pre-existing behavior.
            if (isDirectory(st, path)) {
                _ = file_mod.remove(tmp_s) catch {};
                return error.WriteFailed;
            }
            const bak_path = try allocBytes(st.arena, path.len + 6);
            var bsuffix: []const u8 = ".z9bak";
            pi = 0;
            while (pi < path.len) : (pi += 1) bak_path[pi] = path[pi];
            si = 0;
            while (si < 6) : (si += 1) bak_path[pi + si] = bsuffix[si];
            const bak_s = bak_path[0 .. path.len + 6];

            // A stale backup (crash after swap, or a prior failed restore) must
            // not block every future save: the live target is authoritative.
            if (file_mod.exists(bak_s)) {
                file_mod.remove(bak_s) catch {
                    _ = file_mod.remove(tmp_s) catch {};
                    return error.WriteFailed;
                };
            }

            var moved_aside = true;
            file_mod.rename(path, bak_s) catch {
                moved_aside = false;
            };
            if (!moved_aside) {
                _ = file_mod.remove(tmp_s) catch {};
                return error.WriteFailed;
            }
            var replaced = true;
            file_mod.rename(tmp_s, path) catch {
                replaced = false;
            };
            if (!replaced) {
                // Restore the original; if even that fails, leave the backup
                // in place (the data is not deleted).
                file_mod.rename(bak_s, path) catch {};
                _ = file_mod.remove(tmp_s) catch {};
                return error.WriteFailed;
            }
            _ = file_mod.remove(bak_s) catch {};
        } else {
            _ = file_mod.remove(tmp_s) catch {};
            return error.WriteFailed;
        }
    }
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

pub fn bufEditGen(b: *GapBuffer) u64 {
    return state(b).edit_gen;
}

fn insertCanonical(st: *BufState, at: usize, bytes: []const u8) BufError!void {
    try ensureGap(st, bytes.len);
    moveGapTo(st, at);
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        st.buf[st.gap_start + i] = bytes[i];
    }
    st.gap_start += bytes.len;
    st.len += bytes.len;
    st.dirty = true;
    st.edit_gen += 1;
}

pub fn bufInsert(b: *GapBuffer, pos: usize, bytes: []const u8) BufError!void {
    const st = state(b);
    var at = pos;
    if (at > st.len) at = st.len;

    // Canonicalize both directions: every CRLF in the input becomes one LF.
    // Internal bytes stay LF regardless of the file's stored ending.
    const cr = countCrlf(bytes);
    if (cr == 0) {
        try insertCanonical(st, at, bytes);
        return;
    }
    const canon_len = bytes.len - cr;
    if (st.len + canon_len > MAX_BUF) return error.TooLarge;
    const tmp = try allocBytes(st.arena, canon_len + 1);
    var src: usize = 0;
    var dst: usize = 0;
    while (src < bytes.len) {
        // On CRLF, skip only the CR; the following LF is copied.
        if (bytes[src] == '\r' and src + 1 < bytes.len and bytes[src + 1] == '\n') {
            src += 1;
        }
        tmp[dst] = bytes[src];
        dst += 1;
        src += 1;
    }
    try insertCanonical(st, at, tmp[0..dst]);
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
    st.edit_gen += 1;
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
    if (pos < st.gap_start) {
        var take = n;
        if (take > st.gap_start - pos) take = st.gap_start - pos;
        if (take > 0) mem_mod.copyU8(out.ptr, st.buf + pos, take);
        if (n > take) mem_mod.copyU8(out.ptr + take, st.buf + pos + take + gs, n - take);
    } else {
        mem_mod.copyU8(out.ptr, st.buf + pos + gs, n);
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

pub fn bufLineCountCached(b: *GapBuffer) usize {
    const st = state(b);
    ensureLineMap(st);
    if (st.map.fallback) return lineCountOf(st);
    return st.map.count;
}

pub fn bufLineStartCached(b: *GapBuffer, line: usize) usize {
    const st = state(b);
    ensureLineMap(st);
    if (st.map.fallback) return lineStartOf(st, line);
    if (line >= st.map.count) return st.len;
    return @intCast(usize, st.map.starts[line]);
}

pub fn bufLineRangeCached(b: *GapBuffer, line: usize, start: *usize, len: *usize) void {
    const st = state(b);
    ensureLineMap(st);
    if (st.map.fallback) {
        bufLineRange(b, line, start, len);
        return;
    }
    if (line >= st.map.count) {
        start.* = st.len;
        len.* = 0;
        return;
    }
    const s = @intCast(usize, st.map.starts[line]);
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
