// match_test.zig — native Linux tests for z9edit bracket match/balance.
//
// Build/run (repo root):
//   "$ZIG" -osl --output-dir "$OUT/match" examples/z98/z9edit/tests/match_test.zig
//   sh "$OUT/match/build_target.sh" linux "$OUT/match/match_test"
//   "$OUT/match/match_test"

const arena_mod = @import("std_arena.zig");
const io = @import("std_io");
const os = @import("std_os");
const buffer = @import("../buffer.zig");
const match = @import("../match.zig");

var arena_buf: [1024 * 1024]u8 = undefined;
var arena: arena_mod.Arena = undefined;
var fails: usize = 0;

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

fn make(src: []const u8) ?*buffer.GapBuffer {
    const b = buffer.bufInit(&arena, 32) catch {
        return null;
    };
    buffer.bufInsert(b, 0, src) catch {
        return null;
    };
    return b;
}

fn tPairSimple() bool {
    const b = make("(abc) [x] {y}") orelse return false;
    var m: usize = 0;
    if (!match.matchPairAt(b, 0, &m) or m != 4) return false;
    if (!match.matchPairAt(b, 4, &m) or m != 0) return false;
    if (!match.matchPairAt(b, 6, &m) or m != 8) return false;
    if (!match.matchPairAt(b, 8, &m) or m != 6) return false;
    if (!match.matchPairAt(b, 10, &m) or m != 12) return false;
    if (match.matchPairAt(b, 2, &m)) return false;
    return true;
}

fn tPairCrossLine() bool {
    const b = make("(\n abc \n)") orelse return false;
    var m: usize = 0;
    return match.matchPairAt(b, 0, &m) and m == 8;
}

fn tNestedOk() bool {
    const b = make("a(b[c]d)e") orelse return false;
    var m: usize = 0;
    if (!match.matchPairAt(b, 1, &m) or m != 7) return false;
    if (!match.matchPairAt(b, 3, &m) or m != 5) return false;
    var u: match.Unbalance = undefined;
    return !match.matchUnbalanced(b, &u);
}

fn tUnbalancedOpener() bool {
    const b = make("fn f() {\n  x();\n") orelse return false;
    var u: match.Unbalance = undefined;
    if (!match.matchUnbalanced(b, &u)) return false;
    return u.ch == '{' and u.line == 1;
}

fn tUnbalancedCloser() bool {
    const b = make("a)\nb") orelse return false;
    var u: match.Unbalance = undefined;
    if (!match.matchUnbalanced(b, &u)) return false;
    return u.ch == ')' and u.line == 1;
}

pub fn main() void {
    arena = arena_mod.init(arena_buf[0..]);

    arena_mod.reset(&arena);
    report("pair_simple", tPairSimple());
    arena_mod.reset(&arena);
    report("pair_cross_line", tPairCrossLine());
    arena_mod.reset(&arena);
    report("nested_ok", tNestedOk());
    arena_mod.reset(&arena);
    report("unbalanced_opener_line", tUnbalancedOpener());
    arena_mod.reset(&arena);
    report("unbalanced_closer", tUnbalancedCloser());

    if (fails != 0) os.exit(1);
}
