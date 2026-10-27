// ui.zig — z9edit GUI shell on std_gfx (Phase 2 P4-M3).
//
// Z98 subset only; direct imports (no std barrel). This module owns the editor
// view state (caret, selection, scroll, lexer carry, ident cache) and wires the
// headless core to std_gfx. All coordinates in cells; the last row is the
// status bar. The shell never leaks a raw vtable or a Win32 handle.

const gfx = @import("std_gfx.zig");
const arena_mod = @import("std_arena.zig");
const time_mod = @import("std_time.zig");
const buffer = @import("buffer.zig");
const lexer = @import("lexer.zig");
const idents = @import("idents.zig");
const match = @import("match.zig");
const undo = @import("undo.zig");
const errtab = @import("errtab.zig");

pub const UiError = error{ OutOfMemory, SaveFailed };

const TAB_W: u32 = 8;
const TITLE_MAX: usize = 200;
const LINE_MAX: usize = 256;
const TOK_MAX: usize = 256;
const STATUS_MAX: usize = 220;
const IDLE_MS: u32 = 2000;

const COL_BG: gfx.Color = 0;
const COL_FG: gfx.Color = 2;
const COL_COMMENT: gfx.Color = 3;
const COL_DECL: gfx.Color = 5;
const COL_NUMBER: gfx.Color = 6;
const COL_STATUS_BG: gfx.Color = 7;
const COL_KEYWORD: gfx.Color = 9;
const COL_BUILTIN: gfx.Color = 10;
const COL_STRING: gfx.Color = 11;
const COL_TYPE: gfx.Color = 12;
const COL_SEL: gfx.Color = 13;
const COL_WARN: gfx.Color = 14;
const COL_BRIGHT: gfx.Color = 15;

const UiImpl = struct {
    arena: *arena_mod.Arena,
    g: *gfx.Gfx,
    b: *buffer.GapBuffer,
    u: *undo.Undo,
    ids: *idents.IdentSet,
    ids_arena: arena_mod.Arena,
    path: []const u8,
    save_path: []const u8,
    cols: u32,
    rows: u32,
    gutter: u32,
    scroll: usize,
    caret: usize,
    anchor: usize,
    dragging: bool,
    copy: [*]u8,
    copy_len: usize,
    lex: lexer.LexState,
    lex_line: usize,
    last_edit_ms: u32,
    edit_pending: bool,
    title: [TITLE_MAX]u8,
    title_len: usize,
    err: u8, // 0 none, 1 OutOfMemory, 2 SaveFailed
};

// Opaque to main.zig: one pointer to the private state.
pub const UiState = struct { opaque: *UiImpl };

var g_dummy: [1]u8 = undefined;

fn allocBytes(arena: *arena_mod.Arena, n: usize) UiError![*]u8 {
    return arena_mod.alloc(arena, n) catch {
        return error.OutOfMemory;
    };
}

fn basenameOf(path: []const u8) []const u8 {
    var i: usize = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') return path[i + 1 ..];
    }
    return path;
}

fn putBytes(out: []u8, pos_in: usize, s: []const u8) usize {
    var pos = pos_in;
    var i: usize = 0;
    while (i < s.len and pos < out.len) : (i += 1) {
        out[pos] = s[i];
        pos += 1;
    }
    return pos;
}

fn putU32(out: []u8, pos_in: usize, v_in: u32) usize {
    var tmp: [12]u8 = undefined;
    var n: usize = 0;
    var v = v_in;
    if (v == 0) {
        tmp[0] = '0';
        n = 1;
    } else {
        while (v > 0) : (v = v / 10) {
            tmp[n] = @intCast(u8, 48 + (v % 10));
            n += 1;
        }
    }
    var pos = pos_in;
    while (n > 0) {
        n -= 1;
        if (pos < out.len) out[pos] = tmp[n];
        pos += 1;
    }
    return pos;
}

fn putU32Pad4(out: []u8, pos_in: usize, v_in: u32) usize {
    var tmp: [4]u8 = [4]u8{ '0', '0', '0', '0' };
    var v = v_in;
    var i: usize = 4;
    while (i > 0 and v > 0) {
        i -= 1;
        tmp[i] = @intCast(u8, 48 + (v % 10));
        v = v / 10;
    }
    var pos = pos_in;
    i = 0;
    while (i < 4 and pos < out.len) : (i += 1) {
        out[pos] = tmp[i];
        pos += 1;
    }
    return pos;
}

