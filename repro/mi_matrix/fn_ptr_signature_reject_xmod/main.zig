// repro/mi_matrix/fn_ptr_signature_reject_xmod/main.zig — FX17-F reject census.
//
// One signature-mismatched function-pointer coercion per assignment/coercion
// position (D2): local declaration initializer, local assignment, struct-literal
// field initializer, field assignment, parameter (call argument, direct and via
// a local function pointer), return, module const, module var, the `?fn` unwrap
// (declaration / field initializer / field assignment / call argument), and the
// cross-module variants (function value -> local / field / call argument,
// cross-module const). Every one is a level-0 `error[3000]` (census in
// expected_error.txt), rc 2 / 0 `.c`, classify GREEN. The matching forms are the
// positive control `fn_ptr_signature_ok_xmod`.
const std = @import("std");
const lib = @import("helper.zig");

const Shape = struct { draw_fn: fn (*void) void, data: *void };
const Shape2 = struct { draw_fn: fn (*i32) void, data: *void };
const OptShape = struct { draw_fn: ?fn (*void) void };
const DrawFn = fn (*void) void;

fn wrongPtr(data: *i32) void { _ = data; }
fn wrongKind(x: i32) void { _ = x; }
fn right(data: *void) void { _ = data; }
fn wrongRet(data: *void) i32 { _ = data; return 1; }
fn noArgs() void { }
fn vararg(a: *void, b: i32, ...) void { _ = a; _ = b; }
fn takes(f: fn (*void) void) void { _ = f; }
fn takesOpt(f: ?fn (*void) void) void { _ = f; }
fn getWrong() fn (*void) void { return wrongPtr; }
extern "stdcall" fn convCb(data: *void) void;

// module const initializer and module var initializer.
const MConst: fn (*void) void = wrongPtr;
var MVar: fn (*void) void = wrongPtr;

pub fn main() void {
    var n: i32 = 7;
    // local declaration initializer.
    const f1: fn (*void) void = wrongPtr;
    // local assignment.
    var f2: fn (*void) void = right;
    f2 = wrongPtr;
    // struct-literal field initializer.
    var s = Shape{ .draw_fn = wrongPtr, .data = @ptrCast(*void, &n) };
    // field assignment (parameter kind mismatch).
    s.draw_fn = wrongKind;
    // return (from a mismatched function value).
    const g = getWrong();
    _ = g;
    // call argument, direct function value.
    takes(wrongKind);
    // call argument, via a local function pointer.
    const fp: fn (*i32) void = wrongPtr;
    takes(fp);
    // `?fn` declaration initializer.
    const o1: ?fn (*void) void = wrongPtr;
    // `?fn` struct-literal field initializer.
    const o2 = OptShape{ .draw_fn = wrongPtr };
    // `?fn` field assignment.
    var o3: OptShape = undefined;
    o3.draw_fn = wrongPtr;
    // `?fn` call argument.
    takesOpt(wrongPtr);
    // field assignment: wrong return type.
    s.draw_fn = wrongRet;
    // field assignment: arity mismatch.
    s.draw_fn = noArgs;
    // field assignment: calling-convention mismatch.
    s.draw_fn = convCb;
    // field assignment: variadic flag mismatch.
    s.draw_fn = vararg;
    // named-alias declaration initializer.
    const f3: DrawFn = wrongPtr;
    // reverse direction: field read -> field assignment.
    var s2: Shape2 = undefined;
    s2.draw_fn = s.draw_fn;
    // cross-module function value -> local declaration.
    const x1: fn (*void) void = lib.wrongPtr;
    // cross-module function value -> struct-literal field initializer.
    const xs = Shape{ .draw_fn = lib.wrongPtr, .data = @ptrCast(*void, &n) };
    // cross-module function value -> call argument.
    takes(lib.wrongPtr);
    // cross-module const initializer.
    const X4: fn (*void) void = lib.WRONG;
    _ = f1; _ = f2; _ = s; _ = o1; _ = o2; _ = o3;
    _ = f3; _ = s2; _ = x1; _ = xs; _ = X4; _ = MConst; _ = MVar;
    _ = fp;
}
