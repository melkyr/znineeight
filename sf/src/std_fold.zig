// std_fold.zig — Z98 std lib: per-type left folds over slices.
//
// Contract: alloc no | errors no | coroutine no. No imports.
//
// Each function walks `xs` in order and applies the caller-supplied combiner
// as `acc = f(acc, x)`, returning the final accumulator. The combiner is a
// plain function pointer (the indirect-call path); there are no generics and
// no new builtins — one concrete function per element type.

pub fn foldU32(xs: []const u32, acc: u32, f: fn (u32, u32) u32) u32 {
    var a: u32 = acc;
    var i: usize = 0;
    while (i < xs.len) : (i += 1) {
        a = f(a, xs[i]);
    }
    return a;
}

pub fn foldI32(xs: []const i32, acc: i32, f: fn (i32, i32) i32) i32 {
    var a: i32 = acc;
    var i: usize = 0;
    while (i < xs.len) : (i += 1) {
        a = f(a, xs[i]);
    }
    return a;
}

pub fn foldUsize(xs: []const usize, acc: usize, f: fn (usize, usize) usize) usize {
    var a: usize = acc;
    var i: usize = 0;
    while (i < xs.len) : (i += 1) {
        a = f(a, xs[i]);
    }
    return a;
}
