// buffer_test.zig — native Linux tests for the z9edit gap buffer.
//
// Build/run (repo root):
//   "$ZIG" -osl --output-dir "$OUT/buffer" examples/z98/z9edit/tests/buffer_test.zig
//   sh "$OUT/buffer/build_target.sh" linux "$OUT/buffer/buffer_test"
//   "$OUT/buffer/buffer_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const arena_mod = @import("std_arena.zig");
const file_mod = @import("std_file.zig");
const io = @import("std_io");
const os = @import("std_os");
const buffer = @import("../buffer.zig");

var arena_buf: [1024 * 1024]u8 = undefined;
var arena: arena_mod.Arena = undefined;
var fails: usize = 0;

var P_CRLF_IN: []const u8 = "/tmp/z9edit_buffer_crlf_in.txt";
var P_CRLF_OUT: []const u8 = "/tmp/z9edit_buffer_crlf_out.txt";
var P_LF_IN: []const u8 = "/tmp/z9edit_buffer_lf_in.txt";
var P_LF_OUT: []const u8 = "/tmp/z9edit_buffer_lf_out.txt";
var P_MISSING: []const u8 = "/tmp/z9edit_buffer_missing_do_not_create.txt";

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

fn buffered(b: *buffer.GapBuffer, out: []u8) ?usize {
    const n = buffer.bufCopy(b, 0, buffer.bufLen(b), out);
    return n;
}

fn tInsertDelete() bool {
    const b = buffer.bufInit(&arena, 16) catch {
        return false;
    };
    buffer.bufInsert(b, 0, "hello world") catch {
        return false;
    };
    buffer.bufInsert(b, 5, ",") catch {
        return false;
    };
    if (buffer.bufLen(b) != 12) return false;
    var out: [64]u8 = undefined;
    const n = buffered(b, out[0..]) orelse return false;
    if (!eq(out[0..n], "hello, world")) return false;
    buffer.bufDelete(b, 5, 1) catch {
        return false;
    };
    const n2 = buffered(b, out[0..]) orelse return false;
    return eq(out[0..n2], "hello world");
}

fn tLineIndexAfterInsert() bool {
    const b = buffer.bufInit(&arena, 8) catch {
        return false;
    };
    buffer.bufInsert(b, 0, "one\ntwo\nthree") catch {
        return false;
    };
    if (buffer.bufLineCount(b) != 3) return false;
    var s: usize = 0;
    var l: usize = 0;
    buffer.bufLineRange(b, 1, &s, &l);
    var out: [64]u8 = undefined;
    var n = buffer.bufCopy(b, s, l, out[0..]);
    if (!eq(out[0..n], "two")) return false;
    buffer.bufInsert(b, 3, "\n") catch {
        return false;
    };
    if (buffer.bufLineCount(b) != 4) return false;
    buffer.bufLineRange(b, 1, &s, &l);
    if (l != 0) return false;
    buffer.bufLineRange(b, 2, &s, &l);
    n = buffer.bufCopy(b, s, l, out[0..]);
    return eq(out[0..n], "two");
}

fn tOffsetLineCol() bool {
    const b = buffer.bufInit(&arena, 8) catch {
        return false;
    };
    buffer.bufInsert(b, 0, "abc\ndefgh\nij") catch {
        return false;
    };
    if (buffer.bufOffsetOf(b, 0, 0) != 0) return false;
    if (buffer.bufOffsetOf(b, 1, 3) != 7) return false;
    if (buffer.bufOffsetOf(b, 2, 2) != 12) return false;
    var ln: usize = 0;
    var col: usize = 0;
    buffer.bufLineColOf(b, 7, &ln, &col);
    if (ln != 1 or col != 3) return false;
    buffer.bufLineColOf(b, 12, &ln, &col);
    if (ln != 2 or col != 2) return false;
    return true;
}

fn tCrlfNoEdit() bool {
    if (!writeFile(P_CRLF_IN, "a\r\nb\r\n")) return false;
    const b = buffer.bufLoad(&arena, P_CRLF_IN) catch {
        return false;
    };
    if (!buffer.bufUsesCrlf(b)) return false;
    if (buffer.bufDirty(b)) return false;
    buffer.bufSave(b, P_CRLF_OUT) catch {
        return false;
    };
    if (buffer.bufDirty(b)) return false;
    const got = readFile(P_CRLF_OUT) orelse return false;
    return eq(got, "a\r\nb\r\n");
}

fn tLfPreserved() bool {
    if (!writeFile(P_LF_IN, "a\nb\n")) return false;
    const b = buffer.bufLoad(&arena, P_LF_IN) catch {
        return false;
    };
    if (buffer.bufUsesCrlf(b)) return false;
    buffer.bufSave(b, P_LF_OUT) catch {
        return false;
    };
    const got = readFile(P_LF_OUT) orelse return false;
    return eq(got, "a\nb\n");
}

fn tCrlfAfterInsert() bool {
    if (!writeFile(P_CRLF_IN, "a\r\nb\r\n")) return false;
    const b = buffer.bufLoad(&arena, P_CRLF_IN) catch {
        return false;
    };
    const end = buffer.bufLen(b);
    buffer.bufInsert(b, end, "\n") catch {
        return false;
    };
    if (!buffer.bufDirty(b)) return false;
    if (!buffer.bufUsesCrlf(b)) return false;
    buffer.bufSave(b, P_CRLF_OUT) catch {
        return false;
    };
    if (buffer.bufDirty(b)) return false;
    const got = readFile(P_CRLF_OUT) orelse return false;
    return eq(got, "a\r\nb\r\n\r\n");
}

fn tLoadMissing() bool {
    file_mod.remove(P_MISSING) catch {};
    const b = buffer.bufLoad(&arena, P_MISSING) catch |e| {
        return e == error.ReadFailed;
    };
    _ = b;
    return false;
}

pub fn main() void {
    arena = arena_mod.init(arena_buf[0..]);

    arena_mod.reset(&arena);
    report("insert_delete_roundtrip", tInsertDelete());
    arena_mod.reset(&arena);
    report("line_index_after_insert", tLineIndexAfterInsert());
    arena_mod.reset(&arena);
    report("offset_linecol_roundtrip", tOffsetLineCol());
    arena_mod.reset(&arena);
    report("crlf_preserved_noedit", tCrlfNoEdit());
    arena_mod.reset(&arena);
    report("lf_preserved", tLfPreserved());
    arena_mod.reset(&arena);
    report("crlf_preserved_after_insert", tCrlfAfterInsert());
    arena_mod.reset(&arena);
    report("load_missing_error", tLoadMissing());

    if (fails != 0) os.exit(1);
}
