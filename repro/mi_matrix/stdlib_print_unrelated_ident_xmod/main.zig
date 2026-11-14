// stdlib_print_unrelated_ident_xmod — Task 10 (B8) auto-import precision pin.
//
// The Task-1 auto-import scan (`main.zig` `astStoreHasPrintRef`) intentionally
// matches ANY `ident_expr`/`field_access` named `print`, so the lowerer's
// name-keyed print special case still sees an aliased callee (`const p =
// io.print; p(...)`). The over-approximation meant an UNRELATED identifier
// named `print` also triggered the std_fmt.zig auto-import, and a search path
// without std_fmt.zig failed with `error[3048]` even though no print was
// lowered.
//
// After Task 10 the import probe is silent when std_fmt.zig is absent and
// error[3048] is reported only when a print VALUE was actually lowered. This
// program references `print` two ways (a module const and a struct field) and
// lowers no print, so it builds and runs both with and without std_fmt.zig in
// the search path. Its output uses the @stdoutWrite builtin, not std.fmt.
//
// Expected stdout (exact) and rc 0:
//   b8unrelated
const Config = struct { print: i32 };

const cfg = Config{ .print = 3 };
const print: i32 = 7;

pub fn main() void {
    var total: i32 = print + cfg.print;
    if (total == 10) {
        @stdoutWrite("b8unrelated\n", 12);
    }
}
