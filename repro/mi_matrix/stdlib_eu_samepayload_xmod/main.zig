// stdlib_eu_samepayload_xmod — Task B5 same-payload positive control.
//
// A runtime error-union-to-error-union coercion whose error set widens but
// whose PAYLOAD is identical (`F!i32 -> E!i32`, `F subset E`) is legal Zig and
// must stay accepted and byte-identical. This is the path Task B5's exact
// payload-equality predicate deliberately preserves.
//
// Both the errdefer/dynamic path and the plain path are exercised, and the
// error tag and the success payload are `@panic`-guarded so a regression that
// mis-coerces the value traps instead of passing silently.
//
// Contract (deterministic stdout, RUNRC=0):
//   undo
//   ederr-caught
//   7
//   noederr-caught
//   7
//   done
// (`undo` is the errdefer of the error arm only; the two success returns must
// NOT print `undo`.)
const std = @import("std");
const E = error{Boom, Other};
const F = error{Boom};

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

fn gErr() F!i32 { return error.Boom; }
fn gOk() F!i32 { return 7; }

// errdefer + dynamic error-union return, same payload, subset set.
fn withEdErr() E!i32 {
    errdefer std.io.print("undo\n");
    return gErr();
}

fn withEdOk() E!i32 {
    errdefer std.io.print("undo\n");
    return gOk();
}

// plain dynamic error-union return, same payload, subset set.
fn noEdErr() E!i32 {
    return gErr();
}

fn noEdOk() E!i32 {
    return gOk();
}

pub fn main() !void {
    withEdErr() catch |c| {
        if (c != error.Boom) @panic("withEdErr tag");
        std.io.print("ederr-caught\n");
    };
    var v1: i32 = withEdOk() catch { @panic("withEdOk errored"); };
    if (v1 != 7) @panic("withEdOk payload");
    p(v1);

    noEdErr() catch |c| {
        if (c != error.Boom) @panic("noEdErr tag");
        std.io.print("noederr-caught\n");
    };
    var v2: i32 = noEdOk() catch { @panic("noEdOk errored"); };
    if (v2 != 7) @panic("noEdOk payload");
    p(v2);

    std.io.print("done\n");
}
