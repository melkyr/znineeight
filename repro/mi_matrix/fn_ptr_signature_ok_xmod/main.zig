// repro/mi_matrix/fn_ptr_signature_ok_xmod/main.zig — FX17-F positive control.
//
// Every legal function-pointer coercion stays accepted after the FX17-F
// signature enforcement: exact matches at every position, named aliases,
// callconv-qualified matches, `?fn` (null and value), explicit `@ptrCast` to a
// mismatched signature, `@ptrToInt`/`@intToPtr`, `undefined`, a
// function-pointer-returning function, cross-module same-signature values, and
// the `*const fn` double-pointer spelling (D4 residual: it keeps its
// pre-existing level-1 `warning[3000]` and is NOT enforced here).
//
// Contract: rc 0, deterministic 3x, golden stdout below; every observation is
// accumulated into `acc` so a wrong call is visible, and printed once.
const std = @import("std");
const lib = @import("helper.zig");

const Shape = struct { draw_fn: fn (*void) void, data: *void };
const OptShape = struct { draw_fn: ?fn (*void) void };
const DrawFn = fn (*void) void;

var acc: i32 = 0;

fn addOne(data: *void) void {
    _ = data;
    acc += 1;
}

fn addTwo(data: *void) void {
    _ = data;
    acc += 2;
}

fn wrongSig(data: *i32) void {
    _ = data;
    acc += 4;
}

fn getOp() fn (*void) void {
    return addOne;
}

fn takes(f: fn (*void) void) void {
    f(@ptrCast(*void, &acc));
}

fn takesOpt(f: ?fn (*void) void) void {
    if (f) |g| {
        g(@ptrCast(*void, &acc));
    }
}

pub fn main() void {
    var n: i32 = 7;
    // exact-match local declaration.
    const f: fn (*void) void = addOne;
    // exact-match struct-literal field initializer.
    var s = Shape{ .draw_fn = addOne, .data = @ptrCast(*void, &n) };
    // exact-match field assignment.
    s.draw_fn = addOne;
    // named-alias declaration.
    const fa: DrawFn = addOne;
    // callconv-qualified target type (matching `undefined`; the real
    // `extern "stdcall"` function-value match is in the standalone positive).
    const okc: extern "stdcall" fn (*void) void = undefined;
    // `?fn` null and value.
    const o1: ?fn (*void) void = null;
    const o2: ?fn (*void) void = addOne;
    // explicit `@ptrCast` to a mismatched signature stays legal.
    var sc = Shape{ .draw_fn = @ptrCast(fn (*void) void, wrongSig), .data = @ptrCast(*void, &n) };
    // `@ptrToInt` / `@intToPtr` round trip.
    const iv = @ptrToInt(addTwo);
    const ip = @intToPtr(fn (*void) void, iv);
    // `undefined` -> function pointer.
    const un: fn (*void) void = undefined;
    // function-pointer-returning function.
    const g = getOp();
    // cross-module same-signature function value -> local / field / call arg.
    const xf: fn (*void) void = lib.right;
    var xs = Shape{ .draw_fn = lib.cb, .data = @ptrCast(*void, &n) };
    // `*const fn` double-pointer spelling keeps its pre-existing warning (D4).
    const cf: *const fn (*void) void = addOne;
    // drive observations.
    f(@ptrCast(*void, &acc));         // addOne +1
    s.draw_fn(s.data);                // addOne +1
    fa(@ptrCast(*void, &acc));        // addOne +1
    sc.draw_fn(sc.data);              // wrongSig via @ptrCast +4
    ip(@ptrCast(*void, &acc));        // addTwo +2
    g(@ptrCast(*void, &acc));         // addOne +1
    xf(@ptrCast(*void, &acc));        // addOne +1
    xs.draw_fn(xs.data);              // lib.cb is a no-op +0
    takes(addOne);                    // +1
    takesOpt(o1);                     // null -> +0
    takesOpt(o2);                     // addOne +1
    _ = okc; _ = un; _ = cf;
    std.io.printInt(acc);
    std.io.writeByte('\n');
}