fn digitsOf(v_in: usize) u32 {
    var v = v_in;
    var n: u32 = 1;
    while (v >= 10) : (v = v / 10) n += 1;
    return n;
}

fn gutterWidth(line_count: usize) u32 {
    return digitsOf(line_count) + 1;
}

fn isBracket(c: u8) bool {
    return c == '(' or c == ')' or c == '[' or c == ']' or c == '{' or c == '}';
}

fn canonLen(bytes: []const u8) usize {
    var n: usize = bytes.len;
    var i: usize = 0;
    while (i + 1 < bytes.len) : (i += 1) {
        if (bytes[i] == '\r' and bytes[i + 1] == '\n') n -= 1;
    }
    return n;
}

fn selStart(st: *UiImpl) usize {
    if (st.anchor < st.caret) return st.anchor;
    return st.caret;
}

fn selEnd(st: *UiImpl) usize {
    if (st.anchor < st.caret) return st.caret;
    return st.anchor;
}

fn hasSelection(st: *UiImpl) bool {
    return st.anchor != st.caret;
}

fn setErr(st: *UiImpl, code: u8) void {
    if (st.err == 0) st.err = code;
}

fn refreshTitle(st: *UiImpl) void {
    var p: usize = 0;
    p = putBytes(st.title[0..], p, "z9edit \xe2\x80\x94 ");
    if (buffer.bufDirty(st.b)) {
        p = putBytes(st.title[0..], p, "*");
    }
    p = putBytes(st.title[0..], p, basenameOf(st.path));
    st.title_len = p;
    _ = gfx.gfxSetTitle(st.g, st.title[0..p]);
}

fn markEdited(st: *UiImpl) void {
    st.last_edit_ms = time_mod.ticksMs();
    st.edit_pending = true;
    refreshTitle(st);
}

fn rebuildIdents(st: *UiImpl) void {
    arena_mod.reset(&st.ids_arena);
    st.ids = idents.identScan(&st.ids_arena, st.b) catch {
        setErr(st, 1);
        return;
    };
    st.edit_pending = false;
}

fn lineText(st: *UiImpl, line: usize, out: []u8) []const u8 {
    var start: usize = 0;
    var len: usize = 0;
    buffer.bufLineRange(st.b, line, &start, &len);
    var n = len;
    if (n > out.len) n = out.len;
    if (n == 0) return out[0..0];
    _ = buffer.bufCopy(st.b, start, n, out[0..n]);
    return out[0..n];
}

fn lineByteLen(st: *UiImpl, line: usize) usize {
    var start: usize = 0;
    var len: usize = 0;
    buffer.bufLineRange(st.b, line, &start, &len);
    return len;
}

fn caretLineCol(st: *UiImpl, line: *usize, col: *usize) void {
    buffer.bufLineColOf(st.b, st.caret, line, col);
}

fn ensureVisible(st: *UiImpl) void {
    var line: usize = 0;
    var col: usize = 0;
    caretLineCol(st, &line, &col);
    const rows = st.rows;
    var content: usize = 0;
    if (rows > 1) content = @intCast(usize, rows - 1);
    if (content == 0) {
        st.scroll = 0;
        return;
    }
    if (line < st.scroll) st.scroll = line;
    if (line >= st.scroll + content) st.scroll = line - content + 1;
}

fn clampScroll(st: *UiImpl) void {
    const lc = buffer.bufLineCount(st.b);
    var content: usize = 0;
    if (st.rows > 1) content = @intCast(usize, st.rows - 1);
    var max: usize = 0;
    if (lc > content) max = lc - content;
    if (st.scroll > max) st.scroll = max;
}

fn setCaret(st: *UiImpl, pos_in: usize) void {
    var pos = pos_in;
    const len = buffer.bufLen(st.b);
    if (pos > len) pos = len;
    st.caret = pos;
}

fn moveTo(st: *UiImpl, pos_in: usize, extend: bool) void {
    if (extend) {
        if (!hasSelection(st)) st.anchor = st.caret;
    } else {
        st.anchor = pos_in;
    }
    setCaret(st, pos_in);
    ensureVisible(st);
}

fn lineStartOf(st: *UiImpl, line: usize) usize {
    return buffer.bufOffsetOf(st.b, line, 0);
}

fn lineEndOf(st: *UiImpl, line: usize) usize {
    var start: usize = 0;
    var len: usize = 0;
    buffer.bufLineRange(st.b, line, &start, &len);
    return start + len;
}

