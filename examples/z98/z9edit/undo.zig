// undo.zig — z9edit headless core: insert/delete undo stack (no redo).
//
// Z98 subset only, GUI-free. `undoRecordInsert` records that bytes were inserted
// (its inverse deletes them); `undoRecordDelete` records bytes that were removed
// (its inverse reinserts the caller-supplied copy). `undoApply` pops the top
// record, applies its inverse to the buffer, and returns false only when the
// stack is empty. Records are arena-backed and never freed.

const arena_mod = @import("std_arena.zig");
const mem_mod = @import("std_mem.zig");
const buffer = @import("buffer.zig");

const Kind = enum(u8) { insert, delete };

const Record = struct {
    kind: Kind,
    pos: usize,
    blen: usize,
    bytes: [*]u8,
    next: ?*Record,
};

const UndoState = struct {
    arena: *arena_mod.Arena,
    top: ?*Record,
    count: usize,
};

pub const Undo = struct { opaque: *UndoState };

// Undo init has no error union by contract. If the arena cannot even back the
// small state wrapper, fall back to this static empty stack (the caller cannot
// record into it meaningfully, but the API stays total).
var g_fallback_state: UndoState = undefined;
var g_fallback_wrap: Undo = undefined;

fn fallback(arena: *arena_mod.Arena) *Undo {
    g_fallback_state.arena = arena;
    g_fallback_state.top = null;
    g_fallback_state.count = 0;
    g_fallback_wrap.opaque = &g_fallback_state;
    return &g_fallback_wrap;
}

pub fn undoInit(arena: *arena_mod.Arena) *Undo {
    const raw_wrap = arena_mod.alloc(arena, @sizeOf(Undo)) catch {
        return fallback(arena);
    };
    const wrap: *Undo = @ptrCast(*Undo, raw_wrap);
    const raw_state = arena_mod.alloc(arena, @sizeOf(UndoState)) catch {
        return fallback(arena);
    };
    const st: *UndoState = @ptrCast(*UndoState, raw_state);
    st.arena = arena;
    st.top = null;
    st.count = 0;
    wrap.opaque = st;
    return wrap;
}

var g_dummy_byte: [1]u8 = undefined;

fn push(u: *Undo, kind: Kind, pos: usize, bytes: []const u8) buffer.BufError!void {
    const st = u.opaque;
    const raw_rec = arena_mod.alloc(st.arena, @sizeOf(Record)) catch {
        return error.OutOfMemory;
    };
    const rec: *Record = @ptrCast(*Record, raw_rec);
    var copy: [*]u8 = @ptrCast([*]u8, &g_dummy_byte[0]);
    if (bytes.len > 0) {
        copy = arena_mod.alloc(st.arena, bytes.len) catch {
            return error.OutOfMemory;
        };
        mem_mod.copyU8(copy, bytes.ptr, bytes.len);
    }
    rec.kind = kind;
    rec.pos = pos;
    rec.blen = bytes.len;
    rec.bytes = copy;
    rec.next = st.top;
    st.top = rec;
    st.count += 1;
}

pub fn undoRecordInsert(u: *Undo, pos: usize, bytes: []const u8) buffer.BufError!void {
    try push(u, .insert, pos, bytes);
}

pub fn undoRecordDelete(u: *Undo, pos: usize, bytes: []const u8) buffer.BufError!void {
    try push(u, .delete, pos, bytes);
}

pub fn undoApply(u: *Undo, b: *buffer.GapBuffer) bool {
    const st = u.opaque;
    if (st.top) |r| {
        st.top = r.next;
        if (st.count > 0) st.count -= 1;
        if (r.kind == .insert) {
            buffer.bufDelete(b, r.pos, r.blen) catch {
                return false;
            };
            return true;
        }
        buffer.bufInsert(b, r.pos, r.bytes[0..r.blen]) catch {
            return false;
        };
        return true;
    }
    return false;
}
