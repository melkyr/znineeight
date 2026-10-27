// undo_test.zig — native Linux tests for the z9edit undo stack.
//
// Build/run (repo root):
//   "$ZIG" -osl --output-dir "$OUT/undo" examples/z98/z9edit/tests/undo_test.zig
//   sh "$OUT/undo/build_target.sh" linux "$OUT/undo/undo_test"
//   "$OUT/undo/undo_test"

const arena_mod = @import("std_arena.zig");
const file_mod = @import("std_file.zig");
const io = @import("std_io");
const os = @import("std_os");
const buffer = @import("../buffer.zig");
const undo = @import("../undo.zig");

var arena_buf: [1024 * 1024]u8 = undefined;
var arena: arena_mod.Arena = undefined;
var fails: usize = 0;

var P_CRLF_IN: []const u8 = "/tmp/z9edit_undo_crlf_in.txt";
var P_CRLF_OUT: []const u8 = "/tmp/z9edit_undo_crlf_out.txt";

fn report(name: []const u8, ok: bool) void {
    if (ok) {
        io.write("ok - ");
    } else {
        io.write("FAIL - ");
        fails += 1;
    }
    io.write(name);
    io.write("\n");
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn contentIs(b: *buffer.GapBuffer, expected: []const u8) bool {
    var out: [256]u8 = undefined;
    const n = buffer.bufCopy(b, 0, buffer.bufLen(b), out[0..]);
    return eq(out[0..n], expected);
}

fn writeFile(path: []const u8, data: []const u8) bool {
    file_mod.writeAll(path, data) catch {
        return false;
    };
    return true;
}

fn readFile(path: []const u8) ?[]u8 {
    return file_mod.readAll(&arena, path) catch {
        return null;
    };
}

fn tUndoInsert() bool {
    const b = buffer.bufInit(&arena, 8) catch {
        return false;
    };
    const u = undo.undoInit(&arena);
    buffer.bufInsert(b, 0, "hello") catch {
        return false;
    };
    undo.undoRecordInsert(u, 0, "hello") catch {
        return false;
    };
    if (!contentIs(b, "hello")) return false;
    if (!undo.undoApply(u, b)) return false;
    return contentIs(b, "");
}

fn tUndoDelete() bool {
    const b = buffer.bufInit(&arena, 8) catch {
        return false;
    };
    const u = undo.undoInit(&arena);
    buffer.bufInsert(b, 0, "hello world") catch {
        return false;
    };
    var cut: [16]u8 = undefined;
    const n = buffer.bufCopy(b, 0, 5, cut[0..]);
    buffer.bufDelete(b, 0, 5) catch {
        return false;
    };
    if (!contentIs(b, " world")) return false;
    undo.undoRecordDelete(u, 0, cut[0..n]) catch {
        return false;
    };
    if (!undo.undoApply(u, b)) return false;
    return contentIs(b, "hello world");
}

fn tEmptyFalse() bool {
    const b = buffer.bufInit(&arena, 8) catch {
        return false;
    };
    const u = undo.undoInit(&arena);
    return !undo.undoApply(u, b);
}

fn tUndoInsertCrlfExact() bool {
    if (!writeFile(P_CRLF_IN, "a\r\nb\r\n")) return false;
    const b = buffer.bufLoad(&arena, P_CRLF_IN) catch {
        return false;
    };
    const u = undo.undoInit(&arena);
    const end = buffer.bufLen(b);
    buffer.bufInsert(b, end, "\n") catch {
        return false;
    };
    undo.undoRecordInsert(u, end, "\n") catch {
        return false;
    };
    if (!undo.undoApply(u, b)) return false;
    buffer.bufSave(b, P_CRLF_OUT) catch {
        return false;
    };
    const got = readFile(P_CRLF_OUT) orelse return false;
    return eq(got, "a\r\nb\r\n");
}

fn tCrlfUndoDeleteExact() bool {
    if (!writeFile(P_CRLF_IN, "a\r\nb\r\n")) return false;
    const b = buffer.bufLoad(&arena, P_CRLF_IN) catch {
        return false;
    };
    const u = undo.undoInit(&arena);
    var cut: [16]u8 = undefined;
    const n = buffer.bufCopy(b, 2, 2, cut[0..]);
    buffer.bufDelete(b, 2, 2) catch {
        return false;
    };
    undo.undoRecordDelete(u, 2, cut[0..n]) catch {
        return false;
    };
    if (!undo.undoApply(u, b)) return false;
    buffer.bufSave(b, P_CRLF_OUT) catch {
        return false;
    };
    const got = readFile(P_CRLF_OUT) orelse return false;
    return eq(got, "a\r\nb\r\n");
}

pub fn main() void {
    arena = arena_mod.init(arena_buf[0..]);

    arena_mod.reset(&arena);
    report("undo_insert_inverse", tUndoInsert());
    arena_mod.reset(&arena);
    report("undo_delete_inverse", tUndoDelete());
    arena_mod.reset(&arena);
    report("undo_empty_false", tEmptyFalse());
    arena_mod.reset(&arena);
    report("undo_insert_crlf_exact", tUndoInsertCrlfExact());
    arena_mod.reset(&arena);
    report("crlf_file_undo_delete_exact", tCrlfUndoDeleteExact());

    if (fails != 0) os.exit(1);
}