fn moveLeft(st: *UiImpl, extend: bool) void {
    var p = st.caret;
    if (p > 0) p -= 1;
    moveTo(st, p, extend);
}

fn moveRight(st: *UiImpl, extend: bool) void {
    var p = st.caret;
    const len = buffer.bufLen(st.b);
    if (p < len) p += 1;
    moveTo(st, p, extend);
}

fn moveVertical(st: *UiImpl, delta_up: i32, extend: bool) void {
    var line: usize = 0;
    var col: usize = 0;
    caretLineCol(st, &line, &col);
    const lc = buffer.bufLineCount(st.b);
    var target = line;
    if (delta_up > 0) {
        var d: usize = @intCast(usize, delta_up);
        while (d > 0 and target > 0) : (d -= 1) target -= 1;
    } else {
        var d: usize = @intCast(usize, 0 - delta_up);
        while (d > 0 and target + 1 < lc) : (d -= 1) target += 1;
    }
    const ll = lineByteLen(st, target);
    var c = col;
    if (c > ll) c = ll;
    moveTo(st, buffer.bufOffsetOf(st.b, target, c), extend);
}

fn movePage(st: *UiImpl, up: bool, extend: bool) void {
    var page: usize = 1;
    if (st.rows > 1) page = @intCast(usize, st.rows - 1);
    var line: usize = 0;
    var col: usize = 0;
    caretLineCol(st, &line, &col);
    const lc = buffer.bufLineCount(st.b);
    var target = line;
    if (up) {
        if (target > page) target -= page else target = 0;
    } else {
        target += page;
        if (target >= lc) target = lc - 1;
    }
    const ll = lineByteLen(st, target);
    var c = col;
    if (c > ll) c = ll;
    moveTo(st, buffer.bufOffsetOf(st.b, target, c), extend);
}

fn moveHome(st: *UiImpl, extend: bool) void {
    var line: usize = 0;
    var col: usize = 0;
    caretLineCol(st, &line, &col);
    moveTo(st, lineStartOf(st, line), extend);
}

fn moveEnd(st: *UiImpl, extend: bool) void {
    var line: usize = 0;
    var col: usize = 0;
    caretLineCol(st, &line, &col);
    moveTo(st, lineEndOf(st, line), extend);
}

fn deleteRange(st: *UiImpl, pos: usize, count: usize) UiError!void {
    if (count == 0) return;
    const raw = try allocBytes(st.arena, count);
    const n = buffer.bufCopy(st.b, pos, count, raw[0..count]);
    if (n == 0) return;
    buffer.bufDelete(st.b, pos, n) catch {
        return error.OutOfMemory;
    };
    undo.undoRecordDelete(st.u, pos, raw[0..n]) catch {
        return error.OutOfMemory;
    };
    if (st.caret >= pos and st.caret <= pos + n) {
        st.caret = pos;
    } else if (st.caret > pos + n) {
        st.caret -= n;
    }
    if (st.anchor >= pos and st.anchor <= pos + n) {
        st.anchor = pos;
    } else if (st.anchor > pos + n) {
        st.anchor -= n;
    }
    markEdited(st);
}

fn replaceSelection(st: *UiImpl) UiError!void {
    if (!hasSelection(st)) return;
    const s = selStart(st);
    const e = selEnd(st);
    try deleteRange(st, s, e - s);
    st.caret = s;
    st.anchor = s;
}

fn insertText(st: *UiImpl, text: []const u8) UiError!void {
    try replaceSelection(st);
    buffer.bufInsert(st.b, st.caret, text) catch {
        return error.OutOfMemory;
    };
    undo.undoRecordInsert(st.u, st.caret, text) catch {
        return error.OutOfMemory;
    };
    st.caret += canonLen(text);
    st.anchor = st.caret;
    markEdited(st);
    ensureVisible(st);
}

fn copySelection(st: *UiImpl) UiError!bool {
    if (!hasSelection(st)) return false;
    const s = selStart(st);
    const n = selEnd(st) - s;
    if (n == 0) return false;
    const raw = try allocBytes(st.arena, n);
    const got = buffer.bufCopy(st.b, s, n, raw[0..n]);
    if (got == 0) return false;
    st.copy = raw;
    st.copy_len = got;
    _ = gfx.gfxClipboardSet(st.g, raw[0..got]);
    return true;
}

