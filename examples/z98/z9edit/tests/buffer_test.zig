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
const undo = @import("../undo.zig");

var arena_buf: [1024 * 1024]u8 = undefined;
var arena: arena_mod.Arena = undefined;
var fails: usize = 0;

var P_CRLF_IN: []const u8 = "/tmp/z9edit_buffer_crlf_in.txt";
var P_DIFF: []const u8 = "/tmp/z9edit_buffer_diff.txt";
var P_CRLF_OUT: []const u8 = "/tmp/z9edit_buffer_crlf_out.txt";
var P_LF_IN: []const u8 = "/tmp/z9edit_buffer_lf_in.txt";
var P_LF_OUT: []const u8 = "/tmp/z9edit_buffer_lf_out.txt";
var P_MISSING: []const u8 = "/tmp/z9edit_buffer_missing_do_not_create.txt";
var P_ATOMIC: []const u8 = "/tmp/z9edit_atomic/target.txt";

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

fn tLfCrlfInsertNormalized() bool {
    if (!writeFile(P_LF_IN, "a\nb\n")) return false;
    const b = buffer.bufLoad(&arena, P_LF_IN) catch {
        return false;
    };
    const end = buffer.bufLen(b);
    buffer.bufInsert(b, end, "\r\n") catch {
        return false;
    };
    if (buffer.bufUsesCrlf(b)) return false;
    buffer.bufSave(b, P_LF_OUT) catch {
        return false;
    };
    const got = readFile(P_LF_OUT) orelse return false;
    return eq(got, "a\nb\n\n");
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

// tier_edit.sh prepares P_ATOMIC with "ORIGINAL\n" and makes
// P_ATOMIC.z9tmp a directory, so the temp write fails. The target must be
// untouched (non-atomic direct writes would truncate it).
fn tAtomicSaveFailure() bool {
    const before = readFile(P_ATOMIC) orelse return false;
    if (!eq(before, "ORIGINAL\n")) return false;
    const b = buffer.bufInit(&arena, 16) catch {
        return false;
    };
    buffer.bufInsert(b, 0, "REPLACEMENT\n") catch {
        return false;
    };
    var failed = false;
    buffer.bufSave(b, P_ATOMIC) catch {
        failed = true;
    };
    if (!failed) return false;
    const after = readFile(P_ATOMIC) orelse return false;
    return eq(after, "ORIGINAL\n");
}

// --- cached-vs-naive line map differential --------------------------------
//
// Every check compares the cached accessors against the naive ones. The naive
// start for any line is bufOffsetOf(line, 0): it returns the line start for
// in-range lines and bufLen for lines past the end, exactly like lineStartOf.
// MAX_LINE_CACHE is 131072 lines; this synthetic file has 131081 lines.

var g_many: [131080]u8 = undefined;

fn rnd(seed: *u32, mod: usize) usize {
    seed.* = (seed.* * 25173 + 13849) % 65521;
    const m: u32 = @intCast(u32, mod);
    return @intCast(usize, (seed.* >> 4) % m);
}

fn sameAt(b: *buffer.GapBuffer, line: usize) bool {
    const ns = buffer.bufOffsetOf(b, line, 0);
    const cs = buffer.bufLineStartCached(b, line);
    if (ns != cs) return false;
    var nstart: usize = 0;
    var nlen: usize = 0;
    var cstart: usize = 0;
    var clen: usize = 0;
    buffer.bufLineRange(b, line, &nstart, &nlen);
    buffer.bufLineRangeCached(b, line, &cstart, &clen);
    if (nstart != cstart or nlen != clen) return false;
    return true;
}

fn sameAll(b: *buffer.GapBuffer) bool {
    const nc = buffer.bufLineCount(b);
    if (buffer.bufLineCountCached(b) != nc) return false;
    var line: usize = 0;
    while (line <= nc + 1) : (line += 1) {
        if (!sameAt(b, line)) return false;
    }
    return true;
}

fn tCachedDiffEdits() bool {
    const b = buffer.bufInit(&arena, 16) catch {
        return false;
    };
    // Empty buffer is one line starting at 0.
    if (!sameAll(b)) return false;
    var seed: u32 = 4660;
    var step: usize = 0;
    while (step < 300) : (step += 1) {
        const before = buffer.bufEditGen(b);
        const len = buffer.bufLen(b);
        if (rnd(&seed, 100) < 55) {
            const at = rnd(&seed, len + 1);
            const which = rnd(&seed, 6);
            if (which == 0) {
                buffer.bufInsert(b, at, "a") catch {
                    return false;
                };
            } else if (which == 1) {
                buffer.bufInsert(b, at, "\n") catch {
                    return false;
                };
            } else if (which == 2) {
                buffer.bufInsert(b, at, "\r\n") catch {
                    return false;
                };
            } else if (which == 3) {
                buffer.bufInsert(b, at, "line\n") catch {
                    return false;
                };
            } else if (which == 4) {
                buffer.bufInsert(b, at, "q\r\nw") catch {
                    return false;
                };
            } else {
                buffer.bufInsert(b, at, "xyz") catch {
                    return false;
                };
            }
        } else if (len == 0) {
            buffer.bufInsert(b, 0, "seed") catch {
                return false;
            };
        } else {
            const at = rnd(&seed, len);
            var n = 1 + rnd(&seed, 8);
            if (n > len - at) n = len - at;
            buffer.bufDelete(b, at, n) catch {
                return false;
            };
        }
        if (buffer.bufEditGen(b) <= before) return false;
        if (!sameAll(b)) return false;
    }
    return true;
}

fn tCachedDiffUndo() bool {
    const b = buffer.bufInit(&arena, 16) catch {
        return false;
    };
    const u = undo.undoInit(&arena);
    var seed: u32 = 90210;
    var step: usize = 0;
    while (step < 120) : (step += 1) {
        const at = rnd(&seed, buffer.bufLen(b) + 1);
        const which = rnd(&seed, 4);
        var chunk: []const u8 = "k";
        if (which == 1) {
            chunk = "\n";
        } else if (which == 2) {
            chunk = "p\r\nq";
        } else if (which == 3) {
            chunk = "tail\n";
        }
        const before = buffer.bufEditGen(b);
        buffer.bufInsert(b, at, chunk) catch {
            return false;
        };
        undo.undoRecordInsert(u, at, chunk) catch {
            return false;
        };
        if (buffer.bufEditGen(b) <= before) return false;
        if (!sameAll(b)) return false;

        if (buffer.bufLen(b) > 0 and (step % 2) == 1) {
            const dpos = rnd(&seed, buffer.bufLen(b));
            var dc = 1 + rnd(&seed, 5);
            const max = buffer.bufLen(b) - dpos;
            if (dc > max) dc = max;
            var tmp: [8]u8 = undefined;
            const got = buffer.bufCopy(b, dpos, dc, tmp[0..]);
            const dbefore = buffer.bufEditGen(b);
            buffer.bufDelete(b, dpos, dc) catch {
                return false;
            };
            undo.undoRecordDelete(u, dpos, tmp[0..got]) catch {
                return false;
            };
            if (buffer.bufEditGen(b) <= dbefore) return false;
            if (!sameAll(b)) return false;
        }

        if ((step % 3) == 0) {
            const ubefore = buffer.bufEditGen(b);
            if (undo.undoApply(u, b)) {
                if (buffer.bufEditGen(b) <= ubefore) return false;
            }
            if (!sameAll(b)) return false;
        }
    }
    return true;
}

fn tCachedDiffLoadNoTrailing() bool {
    // No trailing newline; mixed LF and CRLF input is folded to canonical LF.
    if (!writeFile(P_DIFF, "alpha\nbeta\r\ngamma")) return false;
    const b = buffer.bufLoad(&arena, P_DIFF) catch {
        return false;
    };
    if (buffer.bufEditGen(b) == 0) return false;
    if (buffer.bufLineCount(b) != 3) return false;
    if (!sameAll(b)) return false;
    const before = buffer.bufEditGen(b);
    buffer.bufInsert(b, 0, "x\r\n") catch {
        return false;
    };
    if (buffer.bufEditGen(b) <= before) return false;
    if (!sameAll(b)) return false;
    const dbefore = buffer.bufEditGen(b);
    buffer.bufDelete(b, 0, 1) catch {
        return false;
    };
    if (buffer.bufEditGen(b) <= dbefore) return false;
    return sameAll(b);
}

fn tCachedDiffEndsNewline() bool {
    const b = buffer.bufInit(&arena, 8) catch {
        return false;
    };
    buffer.bufInsert(b, 0, "a\nb\n") catch {
        return false;
    };
    if (buffer.bufLineCount(b) != 3) return false;
    if (!sameAll(b)) return false;
    const before = buffer.bufEditGen(b);
    buffer.bufDelete(b, 3, 1) catch {
        return false;
    };
    if (buffer.bufEditGen(b) <= before) return false;
    if (buffer.bufLineCount(b) != 2) return false;
    return sameAll(b);
}

fn tCachedFallback() bool {
    var i: usize = 0;
    while (i < g_many.len) : (i += 1) g_many[i] = '\n';
    if (!writeFile(P_DIFF, g_many[0..])) return false;
    const b = buffer.bufLoad(&arena, P_DIFF) catch {
        return false;
    };
    const nc = buffer.bufLineCount(b);
    if (nc != 131081) return false;
    if (buffer.bufLineCountCached(b) != nc) return false;
    if (!sameAt(b, 0)) return false;
    if (!sameAt(b, 1)) return false;
    if (!sameAt(b, 65536)) return false;
    if (!sameAt(b, nc - 1)) return false;
    if (!sameAt(b, nc)) return false;
    const before = buffer.bufEditGen(b);
    buffer.bufInsert(b, 0, "z") catch {
        return false;
    };
    if (buffer.bufEditGen(b) <= before) return false;
    if (buffer.bufLineCountCached(b) != buffer.bufLineCount(b)) return false;
    if (!sameAt(b, nc)) return false;
    return sameAt(b, 65536);
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
    report("lf_file_crlf_insert_normalized", tLfCrlfInsertNormalized());
    arena_mod.reset(&arena);
    report("load_missing_error", tLoadMissing());
    arena_mod.reset(&arena);
    report("save_failure_preserves_original", tAtomicSaveFailure());
    arena_mod.reset(&arena);
    report("cached_vs_naive_random_edits", tCachedDiffEdits());
    arena_mod.reset(&arena);
    report("cached_vs_naive_undo", tCachedDiffUndo());
    arena_mod.reset(&arena);
    report("cached_vs_naive_load_no_trailing", tCachedDiffLoadNoTrailing());
    arena_mod.reset(&arena);
    report("cached_vs_naive_ends_newline", tCachedDiffEndsNewline());
    arena_mod.reset(&arena);
    report("cached_vs_naive_fallback_over_cache", tCachedFallback());

    if (fails != 0) os.exit(1);
}
