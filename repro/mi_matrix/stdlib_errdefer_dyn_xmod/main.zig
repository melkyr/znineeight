// stdlib_errdefer_dyn_xmod — Task 10F regression: a dynamic error-union return
// (`return <EU expr>;` where the source and destination error-union types are
// identical, so no coercion is recorded) must run `errdefer` on the error path
// and must NOT run it on the success path.
//
// Defect (pre-fix): the Task 10B classifier keyed `ret_is_error` on a recorded
// `wrap_error_err` coercion or an `error_literal` AST kind. For an EU-typed
// expression (`return x;` with `x: E!T`, or `return g();` with `g() E!T`) no
// coercion is recorded, so `ret_is_error` stayed 0, `expandDefers` skipped the
// errdefer bodies, and no runtime `is_error` branch was emitted — the error
// value was returned with its errdefer silently dropped.
//
// Fix: when (a) no static classification, (b) the return expression's resolved
// type is an error union, (c) the function return type is an error union, and
// (d) a pending errdefer exists, `return_stmt` lowering lowers the value, emits
// `check_error` + `branch` (mirroring the `try` path), and runs
// `expandDefers(0,1,0)` on the error arm / `expandDefers(0,0,0)` on the success
// arm before `ret val`. The pending-errdefer gate keeps every other EU return
// byte-identical.
//
// Cases pinned (each function has an `undo` errdefer that must run iff the
// returned error union is in its error state):
//   (a) varErr    `var x: E!i32 = error.Boom; return x;`  -> undo, caught
//   (b) varOk     `var x: E!i32 = 42;         return x;`  -> 42, NO undo
//   (c) callErr   `return g();`   (g() E!i32 errors)      -> undo, caught
//   (d) callOk    `return gok();` (gok() E!i32 = 7)       -> 7, NO undo
//   (e) voidErr   `var x: E!void = error.Boom; return x;` -> undo, caught
//   (f) voidOk    `var x: E!void = {};         return x;` -> ok, NO undo
//   (g) subErr    `var x: F!i32 = error.Boom;  return x;` -> undo, caught (F subset E)
//   (h) ctrlErr   `return error.Boom;` (static, Task 10B) -> undo, caught
//   (i) tryDyn    `return try x;`      (try control)      -> undo, caught
//   (j) nestedErr `defer` + `errdefer`, dynamic error     -> errdefer then defer, caught
//   (k) nestedOk  `defer` + `errdefer`, dynamic success   -> 9, defer, NO errdefer
//
// GREEN (contract): deterministic byte-exact stdout below (RUNRC=0). No
// success-path line may be preceded by `undo`, and no `-caught` may appear for
// the success cases.
const std = @import("std");
const E = error{Boom};
const F = error{Boom};

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

fn g() E!i32 { return error.Boom; }
fn gok() E!i32 { return 7; }

fn varErr() E!i32 {
    var x: E!i32 = error.Boom;
    errdefer std.io.print("undo\n");
    return x;
}

fn varOk() E!i32 {
    var x: E!i32 = 42;
    errdefer std.io.print("undo\n");
    return x;
}

fn callErr() E!i32 {
    errdefer std.io.print("undo\n");
    return g();
}

fn callOk() E!i32 {
    errdefer std.io.print("undo\n");
    return gok();
}

fn voidErr() E!void {
    var x: E!void = error.Boom;
    errdefer std.io.print("undo\n");
    return x;
}

fn voidOk() E!void {
    var x: E!void = {};
    errdefer std.io.print("undo\n");
    return x;
}

fn subErr() E!i32 {
    var x: F!i32 = error.Boom;
    errdefer std.io.print("undo\n");
    return x;
}

fn ctrlErr() E!i32 {
    errdefer std.io.print("undo\n");
    return error.Boom;
}

fn tryDyn() E!i32 {
    var x: E!i32 = error.Boom;
    errdefer std.io.print("undo\n");
    return try x;
}

fn nestedErr() E!i32 {
    defer std.io.print("nested-defer\n");
    errdefer std.io.print("nested-errdefer\n");
    var v: E!i32 = error.Boom;
    return v;
}

fn nestedOk() E!i32 {
    defer std.io.print("nested-defer\n");
    errdefer std.io.print("nested-errdefer\n");
    var v: E!i32 = 9;
    return v;
}

pub fn main() !void {
    varErr() catch { std.io.print("varErr-caught\n"); };
    var vok: i32 = varOk() catch { std.io.print("varOk-caught\n"); return; };
    p(vok);
    callErr() catch { std.io.print("callErr-caught\n"); };
    var cok: i32 = callOk() catch { std.io.print("callOk-caught\n"); return; };
    p(cok);
    voidErr() catch { std.io.print("voidErr-caught\n"); };
    voidOk() catch { std.io.print("voidOk-caught\n"); };
    std.io.print("voidOk-ok\n");
    subErr() catch { std.io.print("subErr-caught\n"); };
    ctrlErr() catch { std.io.print("ctrlErr-caught\n"); };
    tryDyn() catch { std.io.print("tryDyn-caught\n"); };
    nestedErr() catch { std.io.print("nestedErr-caught\n"); };
    var nok: i32 = nestedOk() catch { std.io.print("nestedOk-caught\n"); return; };
    p(nok);
    std.io.print("done\n");
}