fn pasteClipboard(st: *UiImpl) UiError!void {
    var src: []const u8 = st.copy[0..st.copy_len];
    if (gfx.gfxClipboardGet(st.g, st.arena)) |cl| {
        if (cl.len > 0) src = cl;
    }
    if (src.len == 0) return;
    try insertText(st, src);
}

fn doUndo(st: *UiImpl) void {
    if (!undo.undoApply(st.u, st.b)) return;
    const len = buffer.bufLen(st.b);
    if (st.caret > len) st.caret = len;
    st.anchor = st.caret;
    markEdited(st);
    ensureVisible(st);
}

fn doSave(st: *UiImpl) void {
    buffer.bufSave(st.b, st.save_path) catch {
        setErr(st, 2);
        return;
    };
    rebuildIdents(st);
    refreshTitle(st);
}

fn handleCommand(st: *UiImpl, c_in: u8) bool {
    var c = c_in;
    if (c >= 'A' and c <= 'Z') c = @intCast(u8, c + 32);
    if (c == 'q') return false;
    if (c == 's') {
        doSave(st);
    } else if (c == 'z') {
        doUndo(st);
    } else if (c == 'c') {
        _ = copySelection(st) catch {
            setErr(st, 1);
        };
    } else if (c == 'x') {
        const ok = copySelection(st) catch {
            setErr(st, 1);
            return true;
        };
        if (ok) {
            deleteRange(st, selStart(st), selEnd(st) - selStart(st)) catch {
                setErr(st, 1);
            };
        }
    } else if (c == 'v') {
        pasteClipboard(st) catch {
            setErr(st, 1);
        };
    } else if (c == 'a') {
        st.anchor = 0;
        st.caret = buffer.bufLen(st.b);
        ensureVisible(st);
    }
    return true;
}

fn handleKey(st: *UiImpl, ev: *const gfx.Event) bool {
    const ctrl = (ev.mods & 2) != 0;
    const shift = (ev.mods & 1) != 0;
    if (ctrl) {
        if (ev.ch != 0) return handleCommand(st, ev.ch);
        return true;
    }
    if (ev.code == 0x25) {
        moveLeft(st, shift);
        return true;
    }
    if (ev.code == 0x27) {
        moveRight(st, shift);
        return true;
    }
    if (ev.code == 0x26) {
        moveVertical(st, 1, shift);
        return true;
    }
    if (ev.code == 0x28) {
        moveVertical(st, -1, shift);
        return true;
    }
    if (ev.code == 0x21) {
        movePage(st, true, shift);
        return true;
    }
    if (ev.code == 0x22) {
        movePage(st, false, shift);
        return true;
    }
    if (ev.code == 0x24) {
        moveHome(st, shift);
        return true;
    }
    if (ev.code == 0x23) {
        moveEnd(st, shift);
        return true;
    }
    if (ev.ch == 0) return true;
    if (ev.ch == 8) {
        if (hasSelection(st)) {
            replaceSelection(st) catch {
                setErr(st, 1);
            };
        } else if (st.caret > 0) {
            deleteRange(st, st.caret - 1, 1) catch {
                setErr(st, 1);
            };
        }
        return true;
    }
    if (ev.ch == 127) {
        if (hasSelection(st)) {
            replaceSelection(st) catch {
                setErr(st, 1);
            };
        } else {
            const len = buffer.bufLen(st.b);
            if (st.caret < len) {
                deleteRange(st, st.caret, 1) catch {
                    setErr(st, 1);
                };
            }
        }
        return true;
    }
    if (ev.ch == 9) {
        insertText(st, "\t") catch {
            setErr(st, 1);
        };
        return true;
    }
    if (ev.ch == 13) {
        insertText(st, "\n") catch {
            setErr(st, 1);
        };
        return true;
    }
    if (ev.ch >= 32 and ev.ch <= 126) {
        var one: [1]u8 = undefined;
        one[0] = ev.ch;
        insertText(st, one[0..1]) catch {
            setErr(st, 1);
        };
    }
    return true;
}

fn pointToCaret(st: *UiImpl, x: u32, y: u32) void {
    var content: u32 = 0;
    if (st.rows > 1) content = st.rows - 1;
    if (y >= content) return;
    const lc = buffer.bufLineCount(st.b);
    var line = st.scroll + @intCast(usize, y);
    if (line >= lc) line = lc - 1;
    var col: usize = 0;
    if (x > st.gutter) col = @intCast(usize, x - st.gutter);
    setCaret(st, buffer.bufOffsetOf(st.b, line, col));
    ensureVisible(st);
}

