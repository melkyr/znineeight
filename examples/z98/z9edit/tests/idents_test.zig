// idents_test.zig — native Linux tests for the z9edit declared-identifier scan.
//
// Build/run (repo root):
//   "$ZIG" -osl --output-dir "$OUT/idents" examples/z98/z9edit/tests/idents_test.zig
//   sh "$OUT/idents/build_target.sh" linux "$OUT/idents/idents_test"
//   "$OUT/idents/idents_test"

const arena_mod = @import("std_arena.zig");
const io = @import("std_io");
const os = @import("std_os");
const buffer = @import("../buffer.zig");
const idents = @import("../idents.zig");

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

fn tDecls() bool {
    const src = "const a = 1;\nvar b: u32 = 2;\nfn c(x: u32) u32 { return x; }\npub const d = 4;\n// const NotReal = 1;\nvar s = \"const Fake = 1\";\n";
    const b = buffer.bufInit(&arena, 64) catch {
        return false;
    };
    buffer.bufInsert(b, 0, src) catch {
        return false;
    };
    const set = idents.identScan(&arena, b) catch {
        return false;
    };
    if (!idents.identHas(set, "a")) return false;
    if (!idents.identHas(set, "b")) return false;
    if (!idents.identHas(set, "c")) return false;
    if (!idents.identHas(set, "d")) return false;
    if (idents.identHas(set, "NotReal")) return false;
    if (idents.identHas(set, "Fake")) return false;
    if (idents.identHas(set, "x")) return false;
    return true;
}

fn tUseOnly() bool {
    const src = "foo();\nbar = baz;\nfn real() void {}\n";
    const b = buffer.bufInit(&arena, 32) catch {
        return false;
    };
    buffer.bufInsert(b, 0, src) catch {
        return false;
    };
    const set = idents.identScan(&arena, b) catch {
        return false;
    };
    if (idents.identHas(set, "foo")) return false;
    if (idents.identHas(set, "bar")) return false;
    if (idents.identHas(set, "baz")) return false;
    return idents.identHas(set, "real");
}

pub fn main() void {
    arena = arena_mod.init(arena_buf[0..]);

    arena_mod.reset(&arena);
    report("decl_const_var_fn_collected", tDecls());
    arena_mod.reset(&arena);
    report("use_without_decl_not_collected", tUseOnly());

    if (fails != 0) os.exit(1);
}
