// bareptr_to_slice_ctx_xmod — MUST FRONTEND-REJECT fixture (Task 0i residual pin).
//
// Track4 S23 I. `sf/src/type_registry.zig:1257-1263` is a DUPLICATE
// `ptr_type -> slice_type` assignability block (the Task 0h edit at
// `:1231-1243` removed the bare-pointer returns from the FIRST block only).
// Its `:1261` arm `if (sp2.base == ts2.elem and qok) return true;` still makes a
// bare `*const u8` -> `[]const u8` "assignable", so the frontend emits NO
// diagnostic and `sf/src/lower.zig` inserts no `make_slice`; the emitted C then
// assigns a raw `unsigned char *` to a `Slice` and **gcc** rejects it.
//
// Verified pre/post with the Task 0h compiler `958a5e0f` and the Task 0i
// deletion compiler `ed206028` (`type_registry.zig:1257-1263` deleted):
//   - post (dup present): NO frontend diagnostic in ANY context; gcc error
//     "incompatible types when assigning to type '..._Slice_...' from type
//     'unsigned char *'" (return: "...when returning...").
//   - deletion: var-decl + assignment emit `warning[3000]` at level=1 and
//     emission CONTINUES (still gcc-FAIL); `return` and call-argument emit NO
//     diagnostic at all (silent). So removing the duplicate is necessary but NOT
//     sufficient — Task 0j must ALSO raise the mismatch to a hard error
//     (`level=0`) at these sites.
//
// Contexts exercised (all bare `*const u8` -> `[]const u8`):
//   ctx_vardecl  — `var s: []const u8 = x;`      (site semantic_analyzer.zig:2984-2993)
//   ctx_assign   — `s = x;`                       (site :1872-1881)
//   ctx_return   — `return x;`                    (resolveReturnStmt :1407-1430; NO diag today)
//   ctx_callarg  — `takesSlice(x)`                (site :1561 tryRecordCoercion; NO diag today)
//   ctx_if       — `if (c) x else y`              (funnels to the enclosing var-decl)
//   ctx_switch   — `switch (n) { 1 => x, else => y }` (funnels to the enclosing var-decl)
//
// EXPECTED after Task 0j: frontend emits `error[3000]` (hard, level 0) and emits
// ZERO `.c` (corpus GREEN-guard, matching the zig0 oracle reject).
// Corpus class TODAY: FAIL (gcc) — declared in repro/mi_matrix/EXPECTED_FAIL.md.
const std = @import("std");

fn takesSlice(s: []const u8) usize {
    return s.len;
}

fn ctx_vardecl(x: *const u8) []const u8 {
    var s: []const u8 = x;
    return s;
}

fn ctx_assign(x: *const u8) usize {
    var s: []const u8 = undefined;
    s = x;
    return s.len;
}

fn ctx_return(x: *const u8) []const u8 {
    return x;
}

fn ctx_callarg(x: *const u8) usize {
    return takesSlice(x);
}

fn ctx_if(x: *const u8, y: *const u8, c: bool) []const u8 {
    var s: []const u8 = if (c) x else y;
    return s;
}

fn ctx_switch(x: *const u8, y: *const u8, n: u32) []const u8 {
    var s: []const u8 = switch (n) { 1 => x, else => y };
    return s;
}

pub fn main() void {
    var b: [3]u8 = undefined;
    b[0] = 104;
    b[1] = 105;
    b[2] = 0;
    var n0: usize = ctx_vardecl(&b[0]).len;
    var n1: usize = ctx_assign(&b[0]);
    var n2: usize = ctx_return(&b[0]).len;
    var n3: usize = ctx_callarg(&b[0]);
    var n4: usize = ctx_if(&b[0], &b[0], true).len;
    var n5: usize = ctx_switch(&b[0], &b[0], 1).len;
    std.io.printInt(@intCast(i32, n0 + n1 + n2 + n3 + n4 + n5));
    std.io.writeByte('\n');
}