fn handleMouse(st: *UiImpl, ev: *const gfx.Event) void {
    if (ev.kind == .mouse_down) {
        pointToCaret(st, ev.x, ev.y);
        st.anchor = st.caret;
        st.dragging = true;
        return;
    }
    if (ev.kind == .mouse_move) {
        if (st.dragging) pointToCaret(st, ev.x, ev.y);
        return;
    }
    if (ev.kind == .mouse_up) {
        st.dragging = false;
        return;
    }
}

pub fn uiInit(arena: *arena_mod.Arena, g: *gfx.Gfx, b: *buffer.GapBuffer, path: []const u8) UiError!*UiState {
    const raw_state = try allocBytes(arena, @sizeOf(UiImpl));
    const st: *UiImpl = @ptrCast(*UiImpl, raw_state);
    st.arena = arena;
    st.g = g;
    st.b = b;
    st.u = undo.undoInit(arena);
    st.path = path;
    st.save_path = path;
    st.cols = 80;
    st.rows = 25;
    st.gutter = gutterWidth(buffer.bufLineCount(b));
    st.scroll = 0;
    st.caret = 0;
    st.anchor = 0;
    st.dragging = false;
    st.copy = @ptrCast([*]u8, &g_dummy[0]);
    st.copy_len = 0;
    st.lex = lexer.lexInitState();
    st.lex_line = 0;
    st.last_edit_ms = time_mod.ticksMs();
    st.edit_pending = false;
    st.title_len = 0;
    st.err = 0;
    const id_cap = buffer.bufLen(b) + 768 * 1024;
    const raw_ids = try allocBytes(arena, id_cap);
    st.ids_arena = arena_mod.init(raw_ids[0..id_cap]);
    arena_mod.reset(&st.ids_arena);
    st.ids = idents.identScan(&st.ids_arena, b) catch {
        return error.OutOfMemory;
    };
    refreshTitle(st);
    const raw_wrap = try allocBytes(arena, @sizeOf(UiState));
    const wrap: *UiState = @ptrCast(*UiState, raw_wrap);
    wrap.opaque = st;
    return wrap;
}

// Extra (additive) helper: --smoke saves to a different path than it loaded.
pub fn uiSetSavePath(st: *UiState, path: []const u8) void {
    st.opaque.save_path = path;
}

pub fn uiStep(stw: *UiState, ev: *const gfx.Event) bool {
    const st = stw.opaque;
    if (ev.kind == .close) return false;
    if (ev.kind == .key_down) return handleKey(st, ev);
    if (ev.kind == .mouse_down or ev.kind == .mouse_move or ev.kind == .mouse_up) {
        handleMouse(st, ev);
        return true;
    }
    if (ev.kind == .wheel) {
        var delta: i32 = ev.wheel;
        if (delta < 0) {
            var d: usize = @intCast(usize, 0 - delta);
            while (d > 0 and st.scroll > 0) : (d -= 1) st.scroll -= 1;
        } else {
            var d: usize = @intCast(usize, delta);
            while (d > 0) : (d -= 1) st.scroll += 1;
        }
        clampScroll(st);
        return true;
    }
    return true;
}

fn syncLex(st: *UiImpl, top: usize) void {
    if (top < st.lex_line or (top - st.lex_line) > 512) {
        st.lex = lexer.lexInitState();
        st.lex_line = 0;
    }
    var line_buf: [LINE_MAX]u8 = undefined;
    var toks: [TOK_MAX]lexer.Token = undefined;
    while (st.lex_line < top) {
        const line = lineText(st, st.lex_line, line_buf[0..]);
        _ = lexer.lexLine(&st.lex, line, toks[0..]);
        st.lex_line += 1;
    }
}

fn tokenColor(kind: lexer.TokKind, declared: bool) gfx.Color {
    if (kind == .keyword) return COL_KEYWORD;
    if (kind == .builtin) return COL_BUILTIN;
    if (kind == .errcode) return COL_WARN;
    if (kind == .string) return COL_STRING;
    if (kind == .comment) return COL_COMMENT;
    if (kind == .number) return COL_NUMBER;
    if (kind == .type_name) return COL_TYPE;
    if (kind == .ident) {
        if (declared) return COL_DECL;
        return COL_FG;
    }
    return COL_FG;
}

