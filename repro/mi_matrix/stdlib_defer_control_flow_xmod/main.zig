// stdlib_defer_control_flow_xmod — Task 10D regression: the ACCEPTED half of the
// Zig-matched `defer`/`errdefer` control-flow rule.
//
// Official Zig (src/AstGen.zig) rejects only transfers that leave the defer
// body. A `break`/`continue` whose target loop or labeled block is DECLARED
// inside the body is legal, and a nested `fn` resets the restriction. This
// fixture pins that accepted side so the fix cannot regress into Task 10C's
// (wrong) lexical blanket ban, which would have rejected these programs.
//
// The REJECTED side (outward `return`/`break`/`continue` and `try`) is pinned
// by `repro/mi_matrix/defer_control_flow_reject_xmod`.
//
// Contract: deterministic byte-exact stdout below, RUNRC=0. Defers run at scope
// exit, so each function's "...-body" line prints before its "...-ok" line.
//
//   inner-break-body
//   inner-break-ok
//   inner-continue-body
//   inner-continue-ok
//   labeled-block-body
//   labeled-block-ok
//   labeled-loop-body
//   labeled-loop-ok
//   errdefer-inner-body
//   errdefer-inner-ok
//   errdefer-inner-caught
//   done
const std = @import("std");

const E = error{Boom};

// Unlabeled `break` targeting the loop declared inside the defer body.
fn innerBreak() void {
    defer {
        var i: i32 = 0;
        while (i < 3) : (i += 1) {
            if (i == 1) break;
        }
        std.io.print("inner-break-ok\n");
    }
    std.io.print("inner-break-body\n");
}

// Unlabeled `continue` targeting the loop declared inside the defer body.
fn innerContinue() void {
    defer {
        var i: i32 = 0;
        while (i < 3) : (i += 1) {
            if (i == 1) continue;
        }
        std.io.print("inner-continue-ok\n");
    }
    std.io.print("inner-continue-body\n");
}

// Labeled `break` targeting a labeled block declared inside the defer body.
fn labeledBlock() void {
    defer {
        blk: {
            break :blk;
        }
        std.io.print("labeled-block-ok\n");
    }
    std.io.print("labeled-block-body\n");
}

// Labeled `break` targeting a labeled loop declared inside the defer body.
fn labeledLoop() void {
    defer {
        var i: i32 = 0;
        L: while (i < 3) : (i += 1) {
            if (i == 1) break :L;
        }
        std.io.print("labeled-loop-ok\n");
    }
    std.io.print("labeled-loop-body\n");
}

// The same accepted inner-loop transfer inside an `errdefer` body, on the error
// exit. This is the shape that previously silently swallowed the error return
// when the body instead contained an outward `continue`.
fn errdeferInner() E!void {
    errdefer {
        var i: i32 = 0;
        while (i < 3) : (i += 1) {
            if (i == 1) break;
        }
        std.io.print("errdefer-inner-ok\n");
    }
    std.io.print("errdefer-inner-body\n");
    return error.Boom;
}

pub fn main() void {
    innerBreak();
    innerContinue();
    labeledBlock();
    labeledLoop();
    errdeferInner() catch { std.io.print("errdefer-inner-caught\n"); };
    std.io.print("done\n");
}
