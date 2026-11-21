// opt_fnptr_extern_xmod — Plan A Task 4b-I pin: optional function-pointer
// parameter in an `extern "c"` declaration (and in a local `?fn` parameter).
//
// The C prototype this declaration binds to is
//
//     void take_fn(void (*h)(int));   /* null = 0 */
//
// Today the compiler records the parameter type of a function-pointer
// parameter as `i32` in the function type's shared `xt` parameter list
// (`resolveFnSignatures` snapshots `params_start` BEFORE resolving the
// parameter types, and resolving a `fn(...)`/`?fn(...)` parameter recursively
// appends the nested fn type's own parameters to the same `xt` array), so the
// call site materializes an `int` temp and passes it where a function pointer
// is expected. The local `?fn` parameter round-trip below fails to compile for
// the same reason (an `int` argument to an `Opt_` parameter).
//
// Emission-only: the C definition of `take_fn` lives on the C side (the
// `extern "c"` prototype comes from the C header), so the gate is gcc
// compiling the emitted C, not link/run.
//
// GREEN contract (Task 4b-F): the emitted call site passes `void (*)(int)`
// (null = `0`), the local `?fn` round-trip passes the optional struct
// correctly, gcc compiles the emitted C clean, and — linked against a
// conforming C `take_fn` — the program prints `1`.

const std = @import("std");

extern "c" fn take_fn(h: ?fn(i32) void) void;

fn note(x: i32) void { _ = x; }

fn localRound(h: ?fn(i32) void) i32 {
    var f: fn(i32) void = h orelse note;
    f(3);
    if (h != null) { return 1; }
    return 0;
}

pub fn main() void {
    take_fn(note);
    take_fn(null);
    var r: i32 = localRound(note);
    std.io.printInt(r);
    std.io.writeByte('\n');
}