fn paintGutter(st: *UiImpl, row: u32, number: usize) void {
    var nb: [12]u8 = undefined;
    var p: usize = 0;
    p = putU32(nb[0..], p, @intCast(u32, number));
    const digits: u32 = @intCast(u32, p);
    var x: u32 = 0;
    if (st.gutter > digits + 1) x = st.gutter - digits - 1;
    _ = gfx.gfxDrawText(st.g, x, row, nb[0..p], COL_COMMENT, COL_BG);
}

fn paintTokens(st: *UiImpl, row: u32, line_start: usize, line: []const u8,
    toks: []const lexer.Token, nt: usize, br1: usize, br2: usize, have_br: bool) void {
    const sel_on = hasSelection(st);
    const ss = selStart(st);
    const se = selEnd(st);
    var maxcol: u32 = 0;
    if (st.cols > st.gutter) maxcol = st.cols - st.gutter;
    var screen_col: u32 = 0;
    var ti: usize = 0;
    while (ti < nt and screen_col < maxcol) : (ti += 1) {
        const tok = toks[ti];
        var declared = false;
        if (tok.kind == .ident) {
            const ts = @intCast(usize, tok.start);
            const te = ts + @intCast(usize, tok.len);
            if (te <= line.len) declared = idents.identHas(st.ids, line[ts..te]);
        }
        var bi: usize = 0;
        while (bi < @intCast(usize, tok.len) and screen_col < maxcol) : (bi += 1) {
            const idx = @intCast(usize, tok.start) + bi;
            if (idx >= line.len) break;
            const c = line[idx];
            const abs = line_start + idx;
            var fg = tokenColor(tok.kind, declared);
            var bg = COL_BG;
            if (sel_on and abs >= ss and abs < se) {
                fg = COL_BRIGHT;
                bg = COL_SEL;
            } else if (have_br and (abs == br1 or abs == br2)) {
                fg = COL_BG;
                bg = COL_SEL;
            }
            const x = st.gutter + screen_col;
            if (c == '\t') {
                var next: u32 = (screen_col / TAB_W + 1) * TAB_W;
                if (next > maxcol) next = maxcol;
                while (screen_col < next) : (screen_col += 1) {
                    _ = gfx.gfxDrawText(st.g, st.gutter + screen_col, row, " ", fg, bg);
                }
            } else {
                var one: [1]u8 = undefined;
                one[0] = c;
                _ = gfx.gfxDrawText(st.g, x, row, one[0..1], fg, bg);
                screen_col += 1;
            }
        }
    }
}

fn displayColOf(line: []const u8, byte_col: usize) u32 {
    var d: u32 = 0;
    var i: usize = 0;
    while (i < byte_col and i < line.len) : (i += 1) {
        if (line[i] == '\t') {
            d = (d / TAB_W + 1) * TAB_W;
        } else {
            d += 1;
        }
    }
    return d;
}

fn paintCursor(st: *UiImpl, caret_line: usize, caret_col: usize) void {
    if (st.rows < 2) return;
    if (caret_line < st.scroll) return;
    const row = caret_line - st.scroll;
    if (row >= @intCast(usize, st.rows - 1)) return;
    var lb: [LINE_MAX]u8 = undefined;
    const line = lineText(st, caret_line, lb[0..]);
    const dcol = displayColOf(line, caret_col);
    if (dcol >= st.cols or st.gutter + dcol >= st.cols) return;
    var c: u8 = 32;
    if (caret_col < line.len and line[caret_col] != '\t') c = line[caret_col];
    var one: [1]u8 = undefined;
    one[0] = c;
    _ = gfx.gfxDrawText(st.g, st.gutter + dcol, @intCast(u32, row), one[0..1], COL_BG, COL_BRIGHT);
}

