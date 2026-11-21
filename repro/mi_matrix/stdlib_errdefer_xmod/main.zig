// stdlib_errdefer_xmod — Task 10B regression: errdefer must run on an explicit
// error return, not only on `try` propagation.
//
// Defect (pre-fix): `return_stmt` lowering unconditionally called
// `expandDefers(..., is_error_path=0, ...)`, so every explicit `return` was
// treated as a success exit and all `errdefer` (kind==1) bodies were skipped.
// The `try` path already passed is_error_path=1, so case (c) worked.
//
// Contract (language spec §3.1, Design_p2 §8.3.7): an errdefer runs when the
// scope exits with an error (including an explicit `return error.X` / `return
// err`), and must NOT run on a successful `return`.
//
// Cases pinned:
//   (a) direct()      explicit `return error.Boom`          -> direct-undo runs
//   (b) conditional() conditional explicit error return      -> cond-undo runs
//   (c) viaTry()      `try boomOnly()`                       -> try-undo runs
//   (d) success()     plain `return;`                        -> success-undo MUST NOT run
//   (e) viaErrVar()   `catch |err| { return err; }`          -> errvar-undo runs
//
// GREEN (contract): deterministic byte-exact stdout below (RUNRC=0). The
// `success-undo` / `success-caught` lines must be absent.
const std = @import("std");
const E = error{Boom};

fn boomOnly() E!void { return error.Boom; }

fn direct() E!void {
    errdefer std.io.print("direct-undo\n");
    return error.Boom;
}

fn conditional(x: i32) E!void {
    errdefer std.io.print("cond-undo\n");
    if (x == 0) return error.Boom;
    return;
}

fn viaTry() E!void {
    errdefer std.io.print("try-undo\n");
    try boomOnly();
}

fn viaErrVar() E!void {
    errdefer std.io.print("errvar-undo\n");
    boomOnly() catch |err| { return err; };
}

fn success() E!void {
    errdefer std.io.print("success-undo\n");
    return;
}

pub fn main() !void {
    direct() catch { std.io.print("direct-caught\n"); };
    conditional(0) catch { std.io.print("cond-caught\n"); };
    viaTry() catch { std.io.print("try-caught\n"); };
    viaErrVar() catch { std.io.print("errvar-caught\n"); };
    success() catch { std.io.print("success-caught\n"); };
    std.io.print("done\n");
}
