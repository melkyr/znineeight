// w3000_manyptr_retained — Task 0q3 retained-residual pin (STILL TOLERATED).
//
// Bare `*T` -> `[*]T` at RETURN and CALL-ARGUMENT positions remains accepted
// after Task 0q3. This is the declared residual (NOT marked minor): the
// compiler's OWN source relies on this shape silently there, via the valid
// array->pointer `&arr[0]` idiom (Language_Spec_Z98.md:382, allowed at
// call-arg/return), so promoting it to a hard error would break self-hosting.
// It is distinct from enum -> integer, which Task 0q3 DID promote at
// return/call-argument.
//
// Expected (post-0q3): dump rc=0, gcc-clean, run rc=0, stdout `4`.
const std = @import("std");

fn f(p: *u8) [*]u8 {
    return p;
}

fn g(p: [*]u8) void {
    _ = p;
}

fn h(p: *u8) void {
    _ = p;
}

pub fn main() void {
    var arr: [4]u8 = [4]u8{ 1, 2, 3, 4 };
    var p: *u8 = &arr[0];
    g(p);
    h(&arr[0]);
    var q = f(p);
    _ = q;
    std.io.printInt(@intCast(i32, arr[3]));
    std.io.writeByte('\n');
}