fn paintStatus(st: *UiImpl, caret_line: usize, caret_col: usize) void {
    if (st.rows == 0) return;
    const row = st.rows - 1;
    _ = gfx.gfxFillRect(st.g, 0, row, st.cols, 1, COL_STATUS_BG, COL_STATUS_BG);
    var buf: [STATUS_MAX]u8 = undefined;
    var p: usize = 0;
    p = putBytes(buf[0..], p, " ");
    p = putU32(buf[0..], p, @intCast(u32, caret_line + 1));
    p = putBytes(buf[0..], p, ",");
    p = putU32(buf[0..], p, @intCast(u32, caret_col + 1));
    var ub: match.Unbalance = undefined;
    if (match.matchUnbalanced(st.b, &ub)) {
        p = putBytes(buf[0..], p, "  unbalanced ");
        var one: [1]u8 = undefined;
        one[0] = ub.ch;
        p = putBytes(buf[0..], p, one[0..1]);
        p = putBytes(buf[0..], p, " from line ");
        p = putU32(buf[0..], p, @intCast(u32, ub.line));
    }
    var lb: [LINE_MAX]u8 = undefined;
    const line = lineText(st, caret_line, lb[0..]);
    const code = lexer.lexErrCodeAt(line, caret_col);
    if (code != 0) {
        p = putBytes(buf[0..], p, "  error[");
        p = putU32Pad4(buf[0..], p, code);
        p = putBytes(buf[0..], p, "]");
        if (errtab.errtabMessage(code)) |msg| {
            p = putBytes(buf[0..], p, " ");
            p = putBytes(buf[0..], p, msg);
        }
    }
    if (p > st.cols) p = @intCast(usize, st.cols);
    _ = gfx.gfxDrawText(st.g, 0, row, buf[0..p], 0, COL_STATUS_BG);
}

pub fn uiPaint(stw: *UiState) UiError!void {
    const st = stw.opaque;
    if (st.err == 1) return error.OutOfMemory;
    if (st.err == 2) return error.SaveFailed;

    // Declared-ident freshness: rebuild after >= 2 s of edit idle.
    if (st.edit_pending) {
        const now = time_mod.ticksMs();
        if (now - st.last_edit_ms >= IDLE_MS) rebuildIdents(st);
    }

    var bw: u32 = 0;
    var bh: u32 = 0;
    gfx.gfxBufferSize(st.g, &bw, &bh);
    var cw: u32 = 0;
    var ch: u32 = 0;
    gfx.gfxCharSize(st.g, &cw, &ch);
    if (cw == 0 or ch == 0) return;
    st.cols = bw / cw;
    st.rows = bh / ch;
    if (st.cols == 0 or st.rows == 0) return;
    st.gutter = gutterWidth(buffer.bufLineCount(st.b));
    if (st.gutter >= st.cols) st.gutter = 1;
    clampScroll(st);

    var caret_line: usize = 0;
    var caret_col: usize = 0;
    caretLineCol(st, &caret_line, &caret_col);

    var br1: usize = 0;
    var br2: usize = 0;
    var have_br = false;
    var br_at: usize = 0;
    var br_found = false;
    const blen = buffer.bufLen(st.b);
    if (st.caret < blen and isBracket(buffer.bufByteAt(st.b, st.caret))) {
        br_at = st.caret;
        br_found = true;
    } else if (st.caret > 0 and isBracket(buffer.bufByteAt(st.b, st.caret - 1))) {
        br_at = st.caret - 1;
        br_found = true;
    }
    if (br_found) {
        var mate: usize = 0;
        if (match.matchPairAt(st.b, br_at, &mate)) {
            have_br = true;
            br1 = br_at;
            br2 = mate;
        }
    }

    _ = gfx.gfxClear(st.g, COL_BG);

    var content_rows: u32 = 0;
    if (st.rows > 1) content_rows = st.rows - 1;
    const lc = buffer.bufLineCount(st.b);
    syncLex(st, st.scroll);
    var ls = st.lex;
    var n: u32 = 0;
    var lb: [LINE_MAX]u8 = undefined;
    var toks: [TOK_MAX]lexer.Token = undefined;
    while (n < content_rows and st.scroll + @intCast(usize, n) < lc) : (n += 1) {
        const line_no = st.scroll + @intCast(usize, n);
        var lstart: usize = 0;
        var llen: usize = 0;
        buffer.bufLineRange(st.b, line_no, &lstart, &llen);
        var cp = llen;
        if (cp > LINE_MAX) cp = LINE_MAX;
        if (cp > 0) _ = buffer.bufCopy(st.b, lstart, cp, lb[0..cp]);
        const line = lb[0..cp];
        paintGutter(st, n, line_no + 1);
        const nt = lexer.lexLine(&ls, line, toks[0..]);
        paintTokens(st, n, lstart, line, toks[0..], nt, br1, br2, have_br);
    }

    paintCursor(st, caret_line, caret_col);
    paintStatus(st, caret_line, caret_col);
}
