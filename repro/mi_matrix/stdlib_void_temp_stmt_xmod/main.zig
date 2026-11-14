// stdlib_void_temp_stmt_xmod — Task 8 positive runtime fixture.
//
// Two void/value-`if` statement residuals (pre-existing; carried from Task 9D):
//
//   (i) `_ = foo();` — discarding a void call — ICEd with
//       `error[3043]: internal: invalid temp index 0 (len 0)`. A known-direct
//       void call lowers to temp 0 (its "no result" marker, not the TEMP_NONE
//       void-`if` sentinel), and the plain-assign path ran
//       `getTempType(self, 0)` on it: out of bounds while the temp table was
//       still empty, and a spurious `(void)zT_0;` naming an unrelated temp
//       otherwise.
//
//   (ii) `return if (c) foo();` — a void `if` returned from a void function —
//        compiled rc=0 but emitted gcc-invalid C
//        (`return zT_4294967295;`, the TEMP_NONE sentinel).
//
//   (iii) fix round: `fn f(c: bool) !void { return if (c) foo(); }` — the
//        same void `if` returned from an error-union(void) function — ICEd
//        (`error[3043] invalid temp index 294967295`): `lowerExpr`'s coercion
//        wrapper applied the recorded void->`!void` coercion to the TEMP_NONE
//        sentinel, so `materializeInto` dereferenced it with `getTempType`
//        before `return_stmt` was reached.
//
// All three are fixed in `sf/src/lower.zig` (skip the l-value store for a
// void-typed RHS; emit a valueless return for the TEMP_NONE sentinel; skip a
// recorded coercion on the TEMP_NONE sentinel).
//
// Covers:
//   * `_ = foo();` as the FIRST lowered statement of the function (empty temp
//     table — the exact ICE shape)
//   * `_ = { foo(); };` (void block discard, the same no-value path)
//   * `_ = if (c) foo();` / `_ = if (c) foo() else baz();` (void value-`if`
//     discard — Task 9D path; controls)
//   * a void call statement and a non-void `_ = bar();` discard (controls)
//   * `return if (c) foo();` true and false
//   * `return if (c) foo() else baz();` true and false
//   * `return foo();` direct (control)
//   * `fn f() !void` EU(void) returns: `return if (c) foo();` and
//     `return if (c) foo() else baz();`, true and false
//
// Every aggregate is `@panic`-guarded, so a wrong hit count traps (rc 133)
// instead of printing as if correct. Golden from the FIXED compiler, 3x
// byte-exact and cross-checked against a Zig 0.15.2 twin (`std.debug.print`).
const std = @import("std");

var g_hits: u32 = 0;

fn foo() void { g_hits += 1; }
fn baz() void { g_hits += 100; }
fn bar() u32 { g_hits += 10; return 7; }

fn retIf(c: bool) void {
    return if (c) foo();
}

fn retIfElseVoid(c: bool) void {
    return if (c) foo() else baz();
}

fn retCall() void {
    return foo();
}

fn retIfEu(c: bool) !void {
    return if (c) foo();
}

fn retIfElseEu(c: bool) !void {
    return if (c) foo() else baz();
}

pub fn main() void {
    // (i) the reported shape: the discard is the first lowered statement.
    _ = foo(); // +1
    // The same no-value path through a void block.
    _ = { foo(); }; // +1
    const c: bool = true;
    // Void value-`if` discards (Task 9D TEMP_NONE path).
    _ = if (c) foo(); // +1
    _ = if (c) foo() else baz(); // +1
    // Controls: a void call statement and a non-void value discard.
    foo(); // +1
    _ = bar(); // +10
    // (ii) a void `if` returned from a void function.
    retIf(true); // +1
    retIf(false); // +0
    // Both arms void, true and false.
    retIfElseVoid(true); // +1
    retIfElseVoid(false); // +100
    // Control: a direct void call returned.
    retCall(); // +1
    // (iii) the same void `if` returned from an EU(void) function.
    retIfEu(true) catch { @panic("retIfEu(true) failed"); }; // +1
    retIfEu(false) catch { @panic("retIfEu(false) failed"); }; // +0
    retIfElseEu(true) catch { @panic("retIfElseEu(true) failed"); }; // +1
    retIfElseEu(false) catch { @panic("retIfElseEu(false) failed"); }; // +100
    if (g_hits != 220) { @panic("void-temp guard failed"); }
    std.io.print("hits={}\n", .{g_hits});
}
