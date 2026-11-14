// idents.zig — z9edit headless core: declared-identifier set.
//
// Z98 subset only, GUI-free. Scans the file once (load / save / 2 s idle in the
// shell) and records the name that follows a `const`, `var`, or `fn` keyword.
// The scan runs through the real line lexer, so `const` in a comment or string
// cannot seed a declaration. Names are copied into the caller's arena, so the
// set stays valid even after the buffer is edited again.

const arena_mod = @import("std_arena.zig");
const str_mod = @import("std_str.zig");
const mem_mod = @import("std_mem.zig");
const buffer = @import("buffer.zig");
const lexer = @import("lexer.zig");

const MAX_IDENTS: usize = 16384;
const MAX_TOKENS: usize = 256;

const IdentState = struct {
    names: [*][]const u8,
    count: usize,
    cap: usize,
};

pub const IdentSet = struct { opaque: *IdentState };

fn allocBytes(arena: *arena_mod.Arena, n: usize) buffer.BufError![*]u8 {
    return arena_mod.alloc(arena, n) catch |e| {
        return error.OutOfMemory;
    };
}

fn record(arena: *arena_mod.Arena, set: *IdentState, name: []const u8) buffer.BufError!void {
    if (name.len == 0 or set.count >= set.cap) return;
    const raw = try allocBytes(arena, name.len);
    mem_mod.copyU8(raw, name.ptr, name.len);
    set.names[set.count] = raw[0..name.len];
    set.count += 1;
}

fn isDeclKeyword(t: lexer.Token, line: []const u8) bool {
    if (t.kind != .keyword) return false;
    const s = line[t.start..t.start + t.len];
    return str_mod.eql(s, "const") or str_mod.eql(s, "var") or str_mod.eql(s, "fn");
}

pub fn identScan(arena: *arena_mod.Arena, b: *buffer.GapBuffer) buffer.BufError!*IdentSet {
    const raw_wrap = arena_mod.alloc(arena, @sizeOf(IdentSet)) catch |e| {
        return error.OutOfMemory;
    };
    const wrap: *IdentSet = @ptrCast(*IdentSet, raw_wrap);
    const raw_state = arena_mod.alloc(arena, @sizeOf(IdentState)) catch |e| {
        return error.OutOfMemory;
    };
    const st: *IdentState = @ptrCast(*IdentState, raw_state);
    const raw_names = arena_mod.alloc(arena, MAX_IDENTS * @sizeOf([]const u8)) catch |e| {
        return error.OutOfMemory;
    };
    st.names = @ptrCast([*][]const u8, raw_names);
    st.count = 0;
    st.cap = MAX_IDENTS;
    wrap.opaque = st;

    const len = buffer.bufLen(b);
    const raw_text = try allocBytes(arena, len + 1);
    _ = buffer.bufCopy(b, 0, len, raw_text[0..len]);
    const text = raw_text[0..len];

    var tokens: [MAX_TOKENS]lexer.Token = undefined;
    var state = lexer.lexInitState();
    var line_start: usize = 0;
    var i: usize = 0;
    while (i <= text.len) : (i += 1) {
        if (i != text.len and text[i] != '\n') continue;
        var e = i;
        if (e > line_start and text[e - 1] == '\r') e -= 1;
        const line = text[line_start..e];
        const nt = lexer.lexLine(&state, line, tokens[0..]);
        var k: usize = 0;
        while (k < nt) : (k += 1) {
            if (!isDeclKeyword(tokens[k], line)) continue;
            var j = k + 1;
            while (j < nt and tokens[j].kind == .plain) : (j += 1) {}
            if (j < nt and tokens[j].kind == .ident) {
                const nm = tokens[j];
                const name = line[nm.start..nm.start + nm.len];
                try record(arena, st, name);
            }
        }
        line_start = i + 1;
    }
    return wrap;
}

pub fn identHas(set: *IdentSet, name: []const u8) bool {
    const st = set.opaque;
    var i: usize = 0;
    while (i < st.count) : (i += 1) {
        if (str_mod.eql(st.names[i], name)) return true;
    }
    return false;
}
