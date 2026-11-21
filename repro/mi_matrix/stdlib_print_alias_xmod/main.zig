// stdlib_print_alias_xmod — Task 1 fix round 1 (review Important) regression
// fixture: auto-import for an ALIASED `print` callee.
//
// DEFECT (before the fix): the auto-import scan only looked at `fn_call`
// callees named `print`, so `const p = io.print; p("...", .{...});` was NOT
// detected. The lowerer's print special case (`lower.zig`, keyed on the
// resolved fn name_id) still intercepted the indirect call, so the emitter
// wrote an UNMANGLED `printI32(...)` with no std_fmt module in the graph:
// dump rc 0, then the link failed with `undefined reference to 'printI32'`.
// The base compiler supported the shape (it emitted `std_print_i32(...)`).
//
// FIX: the scan (`main.zig` `astStoreHasPrintRef`) now matches any
// `ident_expr`/`field_access` payload named `print` — the alias initializer
// `io.print` is that reference — so std_fmt is auto-imported for the indirect
// call too. Over-approximation is safe: an unreferenced std_fmt is pruned.
//
// Expected stdout (exact) and rc 0:
//   alias=7
//   bool=true
const io = @import("std_io.zig");

pub fn main() void {
    const p = io.print;
    p("alias={}\n", .{7});
    p("bool={}\n", .{true});
}
